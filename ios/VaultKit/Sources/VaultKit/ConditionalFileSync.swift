// ConditionalFileSync.swift
//
// Fetch a vault file, keep the last GOOD copy (add-vault-connection design
// D8, spec "Fetched data replaces the cached copy only after it validates").
//
//   refresh(path, validate:)
//     - sends the stored ETag as If-None-Match; 304 -> `.unchanged`;
//     - 200 -> runs the caller's validator on the bytes. Only if it passes
//       are the bytes (cache/<sha256-of-path>.bin, atomic) and the new ETag
//       (fetch-cache.json) committed. If it throws, the last good bytes and
//       ETag stay, and the REJECTED ETag is remembered: the next request
//       sends it as If-None-Match and gets a 304, so the same broken file is
//       neither downloaded nor logged again on every foreground.
//   cachedFile(path) -> the last good bytes with their fetch date, so a cold
//     launch offline still has the last plan.
//
// In this change the app's validator is minimal (a JSON object, at most
// 5 MB); add-training-today-and-plan passes TrainingCore's decoder.
//
// Files (both under Application Support/VaultKit, both excluded from
// backups: a re-fetchable copy of vault data, whose system of record is the
// vault): `fetch-cache.json` (per path: ETag, rejected ETag, dates, byte
// count, cache file name) and `cache/*.bin`. The metadata goes through
// `PersistedJSON` like every store. The bytes are written BEFORE the
// metadata; a crash between the two leaves the old metadata beside the new
// (already validated) bytes, and `cachedFile` checks the byte count against
// the metadata, so a mismatch reads as "no cached copy", never as bytes
// from one version paired with another's dates.
//
// Depended on by: VaultSyncCoordinator; later TrainingCore's
// ProjectionStore. Tests: ConditionalFileSyncTests (over the GitHub
// transport with a stub, and over an in-memory transport).

import Foundation
import CryptoKit
import GarminKit

public struct FetchCacheEntry: Codable, Equatable, Sendable {
    /// ETag of the last good copy.
    public var etag: String?
    /// ETag of a copy the validator refused (design D8).
    public var rejectedETag: String?
    /// When the last good copy was downloaded.
    public var fetchedAt: Date?
    /// When the last request for this path got an answer (200 or 304).
    public var checkedAt: Date?
    public var byteCount: Int
    /// `cache/<name>` holding the last good bytes.
    public var fileName: String

    public init(etag: String? = nil, rejectedETag: String? = nil, fetchedAt: Date? = nil, checkedAt: Date? = nil, byteCount: Int = 0, fileName: String) {
        self.etag = etag
        self.rejectedETag = rejectedETag
        self.fetchedAt = fetchedAt
        self.checkedAt = checkedAt
        self.byteCount = byteCount
        self.fileName = fileName
    }
}

/// The last good copy of a file.
public struct CachedVaultFile: Equatable, Sendable {
    public let bytes: Data
    public let fetchedAt: Date?
}

public enum FetchReport: Equatable, Sendable {
    /// New bytes validated and committed.
    case updated(byteCount: Int)
    /// 304 (or the same bytes again).
    case unchanged
    /// Downloaded, refused by the validator; the last good copy stays.
    case rejected(reason: String)
    /// The request failed; the last good copy stays.
    case failed(VaultOutcome)
}

public struct ConditionalFetchResult: Equatable, Sendable {
    public let report: FetchReport
    public let tokenExpiresAt: Date?

    /// The outcome the connection status records.
    public var statusOutcome: VaultOutcome {
        switch report {
        case .updated, .unchanged, .rejected: return .success
        case .failed(let outcome): return outcome
        }
    }
}

public actor ConditionalFileSync {
    public static let metadataFileName = "fetch-cache.json"
    public static let cacheDirectoryName = "cache"

    private let transport: VaultTransport
    private let directory: URL
    private let metadataURL: URL
    private var entries: [String: FetchCacheEntry] = [:]
    private var loaded = false

    public init(transport: VaultTransport, directory: URL = VaultStorage.defaultDirectory()) {
        self.transport = transport
        self.directory = directory
        self.metadataURL = directory.appendingPathComponent("fetch-cache.json")
    }

    private var cacheDirectory: URL {
        directory.appendingPathComponent(Self.cacheDirectoryName, isDirectory: true)
    }

    /// `<sha256 of the hub path>.bin`: a fixed, safe file name per path.
    static func cacheFileName(for path: HubPath) -> String {
        SHA256.hash(data: Data(path.rawValue.utf8)).map { String(format: "%02x", $0) }.joined() + ".bin"
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load([String: FetchCacheEntry].self, from: metadataURL, decoder: VaultStorage.makeDecoder(), category: VaultLog.category)
        entries = result.value ?? [:]
        loaded = !result.isUnreadable
    }

    private func persist(_ updated: [String: FetchCacheEntry]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: metadataURL, category: VaultLog.category)
        try VaultStorage.write(try VaultStorage.makeEncoder().encode(updated), to: metadataURL)
        entries = updated
    }

    public func entry(for path: HubPath) -> FetchCacheEntry? {
        loadIfNeeded()
        return entries[path.rawValue]
    }

    /// The last good bytes, or `nil` if there are none (or the bytes file
    /// doesn't match its metadata -- see this file's header).
    public func cachedFile(_ path: HubPath) -> CachedVaultFile? {
        loadIfNeeded()
        guard let entry = entries[path.rawValue], entry.etag != nil || entry.fetchedAt != nil else { return nil }
        let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
        guard let bytes = try? Data(contentsOf: fileURL), bytes.count == entry.byteCount else { return nil }
        return CachedVaultFile(bytes: bytes, fetchedAt: entry.fetchedAt)
    }

    /// One conditional fetch of `path`. Never throws; every failure is a
    /// report, and the last good copy is untouched by any of them.
    public func refresh(_ path: HubPath, now: Date = Date(), validate: @Sendable (Data) throws -> Void) async -> ConditionalFetchResult {
        loadIfNeeded()
        let existing = entries[path.rawValue]
        let conditional = existing?.rejectedETag ?? existing?.etag
        let result = await transport.fetch(path, ifNoneMatch: conditional)

        switch result.outcome {
        case .failed(let outcome):
            return ConditionalFetchResult(report: .failed(outcome), tokenExpiresAt: result.tokenExpiresAt)

        case .notModified:
            var entry = existing ?? FetchCacheEntry(fileName: Self.cacheFileName(for: path))
            entry.checkedAt = now
            saveQuietly(entry, for: path)
            return ConditionalFetchResult(report: .unchanged, tokenExpiresAt: result.tokenExpiresAt)

        case .fetched(let bytes, let etag):
            var entry = existing ?? FetchCacheEntry(fileName: Self.cacheFileName(for: path))
            entry.checkedAt = now
            do {
                try validate(bytes)
            } catch {
                entry.rejectedETag = etag
                saveQuietly(entry, for: path)
                let reason = String(String(describing: error).prefix(200))
                VaultLog.log(.error, "\(path.rawValue): downloaded \(bytes.count) bytes but they did not validate; keeping the last good copy (\(reason))")
                return ConditionalFetchResult(report: .rejected(reason: reason), tokenExpiresAt: result.tokenExpiresAt)
            }
            let fileName = Self.cacheFileName(for: path)
            do {
                try VaultStorage.write(bytes, to: cacheDirectory.appendingPathComponent(fileName))
                entry.etag = etag
                entry.rejectedETag = nil
                entry.fetchedAt = now
                entry.byteCount = bytes.count
                entry.fileName = fileName
                var updated = entries
                updated[path.rawValue] = entry
                try persist(updated)
            } catch {
                VaultLog.log(.error, "\(path.rawValue): validated \(bytes.count) bytes but could not store them (\(type(of: error)))")
                return ConditionalFetchResult(report: .failed(.unexpected(status: 200)), tokenExpiresAt: result.tokenExpiresAt)
            }
            return ConditionalFetchResult(report: .updated(byteCount: bytes.count), tokenExpiresAt: result.tokenExpiresAt)
        }
    }

    /// Bookkeeping-only save (dates, a rejected ETag): logged if it fails,
    /// never surfaced -- the cached bytes are unaffected either way.
    private func saveQuietly(_ entry: FetchCacheEntry, for path: HubPath) {
        var updated = entries
        updated[path.rawValue] = entry
        do {
            try persist(updated)
        } catch {
            VaultLog.log(.warning, "\(path.rawValue): fetch bookkeeping could not be saved (\(type(of: error)))")
        }
    }

    /// Disconnect (design D3): forget every cached copy.
    public func clear() throws {
        loadIfNeeded()
        try persist([:])
        try? FileManager.default.removeItem(at: cacheDirectory)
    }
}

/// Validators for `ConditionalFileSync.refresh`. Until
/// add-training-today-and-plan passes TrainingCore's decoder, the app checks
/// only that the projection is a JSON object of at most 5 MB (task 4.5).
public enum VaultValidators {
    public static let projectionMaxBytes = 5 * 1024 * 1024

    public enum Problem: Error, Equatable, Sendable, CustomStringConvertible {
        case tooLarge(byteCount: Int)
        case notJSONObject

        public var description: String {
            switch self {
            case .tooLarge(let byteCount): return "too large (\(byteCount) bytes)"
            case .notJSONObject: return "not a JSON object"
            }
        }
    }

    public static func jsonObject(_ bytes: Data, maxBytes: Int = projectionMaxBytes) throws {
        guard bytes.count <= maxBytes else { throw Problem.tooLarge(byteCount: bytes.count) }
        guard (try? JSONSerialization.jsonObject(with: bytes)) is [String: Any] else { throw Problem.notJSONObject }
    }
}

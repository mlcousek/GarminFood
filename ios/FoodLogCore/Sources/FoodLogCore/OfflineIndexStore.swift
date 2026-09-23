// OfflineIndexStore.swift
//
// Keeps the Czech offline index on disk and up to date
// (add-offline-czech-food-index design.md D3, task 3.3). The weekly CI
// build publishes `manifest.json` plus the gzipped index on the rolling
// `food-index` GitHub Release. This actor:
//   - checks the manifest at most once every 24 h, unless forced by
//     Settings' "Download now";
//   - downloads only when the manifest's SHA-256 differs from what's
//     installed, and only on Wi-Fi unless the user allowed cellular. Low
//     Data Mode is always respected;
//   - verifies the SHA-256 and fully decodes the new file BEFORE it
//     replaces anything, then swaps it in with `replaceItemAt` and
//     excludes it from backup, since it can be downloaded again. A failed,
//     partial or corrupted download never touches the working index (spec
//     "Corrupted download");
//   - loads the installed file into `OfflineFoodIndexHolder`, off the main
//     actor, so search never waits on it;
//   - persists a small status record (version, count, size, last check,
//     last error) for the Settings row. Failures go to DiagnosticsLog and
//     that row, never to a modal: the index is a nice-to-have, and search
//     works without it.
//
// The network is behind `OfflineIndexFetching` (faked in tests). The real
// URLSession implementation is at the bottom. Its session disallows
// expensive and constrained networks, so "Wi-Fi only" is enforced by the
// OS, not by a reachability guess. Nothing here talks to Garmin.
//
// Used by the app's composition root (AppServices), BackgroundRefresh, the
// foreground check and SettingsView. Tested by OfflineIndexStoreTests.

import CryptoKit
import Foundation
import GarminKit

/// What Settings shows. Every field is optional so older files keep decoding.
public struct OfflineIndexStatus: Codable, Sendable, Equatable {
    public var installedVersion: String?
    public var installedCount: Int?
    public var installedBytes: Int?
    public var installedSHA256: String?
    public var installedAt: Date?
    public var lastCheckAt: Date?
    public var lastError: String?
    public var lastErrorAt: Date?

    public init(
        installedVersion: String? = nil,
        installedCount: Int? = nil,
        installedBytes: Int? = nil,
        installedSHA256: String? = nil,
        installedAt: Date? = nil,
        lastCheckAt: Date? = nil,
        lastError: String? = nil,
        lastErrorAt: Date? = nil
    ) {
        self.installedVersion = installedVersion
        self.installedCount = installedCount
        self.installedBytes = installedBytes
        self.installedSHA256 = installedSHA256
        self.installedAt = installedAt
        self.lastCheckAt = lastCheckAt
        self.lastError = lastError
        self.lastErrorAt = lastErrorAt
    }

    public var isInstalled: Bool { installedSHA256 != nil }
}

public enum OfflineIndexUpdateOutcome: Sendable, Equatable {
    /// Checked less than 24 h ago; nothing asked.
    case checkedRecently
    /// Another check is already running.
    case alreadyRunning
    /// The published index is the one installed.
    case upToDate
    case installed(count: Int)
    /// Only cellular or a Low Data Mode network is available, and cellular
    /// isn't allowed. Not an error: the next foreground on Wi-Fi retries.
    case waitingForWiFi
    case failed(String)
}

/// The two requests an update needs. `allowsCellular` false means Wi-Fi
/// (or wired) only.
public protocol OfflineIndexFetching: Sendable {
    func fetchManifest(from url: URL, allowsCellular: Bool) async throws -> Data
    /// Downloads `url` to a temporary file the caller then owns (and deletes).
    func download(from url: URL, allowsCellular: Bool) async throws -> URL
}

public enum OfflineIndexChecksum {
    /// Lowercase hex SHA-256.
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public actor OfflineIndexStore {
    public static let defaultManifestURL = URL(string: "https://github.com/mlcousek/GarminFood/releases/download/food-index/manifest.json")!
    public static let minimumCheckInterval: TimeInterval = 24 * 60 * 60
    static let indexFileName = "czech-food-index.json.gz"
    static let stagingFileName = "czech-food-index.staging.gz"
    static let statusFileName = "offline-index-status.json"

    /// What the search source and barcode fallback read. The composition
    /// root creates it and hands the same instance to both; this actor only
    /// writes to it.
    private let holder: OfflineFoodIndexHolder

    private let directory: URL
    private let fetcher: any OfflineIndexFetching
    private let manifestURL: URL
    private let clock: @Sendable () -> Date
    private var status: OfflineIndexStatus
    /// `false` only while the status file exists but could not be read
    /// (e.g. this process started before first unlock): `persistStatus()`
    /// then refuses to overwrite it, and the next entry point retries the
    /// read (fix/store-unreadable-latch).
    private var statusLoaded: Bool
    private var loadAttempted = false
    private var updateInFlight = false

    public init(
        holder: OfflineFoodIndexHolder,
        directory: URL = OfflineIndexStore.defaultDirectory(),
        fetcher: any OfflineIndexFetching = URLSessionOfflineIndexFetcher(),
        manifestURL: URL = OfflineIndexStore.defaultManifestURL,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.directory = directory
        self.fetcher = fetcher
        self.manifestURL = manifestURL
        self.holder = holder
        self.clock = clock
        self.status = FoodLogCoreStorage.loadPersistedJSON(
            OfflineIndexStatus.self,
            from: directory.appendingPathComponent(Self.statusFileName),
            decoder: JSONDecoder(),
            category: "OfflineIndexStore"
        ) ?? OfflineIndexStatus()
    }

    public static func defaultDirectory() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("OfflineIndex", isDirectory: true)
    }

    private var indexFileURL: URL { directory.appendingPathComponent(Self.indexFileName) }
    private var statusFileURL: URL { directory.appendingPathComponent(Self.statusFileName) }

    public func currentStatus() -> OfflineIndexStatus {
        status
    }

    /// Decodes the installed file into `holder`, once per process. Call at
    /// launch, in a background task. A file that no longer decodes is left
    /// in place (the next successful download replaces it) and reported.
    public func loadInstalledIndexIfNeeded() {
        guard !loadAttempted else { return }
        loadAttempted = true
        guard holder.index == nil, FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: indexFileURL)
            holder.replace(with: try OfflineFoodIndex.decode(gzipData: data))
        } catch {
            recordFailure("Couldn't read the installed offline database: \(error)")
        }
    }

    /// The manifest check and, when needed, download and install.
    /// `force` skips the 24 h throttle ("Download now").
    public func checkForUpdate(force: Bool = false, allowsCellular: Bool = false) async -> OfflineIndexUpdateOutcome {
        guard !updateInFlight else { return .alreadyRunning }
        let now = clock()
        if !force, let lastCheck = status.lastCheckAt, now.timeIntervalSince(lastCheck) < Self.minimumCheckInterval, now >= lastCheck {
            return .checkedRecently
        }
        updateInFlight = true
        defer { updateInFlight = false }
        loadInstalledIndexIfNeeded()

        let manifest: OfflineIndexManifest
        do {
            let data = try await fetcher.fetchManifest(from: manifestURL, allowsCellular: allowsCellular)
            manifest = try Self.decodeManifest(data)
        } catch {
            return transportOutcome(error, stage: "manifest")
        }

        let previousCheck = status.lastCheckAt
        status.lastCheckAt = now
        guard manifest.schema <= OfflineIndexFile.supportedSchema else {
            return failed(OfflineIndexError.unsupportedSchema(manifest.schema).description)
        }
        if manifest.sha256.lowercased() == status.installedSHA256, holder.index != nil {
            clearError()
            return .upToDate
        }
        guard let fileURL = URL(string: manifest.file, relativeTo: manifestURL)?.absoluteURL else {
            return failed(OfflineIndexError.invalidManifest("bad file name").description)
        }

        let downloaded: URL
        do {
            downloaded = try await fetcher.download(from: fileURL, allowsCellular: allowsCellular)
        } catch {
            let outcome = transportOutcome(error, stage: "download")
            if outcome == .waitingForWiFi {
                // Not a real answer yet: retry on the next Wi-Fi foreground.
                status.lastCheckAt = previousCheck
                persistStatus()
            }
            return outcome
        }

        do {
            let count = try install(downloadedFile: downloaded, manifest: manifest)
            DiagnosticsLog.log(.info, category: "OfflineIndex", "Installed offline index \(manifest.version) (\(count) products)")
            return .installed(count: count)
        } catch {
            return failed("Offline database update rejected: \(error)")
        }
    }

    /// Verifies, decodes and atomically installs a downloaded file. Throws
    /// without touching the installed index on any mismatch. Internal for tests.
    @discardableResult
    func install(downloadedFile: URL, manifest: OfflineIndexManifest) throws -> Int {
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: downloadedFile) }

        let data = try Data(contentsOf: downloadedFile)
        let actual = OfflineIndexChecksum.sha256Hex(data)
        guard actual == manifest.sha256.lowercased() else {
            throw OfflineIndexError.checksumMismatch(expected: manifest.sha256, actual: actual)
        }
        // Proves the file is usable before it replaces anything.
        let index = try OfflineFoodIndex.decode(gzipData: data)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let staging = directory.appendingPathComponent(Self.stagingFileName)
        try? fileManager.removeItem(at: staging)
        try data.write(to: staging)
        if fileManager.fileExists(atPath: indexFileURL.path) {
            _ = try fileManager.replaceItemAt(indexFileURL, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: indexFileURL)
        }
        var installedURL = indexFileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? installedURL.setResourceValues(values)

        holder.replace(with: index)
        loadAttempted = true
        status.installedVersion = manifest.version
        status.installedCount = index.count
        status.installedBytes = data.count
        status.installedSHA256 = actual
        status.installedAt = clock()
        status.lastError = nil
        status.lastErrorAt = nil
        persistStatus()
        return index.count
    }

    static func decodeManifest(_ data: Data) throws -> OfflineIndexManifest {
        let manifest: OfflineIndexManifest
        do {
            manifest = try JSONDecoder().decode(OfflineIndexManifest.self, from: data)
        } catch {
            throw OfflineIndexError.invalidManifest(String(describing: error))
        }
        // The file must sit next to the manifest: a plain name, no path.
        let file = manifest.file
        guard !file.isEmpty, !file.contains("/"), !file.contains("\\"), !file.hasPrefix("."), file.count <= 128 else {
            throw OfflineIndexError.invalidManifest("file must be a plain file name")
        }
        guard manifest.sha256.count == 64, manifest.sha256.allSatisfy(\.isHexDigit) else {
            throw OfflineIndexError.invalidManifest("sha256 must be 64 hex digits")
        }
        return manifest
    }

    // MARK: - Outcomes

    private func transportOutcome(_ error: Error, stage: String) -> OfflineIndexUpdateOutcome {
        if Self.isWaitingForAllowedNetwork(error) {
            return .waitingForWiFi
        }
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return .failed("Cancelled")
        }
        return failed("Offline database \(stage) failed: \(error)")
    }

    /// URLSession's "only a disallowed (cellular / expensive / Low Data)
    /// network is available" failure.
    static func isWaitingForAllowedNetwork(_ error: Error) -> Bool {
        guard let urlError = error as? URLError, let reason = urlError.networkUnavailableReason else { return false }
        switch reason {
        case .cellular, .expensive, .constrained:
            return true
        @unknown default:
            return false
        }
    }

    private func failed(_ message: String) -> OfflineIndexUpdateOutcome {
        recordFailure(message)
        return .failed(message)
    }

    private func recordFailure(_ message: String) {
        DiagnosticsLog.log(.warning, category: "OfflineIndex", message)
        status.lastError = message
        status.lastErrorAt = clock()
        persistStatus()
    }

    private func clearError() {
        status.lastError = nil
        status.lastErrorAt = nil
        persistStatus()
    }

    private func persistStatus() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(status) else { return }
        try? data.write(to: statusFileURL, options: .atomic)
    }
}

// MARK: - URLSession

/// The real fetcher. A fresh ephemeral-cache session per request, so the
/// cellular setting of the moment applies and nothing stale is served.
public struct URLSessionOfflineIndexFetcher: OfflineIndexFetching {
    public init() {}

    public func fetchManifest(from url: URL, allowsCellular: Bool) async throws -> Data {
        let session = Self.session(allowsCellular: allowsCellular)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: url)
        try Self.checkStatus(response)
        return data
    }

    public func download(from url: URL, allowsCellular: Bool) async throws -> URL {
        let session = Self.session(allowsCellular: allowsCellular)
        defer { session.finishTasksAndInvalidate() }
        let (temporaryURL, response) = try await session.download(from: url)
        do {
            try Self.checkStatus(response)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        // Move it somewhere we own before URLSession can clean it up.
        let owned = FileManager.default.temporaryDirectory.appendingPathComponent("offline-index-\(UUID().uuidString).gz")
        try FileManager.default.moveItem(at: temporaryURL, to: owned)
        return owned
    }

    static func session(allowsCellular: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsCellularAccess = allowsCellular
        configuration.allowsExpensiveNetworkAccess = allowsCellular
        configuration.allowsConstrainedNetworkAccess = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": OpenFoodFactsClient.userAgent]
        return URLSession(configuration: configuration)
    }

    static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw OfflineIndexError.httpStatus(http.statusCode)
        }
    }
}

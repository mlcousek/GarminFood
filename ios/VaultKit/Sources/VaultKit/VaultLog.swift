// VaultLog.swift
//
// The one way VaultKit writes to the in-app diagnostics log, always under
// the `vault` category (add-vault-connection task 4.6). Two reasons it is a
// funnel rather than direct `DiagnosticsLog.log` calls:
//
//   1. Redaction is a rule of this package (design D3): a log line may carry
//      a status code, a hub-relative path, a byte count and a typed outcome
//      -- never the token, the repository owner or name, a URL, or a raw
//      error description (a `URLError`'s description embeds the request
//      URL, which names the repository). Keeping every call here makes that
//      reviewable in one place.
//   2. `RedactionTests` must see every line synchronously. `DiagnosticsLog`'s
//      static entry point is fire-and-forget (a `Task`), so a test cannot
//      reliably read its lines back; an observer registered here receives
//      each line on the calling thread before it is handed to the real log.
//
// Also holds `VaultStorage`, the package's Application Support directory.
//
// Depended on by: every VaultKit type that logs or persists.

import Foundation
import GarminKit

public enum VaultLog {
    public static let category = "vault"

    /// Writes one line to `DiagnosticsLog` (category `vault`) and to every
    /// registered observer. Callers pass only redacted material -- see this
    /// file's header.
    public static func log(_ level: DiagnosticsLevel, _ message: String) {
        observers.notify(level, message)
        DiagnosticsLog.log(level, category: category, message)
    }

    /// Registers `observer` for every line logged from now on; returns a
    /// token for `removeObserver`. Tests only.
    @discardableResult
    static func addObserver(_ observer: @escaping @Sendable (DiagnosticsLevel, String) -> Void) -> UUID {
        observers.add(observer)
    }

    static func removeObserver(_ id: UUID) {
        observers.remove(id)
    }

    private static let observers = ObserverList()

    /// Lock-protected, so `log` may be called from any actor or thread.
    private final class ObserverList: @unchecked Sendable {
        private let lock = NSLock()
        private var observers: [UUID: @Sendable (DiagnosticsLevel, String) -> Void] = [:]

        func add(_ observer: @escaping @Sendable (DiagnosticsLevel, String) -> Void) -> UUID {
            let id = UUID()
            lock.lock()
            observers[id] = observer
            lock.unlock()
            return id
        }

        func remove(_ id: UUID) {
            lock.lock()
            observers[id] = nil
            lock.unlock()
        }

        func notify(_ level: DiagnosticsLevel, _ message: String) {
            lock.lock()
            let current = Array(observers.values)
            lock.unlock()
            for observer in current {
                observer(level, message)
            }
        }
    }
}

/// `Application Support/VaultKit/`, where every VaultKit file lives
/// (design D12). One directory, so the backup exclusion is one rule.
public enum VaultStorage {
    public static let directoryName = "VaultKit"

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Atomic write with the same data protection the Garmin outboxes use
    /// (`completeUntilFirstUserAuthentication`), creating the directory if
    /// needed.
    static func write(_ data: Data, to fileURL: URL) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    /// The encoder every VaultKit store uses: ISO-8601 dates and sorted
    /// keys, so a file reads the same by hand and in a fixture diff.
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

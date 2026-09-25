// SupplementStoreSupport.swift
//
// What the three supplement stores (SupplementPlanStore,
// SupplementIntakeStore, SupplementLimitsStore -- add-supplements 2.1)
// share: their error type and the one routine that writes a JSON file.
//
// Every supplement store follows the store contract of this package
// (fix-silent-store-wipe, fix/store-unreadable-latch):
//   - load through `FoodLogCoreStorage.loadPersistedJSON`, so an
//     undecodable file is quarantined, never silently wiped;
//   - a file that exists but can't be READ yet (before first unlock) is not
//     latched as loaded: reads throw `PersistedJSONUnreadFileError`, and
//     writes are refused by `ensureSafeToWrite`;
//   - every mutation loads first, so a save on a fresh actor never trips
//     the "never loaded" guard;
//   - the in-memory copy changes only after the write succeeded.
//
// Written files get `completeUntilFirstUserAuthentication` protection (as
// `ActivityCacheStore` does), because the reminder's "Taken" action (D5,
// wave 4) writes intake while the phone may be locked.

import Foundation
import GarminKit

/// Why a supplement store refused a write. Nothing was changed.
public enum SupplementStoreError: Error, Sendable, Equatable, LocalizedError {
    /// The day is in the future, more than 365 days back, or not a day
    /// (design D14).
    case dayNotEditable(String)
    /// Writing the file failed; the detail is the system's own words.
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .dayNotEditable:
            return String(localized: "Only today and the last 365 days can be filled in.", bundle: .module, comment: "Error when supplement intake is logged for a future day or more than 365 days back.")
        case .saveFailed(let detail):
            return String(localized: "Couldn't save your supplements on this phone: \(detail)", bundle: .module, comment: "Error when writing supplement data on the phone fails. %@ is the system's reason.")
        }
    }
}

enum SupplementStoreIO {
    /// Encodes `value` and writes it atomically to `url` (creating the
    /// directory), with first-unlock file protection. Logs and throws
    /// `SupplementStoreError.saveFailed` on failure.
    static func write<T: Encodable>(_ value: T, to url: URL, category: String) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: url, options: .atomic)
        } catch {
            DiagnosticsLog.log(.error, category: category, "could not save \(url.lastPathComponent): \(error)")
            throw SupplementStoreError.saveFailed(error.localizedDescription)
        }
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }
}

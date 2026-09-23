// PersistedStoreLoading.swift
//
// The FoodLogCore-side entry point to GarminKit's `PersistedJSON.load` --
// the shared "load a store's JSON file, and quarantine it instead of
// silently wiping it if it no longer decodes" routine
// (openspec/changes/fix-silent-store-wipe; see GarminKit/PersistedJSON.swift's
// header for the bug this closes and the exact per-outcome behaviour).
//
// Also forwards the save-side guard, `ensureSafeToWrite`
// (fix/store-unreadable-latch): a file that exists but can't be READ yet
// (data protection before first unlock) must not latch the store empty and
// then be overwritten by its next save. Every store here follows the same
// two-line contract -- `loaded = !result.isUnreadable` in `loadIfNeeded()`,
// `try ensureSafeToWrite(...)` at the top of `persist()`.
//
// Exists as a passthrough for two reasons:
//   - every store in THIS package calls it without each file needing its
//     own `import GarminKit`;
//   - Gamification deliberately does NOT depend on GarminKit (its
//     Package.swift header documents why), but its stores have exactly the
//     same bug and need exactly the same fix -- they reach it through here
//     (via `GamificationStorage.loadPersistedJSON`), so there is still only
//     one implementation.
//
// Returns a plain labeled tuple rather than GarminKit's `PersistedJSONLoad`
// so no store (least of all Gamification's) has to name, or rely on member
// visibility of, a GarminKit type.

import Foundation
import GarminKit

extension FoodLogCoreStorage {
    /// Forwards to `GarminKit.PersistedJSON.load` -- same arguments, same
    /// quarantine behaviour for an undecodable file. `value` is `nil` for
    /// every non-success outcome (fall back to empty state, as before);
    /// `isUnreadable` is `true` only when the file exists but could not be
    /// read, in which case the caller must NOT latch its `loaded` flag.
    public static func loadPersistedJSON<T: Decodable>(
        _ type: T.Type,
        from fileURL: URL,
        decoder: JSONDecoder,
        category: String
    ) -> (value: T?, isUnreadable: Bool) {
        let result = PersistedJSON.load(type, from: fileURL, decoder: decoder, category: category)
        return (value: result.value, isUnreadable: result.isUnreadable)
    }

    /// Forwards to `GarminKit.PersistedJSON.ensureSafeToWrite`: throws
    /// (and logs) when `loaded` is still `false`, i.e. the store's file
    /// exists but has never been readable in this process. Call it AFTER
    /// the save path's own `loadIfNeeded()`.
    public static func ensureSafeToWrite(loaded: Bool, fileURL: URL, category: String) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: category)
    }
}

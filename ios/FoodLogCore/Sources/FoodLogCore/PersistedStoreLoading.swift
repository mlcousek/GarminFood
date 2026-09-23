// PersistedStoreLoading.swift
//
// The FoodLogCore-side entry point to GarminKit's `PersistedJSON.load` --
// the shared "load a store's JSON file, and quarantine it instead of
// silently wiping it if it no longer decodes" routine
// (openspec/changes/fix-silent-store-wipe; see GarminKit/PersistedJSON.swift's
// header for the bug this closes and the exact per-outcome behaviour).
//
// Exists as a passthrough for two reasons:
//   - every store in THIS package calls it without each file needing its
//     own `import GarminKit`;
//   - Gamification deliberately does NOT depend on GarminKit (its
//     Package.swift header documents why), but its stores have exactly the
//     same bug and need exactly the same fix -- they reach it through here
//     (via `GamificationStorage.loadPersistedJSON`), so there is still only
//     one implementation.

import Foundation
import GarminKit

extension FoodLogCoreStorage {
    /// Forwards to `GarminKit.PersistedJSON.load` unchanged -- same
    /// arguments, same `nil`-on-any-failure contract, same quarantine
    /// behaviour for an undecodable file.
    public static func loadPersistedJSON<T: Decodable>(
        _ type: T.Type,
        from fileURL: URL,
        decoder: JSONDecoder,
        category: String
    ) -> T? {
        PersistedJSON.load(type, from: fileURL, decoder: decoder, category: category)
    }
}

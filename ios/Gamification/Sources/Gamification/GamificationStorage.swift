// GamificationStorage.swift
//
// Shared Application Support subdirectory for every JSON-file store in this
// package (`XPStore`, `GoalStatusStore`, `ChallengeStore`) -- one directory,
// one place to find them all by hand, matching FoodLogCore's own
// `FoodLogCoreStorage` and GarminKit's outbox rationale: there is no
// interactive debugger for this project (no Mac -- openspec/config.yaml),
// so "trivially inspectable on disk" is a real design goal, not incidental.
//
// Also the single place this package's stores load their file back from
// disk (`loadPersistedJSON`), so an undecodable file is logged and moved
// aside instead of silently wiped by the next save
// (openspec/changes/fix-silent-store-wipe). It forwards to FoodLogCore's
// passthrough rather than GarminKit directly, because this package
// deliberately does not depend on GarminKit (see Package.swift's header).

import FoodLogCore
import Foundation

enum GamificationStorage {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Gamification", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// See FoodLogCore's `FoodLogCoreStorage.loadPersistedJSON` (and
    /// GarminKit's `PersistedJSON.load`) for the contract. On
    /// `isUnreadable` (the file exists but couldn't be read, e.g. before
    /// first unlock) the store must NOT latch `loaded`, and `persist()`
    /// must start with `ensureSafeToWrite` (fix/store-unreadable-latch).
    static func loadPersistedJSON<T: Decodable>(
        _ type: T.Type,
        from fileURL: URL,
        decoder: JSONDecoder,
        category: String
    ) -> (value: T?, isUnreadable: Bool) {
        FoodLogCoreStorage.loadPersistedJSON(type, from: fileURL, decoder: decoder, category: category)
    }

    /// Throws instead of letting a save replace a file this process never
    /// managed to read. Call first thing in `persist()`.
    static func ensureSafeToWrite(loaded: Bool, fileURL: URL, category: String) throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: category)
    }
}

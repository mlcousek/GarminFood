// GamificationStorage.swift
//
// Shared Application Support subdirectory for every JSON-file store in this
// package (`XPStore`, `GoalStatusStore`, `ChallengeStore`) -- one directory,
// one place to find them all by hand, matching FoodLogCore's own
// `FoodLogCoreStorage` and GarminKit's outbox rationale: there is no
// interactive debugger for this project (no Mac -- openspec/config.yaml),
// so "trivially inspectable on disk" is a real design goal, not incidental.

import Foundation

enum GamificationStorage {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("Gamification", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// StoreCatalog.swift
//
// add-data-safety D1: the one list of every JSON store this app persists,
// with a schema version per store. Why it exists: backups (snapshots and
// exported files) must be refused by a build that cannot read them, and
// "can this build read that file" is a per-store question. Adding a
// `version` field inside ~35 store files owned by other changes would need
// its own migration; a catalog gives backups the same guarantee without
// touching any store's on-disk shape.
//
// Rules (docs/data-compatibility.md):
//   - bump `schemaVersion` when a change makes the file unreadable by the
//     PREVIOUS release (a new enum case, a changed type). Additive Optional
//     fields do not bump it.
//   - a new store adds an entry here; `StoreCatalogTests` fails when a
//     store file name in GarminKit/FoodLogCore/Gamification sources is not
//     covered.
//
// The catalog does NOT decide what gets backed up -- `BackupExclusions`
// does, generically, so a store missing from here is still copied. The
// catalog adds versions (for `BackupCompatibility`) and preview areas (for
// `BackupPreview`). Paths are relative to Application Support.
//
// Depended on by: BackupVault, BackupCompatibility, BackupPreview.

import Foundation

/// The group a store is shown under in the import preview.
public enum BackupArea: String, Codable, Sendable, CaseIterable {
    case foodLog
    case customFoods
    case mealPresets
    case favorites
    case weight
    case hydration
    case dayNotes
    case fasting
    case supplements
    case history
    case progress
    case deviceOnly
    case other
}

/// Where a store's file(s) live, relative to Application Support.
public enum StoreLocation: Sendable, Equatable {
    /// Exactly one file, e.g. `FoodLogCore/custom-foods.json`.
    case file(String)
    /// Every `.json` file under a directory (recursively). `fileNames`,
    /// when given, lists the literal file names used inside it -- only for
    /// the source-coverage test, since those names are not paths.
    case directory(String, fileNames: [String])
    /// Every file directly in `directory` whose name starts with `prefix`
    /// (per-process names like `outbox-<process>.json`).
    case prefixed(directory: String, prefix: String)

    func matches(relativePath path: String) -> Bool {
        switch self {
        case .file(let exact):
            return path == exact
        case .directory(let directory, _):
            return path.hasPrefix(directory + "/")
        case .prefixed(let directory, let prefix):
            guard path.hasPrefix(directory + "/") else { return false }
            let rest = String(path.dropFirst(directory.count + 1))
            return !rest.contains("/") && rest.hasPrefix(prefix)
        }
    }
}

public struct StoreCatalogEntry: Sendable, Equatable {
    public let id: String
    public let location: StoreLocation
    public let schemaVersion: Int
    public let area: BackupArea
    /// `false` for stores `BackupExclusions` leaves out on purpose (design
    /// D3/D8). `StoreCatalogTests` checks the two agree.
    public let inBackup: Bool

    public init(id: String, location: StoreLocation, schemaVersion: Int, area: BackupArea, inBackup: Bool = true) {
        self.id = id
        self.location = location
        self.schemaVersion = schemaVersion
        self.area = area
        self.inBackup = inBackup
    }
}

public enum StoreCatalog {
    public static let entries: [StoreCatalogEntry] = [
        // GarminKit -- device delivery state and diagnostics, never backed up.
        StoreCatalogEntry(id: "garminkit.outbox", location: .prefixed(directory: "GarminKit", prefix: "outbox-"), schemaVersion: 1, area: .deviceOnly, inBackup: false),
        StoreCatalogEntry(id: "garminkit.weight-outbox", location: .prefixed(directory: "GarminKit", prefix: "weight-outbox-"), schemaVersion: 1, area: .deviceOnly, inBackup: false),
        StoreCatalogEntry(id: "garminkit.hydration-outbox", location: .prefixed(directory: "GarminKit", prefix: "hydration-outbox-"), schemaVersion: 1, area: .deviceOnly, inBackup: false),
        StoreCatalogEntry(id: "garminkit.diagnostics-log", location: .file("GarminKit/diagnostics-log.json"), schemaVersion: 1, area: .deviceOnly, inBackup: false),

        // FoodLogCore
        StoreCatalogEntry(id: "foodlog.local-food-log", location: .directory("FoodLogCore/FoodLog", fileNames: []), schemaVersion: 1, area: .foodLog),
        StoreCatalogEntry(id: "foodlog.usage-history", location: .file("FoodLogCore/usage-history.json"), schemaVersion: 1, area: .history),
        StoreCatalogEntry(id: "foodlog.serving-defaults", location: .file("FoodLogCore/serving-defaults.json"), schemaVersion: 1, area: .history),
        StoreCatalogEntry(id: "foodlog.custom-foods", location: .file("FoodLogCore/custom-foods.json"), schemaVersion: 1, area: .customFoods),
        StoreCatalogEntry(id: "foodlog.meal-presets", location: .file("FoodLogCore/meal-presets.json"), schemaVersion: 1, area: .mealPresets),
        StoreCatalogEntry(id: "foodlog.food-cache", location: .file("FoodLogCore/food-cache.json"), schemaVersion: 1, area: .history),
        StoreCatalogEntry(id: "foodlog.favorite-foods", location: .file("FoodLogCore/favorite-foods.json"), schemaVersion: 1, area: .favorites),
        StoreCatalogEntry(id: "foodlog.fasting-sessions", location: .file("FoodLogCore/fasting-sessions.json"), schemaVersion: 1, area: .fasting),
        StoreCatalogEntry(id: "foodlog.day-notes", location: .file("FoodLogCore/day-notes.json"), schemaVersion: 1, area: .dayNotes),
        StoreCatalogEntry(id: "foodlog.weight-entries", location: .file("FoodLogCore/weight-entries.json"), schemaVersion: 1, area: .weight),
        StoreCatalogEntry(id: "foodlog.hydration-entries", location: .file("FoodLogCore/hydration-entries.json"), schemaVersion: 1, area: .hydration),
        // add-standalone-mode 4.1 (#90): standalone mode's goal history.
        StoreCatalogEntry(id: "foodlog.local-goals", location: .file("FoodLogCore/local-goals.json"), schemaVersion: 1, area: .other),
        StoreCatalogEntry(id: "foodlog.day-log-digests", location: .file("FoodLogCore/day-log-digests.json"), schemaVersion: 1, area: .history),
        StoreCatalogEntry(id: "foodlog.activity-cache", location: .file("FoodLogCore/activity-cache.json"), schemaVersion: 1, area: .history),
        StoreCatalogEntry(id: "foodlog.food-provenance", location: .file("FoodLogCore/food-provenance.json"), schemaVersion: 1, area: .history),
        StoreCatalogEntry(id: "foodlog.garmin-health-cache", location: .file("FoodLogCore/garmin-health-cache.json"), schemaVersion: 1, area: .deviceOnly, inBackup: false),
        StoreCatalogEntry(id: "foodlog.offline-index", location: .directory("FoodLogCore/OfflineIndex", fileNames: ["offline-index-status.json"]), schemaVersion: 1, area: .deviceOnly, inBackup: false),
        // add-supplements (#85): the plan, the limit overrides and the
        // month-sharded intake log.
        StoreCatalogEntry(id: "foodlog.supplement-plan", location: .file("FoodLogCore/supplement-plan.json"), schemaVersion: 1, area: .supplements),
        StoreCatalogEntry(id: "foodlog.supplement-limits", location: .file("FoodLogCore/supplement-limits.json"), schemaVersion: 1, area: .supplements),
        StoreCatalogEntry(id: "foodlog.supplement-intake", location: .directory("FoodLogCore/SupplementIntake", fileNames: []), schemaVersion: 1, area: .supplements),

        // Gamification
        StoreCatalogEntry(id: "gamification.xp-ledger", location: .file("Gamification/xp-ledger.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.achievements", location: .file("Gamification/achievements.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.challenge-state", location: .file("Gamification/challenge-state.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.challenge-history", location: .file("Gamification/challenge-history.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.daily-challenges", location: .file("Gamification/daily-challenges.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.goal-status", location: .file("Gamification/goal-status.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.lifetime-stats", location: .file("Gamification/lifetime-stats.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(id: "gamification.reward-ledger", location: .file("Gamification/reward-ledger.json"), schemaVersion: 1, area: .progress),
        StoreCatalogEntry(
            id: "gamification.features",
            location: .directory("Gamification/features", fileNames: [
                "bingo.json", "seasonal.json", "collections.json", "journeys.json",
                "records.json", "sport.json", "boss.json", "streak-freezes.json"
            ]),
            schemaVersion: 1,
            area: .progress
        ),

        // App target
        StoreCatalogEntry(id: "app.siri-donations", location: .file("GarminFood/donations.json"), schemaVersion: 1, area: .deviceOnly, inBackup: false)
    ]

    /// The entry a file at `relativePath` belongs to, or `nil` for a store
    /// this build doesn't know (a newer app's, or one not registered yet).
    public static func entry(forRelativePath relativePath: String) -> StoreCatalogEntry? {
        entries.first { $0.location.matches(relativePath: relativePath) }
    }

    public static func entry(id: String) -> StoreCatalogEntry? {
        entries.first { $0.id == id }
    }
}

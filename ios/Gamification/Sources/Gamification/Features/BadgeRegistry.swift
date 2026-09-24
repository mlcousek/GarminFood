// BadgeRegistry.swift
//
// Design D9: every badge the app can show = the core `AchievementCatalog`
// + each registered feature's static `badges`, de-duplicated by id. The
// Achievements screen and its summary card read THIS instead of
// `AchievementCatalog.all`, so a wave-2 feature's badges appear without
// editing any UI. A duplicate id is a programming error caught by
// `BadgeRegistryTests`, not a runtime choice (the first definition wins
// here only so a release build never crashes on it).
//
// Badge id namespaces: `achv-*` (core), `bingo.*`, `event.*`,
// `collection.*`, `journey.*`, `record.*`, `secret.*`, `sport.*`, `boss.*`,
// `freeze.*`.
//
// Depends on: AchievementCatalog, GamificationFeatureRegistry.
// Depended on by: the app's AchievementsView / summary card / FeatureHost.

import Foundation

public enum BadgeRegistry {
    /// Core catalog followed by feature badges in registry order.
    public static func badges(features: [any GamificationFeature]) -> [AchievementDefinition] {
        merge(AchievementCatalog.all, features.flatMap { $0.badges })
    }

    /// Uses a throwaway set of feature instances (badges are static facts;
    /// the instances do no I/O until `update` is called).
    public static var all: [AchievementDefinition] {
        badges(features: GamificationFeatureRegistry.makeAll(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("badge-registry", isDirectory: true)))
    }

    /// Every id that appears more than once across core + features.
    public static func duplicateIds(features: [any GamificationFeature]) -> [String] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for id in (AchievementCatalog.all + features.flatMap { $0.badges }).map(\.id) {
            if !seen.insert(id).inserted, !duplicates.contains(id) {
                duplicates.append(id)
            }
        }
        return duplicates
    }

    static func merge(_ core: [AchievementDefinition], _ extra: [AchievementDefinition]) -> [AchievementDefinition] {
        var seen = Set<String>()
        var result: [AchievementDefinition] = []
        result.reserveCapacity(core.count + extra.count)
        for definition in core + extra where seen.insert(definition.id).inserted {
            result.append(definition)
        }
        return result
    }
}

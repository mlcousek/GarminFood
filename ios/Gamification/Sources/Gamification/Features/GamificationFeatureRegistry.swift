// GamificationFeatureRegistry.swift
//
// The ONE list of gamification features (design D7). All eight planned
// features are pre-registered here, each pointing at a stub type in its own
// folder, so the six wave-2 changes and wave 3 only replace their stub
// file's contents and never edit this file (the "Wave plan & file
// ownership" rule; the single tolerated exception is one appended line).
//
// Order is fixed (it is the order features run in and the order the app's
// Progress slots appear in): bingo, seasonal, collections, journeys,
// records, secrets, sport & body, boss, then the optional supplements
// feature (add-supplements, appended -- the one tolerated line).
//
// Each feature gets its own directory `<directory>/<featureId>/` for its
// JSON stores.
//
// Depends on: GamificationFeature and the eight feature types.
// Depended on by: BadgeRegistry, the app's FeatureHost.

import Foundation

public enum GamificationFeatureRegistry {
    /// Feature ids in run order.
    public static let orderedIds: [String] = [
        WeeklyBingoFeature.id,
        SeasonalEventsFeature.id,
        FoodCollectionsFeature.id,
        JourneysFeature.id,
        PersonalRecordsFeature.id,
        SecretAchievementsFeature.id,
        SportAndBodyFeature.id,
        WeeklyBossFeature.id,
        // add-supplements D9: optional (off by default); does nothing
        // until the host passes an active supplement digest.
        SupplementsFeature.id,
    ]

    /// `<Gamification storage>/features/`.
    public static func defaultDirectory() -> URL {
        GamificationStorage.directory().appendingPathComponent("features", isDirectory: true)
    }

    /// One fresh instance per feature, in `orderedIds` order. Create once
    /// per process (the app's FeatureHost) -- features are actors that own
    /// their stores.
    public static func makeAll(directory: URL = defaultDirectory()) -> [any GamificationFeature] {
        func dir(_ id: String) -> URL {
            directory.appendingPathComponent(id, isDirectory: true)
        }
        return [
            WeeklyBingoFeature(directory: dir(WeeklyBingoFeature.id)),
            SeasonalEventsFeature(directory: dir(SeasonalEventsFeature.id)),
            FoodCollectionsFeature(directory: dir(FoodCollectionsFeature.id)),
            JourneysFeature(directory: dir(JourneysFeature.id)),
            PersonalRecordsFeature(directory: dir(PersonalRecordsFeature.id)),
            SecretAchievementsFeature(directory: dir(SecretAchievementsFeature.id)),
            SportAndBodyFeature(directory: dir(SportAndBodyFeature.id)),
            WeeklyBossFeature(directory: dir(WeeklyBossFeature.id)),
            SupplementsFeature(directory: dir(SupplementsFeature.id)),
        ]
    }
}

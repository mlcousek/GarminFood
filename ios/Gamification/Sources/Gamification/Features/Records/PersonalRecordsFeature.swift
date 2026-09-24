// PersonalRecordsFeature.swift
//
// STUB registered by add-gamification-signals (design D7 "Registration"):
// the "records" feature slot. `add-journeys-and-records` replaces this file's contents
// (and may add sibling files in this folder); it does not need to touch
// `GamificationFeatureRegistry`, which already creates this type with
// `init(directory:)`.
//
// Until then it grants nothing, unlocks nothing and declares no badges.
// Its JSON stores belong under `directory` (<features dir>/records/).
//
// Depends on: GamificationFeature. Depended on by: GamificationFeatureRegistry.

import Foundation

public actor PersonalRecordsFeature: GamificationFeature {
    public static let id = "records"

    public nonisolated var featureId: String { Self.id }
    public nonisolated var badges: [AchievementDefinition] { [] }

    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func update(_ context: FeatureContext) async -> FeatureUpdate {
        .empty
    }
}

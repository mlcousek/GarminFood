// WeeklyBingoFeature.swift
//
// STUB registered by add-gamification-signals (design D7 "Registration"):
// the "bingo" feature slot. `add-weekly-bingo` replaces this file's contents
// (and may add sibling files in this folder); it does not need to touch
// `GamificationFeatureRegistry`, which already creates this type with
// `init(directory:)`.
//
// Until then it grants nothing, unlocks nothing and declares no badges.
// Its JSON stores belong under `directory` (<features dir>/bingo/).
//
// Depends on: GamificationFeature. Depended on by: GamificationFeatureRegistry.

import Foundation

public actor WeeklyBingoFeature: GamificationFeature {
    public static let id = "bingo"

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

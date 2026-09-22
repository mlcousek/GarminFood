// AchievementRarity.swift
//
// Badge-medallion "how rare is this" grade for AchievementsView (owner ask:
// "badges with images, tiers" -- see GarminFood/DesignSystem/BadgeMedallion
// .swift's header for why there's no literal image asset). Deliberately a
// PURE function of the achievement's own `AchievementCondition`, not a
// hand-authored field on all 120+ `AchievementDefinition`s in the catalog:
// at this size, a hand-maintained rarity would inevitably drift out of sync
// the next time someone tweaks a threshold. Deriving it here means rarity
// can never disagree with how hard the achievement actually is, and it
// needs zero changes to `AchievementStore`'s persistence (which only ever
// stores id -> unlock date, and still does -- see that file).

import Foundation

public enum AchievementRarity: Int, Sendable, Equatable, Hashable, CaseIterable, Comparable {
    case common, uncommon, rare, epic, legendary

    public static func < (lhs: AchievementRarity, rhs: AchievementRarity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var displayName: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .epic: return "Epic"
        case .legendary: return "Legendary"
        }
    }

    /// Buckets `value` against three ascending breakpoints, each marking
    /// the start of the next grade up from `.common`.
    private static func bucket(_ value: Double, uncommon: Double, rare: Double, epic: Double, legendary: Double) -> AchievementRarity {
        if value >= legendary { return .legendary }
        if value >= epic { return .epic }
        if value >= rare { return .rare }
        if value >= uncommon { return .uncommon }
        return .common
    }

    /// Derives a rarity purely from how hard `condition` is to satisfy.
    /// Breakpoints are hand-tuned per condition family against the actual
    /// numbers in `AchievementCatalog` (see `AchievementRarityTests` for
    /// worked examples) so the five grades spread roughly evenly across
    /// each family rather than clustering at one end.
    public static func derive(from condition: AchievementCondition) -> AchievementRarity {
        switch condition {
        case .streakAtLeast(let days):
            return bucket(Double(days), uncommon: 14, rare: 60, epic: 180, legendary: 500)
        case .levelAtLeast(let level):
            return bucket(Double(level), uncommon: 10, rare: 30, epic: 75, legendary: 150)
        case .totalLogsAtLeast(let count):
            return bucket(Double(count), uncommon: 50, rare: 250, epic: 1000, legendary: 5000)
        case .distinctFoodsAtLeast(let count):
            return bucket(Double(count), uncommon: 10, rare: 50, epic: 200, legendary: 500)
        case .challengesCompletedAtLeast(let count):
            return bucket(Double(count), uncommon: 5, rare: 25, epic: 50, legendary: 100)
        case .allChallengesCompleted:
            // Every template in the whole catalog, at least once -- the
            // hardest single condition in the catalog by construction.
            return .legendary
        case .dailyChallengesCompletedAtLeast(let count):
            return bucket(Double(count), uncommon: 10, rare: 100, epic: 250, legendary: 1000)
        case .goalHitDaysAtLeast(_, let count):
            return bucket(Double(count), uncommon: 50, rare: 100, epic: 365, legendary: 730)
        case .singleDayCaloriesAtLeast(let calories):
            return bucket(calories, uncommon: 4000, rare: 6000, epic: 8000, legendary: 10000)
        case .totalCaloriesAtLeast(let calories):
            return bucket(calories, uncommon: 50_000, rare: 500_000, epic: 3_000_000, legendary: 15_000_000)
        case .perfectCalendarMonth, .loggedOnLeapDay, .loggedOnNewYearsDay, .loggedAtMidnight:
            // Each is a genuinely rare, date/behavior-gated one-off rather
            // than a scalable count -- fixed at `.rare` rather than bucketed.
            return .rare
        case .anniversaryYears(let years):
            return bucket(Double(years), uncommon: 1, rare: 2, epic: 3, legendary: 4)
        case .unlockedFractionOfOthers(let fraction):
            // Meta/completionist achievements are always at least `.rare`
            // (unlocking a QUARTER of a 100+ item catalog is no small
            // thing), scaling up to `.legendary` at full completion.
            if fraction >= 1.0 { return .legendary }
            if fraction >= 0.5 { return .epic }
            return .rare
        }
    }
}

// XPBudget.swift
//
// rebalance-xp-economy design D2: the levelling pace as an explicit, tested
// budget instead of a hand-tuned guess. Every XP source has ONE line with
// its expected long-run XP per day for a typical active user (the reward
// constant times an assumed frequency, commented per line). The sum of the
// always-on lines (`coreDailyXP`) is what `LevelCurve.growthFactor` is
// solved against: level 84 after 1,095 days (design D1). XPBudgetTests
// pins the literal in LevelCurve to `solveGrowthFactor(...)`, so changing a
// reward constant here, or adding a feature, without re-solving fails CI
// with the value to paste.
//
// Optional sources (design D4, e.g. supplements) are NOT part of the curve.
// While enabled, their grants are scaled by `optionalMultiplier`,
// m = min(1, 0.005 x core / enabled optional), so that together they add at
// most `optionalPaceAllowance` (0.5%) of the core budget, and turning a
// feature on can't speed levelling up. The feature applies it itself when
// it fills its `RewardGrant.xp`:
// `XPBudget.optionalGrantXP(amount, enabledOptionalSources: ...)`, i.e.
// `scaledGrant(amount, multiplier: optionalMultiplier(...))`. A grant never
// scales below 1 XP, so an optional source should pay at most about one
// grant a day; its own test runs the +-1% simulation from XPBudgetTests.
//
// Pure: no I/O, no state.
//
// Depends on: XPAward (+Features), BossFight, SeasonalEventCatalog,
// LevelCurve (base XP), the feature ids in GamificationFeatureRegistry.
// Depended on by: XPBudgetTests (pins LevelCurve.growthFactor); optional
// features such as supplements (multiplier).

import Foundation

public struct XPBudgetLine: Sendable, Equatable {
    /// A core source name ("log", "streak", ...) or a gamification feature
    /// id (`GamificationFeatureRegistry.orderedIds`): exactly one line each.
    public let source: String
    /// Long-run average XP per day for a typical active user.
    public let expectedDailyXP: Double
    /// Off by default and user-enabled (design D4): excluded from
    /// `coreDailyXP`, scaled by `optionalMultiplier` while enabled.
    public let optional: Bool

    public init(source: String, expectedDailyXP: Double, optional: Bool = false) {
        self.source = source
        self.expectedDailyXP = expectedDailyXP
        self.optional = optional
    }
}

public enum XPBudget {
    // MARK: - Pace target (design D1)

    /// Level 84 after three years of a typical active day: the 2026-09-18
    /// promise.
    public static let targetLevel = 84
    public static let targetDays = 1_095

    // MARK: - Frequency units

    private static let week = 7.0
    private static let month = 365.0 / 12.0
    private static let year = 365.0
    private static let threeYears = 1_095.0

    /// Assumed rotation-weighted mean reward of a long-running challenge.
    /// XPBudgetTests checks it against `ChallengeCatalog.all` weighted by
    /// `ChallengeRotationPolicy.staticWeight` (±10%; ≈ 84 on 2026-09-25).
    public static let assumedMeanChallengeReward = 85.0

    /// Badge XP of a feature: `count` unlocks spread over three years, each
    /// paying the generic `achievementBonus` (FeatureHost).
    private static func badgeXP(_ count: Double) -> Double {
        Double(XPAward.achievementBonus) * count / threeYears
    }

    // MARK: - The table (design D3; one line per source)

    public static let lines: [XPBudgetLine] = [
        // --- core, always on ---
        // flatPerLog (10) x 3.5 entries a day.
        XPBudgetLine(source: "log", expectedDailyXP: Double(XPAward.flatPerLog) * 3.5),
        // streakExtensionBonus (20) on every active day.
        XPBudgetLine(source: "streak", expectedDailyXP: Double(XPAward.streakExtensionBonus) * 1.0),
        // goalHitBonus (25) on 60% of days.
        XPBudgetLine(source: "goal", expectedDailyXP: Double(XPAward.goalHitBonus) * 0.6),
        // dailyChallengeBonus (15), two a day, 60% completed.
        XPBudgetLine(source: "dailyChallenge", expectedDailyXP: Double(XPAward.dailyChallengeBonus) * 2 * 0.6),
        // One challenge slot, ~7-day windows: a completion every 9 days at
        // the rotation-weighted mean reward.
        XPBudgetLine(source: "challenge", expectedDailyXP: assumedMeanChallengeReward / 9),
        // achievementBonus (30) for ~15 core badge unlocks a year.
        XPBudgetLine(source: "achievement", expectedDailyXP: Double(XPAward.achievementBonus) * 15 / year),

        // --- wave-2 features (GamificationFeatureRegistry), always on ---
        // bingoLine (25) 1.5 lines a week; bingoFullCard (150) once in 8
        // weeks; 6 badges.
        XPBudgetLine(
            source: WeeklyBingoFeature.id,
            expectedDailyXP: Double(XPAward.bingoLine) * 1.5 / week
                + Double(XPAward.bingoFullCard) / (8 * week)
                + badgeXP(6)
        ),
        // seasonalEventCompleted (50) for 6 of the 12 events a year;
        // bonusQuestXP (25) for 3 of the 8 bonus quests a year; 10 badges.
        XPBudgetLine(
            source: SeasonalEventsFeature.id,
            expectedDailyXP: (Double(XPAward.seasonalEventCompleted) * 6
                + Double(SeasonalEventCatalog.bonusQuestXP) * 3) / year
                + badgeXP(10)
        ),
        // collectionDiscovery (5) once every two weeks (85 entries, a
        // declining rate); 6 badges.
        XPBudgetLine(
            source: FoodCollectionsFeature.id,
            expectedDailyXP: Double(XPAward.collectionDiscovery) * 0.5 / week + badgeXP(6)
        ),
        // journeyMilestone (40): ~40 of the 44 milestones in three years
        // (~1 a month); 8 badges.
        XPBudgetLine(
            source: JourneysFeature.id,
            expectedDailyXP: Double(XPAward.journeyMilestone) * 40 / threeYears + badgeXP(8)
        ),
        // personalRecord (20): ~3 PRs a month; 3 badges.
        XPBudgetLine(
            source: PersonalRecordsFeature.id,
            expectedDailyXP: Double(XPAward.personalRecord) * 3 / month + badgeXP(3)
        ),
        // secretUnlocked (50) + the badge bonus: 12 of the 16 secrets in
        // three years.
        XPBudgetLine(
            source: SecretAchievementsFeature.id,
            expectedDailyXP: Double(XPAward.secretUnlocked + XPAward.achievementBonus) * 12 / threeYears
        ),
        // sportBadge (0) + the badge bonus: 10 badges in three years.
        XPBudgetLine(
            source: SportAndBodyFeature.id,
            expectedDailyXP: Double(XPAward.sportBadge + XPAward.achievementBonus) * 10 / threeYears
        ),
        // Boss defeat XP (150 + 25 per target day above 3) at a typical
        // target of 5, won every other week; 6 badges.
        XPBudgetLine(
            source: WeeklyBossFeature.id,
            expectedDailyXP: Double(BossFight.defeatXP(target: 5)) * 0.5 / week + badgeXP(6)
        ),

        // --- optional sources (design D4) ---
        // add-supplements adds its line here (optional: true).
    ]

    // MARK: - Sums

    /// Expected XP/day of a typical active day from the always-on sources:
    /// what the level curve is solved against.
    public static var coreDailyXP: Double {
        dailyXP(of: lines)
    }

    /// Sum of `lines`' non-optional lines, plus the optional lines whose
    /// source is in `enabledOptionalSources` (unscaled).
    public static func dailyXP(of lines: [XPBudgetLine], enabledOptionalSources: Set<String> = []) -> Double {
        lines.reduce(0.0) { sum, line in
            guard !line.optional || enabledOptionalSources.contains(line.source) else { return sum }
            return sum + line.expectedDailyXP
        }
    }

    // MARK: - Solving the curve (design D2)

    /// XP to go from level 1 to `targetLevel` on an unrounded geometric
    /// curve with `LevelCurve.baseXPForFirstLevelUp`.
    public static func cumulativeXP(toReach targetLevel: Int, growthFactor: Double) -> Double {
        guard targetLevel > 1 else { return 0 }
        var total = 0.0
        var band = LevelCurve.baseXPForFirstLevelUp
        for _ in 1..<targetLevel {
            total += band
            band *= growthFactor
        }
        return total
    }

    /// The growth factor in [1.0, 1.2] at which `days` x `dailyXP` reaches
    /// exactly `targetLevel`. Bisection, run to far below the 0.1% the
    /// design asks for, so the result is stable. Clamps to the interval's
    /// ends when the target lies outside it.
    public static func solveGrowthFactor(targetLevel: Int, days: Int, dailyXP: Double) -> Double {
        let wanted = Double(days) * dailyXP
        var low = 1.0
        var high = 1.2
        for _ in 0..<200 {
            let mid = (low + high) / 2
            let reached = cumulativeXP(toReach: targetLevel, growthFactor: mid)
            if abs(reached - wanted) <= wanted * 1e-9 { return mid }
            if reached < wanted {
                low = mid
            } else {
                high = mid
            }
            if high - low < 1e-12 { break }
        }
        return (low + high) / 2
    }

    /// The factor the table asks for: what `LevelCurve.growthFactor` must
    /// equal (to 1e-4).
    public static var solvedGrowthFactor: Double {
        solveGrowthFactor(targetLevel: targetLevel, days: targetDays, dailyXP: coreDailyXP)
    }

    /// Days a typical active day needs to reach `level` on the live curve
    /// (`LevelCurve.threshold`, rounded bands).
    public static func daysToReach(level: Int, dailyXP: Double = coreDailyXP) -> Double {
        guard dailyXP > 0 else { return .infinity }
        return Double(LevelCurve.threshold(forLevel: level)) / dailyXP
    }

    // MARK: - Optional sources (design D4)

    /// How much optional sources may add together, as a share of the core
    /// budget: 0.5%, so the days to level 84 stay within ±1%.
    public static let optionalPaceAllowance = 0.005

    /// The multiplier for XP granted by any enabled optional source: 1 when
    /// the enabled lines fit the allowance, otherwise the factor that
    /// shrinks them to it.
    public static func optionalMultiplier(
        enabledOptionalSources: Set<String>,
        lines: [XPBudgetLine] = XPBudget.lines
    ) -> Double {
        let core = dailyXP(of: lines)
        let optional = lines
            .filter { $0.optional && enabledOptionalSources.contains($0.source) }
            .reduce(0.0) { $0 + $1.expectedDailyXP }
        guard optional > 0 else { return 1 }
        return min(1, optionalPaceAllowance * core / optional)
    }

    /// The XP an optional source should put in its `RewardGrant.xp`:
    /// `xp` scaled by the multiplier for the currently enabled optional
    /// sources (`RewardLedger` then applies it as-is).
    public static func optionalGrantXP(_ xp: Int, enabledOptionalSources: Set<String>) -> Int {
        scaledGrant(xp, multiplier: optionalMultiplier(enabledOptionalSources: enabledOptionalSources))
    }

    /// `xp` x `multiplier`, rounded, at least 1 for a positive grant (a
    /// grant never silently pays nothing); 0 for a non-positive `xp`.
    public static func scaledGrant(_ xp: Int, multiplier: Double) -> Int {
        guard xp > 0 else { return 0 }
        let scaled = (Double(xp) * max(0, min(1, multiplier))).rounded()
        return max(1, Int(scaled))
    }
}

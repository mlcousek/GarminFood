// XPBudget.swift
//
// rebalance-xp-economy design D2: the levelling pace as an explicit, tested
// budget instead of a hand-tuned guess. Every XP source has ONE line with
// its expected long-run XP per day for a typical active user (the reward
// constant times an assumed frequency, commented per line). The sum of the
// always-on lines is `coreDailyXP` (the food economy, ~128).
//
// add-training-gamification-and-150-levels D2: the training experience has
// XP sources of its own. They are the `training` line (`trainingOnly`), the
// sum of `TrainingXPBudget.lines` (~65), and `LevelCurve.growthFactor` is
// now solved against `typicalDailyXP` = core + training (~193): level 150
// after 1,540 days. XPBudgetTests pins the literal in LevelCurve to
// `solveGrowthFactor(...)`, so changing a reward constant here, or adding a
// feature, without re-solving fails CI with the value to paste. The
// food-first experience uses the same curve with the core alone, so it
// reaches level 150 later (~6.4 years). `scenarios` holds the same lines
// for a poor week and a perfect week; they only describe the 3-5 year
// range. `tools/level-curve-model.mjs` mirrors both tables.
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
// LevelCurve (base XP), the feature ids in GamificationFeatureRegistry,
// TrainingXPBudget (the training line).
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
    /// Paid only in the training experience
    /// (add-training-gamification-and-150-levels D2): excluded from
    /// `coreDailyXP`, part of `typicalDailyXP`, never scaled.
    public let trainingOnly: Bool

    public init(source: String, expectedDailyXP: Double, optional: Bool = false, trainingOnly: Bool = false) {
        self.source = source
        self.expectedDailyXP = expectedDailyXP
        self.optional = optional
        self.trainingOnly = trainingOnly
    }
}

/// One always-on source's expected XP per day in a poor week and in a
/// perfect week (the typical value is its `XPBudgetLine`).
public struct XPBudgetScenarioLine: Sendable, Equatable {
    public let source: String
    public let poorDailyXP: Double
    public let perfectDailyXP: Double

    public init(source: String, poor: Double, perfect: Double) {
        self.source = source
        self.poorDailyXP = poor
        self.perfectDailyXP = perfect
    }
}

public enum XPBudget {
    // MARK: - Pace target (design D1)

    /// add-training-gamification-and-150-levels D1: level 150 -- the last
    /// one -- after 1,540 days (4.2 years) of a typical consistent day in
    /// the training experience. Until 2026-10-01 the target was level 84
    /// after 1,095 days of the food economy alone.
    public static let targetLevel = 150
    public static let targetDays = 1_540

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
        // add-supplements D9: supplementStackComplete (6) on 85% of days;
        // creatine-journey milestones (journeyMilestone, 40) -- 5 in three
        // years; 10 badges. ~5.6 XP/day before the multiplier. Every grant
        // it makes is scaled by `optionalMultiplier` (the badge bonus too,
        // in the app's FeatureHost), so this line never moves the curve.
        XPBudgetLine(
            source: SupplementsFeature.id,
            expectedDailyXP: Double(XPAward.supplementStackComplete) * 0.85
                + Double(XPAward.journeyMilestone) * 5 / threeYears
                + badgeXP(10),
            optional: true
        ),

        // --- the training experience (trainingOnly) ---
        // add-training-gamification-and-150-levels D2: check-ins, habits,
        // sessions within the light, kept days and weeks, phases, races and
        // the training badges -- the sum of TrainingXPBudget.lines (one
        // sub-line per source, ~65 XP/day). Paid only in the training
        // experience, in full: it was an optional, scaled badge line until
        // 2026-10-01; now it is part of what the curve is solved against.
        XPBudgetLine(
            source: TrainingRewardsFeature.id,
            expectedDailyXP: TrainingXPBudget.typicalDailyXP,
            trainingOnly: true
        ),
    ]

    // MARK: - Scenarios (add-training-gamification-and-150-levels D3)

    /// The always-on lines in a poor week (food logged on 4 of 7 days, one
    /// goal day in five, no boss) and in a perfect one (everything, every
    /// day). One entry per always-on line (XPBudgetTests checks it).
    public static let scenarios: [XPBudgetScenarioLine] = {
        // One statement per number (cheap to type-check).
        let perLog = Double(XPAward.flatPerLog)
        let streak = Double(XPAward.streakExtensionBonus)
        let goal = Double(XPAward.goalHitBonus)
        let daily = Double(XPAward.dailyChallengeBonus)
        let badge = Double(XPAward.achievementBonus)
        let bingoLine = Double(XPAward.bingoLine)
        let bingoCard = Double(XPAward.bingoFullCard)
        let event = Double(XPAward.seasonalEventCompleted)
        let quest = Double(SeasonalEventCatalog.bonusQuestXP)
        let discovery = Double(XPAward.collectionDiscovery)
        let milestone = Double(XPAward.journeyMilestone)
        let record = Double(XPAward.personalRecord)
        let secret = Double(XPAward.secretUnlocked + XPAward.achievementBonus)
        let sport = Double(XPAward.sportBadge + XPAward.achievementBonus)
        let bossAtSix = Double(BossFight.defeatXP(target: 6))

        // 2.5 entries on 4 days of 7 / 4.5 entries every day.
        let logPoor: Double = perLog * 2.5 * 4.0 / week
        let logPerfect: Double = perLog * 4.5
        let streakPoor: Double = streak * 4.0 / week
        let goalPoor: Double = goal * 0.2
        let dailyPoor: Double = daily * 2.0 * 0.15
        let dailyPerfect: Double = daily * 2.0
        // A completion every three weeks / every 7.5 days.
        let challengePoor: Double = assumedMeanChallengeReward / 21.0
        let challengePerfect: Double = assumedMeanChallengeReward / 7.5
        let achievementPoor: Double = badge * 6.0 / year
        let achievementPerfect: Double = badge * 20.0 / year
        // Half a line a week / three lines a week and a full card every
        // third week, all seven badges.
        let bingoPoor: Double = bingoLine * 0.5 / week
        let bingoPerfect: Double = bingoLine * 3.0 / week + bingoCard / (3.0 * week) + badgeXP(7)
        // Two events a year / all twelve and all eight bonus quests.
        let seasonalPoor: Double = event * 2.0 / year
        let seasonalPerfect: Double = (event * 12.0 + quest * 8.0) / year + badgeXP(10)
        let collectionsPoor: Double = discovery * 0.2 / week
        let collectionsPerfect: Double = discovery * 1.0 / week + badgeXP(6)
        let journeysPoor: Double = milestone * 20.0 / threeYears
        let journeysPerfect: Double = milestone * 44.0 / threeYears + badgeXP(8)
        let recordsPoor: Double = record * 1.0 / month
        let recordsPerfect: Double = record * 4.0 / month + badgeXP(3)
        let secretsPoor: Double = secret * 4.0 / threeYears
        let secretsPerfect: Double = secret * 16.0 / threeYears
        let sportPoor: Double = sport * 3.0 / threeYears
        let sportPerfect: Double = sport * 14.0 / threeYears
        // No boss beaten / one every week at a target of 6, seven badges.
        let bossPerfect: Double = bossAtSix / week + badgeXP(7)

        return [
            XPBudgetScenarioLine(source: "log", poor: logPoor, perfect: logPerfect),
            XPBudgetScenarioLine(source: "streak", poor: streakPoor, perfect: streak),
            XPBudgetScenarioLine(source: "goal", poor: goalPoor, perfect: goal),
            XPBudgetScenarioLine(source: "dailyChallenge", poor: dailyPoor, perfect: dailyPerfect),
            XPBudgetScenarioLine(source: "challenge", poor: challengePoor, perfect: challengePerfect),
            XPBudgetScenarioLine(source: "achievement", poor: achievementPoor, perfect: achievementPerfect),
            XPBudgetScenarioLine(source: WeeklyBingoFeature.id, poor: bingoPoor, perfect: bingoPerfect),
            XPBudgetScenarioLine(source: SeasonalEventsFeature.id, poor: seasonalPoor, perfect: seasonalPerfect),
            XPBudgetScenarioLine(source: FoodCollectionsFeature.id, poor: collectionsPoor, perfect: collectionsPerfect),
            XPBudgetScenarioLine(source: JourneysFeature.id, poor: journeysPoor, perfect: journeysPerfect),
            XPBudgetScenarioLine(source: PersonalRecordsFeature.id, poor: recordsPoor, perfect: recordsPerfect),
            XPBudgetScenarioLine(source: SecretAchievementsFeature.id, poor: secretsPoor, perfect: secretsPerfect),
            XPBudgetScenarioLine(source: SportAndBodyFeature.id, poor: sportPoor, perfect: sportPerfect),
            XPBudgetScenarioLine(source: WeeklyBossFeature.id, poor: 0, perfect: bossPerfect),
        ]
    }()

    /// Whether `source` is an optional source (design D4): its grants --
    /// and the host's badge bonus for its badges -- go through
    /// `optionalGrantXP`.
    public static func isOptional(source: String) -> Bool {
        lines.contains { $0.source == source && $0.optional }
    }

    // MARK: - Sums

    /// Expected XP/day of a typical active day from the always-on FOOD
    /// sources (~128). The optional-source allowance refers to it, and it
    /// is the whole budget of the food-first experience.
    public static var coreDailyXP: Double {
        dailyXP(of: lines)
    }

    /// Expected XP/day of the training experience's own sources (~65).
    public static var trainingDailyXP: Double {
        lines.reduce(0.0) { $0 + ($1.trainingOnly ? $1.expectedDailyXP : 0) }
    }

    /// A typical consistent day in the training experience (~193): what the
    /// level curve is solved against.
    public static var typicalDailyXP: Double {
        coreDailyXP + trainingDailyXP
    }

    /// A poor week's XP/day in the training experience (~74).
    public static var poorDailyXP: Double {
        scenarios.reduce(0.0) { $0 + $1.poorDailyXP } + TrainingXPBudget.poorDailyXP
    }

    /// A perfect week's XP/day in the training experience (~278).
    public static var perfectDailyXP: Double {
        scenarios.reduce(0.0) { $0 + $1.perfectDailyXP } + TrainingXPBudget.perfectDailyXP
    }

    /// Sum of `lines`' always-on lines, plus the optional lines whose
    /// source is in `enabledOptionalSources` (unscaled). Training-only
    /// lines are never part of it.
    public static func dailyXP(of lines: [XPBudgetLine], enabledOptionalSources: Set<String> = []) -> Double {
        lines.reduce(0.0) { sum, line in
            guard !line.trainingOnly else { return sum }
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
        solveGrowthFactor(targetLevel: targetLevel, days: targetDays, dailyXP: typicalDailyXP)
    }

    /// Days of `dailyXP` needed to reach `level` on the live curve
    /// (`LevelCurve.threshold`, rounded bands). The default is the food
    /// core alone (the food-first experience); pass `typicalDailyXP` for
    /// the training experience.
    public static func daysToReach(level: Int, dailyXP: Double = coreDailyXP) -> Double {
        guard dailyXP > 0 else { return .infinity }
        return Double(LevelCurve.threshold(forLevel: level)) / dailyXP
    }

    // MARK: - Optional sources (design D4)

    /// How much optional sources may add together, as a share of the core
    /// budget: 0.5%, so the days to any level stay within ±1%.
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

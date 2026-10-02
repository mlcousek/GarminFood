// XPBudgetTests.swift
//
// rebalance-xp-economy tasks 3.1, 3.2 and 3.4 (design D1, D2, D4): the XP
// budget table, the growth-factor solver, the literal in `LevelCurve` that
// must match it, the pace checks, one budget line per registered feature,
// and the optional-source allowance. The curve migrations are in
// XPCurveMigrationTests.
//
// add-training-gamification-and-150-levels D1-D3: the target is level 150
// after 1,540 days of a typical TRAINING-experience day (the food core plus
// the training lines), the three scenario totals are pinned to the numbers
// tools/level-curve-model.mjs prints, and the training lines stay smaller
// than the food core.
//
// Depends on: XPBudget, LevelCurve, GamificationFeatureRegistry,
// ChallengeCatalog + ChallengeRotationPolicy (mean challenge reward).

import XCTest
@testable import Gamification

final class XPBudgetTests: XCTestCase {
    private var core: Double { XPBudget.coreDailyXP }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("xp-budget-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: - 3.1 Solver

    func testSolverRoundTripsKnownCurves() {
        for factor in [1.03, 1.045, 1.0505, 1.06, 1.08] {
            let daily = XPBudget.cumulativeXP(toReach: 84, growthFactor: factor) / 1_095
            let solved = XPBudget.solveGrowthFactor(targetLevel: 84, days: 1_095, dailyXP: daily)
            XCTAssertEqual(solved, factor, accuracy: 1e-6, "round trip of \(factor)")
        }
    }

    func testSolverIsMonotonicInDailyXP() {
        let dailies: [Double] = [50, 75, 100, 128, 160, 200]
        let factors = dailies.map { XPBudget.solveGrowthFactor(targetLevel: 84, days: 1_095, dailyXP: $0) }
        for (lower, higher) in zip(factors, factors.dropFirst()) {
            XCTAssertLessThan(lower, higher, "more XP a day must allow a steeper curve")
        }
    }

    func testSolvedFactorHitsTheTargetWithinTheTolerance() {
        let wanted = Double(XPBudget.targetDays) * XPBudget.typicalDailyXP
        let reached = XPBudget.cumulativeXP(toReach: XPBudget.targetLevel, growthFactor: XPBudget.solvedGrowthFactor)
        XCTAssertEqual(reached, wanted, accuracy: wanted * 0.001)
    }

    func testGrowthFactorMatchesBudget() {
        let solved = XPBudget.solvedGrowthFactor
        XCTAssertEqual(
            LevelCurve.growthFactor,
            solved,
            accuracy: 1e-4,
            "XPBudget changed: set LevelCurve.growthFactor to \(String(format: "%.5f", solved)) (typical \(String(format: "%.2f", XPBudget.typicalDailyXP)) XP/day) and update tools/level-curve-model.mjs"
        )
    }

    // MARK: - Pace (add-training-gamification-and-150-levels D1, D3)

    private var typical: Double { XPBudget.typicalDailyXP }

    func testTargetIsLevel150After1540Days() {
        XCTAssertEqual(XPBudget.targetLevel, LevelCurve.maxLevel)
        XCTAssertEqual(XPBudget.targetLevel, 150)
        XCTAssertEqual(XPBudget.targetDays, 1_540)
    }

    func testTypicalDayReachesLevel150InAboutFourYears() {
        let days = XPBudget.daysToReach(level: 150, dailyXP: typical)
        XCTAssertGreaterThanOrEqual(days, 1_525, "level 150 after \(days) days")
        XCTAssertLessThanOrEqual(days, 1_555, "level 150 after \(days) days")
    }

    func testTypicalDayReachesLevel10WithinThreeWeeks() {
        let days = XPBudget.daysToReach(level: 10, dailyXP: typical)
        XCTAssertGreaterThanOrEqual(days, 3, "level 10 after \(days) days")
        XCTAssertLessThanOrEqual(days, 21, "level 10 after \(days) days")
    }

    func testNoLevelTakesMoreThanEightWeeksOfTypicalPlay() {
        var slowest = 0.0
        for level in 1..<LevelCurve.maxLevel {
            slowest = max(slowest, Double(LevelCurve.xpRequired(afterLevel: level)) / typical)
        }
        XCTAssertLessThanOrEqual(slowest, 56, "the slowest level takes \(slowest) typical days")
        XCTAssertGreaterThan(slowest, 28, "the late game should not be trivial either")
    }

    /// The owner's range, "about 3 to 5 years": perfect play every single
    /// day is the floor, three typical weeks and a poor one the ceiling.
    func testPerfectAndMixedPlayStayInsideThreeToFiveYears() {
        let perfect = XPBudget.daysToReach(level: 150, dailyXP: XPBudget.perfectDailyXP)
        XCTAssertGreaterThanOrEqual(perfect, 2.9 * 365.25, "perfect play: \(perfect) days")
        XCTAssertLessThan(perfect, XPBudget.daysToReach(level: 150, dailyXP: typical))
        let mixedDaily = (3 * typical + XPBudget.poorDailyXP) / 4
        let mixed = XPBudget.daysToReach(level: 150, dailyXP: mixedDaily)
        XCTAssertLessThanOrEqual(mixed, 5 * 365.25, "three typical weeks and a poor one: \(mixed) days")
    }

    /// Food-first keeps the same curve with its own, unchanged budget, so
    /// it takes longer (design D2: about 6.4 years).
    func testFoodFirstAloneReachesLevel150Later() {
        let days = XPBudget.daysToReach(level: 150)
        XCTAssertGreaterThan(days, 2_200)
        XCTAssertLessThan(days, 2_450)
    }

    /// The numbers tools/level-curve-model.mjs prints: when a reward or a
    /// frequency changes, both tables change together.
    func testScenarioTotalsMatchTheModel() {
        XCTAssertEqual(core, 128.036, accuracy: 0.05)
        XCTAssertEqual(XPBudget.trainingDailyXP, 64.907, accuracy: 0.05)
        XCTAssertEqual(XPBudget.typicalDailyXP, 192.944, accuracy: 0.05)
        XCTAssertEqual(XPBudget.poorDailyXP, 73.776, accuracy: 0.05)
        XCTAssertEqual(XPBudget.perfectDailyXP, 277.540, accuracy: 0.05)
        XCTAssertEqual(XPBudget.trainingDailyXP, TrainingXPBudget.typicalDailyXP, accuracy: 1e-9)
    }

    func testEveryAlwaysOnLineHasOneScenarioLine() {
        let alwaysOn = XPBudget.lines.filter { !$0.optional && !$0.trainingOnly }
        XCTAssertEqual(XPBudget.scenarios.map(\.source), alwaysOn.map(\.source), "one scenario line per always-on line, same order")
        for line in alwaysOn {
            guard let scenario = XPBudget.scenarios.first(where: { $0.source == line.source }) else { continue }
            XCTAssertLessThanOrEqual(scenario.poorDailyXP, line.expectedDailyXP, line.source)
            XCTAssertGreaterThanOrEqual(scenario.perfectDailyXP, line.expectedDailyXP, line.source)
        }
        for line in TrainingXPBudget.lines {
            XCTAssertLessThanOrEqual(line.poorDailyXP, line.typicalDailyXP, line.source)
            XCTAssertGreaterThanOrEqual(line.perfectDailyXP, line.typicalDailyXP, line.source)
            XCTAssertGreaterThan(line.typicalDailyXP, 0, line.source)
        }
        let sources = TrainingXPBudget.lines.map(\.source)
        XCTAssertEqual(Set(sources).count, sources.count)
    }

    /// Design D2: food logging stays the larger half, and no single
    /// training source dominates.
    func testTrainingStaysSmallerThanTheFoodCore() throws {
        let line = try XCTUnwrap(XPBudget.lines.first { $0.source == TrainingRewardsFeature.id })
        XCTAssertTrue(line.trainingOnly)
        XCTAssertFalse(line.optional)
        XCTAssertFalse(XPBudget.isOptional(source: TrainingRewardsFeature.id), "training XP is real, not a scaled optional source")
        XCTAssertLessThanOrEqual(XPBudget.trainingDailyXP, 0.6 * core)
        for sub in TrainingXPBudget.lines {
            XCTAssertLessThanOrEqual(sub.typicalDailyXP, 0.15 * core, "training source '\(sub.source)' pays \(sub.typicalDailyXP) XP/day")
        }
        // The optional allowance still refers to the food core alone.
        XCTAssertEqual(XPBudget.dailyXP(of: XPBudget.lines), core, accuracy: 1e-9)
    }

    /// Nothing in the training budget is a volume or "more" reward: honest
    /// calls and the wise call are as frequent in perfect play as in
    /// typical play.
    func testHonestCallsAreNotMaximised() throws {
        for source in ["honestCall", "wiseCall", "gateTest"] {
            let line = try XCTUnwrap(TrainingXPBudget.lines.first { $0.source == source }, source)
            XCTAssertEqual(line.perfect, line.typical, accuracy: 1e-9, source)
        }
    }

    // MARK: - 3.2 Registry coverage and the table itself

    func testEveryRegisteredFeatureHasExactlyOneBudgetLine() {
        let ids = GamificationFeatureRegistry.makeAll(directory: tempDirectory()).map { $0.featureId }
        XCTAssertFalse(ids.isEmpty)
        for id in ids {
            let count = XPBudget.lines.filter { $0.source == id }.count
            XCTAssertEqual(count, 1, "feature '\(id)' needs exactly one XPBudget line, found \(count)")
        }
    }

    func testBudgetSourcesAreUniqueAndPositive() {
        let sources = XPBudget.lines.map(\.source)
        XCTAssertEqual(Set(sources).count, sources.count, "duplicate XPBudget sources: \(sources)")
        for line in XPBudget.lines {
            XCTAssertGreaterThan(line.expectedDailyXP, 0, line.source)
        }
    }

    func testNoWaveTwoFeatureExceedsAQuarterOfCore() {
        for id in GamificationFeatureRegistry.orderedIds {
            // The training line has its own share rule
            // (testTrainingStaysSmallerThanTheFoodCore).
            guard let line = XPBudget.lines.first(where: { $0.source == id }), !line.trainingOnly else { continue }
            XCTAssertLessThanOrEqual(
                line.expectedDailyXP,
                0.25 * core,
                "'\(id)' pays \(line.expectedDailyXP) XP/day, over 25% of \(core): lower its constants (design D3)"
            )
        }
    }

    func testAssumedMeanChallengeRewardMatchesTheRotation() {
        var weightedXP = 0.0
        var weights = 0.0
        for template in ChallengeCatalog.all {
            let weight = Double(ChallengeRotationPolicy.staticWeight(for: template))
            weightedXP += weight * Double(template.xpReward)
            weights += weight
        }
        XCTAssertGreaterThan(weights, 0)
        let mean = weightedXP / weights
        XCTAssertEqual(
            mean,
            XPBudget.assumedMeanChallengeReward,
            accuracy: XPBudget.assumedMeanChallengeReward * 0.1,
            "rotation-weighted mean challenge reward is \(mean): update assumedMeanChallengeReward"
        )
    }

    // MARK: - 3.4 Optional sources (design D4)

    private func linesWithOptional(_ dailyXP: Double, source: String = "test-optional") -> [XPBudgetLine] {
        XPBudget.lines + [XPBudgetLine(source: source, expectedDailyXP: dailyXP, optional: true)]
    }

    func testOptionalLinesStayOutOfTheCoreBudget() {
        let lines = linesWithOptional(10)
        XCTAssertEqual(XPBudget.dailyXP(of: lines), core, accuracy: 1e-9)
        XCTAssertEqual(XPBudget.dailyXP(of: lines, enabledOptionalSources: ["test-optional"]), core + 10, accuracy: 1e-9)
    }

    func testMultiplierIsOneWithoutEnabledOptionalSources() {
        let lines = linesWithOptional(10)
        XCTAssertEqual(XPBudget.optionalMultiplier(enabledOptionalSources: [], lines: lines), 1)
        XCTAssertEqual(XPBudget.optionalMultiplier(enabledOptionalSources: ["unknown"], lines: lines), 1)
        // A source that isn't in the shipped table is never scaled.
        XCTAssertEqual(XPBudget.optionalGrantXP(10, enabledOptionalSources: ["test-optional"]), 10)
    }

    func testMultiplierFollowsTheAllowance() {
        // Fits the 0.5% allowance: unscaled.
        let small = core * 0.004
        XCTAssertEqual(XPBudget.optionalMultiplier(enabledOptionalSources: ["test-optional"], lines: linesWithOptional(small)), 1)
        // Over it: m = 0.005 x core / optional.
        let multiplier = XPBudget.optionalMultiplier(enabledOptionalSources: ["test-optional"], lines: linesWithOptional(10))
        XCTAssertEqual(multiplier, 0.005 * core / 10, accuracy: 1e-12)
    }

    func testScaledGrant() {
        XCTAssertEqual(XPBudget.scaledGrant(10, multiplier: 1), 10)
        XCTAssertEqual(XPBudget.scaledGrant(10, multiplier: 0.25), 3)
        XCTAssertEqual(XPBudget.scaledGrant(10, multiplier: 0.01), 1, "a positive grant never pays nothing")
        XCTAssertEqual(XPBudget.scaledGrant(10, multiplier: 2), 10, "the multiplier never raises a grant")
        XCTAssertEqual(XPBudget.scaledGrant(0, multiplier: 1), 0)
        XCTAssertEqual(XPBudget.scaledGrant(-5, multiplier: 1), 0)
    }

    /// Simulates a typical day with one optional source enabled, paying at
    /// most one grant a day, and checks the days to the last level stay
    /// within ±1% of the core-only budget.
    func testOptionalSourceKeepsTheLastLevelWithinOnePercent() {
        let coreDays = XPBudget.daysToReach(level: XPBudget.targetLevel)
        // (grant XP, grants per day)
        let cases: [(grant: Int, perDay: Double)] = [(1, 1), (2, 1), (5, 1), (10, 1), (20, 1), (50, 1.0 / 7), (5, 0.5)]
        for (grant, perDay) in cases {
            let lines = linesWithOptional(Double(grant) * perDay)
            let multiplier = XPBudget.optionalMultiplier(enabledOptionalSources: ["test-optional"], lines: lines)
            let paid = Double(XPBudget.scaledGrant(grant, multiplier: multiplier)) * perDay
            let days = XPBudget.daysToReach(level: XPBudget.targetLevel, dailyXP: core + paid)
            XCTAssertEqual(
                days / coreDays,
                1,
                accuracy: 0.01,
                "grant \(grant) x \(perDay)/day pays \(paid) XP/day: the last level after \(days) days vs \(coreDays)"
            )
        }
    }
}

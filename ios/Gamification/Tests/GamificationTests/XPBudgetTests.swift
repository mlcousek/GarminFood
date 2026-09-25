// XPBudgetTests.swift
//
// rebalance-xp-economy tasks 3.1, 3.2 and 3.4 (design D1, D2, D4): the XP
// budget table, the growth-factor solver, the literal in `LevelCurve` that
// must match it, the pace checks, one budget line per registered feature,
// and the optional-source allowance. The 1.0505 -> today migration is in
// XPCurveMigrationTests.
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
        let wanted = Double(XPBudget.targetDays) * core
        let reached = XPBudget.cumulativeXP(toReach: XPBudget.targetLevel, growthFactor: XPBudget.solvedGrowthFactor)
        XCTAssertEqual(reached, wanted, accuracy: wanted * 0.001)
    }

    func testGrowthFactorMatchesBudget() {
        let solved = XPBudget.solvedGrowthFactor
        XCTAssertEqual(
            LevelCurve.growthFactor,
            solved,
            accuracy: 1e-4,
            "XPBudget changed: set LevelCurve.growthFactor to \(String(format: "%.5f", solved)) (core \(String(format: "%.2f", core)) XP/day)"
        )
    }

    // MARK: - 3.1 Pace (design D1)

    func testTypicalDayReachesLevel84InThreeYears() {
        let days = XPBudget.daysToReach(level: 84)
        XCTAssertGreaterThanOrEqual(days, 1_084, "level 84 after \(days) days")
        XCTAssertLessThanOrEqual(days, 1_106, "level 84 after \(days) days")
    }

    func testTypicalDayReachesLevel10InOneToThreeWeeks() {
        let days = XPBudget.daysToReach(level: 10)
        XCTAssertGreaterThanOrEqual(days, 7, "level 10 after \(days) days")
        XCTAssertLessThanOrEqual(days, 21, "level 10 after \(days) days")
    }

    func testTypicalDayReachesLevel50InFiveToTenMonths() {
        let days = XPBudget.daysToReach(level: 50)
        XCTAssertGreaterThanOrEqual(days, 150, "level 50 after \(days) days")
        XCTAssertLessThanOrEqual(days, 300, "level 50 after \(days) days")
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
            guard let line = XPBudget.lines.first(where: { $0.source == id }) else { continue }
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
        // Nothing optional in the shipped table yet: grants pass through.
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
    /// most one grant a day, and checks the days to level 84 stay within
    /// ±1% of the core-only budget.
    func testOptionalSourceKeepsLevel84WithinOnePercent() {
        let coreDays = XPBudget.daysToReach(level: 84)
        // (grant XP, grants per day)
        let cases: [(grant: Int, perDay: Double)] = [(1, 1), (2, 1), (5, 1), (10, 1), (20, 1), (50, 1.0 / 7), (5, 0.5)]
        for (grant, perDay) in cases {
            let lines = linesWithOptional(Double(grant) * perDay)
            let multiplier = XPBudget.optionalMultiplier(enabledOptionalSources: ["test-optional"], lines: lines)
            let paid = Double(XPBudget.scaledGrant(grant, multiplier: multiplier)) * perDay
            let days = XPBudget.daysToReach(level: 84, dailyXP: core + paid)
            XCTAssertEqual(
                days / coreDays,
                1,
                accuracy: 0.01,
                "grant \(grant) x \(perDay)/day pays \(paid) XP/day: level 84 after \(days) days vs \(coreDays)"
            )
        }
    }
}

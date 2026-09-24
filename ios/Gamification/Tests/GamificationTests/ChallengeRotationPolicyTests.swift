// ChallengeRotationPolicyTests.swift
//
// add-gamification-signals 6.5 (design D11, challenges spec "Rotation
// favours curated and real-world challenges over number ladders"): weights
// per family, the allowlist, weighted-pick determinism, requirement
// filtering, and the "complete every challenge" denominator.

import XCTest
import FoodLogCore
@testable import Gamification

final class ChallengeRotationPolicyTests: XCTestCase {
    private typealias F = SignalFixtures

    private func template(_ id: String) -> ChallengeTemplate {
        ChallengeCatalog.all.first { $0.id == id }!
    }

    private var waterDays: [DaySignals] {
        [F.day(2026, 9, 20, entries: [F.entry("x", at: TestClock.date(2026, 9, 20))],
               waterML: 2000, waterGoalML: 2500, activities: [])]
    }

    func testStaticWeightsPerFamily() {
        XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template("perfect-week")), 2)
        XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template("sig-something-fishy")), 3)
        XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template("log-streak-10")), 1)
        XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template("log-streak-4")), 0)
        XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template("goal-days-protein-12")), 1)
        XCTAssertEqual(ChallengeRotationPolicy.staticWeight(for: template("goal-days-fat-12")), 0)
    }

    func testAllowlistIsTwoTiersPerLadderFamilyAndAllExist() {
        let allIds = Set(ChallengeCatalog.all.map(\.id))
        XCTAssertTrue(ChallengeRotationPolicy.ladderAllowlist.isSubset(of: allIds))
        let families = ChallengeCatalog.ladderFamilies
        XCTAssertEqual(families.count, 14)
        for (family, ids) in families {
            let kept = ids.filter { ChallengeRotationPolicy.ladderAllowlist.contains($0) }
            XCTAssertEqual(kept.count, 2, family)
        }
        XCTAssertEqual(ChallengeRotationPolicy.ladderAllowlist.count, 28)
        XCTAssertEqual(ChallengeCatalog.handAuthoredIds.count, 13)
    }

    func testCreativeTemplatesDominateTheStaticWeight() {
        let weights = ChallengeCatalog.all.map { ($0, ChallengeRotationPolicy.staticWeight(for: $0)) }
        let total = weights.reduce(0) { $0 + $1.1 }
        let creative = weights.filter { $0.0.kind.isSignalBased }.reduce(0) { $0 + $1.1 }
        let ladder = weights.filter { ChallengeRotationPolicy.ladderAllowlist.contains($0.0.id) }.reduce(0) { $0 + $1.1 }
        XCTAssertEqual(total, 13 * 2 + 24 * 3 + 28)
        XCTAssertGreaterThan(Double(creative) / Double(total), 0.5)
        XCTAssertLessThan(Double(ladder) / Double(total), 0.25)
    }

    func testTrimmedLadderTierIsNeverPicked() {
        for offset in 0..<400 {
            let now = TestClock.date(2026, 1, 1).addingTimeInterval(Double(offset) * 3_607)
            XCTAssertNotEqual(ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: [], now: now).id, "log-streak-4")
        }
    }

    func testSameInputsSamePick() {
        let now = TestClock.date(2026, 9, 24, hour: 9)
        let policy = ChallengeRotationPolicy(recentDays: waterDays)
        let a = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: ["perfect-week"], now: now, policy: policy)
        let b = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: ["perfect-week"], now: now, policy: policy)
        XCTAssertEqual(a.id, b.id)
    }

    func testNoWaterDataMeansNoHydrationStation() {
        let hydration = template("sig-hydration-station")
        XCTAssertEqual(ChallengeRotationPolicy(recentDays: []).weight(for: hydration), 0)
        let noWater = [F.day(2026, 9, 20, entries: [F.entry("x", at: TestClock.date(2026, 9, 20))])]
        XCTAssertEqual(ChallengeRotationPolicy(recentDays: noWater).weight(for: hydration), 0)
        XCTAssertEqual(ChallengeRotationPolicy(recentDays: waterDays).weight(for: hydration), 3)

        for offset in 0..<300 {
            let now = TestClock.date(2026, 1, 1).addingTimeInterval(Double(offset) * 7_919)
            let picked = ChallengeRotation.pickNext(from: ChallengeCatalog.all, excluding: [], now: now,
                                                    policy: ChallengeRotationPolicy(recentDays: noWater))
            XCTAssertNotEqual(picked.id, "sig-hydration-station")
        }
    }

    func testPolicyFromSnapshotLooksBackFourteenDays() {
        let old = F.day(2026, 9, 1, waterML: 2000, waterGoalML: 2500)
        let recent = F.day(2026, 9, 20, entries: [F.entry("x", at: TestClock.date(2026, 9, 20))])
        let keys = (1...20).map { F.dayKey(2026, 9, $0) }
        let snapshot = SignalsSnapshot(days: [old.day: old, recent.day: recent], today: keys.last!, windowDays: keys)
        let policy = ChallengeRotationPolicy(signals: snapshot)
        XCTAssertEqual(policy.recentDays.map(\.day), [recent.day])
        XCTAssertEqual(policy.weight(for: template("sig-hydration-station")), 0)
    }

    func testAllChallengesDenominatorIsRotationTemplatesOnly() {
        let rotation = ChallengeRotationPolicy.rotationTemplateIds()
        XCTAssertEqual(rotation.count, 13 + 24 + 28)
        XCTAssertFalse(rotation.contains("log-streak-4"))

        let everything = ChallengeRotationPolicy.allChallengesProgress(completedTemplateIds: rotation)
        XCTAssertEqual(everything.completed, everything.total)

        // Trimmed tiers completed in the past still sit in history but
        // neither help nor hurt.
        let withTrimmed = ChallengeRotationPolicy.allChallengesProgress(
            completedTemplateIds: rotation.union(["log-streak-4", "goal-days-fat-3"])
        )
        XCTAssertEqual(withTrimmed.completed, withTrimmed.total)

        let missingOne = ChallengeRotationPolicy.allChallengesProgress(
            completedTemplateIds: rotation.subtracting(["sig-nut-job"])
        )
        XCTAssertEqual(missingOne.completed, missingOne.total - 1)

        // End to end through the achievement engine.
        let definition = AchievementDefinition(id: "all", title: "t", subtitle: "t", category: .challenges,
                                               badgeSymbol: "target", condition: .allChallengesCompleted)
        let context = AchievementContext(
            level: 1, longestStreak: 0, totalLogsEver: 0, distinctFoodsInRetainedHistory: 0,
            challengeCompletionCount: everything.completed,
            distinctCompletedChallengeTemplateCount: everything.completed,
            totalChallengeCatalogCount: everything.total,
            dailyChallengeCompletionCount: 0, goalHitDaysEver: [:], maxSingleDayCalories: 0,
            totalCaloriesEver: 0, hasPerfectCalendarMonth: false, hasLoggedOnLeapDay: false,
            hasLoggedOnNewYearsDay: false, hasLoggedAtMidnight: false, yearsSinceFirstLog: 0
        )
        XCTAssertEqual(AchievementEngine.evaluate(context: context, catalog: [definition], alreadyUnlocked: []).map(\.id), ["all"])
    }
}

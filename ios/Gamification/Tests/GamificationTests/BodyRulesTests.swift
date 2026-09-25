// BodyRulesTests.swift
//
// add-sport-and-body-achievements design D2/D7 (body rows): goal direction
// (loss / gain / maintenance / no start), First Kilo, Halfway, Target with
// its 0.2 kg tolerance, Steady as Sněžka with 7 (no) vs 8 (yes) weigh-ins
// in 30 consecutive days, and the kept-fast streak tiers. Pure functions
// over literal snapshots.

import XCTest
import FoodLogCore
@testable import Gamification

final class BodyRulesTests: XCTestCase {
    private typealias F = SportFixtures

    // MARK: - Direction and milestones

    func testDirection() {
        XCTAssertEqual(BodyRules.direction(startKg: 82, targetKg: 76), .loss)
        XCTAssertEqual(BodyRules.direction(startKg: 60, targetKg: 65), .gain)
        XCTAssertEqual(BodyRules.direction(startKg: 70, targetKg: 70.5), .maintenance)
        XCTAssertEqual(BodyRules.direction(startKg: 70, targetKg: 69.5), .maintenance)
        XCTAssertNil(BodyRules.direction(startKg: nil, targetKg: 70))
    }

    func testFirstKiloOnALossGoal() {
        // Spec: start 82.0, target 76.0, a weigh-in of 80.9 unlocks it.
        XCTAssertTrue(BodyRules.reachedFirstKilo(weightKg: 80.9, startKg: 82, targetKg: 76))
        XCTAssertTrue(BodyRules.reachedFirstKilo(weightKg: 81.0, startKg: 82, targetKg: 76))
        XCTAssertFalse(BodyRules.reachedFirstKilo(weightKg: 81.1, startKg: 82, targetKg: 76))
        XCTAssertFalse(BodyRules.reachedFirstKilo(weightKg: 83.5, startKg: 82, targetKg: 76), "wrong direction")
    }

    func testGainGoalMilestones() {
        XCTAssertTrue(BodyRules.reachedFirstKilo(weightKg: 61, startKg: 60, targetKg: 65))
        XCTAssertFalse(BodyRules.reachedFirstKilo(weightKg: 59, startKg: 60, targetKg: 65))
        XCTAssertTrue(BodyRules.reachedHalfway(weightKg: 62.5, startKg: 60, targetKg: 65))
        XCTAssertFalse(BodyRules.reachedHalfway(weightKg: 62.4, startKg: 60, targetKg: 65))
        XCTAssertTrue(BodyRules.reachedTarget(weightKg: 64.8, startKg: 60, targetKg: 65))
        XCTAssertFalse(BodyRules.reachedTarget(weightKg: 64.7, startKg: 60, targetKg: 65))
        XCTAssertTrue(BodyRules.reachedTarget(weightKg: 66, startKg: 60, targetKg: 65), "beyond the target counts")
    }

    func testLossGoalHalfwayAndTargetTolerance() {
        XCTAssertTrue(BodyRules.reachedHalfway(weightKg: 79, startKg: 82, targetKg: 76))
        XCTAssertFalse(BodyRules.reachedHalfway(weightKg: 79.1, startKg: 82, targetKg: 76))
        XCTAssertTrue(BodyRules.reachedTarget(weightKg: 76.2, startKg: 82, targetKg: 76))
        XCTAssertFalse(BodyRules.reachedTarget(weightKg: 76.3, startKg: 82, targetKg: 76))
        XCTAssertTrue(BodyRules.reachedTarget(weightKg: 75, startKg: 82, targetKg: 76))
    }

    func testMaintenanceOnlyAllowsSteady() {
        XCTAssertFalse(BodyRules.reachedFirstKilo(weightKg: 69, startKg: 70, targetKg: 70.3))
        XCTAssertFalse(BodyRules.reachedHalfway(weightKg: 70.3, startKg: 70, targetKg: 70.3))
        XCTAssertFalse(BodyRules.reachedTarget(weightKg: 70.3, startKg: 70, targetKg: 70.3))
    }

    func testWithoutAStartOnlyTargetWithinToleranceApplies() {
        XCTAssertFalse(BodyRules.reachedFirstKilo(weightKg: 70, startKg: nil, targetKg: 76))
        XCTAssertFalse(BodyRules.reachedHalfway(weightKg: 70, startKg: nil, targetKg: 76))
        XCTAssertTrue(BodyRules.reachedTarget(weightKg: 76.2, startKg: nil, targetKg: 76))
        XCTAssertTrue(BodyRules.reachedTarget(weightKg: 75.8, startKg: nil, targetKg: 76))
        XCTAssertFalse(BodyRules.reachedTarget(weightKg: 75.7, startKg: nil, targetKg: 76))
    }

    func testApplicableMilestonesFollowTheDirection() {
        XCTAssertEqual(BodyRules.applicableMilestoneIds(direction: .loss), SportBodyCatalog.weightMilestoneIds)
        XCTAssertEqual(BodyRules.applicableMilestoneIds(direction: .gain), SportBodyCatalog.weightMilestoneIds)
        XCTAssertEqual(BodyRules.applicableMilestoneIds(direction: .maintenance), [SportBodyCatalog.steadyId])
        XCTAssertEqual(BodyRules.applicableMilestoneIds(direction: nil), [SportBodyCatalog.targetId, SportBodyCatalog.steadyId])
    }

    func testWeightBadgesFromTheWindow() {
        let snapshot = F.snapshot([
            F.day(F.key(2026, 9, 10), weighInKg: 81.5),
            F.day(F.key(2026, 9, 20), weighInKg: 80.9),
        ], today: F.key(2026, 9, 24), weightGoal: WeightGoalSignal(startKg: 82, targetKg: 76))
        XCTAssertEqual(BodyRules.weightBadgeIds(in: snapshot, calendar: F.calendar), [SportBodyCatalog.firstKiloId])

        let progress = BodyRules.milestoneProgress(in: snapshot)
        XCTAssertEqual(progress?.latestKg, 80.9)
        XCTAssertEqual(progress?.direction, .loss)
        XCTAssertEqual(progress?.fraction ?? -1, 1.1 / 6, accuracy: 0.0001)
    }

    func testNoWeightGoalMeansNoWeightBadges() {
        let snapshot = F.snapshot([F.day(F.key(2026, 9, 20), weighInKg: 70)], today: F.key(2026, 9, 24))
        XCTAssertTrue(BodyRules.weightBadgeIds(in: snapshot, calendar: F.calendar).isEmpty)
        XCTAssertNil(BodyRules.milestoneProgress(in: snapshot))
    }

    // MARK: - Steady as Sněžka

    /// A 42-day window ending 2026-09-30 with weigh-ins on the given days of
    /// September (all 30 days 1...30 form one run).
    private func steadySnapshot(_ weighIns: [Int: Double]) -> SignalsSnapshot {
        let days = weighIns.map { F.day(F.key(2026, 9, $0.key), weighInKg: $0.value) }
        return F.snapshot(days, today: F.key(2026, 9, 30), windowStart: F.key(2026, 8, 20))
    }

    func testSteadyNeedsEightWeighIns() {
        let seven = Dictionary(uniqueKeysWithValues: [1, 5, 9, 13, 17, 21, 25].map { ($0, 70.4) })
        XCTAssertFalse(BodyRules.steadyMet(in: steadySnapshot(seven), targetKg: 70, calendar: F.calendar))

        var eight = seven
        eight[29] = 69.2
        XCTAssertTrue(BodyRules.steadyMet(in: steadySnapshot(eight), targetKg: 70, calendar: F.calendar))
    }

    func testSteadyFailsWhenAnyWeighInIsOutsideTheBand() {
        var weighIns = Dictionary(uniqueKeysWithValues: [1, 5, 9, 13, 17, 21, 25, 29].map { ($0, 70.0) })
        weighIns[15] = 71.1
        XCTAssertFalse(BodyRules.steadyMet(in: steadySnapshot(weighIns), targetKg: 70, calendar: F.calendar))
    }

    func testSteadyRunMustLieInsideTheWindow() {
        // Eight in-band weigh-ins spread over 30 days, but the window only
        // starts on the 5th -- the run would reach before the window.
        let weighIns = Dictionary(uniqueKeysWithValues: [5, 8, 11, 14, 17, 20, 23, 26].map { ($0, 70.0) })
        let days = weighIns.map { F.day(F.key(2026, 9, $0.key), weighInKg: $0.value) }
        let narrow = F.snapshot(days, today: F.key(2026, 9, 30), windowStart: F.key(2026, 9, 5))
        XCTAssertFalse(BodyRules.steadyMet(in: narrow, targetKg: 70, calendar: F.calendar))
    }

    // MARK: - Fasting

    private func fastingSnapshot(_ outcomes: [FastingOutcome?]) -> SignalsSnapshot {
        // outcomes[0] is 1 September; the last one is today.
        var days: [DaySignals] = []
        for (offset, outcome) in outcomes.enumerated() {
            days.append(F.day(F.key(2026, 9, 1 + offset), fasting: outcome))
        }
        return F.snapshot(days, today: F.key(2026, 9, outcomes.count), windowStart: F.key(2026, 9, 1))
    }

    func testFastingStreakCountsBackFromToday() {
        XCTAssertEqual(BodyRules.keptFastingStreak(in: fastingSnapshot([.kept, .kept, .kept, .kept, .kept])), 5)
        // Today's fast not judged yet: skipped, not a break.
        XCTAssertEqual(BodyRules.keptFastingStreak(in: fastingSnapshot([.kept, .kept, .kept, nil])), 3)
        XCTAssertEqual(BodyRules.keptFastingStreak(in: fastingSnapshot([.kept, .broken, .kept, .kept])), 2)
        // An earlier untracked day ends it.
        XCTAssertEqual(BodyRules.keptFastingStreak(in: fastingSnapshot([.kept, nil, .kept, .kept])), 2)
    }

    func testFastingTiers() {
        XCTAssertEqual(BodyRules.fastingBadgeIds(streak: 2), [])
        XCTAssertEqual(BodyRules.fastingBadgeIds(streak: 3), ["body.fast-3"])
        XCTAssertEqual(BodyRules.fastingBadgeIds(streak: 7), ["body.fast-3", "body.fast-7"])
        XCTAssertEqual(BodyRules.fastingBadgeIds(streak: 14), ["body.fast-3", "body.fast-7", "body.fast-14"])
        XCTAssertEqual(BodyRules.fastingBadgeIds(streak: 30), ["body.fast-3", "body.fast-7", "body.fast-14", "body.fast-30"])
    }
}

// WeightGoalProgressTests.swift
//
// design.md D5 (sync-weight-hydration-with-garmin): goal resolution
// (override > Garmin > fallback) and weight-goal progress -- fraction, kg to
// go, ETA from the 14-day trend, ETA from Garmin's planned rate, and NO ETA
// when the trend points away from the target. Uses the owner's real Garmin
// plan from the 2026-09-23 probe (80.4 -> 76.0 kg, LOSS, 250 g/week) where
// it makes the scenario concrete.

import XCTest
@testable import FoodLogCore

final class WeightGoalProgressTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_150_000)

    private func daysAgo(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    /// Garmin's live plan: grams, LOSS, 250 g/week.
    private var garminGoal: EffectiveWeightGoal {
        GoalResolution.weight(
            targetSource: .garmin,
            startOverrideKg: nil,
            garminTargetGrams: 76_000,
            garminStartGrams: 80_400,
            garminRateGramsPerWeek: 250,
            garminChangeType: "LOSS"
        )!
    }

    // MARK: - Goal resolution

    func testWaterGoalDefaultsToGarmins() {
        let goal = GoalResolution.water(source: .garmin, garminGoalML: 2800)
        XCTAssertEqual(goal, EffectiveWaterGoal(milliliters: 2800, origin: .garmin))
    }

    func testWaterOverrideWins() {
        XCTAssertEqual(GoalResolution.water(source: .override(3000), garminGoalML: 2800), EffectiveWaterGoal(milliliters: 3000, origin: .override))
    }

    func testWaterFallsBackTo2000WithoutEither() {
        XCTAssertEqual(GoalResolution.water(source: .garmin, garminGoalML: nil), EffectiveWaterGoal(milliliters: 2000, origin: .fallback))
        XCTAssertEqual(GoalResolution.water(source: .override(0), garminGoalML: 0).milliliters, 2000, "non-positive values count as unset")
    }

    func testWeightGoalComesFromGarminInGrams() {
        let goal = garminGoal
        XCTAssertEqual(goal.targetKg, 76.0, accuracy: 0.0001)
        XCTAssertEqual(goal.startKg ?? 0, 80.4, accuracy: 0.0001)
        XCTAssertEqual(goal.origin, .garmin)
    }

    func testWeightOverrideReplacesGarminsTarget() {
        let goal = GoalResolution.weight(targetSource: .override(78), startOverrideKg: nil, garminTargetGrams: 76_000, garminStartGrams: 80_400)
        XCTAssertEqual(goal?.targetKg, 78)
        XCTAssertEqual(goal?.origin, .override)
        XCTAssertEqual(goal?.startKg ?? 0, 80.4, accuracy: 0.0001, "start still comes from Garmin unless overridden too")
    }

    func testStartOverrideReplacesGarminsStart() {
        let goal = GoalResolution.weight(targetSource: .garmin, startOverrideKg: 85, garminTargetGrams: 76_000, garminStartGrams: 80_400)
        XCTAssertEqual(goal?.startKg, 85)
    }

    func testNoWeightGoalWithoutTargetFromEitherSide() {
        XCTAssertNil(GoalResolution.weight(targetSource: .garmin, startOverrideKg: 90, garminTargetGrams: nil, garminStartGrams: 80_400))
        XCTAssertNil(GoalResolution.weight(targetSource: .garmin, startOverrideKg: nil, garminTargetGrams: 0, garminStartGrams: nil))
    }

    // MARK: - Fraction / kg to go (spec scenario "Garmin goal shown")

    func testCurrentAboveStartShowsNoProgressAndFullDistance() {
        let progress = WeightGoalProgress.compute(goal: garminGoal, currentKg: 83.9, recentWeighIns: [], now: now)
        XCTAssertEqual(progress.targetKg, 76.0, accuracy: 0.0001)
        XCTAssertEqual(progress.kgToGo, 7.9, accuracy: 0.0001, "83.9 -> 76.0 is 7.9 kg to go")
        XCTAssertEqual(progress.fraction, 0, "heavier than the start is 0%, not negative")
        XCTAssertEqual(progress.direction, .lose)
        XCTAssertFalse(progress.isReached)
    }

    func testHalfwayIsAHalf() {
        let progress = WeightGoalProgress.compute(goal: garminGoal, currentKg: 78.2, recentWeighIns: [], now: now)
        XCTAssertEqual(progress.fraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.kgToGo, 2.2, accuracy: 0.0001)
    }

    func testPastTheTargetIsReachedAndClamped() {
        let progress = WeightGoalProgress.compute(goal: garminGoal, currentKg: 75.5, recentWeighIns: [], now: now)
        XCTAssertTrue(progress.isReached)
        XCTAssertEqual(progress.kgToGo, 0)
        XCTAssertEqual(progress.fraction, 1)
        XCTAssertNil(progress.eta, "nothing left to forecast")
    }

    func testGainGoalWorksTheOtherWay() {
        let goal = EffectiveWeightGoal(targetKg: 70, startKg: 60, origin: .override)
        let progress = WeightGoalProgress.compute(goal: goal, currentKg: 65, recentWeighIns: [], now: now)
        XCTAssertEqual(progress.direction, .gain)
        XCTAssertEqual(progress.fraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertEqual(progress.kgToGo, 5, accuracy: 0.0001)
    }

    func testWithoutAStartThereIsNoFraction() {
        let goal = EffectiveWeightGoal(targetKg: 76, startKg: nil, origin: .override)
        let progress = WeightGoalProgress.compute(goal: goal, currentKg: 80, recentWeighIns: [], now: now)
        XCTAssertNil(progress.fraction)
        XCTAssertEqual(progress.kgToGo, 4, accuracy: 0.0001)
        XCTAssertEqual(progress.direction, .lose)
    }

    // MARK: - ETA

    func testETAFromTheTrendWhenThereAreFourRecentWeighIns() throws {
        // Losing exactly 0.1 kg/day: 80.0, 79.7, 79.4, 79.1 over the last 9 days.
        let points = [
            WeightTrendPoint(date: daysAgo(9), kg: 80.0),
            WeightTrendPoint(date: daysAgo(6), kg: 79.7),
            WeightTrendPoint(date: daysAgo(3), kg: 79.4),
            WeightTrendPoint(date: daysAgo(0), kg: 79.1)
        ]
        let progress = WeightGoalProgress.compute(goal: garminGoal, currentKg: 79.1, recentWeighIns: points, now: now)

        XCTAssertEqual(progress.etaSource, .trend)
        let eta = try XCTUnwrap(progress.eta)
        // 3.1 kg to go at 0.1 kg/day = 31 days.
        XCTAssertEqual(eta.timeIntervalSince(now) / 86_400, 31, accuracy: 0.01)
    }

    func testETAFallsBackToGarminsPlannedRateWithFewerThanFourWeighIns() throws {
        let points = [
            WeightTrendPoint(date: daysAgo(5), kg: 80.0),
            WeightTrendPoint(date: daysAgo(0), kg: 79.5)
        ]
        let progress = WeightGoalProgress.compute(goal: garminGoal, currentKg: 79.5, recentWeighIns: points, now: now)

        XCTAssertEqual(progress.etaSource, .garminPlan)
        let eta = try XCTUnwrap(progress.eta)
        // 3.5 kg to go at 250 g/week = 14 weeks = 98 days.
        XCTAssertEqual(eta.timeIntervalSince(now) / 86_400, 98, accuracy: 0.01)
    }

    func testWeighInsOlderThanFourteenDaysDontCountTowardTheTrend() {
        let points = [
            WeightTrendPoint(date: daysAgo(30), kg: 85),
            WeightTrendPoint(date: daysAgo(20), kg: 84),
            WeightTrendPoint(date: daysAgo(15), kg: 83),
            WeightTrendPoint(date: daysAgo(1), kg: 82)
        ]
        XCTAssertNil(WeightGoalProgress.trendSlopeKgPerDay(points, now: now))
    }

    func testNoETAWhenTheTrendIsMovingAwayFromTheTarget() {
        // Gaining 0.1 kg/day on a LOSS goal.
        let points = [
            WeightTrendPoint(date: daysAgo(9), kg: 82.0),
            WeightTrendPoint(date: daysAgo(6), kg: 82.3),
            WeightTrendPoint(date: daysAgo(3), kg: 82.6),
            WeightTrendPoint(date: daysAgo(0), kg: 82.9)
        ]
        let progress = WeightGoalProgress.compute(goal: garminGoal, currentKg: 82.9, recentWeighIns: points, now: now)
        XCTAssertNil(progress.eta)
        XCTAssertNil(progress.etaSource)
        XCTAssertEqual(progress.kgToGo, 6.9, accuracy: 0.0001, "the distance is still shown")
    }

    func testNoETAWhenGarminsPlanDisagreesWithAnOverrideDirection() {
        // Garmin plans LOSS, but the override target is a gain.
        let goal = GoalResolution.weight(
            targetSource: .override(90),
            startOverrideKg: 80,
            garminTargetGrams: 76_000,
            garminStartGrams: 80_400,
            garminRateGramsPerWeek: 250,
            garminChangeType: "LOSS"
        )!
        let progress = WeightGoalProgress.compute(goal: goal, currentKg: 82, recentWeighIns: [], now: now)
        XCTAssertEqual(progress.direction, .gain)
        XCTAssertNil(progress.eta)
    }

    func testNoETAWithAMaintainPlanAndNoTrend() {
        let goal = EffectiveWeightGoal(targetKg: 76, startKg: 80, origin: .garmin, plannedRateGramsPerWeek: 250, plannedChangeType: "MAINTAIN")
        let progress = WeightGoalProgress.compute(goal: goal, currentKg: 79, recentWeighIns: [], now: now)
        XCTAssertNil(progress.eta)
    }

    func testTrendSlopeIsLeastSquares() throws {
        let points = [
            WeightTrendPoint(date: daysAgo(3), kg: 80.0),
            WeightTrendPoint(date: daysAgo(2), kg: 80.2),
            WeightTrendPoint(date: daysAgo(1), kg: 79.6),
            WeightTrendPoint(date: daysAgo(0), kg: 79.8)
        ]
        // x = 0,1,2,3; y = 80.0,80.2,79.6,79.8 -> slope = -0.12
        let slope = try XCTUnwrap(WeightGoalProgress.trendSlopeKgPerDay(points, now: now))
        XCTAssertEqual(slope, -0.12, accuracy: 0.0001)
    }

    func testFourWeighInsWithinMinutesGiveNoTrend() {
        let points = (0..<4).map { WeightTrendPoint(date: now.addingTimeInterval(Double(-$0) * 60), kg: 80 + Double($0)) }
        XCTAssertNil(WeightGoalProgress.trendSlopeKgPerDay(points, now: now))
    }
}

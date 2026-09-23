// WeightAndWaterOverviewTests.swift
//
// design.md D4/D5 (sync-weight-hydration-with-garmin) as the cards see
// them: the weight goal/progress built from the cached Garmin plan and the
// merged history, and the water goal/total built from the cached Garmin
// day. Uses the owner's real 2026-09-23 values (80.4 -> 76.0 kg plan,
// 1500 / 2800 ml) so the spec scenarios read literally.

import XCTest
@testable import FoodLogCore
import GarminKit

final class WeightAndWaterOverviewTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_790_150_000)

    private var garminPlan: CachedWeightGoal {
        CachedWeightGoal(startingWeightGrams: 80_400, targetWeightGrams: 76_000, weightChangeRateGramsPerWeek: 250, weightChangeType: "LOSS", fetchedAt: now)
    }

    private func row(kg: Double, daysAgo: Double, pk: Int) -> WeighInDisplayEntry {
        let date = now.addingTimeInterval(-daysAgo * 86_400)
        let sample = GarminWeighIn(samplePk: pk, calendarDate: NutritionDate.string(from: date, calendar: calendar), weightGrams: kg * 1000, timestampGMT: date.timeIntervalSince1970 * 1000)
        return WeighInDisplayEntry(source: .garmin(sample, matchedLocalEntry: nil), syncState: .synced, outboxEntryId: nil)
    }

    // MARK: - Weight goal (spec "Weight goal with progress")

    func testGarminGoalShownWithKgToGo() throws {
        let snapshot = GarminHealthSnapshot(weightGoal: garminPlan)
        let goal = WeightAndWaterOverview.weightGoal(snapshot: snapshot, targetSource: .garmin, startOverrideKg: nil)
        let progress = try XCTUnwrap(WeightAndWaterOverview.weightProgress(rows: [row(kg: 83.9, daysAgo: 0, pk: 1)], goal: goal, now: now))

        XCTAssertEqual(progress.targetKg, 76.0, accuracy: 0.0001)
        XCTAssertEqual(progress.kgToGo, 7.9, accuracy: 0.0001, "83.9 kg now, 76.0 kg target")
        XCTAssertEqual(progress.fraction, 0, "above the starting weight: no progress yet, clamped")
    }

    func testLocalOverrideReplacesGarminsTarget() throws {
        let snapshot = GarminHealthSnapshot(weightGoal: garminPlan)
        let goal = WeightAndWaterOverview.weightGoal(snapshot: snapshot, targetSource: .override(78), startOverrideKg: nil)
        let progress = try XCTUnwrap(WeightAndWaterOverview.weightProgress(rows: [row(kg: 83.9, daysAgo: 0, pk: 1)], goal: goal, now: now))
        XCTAssertEqual(progress.targetKg, 78)
        XCTAssertEqual(goal?.origin, .override)
    }

    func testNoGoalAnywhereMeansNoProgress() {
        let goal = WeightAndWaterOverview.weightGoal(snapshot: GarminHealthSnapshot(), targetSource: .garmin, startOverrideKg: nil)
        XCTAssertNil(goal)
        XCTAssertNil(WeightAndWaterOverview.weightProgress(rows: [row(kg: 83.9, daysAgo: 0, pk: 1)], goal: goal, now: now))
    }

    func testNoWeighInsMeansNoProgress() {
        let goal = WeightAndWaterOverview.weightGoal(snapshot: GarminHealthSnapshot(weightGoal: garminPlan), targetSource: .garmin, startOverrideKg: nil)
        XCTAssertNil(WeightAndWaterOverview.weightProgress(rows: [], goal: goal, now: now))
    }

    func testTheMergedRowsFeedTheTrendETA() throws {
        let goal = WeightAndWaterOverview.weightGoal(snapshot: GarminHealthSnapshot(weightGoal: garminPlan), targetSource: .garmin, startOverrideKg: nil)
        // 0.1 kg/day down over the last 6 days, newest first.
        let rows = (0..<6).map { day in row(kg: 80.0 + Double(day) * 0.1, daysAgo: Double(day), pk: day + 1) }
        let progress = try XCTUnwrap(WeightAndWaterOverview.weightProgress(rows: rows, goal: goal, now: now))

        XCTAssertEqual(progress.etaSource, .trend)
        let eta = try XCTUnwrap(progress.eta)
        XCTAssertEqual(eta.timeIntervalSince(now) / 86_400, 40, accuracy: 0.5, "4 kg to go at 0.1 kg/day")
    }

    // MARK: - Water goal (spec "Water goal defaults to Garmin's")

    func testWaterGoalIsGarminsForToday() {
        let snapshot = GarminHealthSnapshot(hydrationDays: [
            "2026-09-23": CachedHydrationDay(daily: HydrationDaily(calendarDate: "2026-09-23", valueInML: 1500, goalInML: 2800), fetchedAt: now)
        ])
        XCTAssertEqual(WeightAndWaterOverview.waterGoal(snapshot: snapshot, source: .garmin, on: "2026-09-23"), EffectiveWaterGoal(milliliters: 2800, origin: .garmin))
    }

    func testWaterGoalFallsBackToTheNewestEarlierCachedDay() {
        let snapshot = GarminHealthSnapshot(hydrationDays: [
            "2026-09-20": CachedHydrationDay(daily: HydrationDaily(goalInML: 2500), fetchedAt: now),
            "2026-09-22": CachedHydrationDay(daily: HydrationDaily(goalInML: 2700), fetchedAt: now),
            "2026-09-24": CachedHydrationDay(daily: HydrationDaily(goalInML: 9999), fetchedAt: now)
        ])
        XCTAssertEqual(WeightAndWaterOverview.garminWaterGoalML(snapshot: snapshot, on: "2026-09-23"), 2700, "yesterday's goal, never a future day's")
    }

    func testWaterOverrideAndFallback() {
        XCTAssertEqual(WeightAndWaterOverview.waterGoal(snapshot: GarminHealthSnapshot(), source: .override(3000), on: "2026-09-23").milliliters, 3000)
        XCTAssertEqual(WeightAndWaterOverview.waterGoal(snapshot: GarminHealthSnapshot(), source: .garmin, on: "2026-09-23"), EffectiveWaterGoal(milliliters: 2000, origin: .fallback))
    }

    // MARK: - Water total (spec "The daily water total comes from Garmin")

    func testWaterTotalIsGarminsPlusPending() {
        let snapshot = GarminHealthSnapshot(hydrationDays: [
            "2026-09-23": CachedHydrationDay(daily: HydrationDaily(calendarDate: "2026-09-23", valueInML: 1500, goalInML: 2800), fetchedAt: now.addingTimeInterval(-60))
        ])
        let pending = HydrationOutboxEntry(valueInML: 250, loggedAt: now, state: .pending)

        XCTAssertEqual(WeightAndWaterOverview.waterTotalML(snapshot: snapshot, outboxEntries: [], on: now, calendar: calendar), 1500)
        XCTAssertEqual(WeightAndWaterOverview.waterTotalML(snapshot: snapshot, outboxEntries: [pending], on: now, calendar: calendar), 1750)
    }
}

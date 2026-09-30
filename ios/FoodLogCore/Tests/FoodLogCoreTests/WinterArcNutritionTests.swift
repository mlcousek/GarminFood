// WinterArcNutritionTests.swift
//
// add-winter-arc-nutrition-and-rewards, the food side:
//   - A1: `FuelDayEvaluator` (carbs against the band, the late-day
//     under-fuelling note, the softened calorie ring) and the training
//     experience's goal judgement (`GoalStatusEvaluator.evaluate(_:fuel:)`)
//     -- eating inside or above the band is never a missed goal;
//   - fasting paused by the plan (`FastingDayEvaluator.history(pausedDays:)`)
//     -- neutral, never broken, the streak runs through it;
//   - A4: `WeightMonitor` -- the 7-day morning average and the one quiet
//     flag at more than 0.7 % a week.
// Every value is synthetic. Calendars are explicit (Prague), so nothing
// depends on the CI runner's time zone.

import XCTest
@testable import FoodLogCore
import GarminKit

final class WinterArcNutritionTests: XCTestCase {
    private var prague: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        prague.date(from: DateComponents(year: 2030, month: month, day: day, hour: hour, minute: minute))!
    }

    /// 6-8 g/kg at 80 kg, protein 1.6 g/kg, a run on the day.
    private let band = FuelDayTarget(carbsMinG: 480, carbsMaxG: 640, proteinG: 128, hasTrainingSessions: true, isFastingPaused: true)

    // MARK: - Summary

    func testCarbsAgainstTheBand() throws {
        let below = try XCTUnwrap(FuelDayEvaluator.summary(carbsG: 300, proteinG: 60, target: band, isToday: true, now: local(22, 12), calendar: prague))
        XCTAssertEqual(below.carbStatus, .below)
        XCTAssertEqual(below.carbFraction, 300.0 / 640.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(below.proteinFraction), 60.0 / 128.0, accuracy: 1e-9)
        XCTAssertFalse(below.showsUnderFuellingNote, "not before 18:00")

        let inside = try XCTUnwrap(FuelDayEvaluator.summary(carbsG: 480, proteinG: 130, target: band, isToday: true, now: local(22, 20), calendar: prague))
        XCTAssertEqual(inside.carbStatus, .inBand, "the lower edge is inside")
        XCTAssertEqual(inside.proteinFraction, 1)

        let above = try XCTUnwrap(FuelDayEvaluator.summary(carbsG: 700, proteinG: 0, target: band, isToday: true, now: local(22, 20), calendar: prague))
        XCTAssertEqual(above.carbStatus, .above)
        XCTAssertEqual(above.carbFraction, 1)
    }

    func testTheUnderFuellingNoteIsLateTodayAndClearlyBelow() throws {
        // 75 % of 480 = 360.
        let late = try XCTUnwrap(FuelDayEvaluator.summary(carbsG: 359, proteinG: 0, target: band, isToday: true, now: local(22, 18), calendar: prague))
        XCTAssertTrue(late.showsUnderFuellingNote)
        let justEnough = try XCTUnwrap(FuelDayEvaluator.summary(carbsG: 360, proteinG: 0, target: band, isToday: true, now: local(22, 21), calendar: prague))
        XCTAssertFalse(justEnough.showsUnderFuellingNote, "below the band but not clearly")
        let pastDay = try XCTUnwrap(FuelDayEvaluator.summary(carbsG: 100, proteinG: 0, target: band, isToday: false, now: local(22, 21), calendar: prague))
        XCTAssertFalse(pastDay.showsUnderFuellingNote, "never on a past day")
    }

    func testNoBandNoSummary() {
        let sessionsOnly = FuelDayTarget(carbsMinG: nil, carbsMaxG: nil, proteinG: nil, hasTrainingSessions: true)
        XCTAssertNil(FuelDayEvaluator.summary(carbsG: 100, proteinG: 50, target: sessionsOnly, isToday: true, now: local(22, 12), calendar: prague))
        XCTAssertNil(FuelDayEvaluator.summary(carbsG: 100, proteinG: 50, target: nil, isToday: true, now: local(22, 12), calendar: prague))
    }

    func testOverIsNeverAWarningOnATrainingDay() {
        XCTAssertNil(FuelDayEvaluator.displayBand(.over, target: band))
        XCTAssertNil(FuelDayEvaluator.displayBand(.slightlyOver, target: band))
        XCTAssertEqual(FuelDayEvaluator.displayBand(.approaching, target: band), .approaching)
        let sessionsOnly = FuelDayTarget(carbsMinG: nil, carbsMaxG: nil, proteinG: nil, hasTrainingSessions: true)
        XCTAssertNil(FuelDayEvaluator.displayBand(.over, target: sessionsOnly))
        let restDay = FuelDayTarget(carbsMinG: nil, carbsMaxG: nil, proteinG: nil, hasTrainingSessions: false, isFastingPaused: true)
        XCTAssertEqual(FuelDayEvaluator.displayBand(.over, target: restDay), .over, "a rest day without a band keeps the old ring")
        XCTAssertEqual(FuelDayEvaluator.displayBand(.over, target: nil), .over, "food-first: unchanged")
    }

    // MARK: - Goal judgement

    private func log(_ json: String) throws -> DailyFoodLog {
        try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    func testEatingInsideTheBandIsAMetGoalEvenOverTheCalorieTarget() throws {
        // 3,100 kcal on a 2,300 kcal target: red before, met now.
        let day = try log(#"{ "dailyNutritionGoals": { "calories": 2300, "protein": 120, "carbs": 250, "fat": 70 }, "dailyNutritionContent": { "calories": 3100, "protein": 125, "carbs": 560, "fat": 80 } }"#)
        XCTAssertEqual(GoalStatusEvaluator.evaluate(day)?.metCalorieGoal, false, "the fixed target says over")
        let judged = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: band))
        XCTAssertTrue(judged.metCalorieGoal)
        XCTAssertTrue(judged.metCarbGoal)
        XCTAssertTrue(judged.metProteinGoal, "125 g >= 90 % of 128 g")
        XCTAssertTrue(judged.metFatGoal)
    }

    func testAboveTheBandIsNotAMiss() throws {
        let day = try log(#"{ "dailyNutritionGoals": { "calories": 2300 }, "dailyNutritionContent": { "calories": 3600, "carbs": 720, "protein": 100 } }"#)
        let judged = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: band))
        XCTAssertTrue(judged.metCalorieGoal)
        XCTAssertFalse(judged.metProteinGoal, "100 g < 115.2 g")
    }

    func testUnderTheBandIsNotMet() throws {
        let day = try log(#"{ "dailyNutritionGoals": { "calories": 2300 }, "dailyNutritionContent": { "calories": 2300, "carbs": 300 } }"#)
        let judged = try XCTUnwrap(GoalStatusEvaluator.evaluate(day, fuel: band))
        XCTAssertFalse(judged.metCalorieGoal, "on the calorie target but under-fuelled")
        XCTAssertFalse(judged.metCarbGoal)
    }

    func testABandJudgesADayWithoutGarminGoals() throws {
        let day = try log(#"{ "dailyNutritionContent": { "calories": 2800, "carbs": 500 } }"#)
        XCTAssertNil(GoalStatusEvaluator.evaluate(day))
        XCTAssertEqual(GoalStatusEvaluator.evaluate(day, fuel: band)?.metCarbGoal, true)
    }

    func testATrainingDayWithoutABandHasNoCalorieCeiling() throws {
        let sessionsOnly = FuelDayTarget(carbsMinG: nil, carbsMaxG: nil, proteinG: nil, hasTrainingSessions: true)
        let over = try log(#"{ "dailyNutritionGoals": { "calories": 2000 }, "dailyNutritionContent": { "calories": 2600 } }"#)
        XCTAssertEqual(GoalStatusEvaluator.evaluate(over, fuel: sessionsOnly)?.metCalorieGoal, true)
        let under = try log(#"{ "dailyNutritionGoals": { "calories": 2000 }, "dailyNutritionContent": { "calories": 1880 } }"#)
        XCTAssertEqual(GoalStatusEvaluator.evaluate(under, fuel: sessionsOnly)?.metCalorieGoal, false, "94 % is under the 95 % floor")
        XCTAssertNil(GoalStatusEvaluator.evaluate(try log(#"{ "dailyNutritionContent": { "calories": 1880 } }"#), fuel: sessionsOnly), "no band, no goals: nothing to judge")
    }

    func testWithoutATargetItIsTheFoodFirstJudgement() throws {
        let day = try log(#"{ "dailyNutritionGoals": { "calories": 2000, "protein": 120 }, "dailyNutritionContent": { "calories": 2400, "protein": 130 } }"#)
        XCTAssertEqual(GoalStatusEvaluator.evaluate(day, fuel: nil), GoalStatusEvaluator.evaluate(day))
    }

    // MARK: - Fasting paused by the plan

    func testAPausedDayIsNeutralAndKeepsTheStreak() {
        let schedule = FastingSchedule(startMinute: 20 * 60, endMinute: 12 * 60)!
        let now = local(24, 15)
        // Food at 09:00 on the 23rd (inside that day's fast), nothing else.
        let logs = [local(23, 9)]
        let unpaused = FastingDayEvaluator.history(schedule: schedule, days: 4, logTimestamps: logs, trackedSince: nil, now: now, calendar: prague)
        XCTAssertEqual(unpaused.first { $0.day == prague.startOfDay(for: local(23, 12)) }?.result, .broken(at: local(23, 9)))
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: unpaused), 1, "today kept, then yesterday broken")

        let paused = FastingDayEvaluator.history(
            schedule: schedule, days: 4, logTimestamps: logs, trackedSince: nil,
            pausedDays: [prague.startOfDay(for: local(23, 12))],
            now: now, calendar: prague
        )
        XCTAssertEqual(paused.first { $0.day == prague.startOfDay(for: local(23, 12)) }?.result, .paused)
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: paused), 3, "the paused day neither counts nor breaks the run")
    }

    // MARK: - Weight monitor

    func testTheMorningAverageAndNoFlagForAStableWeight() throws {
        let samples = [
            WeightSample(date: local(24, 6, 30), kg: 83.0),
            WeightSample(date: local(23, 6, 45), kg: 83.4),
            WeightSample(date: local(23, 13), kg: 85.1), // midday: left out
            WeightSample(date: local(17, 6, 30), kg: 83.3),
        ]
        let summary = try XCTUnwrap(WeightMonitor.summary(samples: samples, now: local(24, 12), calendar: prague))
        XCTAssertEqual(summary.averageKg, 83.2, accuracy: 1e-9)
        XCTAssertEqual(summary.sampleCount, 2)
        XCTAssertTrue(summary.usedMorningOnly)
        XCTAssertEqual(try XCTUnwrap(summary.weeklyChangePercent), (83.2 - 83.3) / 83.3 * 100, accuracy: 1e-9)
        XCTAssertFalse(summary.isFallingTooFast)
    }

    func testWithoutAMorningWeighInEveryWeighInCounts() throws {
        let samples = [WeightSample(date: local(24, 9), kg: 84), WeightSample(date: local(23, 18), kg: 85)]
        let summary = try XCTUnwrap(WeightMonitor.summary(samples: samples, now: local(24, 12), calendar: prague))
        XCTAssertEqual(summary.averageKg, 84.5, accuracy: 1e-9)
        XCTAssertFalse(summary.usedMorningOnly)
        XCTAssertNil(summary.weeklyChangePercent)
        XCTAssertFalse(summary.isFallingTooFast)
    }

    func testTheQuietFlagAboveSevenTenthsOfAPercentAWeek() throws {
        let fast = [WeightSample(date: local(24, 6), kg: 82.3), WeightSample(date: local(16, 6), kg: 83.0)]
        XCTAssertTrue(try XCTUnwrap(WeightMonitor.summary(samples: fast, now: local(24, 12), calendar: prague)).isFallingTooFast, "-0.84 %")
        let slow = [WeightSample(date: local(24, 6), kg: 82.5), WeightSample(date: local(16, 6), kg: 83.0)]
        XCTAssertFalse(try XCTUnwrap(WeightMonitor.summary(samples: slow, now: local(24, 12), calendar: prague)).isFallingTooFast, "-0.60 %")
        let gaining = [WeightSample(date: local(24, 6), kg: 85), WeightSample(date: local(16, 6), kg: 83.0)]
        XCTAssertFalse(try XCTUnwrap(WeightMonitor.summary(samples: gaining, now: local(24, 12), calendar: prague)).isFallingTooFast, "no judgement on a gain")
    }

    func testNoRecentWeighInNoSummary() {
        XCTAssertNil(WeightMonitor.summary(samples: [WeightSample(date: local(10, 6), kg: 83)], now: local(24, 12), calendar: prague))
    }
}

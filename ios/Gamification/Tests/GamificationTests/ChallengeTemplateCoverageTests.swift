// ChallengeTemplateCoverageTests.swift
//
// add-gamification 25.4: every template's completion condition is tested,
// including the case where it is NOT met. ChallengeEngineTests covers the
// other templates; these are the ones the 2026-09-16 audit found untested
// (calorie-control, carb-cutback, explorer, dinner-discipline) plus the
// incomplete cases full-plate and triple-threat were missing.

import XCTest
@testable import Gamification
import FoodLogCore

final class ChallengeTemplateCoverageTests: XCTestCase {
    private func event(_ foodId: String, day: Int, hour: Int = 12) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: "s1", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, day, hour: hour))
    }

    private func goals(days: [Int], calories: Bool = false, protein: Bool = false, carbs: Bool = false) -> [DailyGoalStatus] {
        days.map {
            DailyGoalStatus(
                date: String(format: "2026-01-%02d", $0),
                metCalorieGoal: calories,
                metProteinGoal: protein,
                metCarbGoal: carbs,
                metFatGoal: false
            )
        }
    }

    private func progress(
        _ id: String,
        events: [UsageEvent] = [],
        goals: [DailyGoalStatus] = [],
        startDay: Int = 1,
        now: Date
    ) throws -> ChallengeProgress {
        let template = try XCTUnwrap(ChallengeCatalog.all.first { $0.id == id })
        let active = ActiveChallenge(templateId: id, startedAt: TestClock.date(2026, 1, startDay), baselineStreakLength: 0)
        return ChallengeEngine.progress(
            for: template,
            active: active,
            events: events,
            goalStatuses: goals,
            now: now,
            calendar: TestClock.calendar
        )
    }

    // MARK: - calorie-control: calorie goal on 5 of 7 days

    func testCalorieControlCompletesOnFiveDays() throws {
        let result = try progress("calorie-control", goals: goals(days: [1, 2, 4, 5, 7], calories: true), now: TestClock.date(2026, 1, 7, hour: 20))

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 5)
    }

    func testCalorieControlIsIncompleteOnFourDaysOrOtherMacros() throws {
        let four = try progress("calorie-control", goals: goals(days: [1, 2, 3, 4], calories: true), now: TestClock.date(2026, 1, 7, hour: 20))
        XCTAssertFalse(four.isComplete)
        XCTAssertEqual(four.current, 4)

        let proteinOnly = try progress("calorie-control", goals: goals(days: [1, 2, 3, 4, 5, 6], protein: true), now: TestClock.date(2026, 1, 7, hour: 20))
        XCTAssertEqual(proteinOnly.current, 0)
    }

    func testCalorieControlIgnoresDaysOutsideTheWindow() throws {
        let result = try progress("calorie-control", goals: goals(days: [9, 10, 11, 12, 13], calories: true), now: TestClock.date(2026, 1, 7, hour: 20))

        XCTAssertEqual(result.current, 0)
    }

    // MARK: - carb-cutback: carb goal on 4 of 6 days

    func testCarbCutbackCompletesOnFourDays() throws {
        let result = try progress("carb-cutback", goals: goals(days: [1, 3, 4, 6], carbs: true), now: TestClock.date(2026, 1, 6, hour: 20))

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 4)
    }

    func testCarbCutbackIsIncompleteOnThreeDays() throws {
        let result = try progress("carb-cutback", goals: goals(days: [1, 3, 4], carbs: true), now: TestClock.date(2026, 1, 6, hour: 20))

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    // MARK: - explorer: 5 new foods in 10 days

    func testExplorerCompletesWithFiveNewFoods() throws {
        let events = ["a", "b", "c", "d", "e"].enumerated().map { event($0.element, day: 3 + $0.offset) }

        let result = try progress("explorer", events: events, startDay: 3, now: TestClock.date(2026, 1, 8, hour: 20))

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 5)
    }

    func testExplorerDoesNotCountFoodsLoggedBeforeTheChallenge() throws {
        let before = ["a", "b"].map { event($0, day: 1) }
        let during = ["a", "b", "c", "d", "e"].map { event($0, day: 4) }

        let result = try progress("explorer", events: before + during, startDay: 3, now: TestClock.date(2026, 1, 8, hour: 20))

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 3)
    }

    func testExplorerCountsRepeatsOfANewFoodOnce() throws {
        let events = [event("a", day: 3), event("a", day: 4), event("a", day: 5), event("b", day: 5)]

        let result = try progress("explorer", events: events, startDay: 3, now: TestClock.date(2026, 1, 8, hour: 20))

        XCTAssertEqual(result.current, 2)
    }

    // MARK: - dinner-discipline: dinner-time entry on 4 days

    func testDinnerDisciplineCompletesOnFourEvenings() throws {
        let events = [1, 2, 4, 6].map { event("f\($0)", day: $0, hour: 19) }

        let result = try progress("dinner-discipline", events: events, now: TestClock.date(2026, 1, 7, hour: 22))

        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.current, 4)
    }

    func testDinnerDisciplineIgnoresOtherTimesAndSameDayRepeats() throws {
        let lunches = [1, 2, 3, 4].map { event("l\($0)", day: $0, hour: 12) }
        let twoDinnersOneDay = [event("d1", day: 5, hour: 19), event("d2", day: 5, hour: 21)]

        let result = try progress("dinner-discipline", events: lunches + twoDinnersOneDay, now: TestClock.date(2026, 1, 7, hour: 22))

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 1)
    }

    // MARK: - full-plate and triple-threat: the incomplete cases

    func testFullPlateIsIncompleteWithOnlyTwoQualifyingDays() throws {
        let day1 = [event("a", day: 1, hour: 7), event("b", day: 1, hour: 12), event("c", day: 1, hour: 19)]
        let day2 = [event("d", day: 2, hour: 7), event("e", day: 2, hour: 12), event("f", day: 2, hour: 20)]
        let day3 = [event("g", day: 3, hour: 7), event("h", day: 3, hour: 8)]

        let result = try progress("full-plate", events: day1 + day2 + day3, now: TestClock.date(2026, 1, 4, hour: 22))

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }

    func testTripleThreatIsIncompleteWithOnlyTwoBusyDays() throws {
        let day1 = ["a", "b", "c"].map { event($0, day: 1) }
        let day2 = ["d", "e", "f"].map { event($0, day: 2) }
        let day3 = ["g", "h"].map { event($0, day: 3) }

        let result = try progress("triple-threat", events: day1 + day2 + day3, now: TestClock.date(2026, 1, 4, hour: 22))

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.current, 2)
    }
}

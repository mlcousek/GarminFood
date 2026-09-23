// FastingDayEvaluatorTests.swift
//
// Kept/broken judging, the kept-days streak and the log-timestamp rules
// (FastingSchedule.swift's `FastingDayEvaluator`, FastingLogMoments.swift)
// -- redesign-fasting-schedule 1.2. Explicit Europe/Prague calendar
// throughout, same as FastingScheduleTests.

import XCTest
import GarminKit
@testable import FoodLogCore

final class FastingDayEvaluatorTests: XCTestCase {
    private let hour: TimeInterval = 3600

    private var prague: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        prague.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Tue 22 Sep 20:00 -> Wed 23 Sep 12:00.
    private var wednesdaysFast: FastingWindow {
        FastingWindow(start: local(2026, 9, 22, 20), end: local(2026, 9, 23, 12))
    }

    // MARK: - evaluate

    func testKeptWhenNothingWasLoggedInsideAFinishedWindow() {
        let result = FastingDayEvaluator.evaluate(
            window: wednesdaysFast,
            logTimestamps: [local(2026, 9, 22, 19), local(2026, 9, 23, 13)],
            now: local(2026, 9, 23, 16)
        )
        XCTAssertEqual(result, .kept)
    }

    func testBrokenAtTheFirstLogInsideTheWindow() {
        let result = FastingDayEvaluator.evaluate(
            window: wednesdaysFast,
            logTimestamps: [local(2026, 9, 23, 10), local(2026, 9, 23, 13), local(2026, 9, 23, 9)],
            now: local(2026, 9, 23, 16)
        )
        XCTAssertEqual(result, .broken(at: local(2026, 9, 23, 9)))
    }

    func testALogAtTheExactEndIsNotABreakButOneAtTheExactStartIs() {
        XCTAssertEqual(
            FastingDayEvaluator.evaluate(window: wednesdaysFast, logTimestamps: [local(2026, 9, 23, 12)], now: local(2026, 9, 23, 16)),
            .kept
        )
        XCTAssertEqual(
            FastingDayEvaluator.evaluate(window: wednesdaysFast, logTimestamps: [local(2026, 9, 22, 20)], now: local(2026, 9, 23, 16)),
            .broken(at: local(2026, 9, 22, 20))
        )
    }

    func testInProgressAndUpcomingAreNotJudgedYet() {
        XCTAssertEqual(
            FastingDayEvaluator.evaluate(window: wednesdaysFast, logTimestamps: [], now: local(2026, 9, 23, 7)),
            .inProgress
        )
        XCTAssertEqual(
            FastingDayEvaluator.evaluate(window: wednesdaysFast, logTimestamps: [], now: local(2026, 9, 22, 18)),
            .upcoming
        )
    }

    func testAFastBrokenWhileStillRunningIsAlreadyBroken() {
        let result = FastingDayEvaluator.evaluate(
            window: wednesdaysFast,
            logTimestamps: [local(2026, 9, 23, 9)],
            now: local(2026, 9, 23, 9, 30)
        )
        XCTAssertEqual(result, .broken(at: local(2026, 9, 23, 9)))
    }

    // MARK: - history + streak

    func testHistoryIsNewestFirstAndJudgesEachDaysOwnWindow() {
        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 3,
            logTimestamps: [local(2026, 9, 22, 9)],
            trackedSince: nil,
            now: local(2026, 9, 23, 16),
            calendar: prague
        )

        XCTAssertEqual(days.map(\.day), [local(2026, 9, 23, 0), local(2026, 9, 22, 0), local(2026, 9, 21, 0)])
        XCTAssertEqual(days.map(\.result), [.kept, .broken(at: local(2026, 9, 22, 9)), .kept])
        XCTAssertEqual(days.first?.window, wednesdaysFast)
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: days), 1)
    }

    func testSpecScenarioABreakTodayResetsTheStreakToZero() {
        // 20:00-12:00, food logged at 09:00 today: today is broken and the
        // streak is 0, however many kept days came before.
        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 5,
            logTimestamps: [local(2026, 9, 23, 9)],
            trackedSince: nil,
            now: local(2026, 9, 23, 9, 30),
            calendar: prague
        )

        XCTAssertEqual(days.first?.result, .broken(at: local(2026, 9, 23, 9)))
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: days), 0)
    }

    func testTheRunningFastIsSkippedNotCountedOrBroken() {
        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 4,
            logTimestamps: [local(2026, 9, 20, 9)],
            trackedSince: nil,
            now: local(2026, 9, 23, 7),
            calendar: prague
        )

        XCTAssertEqual(days.map(\.result), [.inProgress, .kept, .kept, .broken(at: local(2026, 9, 20, 9))])
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: days), 2)
    }

    func testWindowsStartingBeforeTrackingBeganAreNotTracked() {
        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 4,
            logTimestamps: [],
            trackedSince: local(2026, 9, 20, 21),
            now: local(2026, 9, 23, 16),
            calendar: prague
        )

        // 21 Sep's fast started 20 Sep 20:00, an hour before tracking began.
        XCTAssertEqual(days.map(\.result), [.kept, .kept, .notTracked, .notTracked])
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: days), 2, "a streak never reaches back past what the data can vouch for")
    }

    func testStreakOrderDoesNotDependOnInputOrder() {
        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 3,
            logTimestamps: [local(2026, 9, 21, 9)],
            trackedSince: nil,
            now: local(2026, 9, 23, 16),
            calendar: prague
        )
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: Array(days.reversed())), 2)
        XCTAssertEqual(FastingDayEvaluator.keptStreak(days: []), 0)
    }

    func testHistoryAcrossTheSpringForwardNightUsesTheShortenedWindow() {
        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 3,
            logTimestamps: [],
            trackedSince: nil,
            now: local(2026, 3, 30, 13),
            calendar: prague
        )

        XCTAssertEqual(days.map(\.result), [.kept, .kept, .kept])
        XCTAssertEqual(days[1].day, local(2026, 3, 29, 0))
        XCTAssertEqual(days[1].window.duration, 15 * hour, accuracy: 0.001)
        XCTAssertEqual(days[0].window.duration, 16 * hour, accuracy: 0.001)
    }

    func testHistoryAcrossTheFallBackNightJudgesALogInTheExtraHour() {
        // 02:30 CET on 25 Oct -- after the clocks went back -- is still
        // inside that night's 17-hour window.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let secondTwoThirty = utc.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 1, minute: 30))!

        let days = FastingDayEvaluator.history(
            schedule: .standard,
            days: 1,
            logTimestamps: [secondTwoThirty],
            trackedSince: nil,
            now: local(2026, 10, 25, 15),
            calendar: prague
        )

        XCTAssertEqual(days.first?.result, .broken(at: secondTwoThirty))
        XCTAssertEqual(days.first?.window.duration ?? 0, 17 * hour, accuracy: 0.001)
    }

    // MARK: - Which logs count as eating

    func testALogForTheSameDayCounts() {
        XCTAssertTrue(FastingLogMoments.countsAsEating(timestamp: local(2026, 9, 23, 9), nutritionDay: "2026-09-23", calendar: prague))
    }

    func testBackfillingYesterdayThisMorningDoesNotCount() {
        XCTAssertFalse(FastingLogMoments.countsAsEating(timestamp: local(2026, 9, 23, 9), nutritionDay: "2026-09-22", calendar: prague))
    }

    func testALateSnackFiledUnderThePreviousDayStillCounts() {
        XCTAssertTrue(
            FastingLogMoments.countsAsEating(timestamp: local(2026, 9, 23, 0, 30), nutritionDay: "2026-09-22", calendar: prague),
            "00:30 is within Garmin's 04:00 day start, so it's still that evening"
        )
    }

    func testPlanningTomorrowDoesNotCount() {
        XCTAssertFalse(FastingLogMoments.countsAsEating(timestamp: local(2026, 9, 23, 9), nutritionDay: "2026-09-24", calendar: prague))
    }

    func testAnOldEventWithoutANutritionDayCounts() {
        XCTAssertTrue(FastingLogMoments.countsAsEating(timestamp: local(2026, 9, 23, 9), nutritionDay: nil, calendar: prague))
    }

    func testMomentsFromUsageEventsDropBackfills() {
        let events = [
            UsageEvent(foodId: "a", servingId: "s", numberOfUnits: 1, timestamp: local(2026, 9, 23, 9), nutritionDay: "2026-09-23"),
            UsageEvent(foodId: "b", servingId: "s", numberOfUnits: 1, timestamp: local(2026, 9, 23, 9, 5), nutritionDay: "2026-09-22"),
            UsageEvent(foodId: "c", servingId: "s", numberOfUnits: 1, timestamp: local(2026, 9, 23, 13)),
        ]

        let moments = FastingLogMoments.moments(from: events, calendar: prague)

        XCTAssertEqual(moments, [local(2026, 9, 23, 9), local(2026, 9, 23, 13)])
    }

    func testMomentsFromACachedGarminLogReadEveryTimestampedEntry() throws {
        let json = """
        {
          "mealDetails": [
            { "loggedFoods": [
              { "logTimestamp": "2026-09-23T07:00:00.000Z" },
              { "logTimestamp": "not a timestamp" },
              { }
            ] }
          ],
          "loggedFoodsWithServingSizes": [
            { "logTimestamp": "2026-09-23T08:00:00Z" }
          ]
        }
        """
        let log = try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))

        let moments = FastingLogMoments.moments(fromGarminLog: log, date: "2026-09-23", calendar: prague)

        XCTAssertEqual(moments, [local(2026, 9, 23, 9), local(2026, 9, 23, 10)])
    }

    /// Scenario-review finding: an edit re-creates the entry in Garmin at
    /// the time of the edit, so reading this app's own ("GCW") entries back
    /// would count "fixed lunch's amount at 21:30" as eating at 21:30. Those
    /// entries are already in the usage history at their real time.
    func testGarminLogSkipsEntriesThisAppWrote() throws {
        let json = """
        {
          "mealDetails": [
            { "loggedFoods": [
              { "logTimestamp": "2026-09-23T07:00:00.000Z", "logSource": "GCM" },
              { "logTimestamp": "2026-09-23T19:30:00.000Z", "logSource": "GCW" }
            ] }
          ]
        }
        """
        let log = try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))

        let moments = FastingLogMoments.moments(fromGarminLog: log, date: "2026-09-23", calendar: prague)

        XCTAssertEqual(moments, [local(2026, 9, 23, 9)], "only the Garmin Connect entry counts")
    }

    func testCoverageIsCompleteUntilTheUsageHistoryHasTrimmed() {
        let events = (0..<3).map { index in
            UsageEvent(foodId: "f\(index)", servingId: "s", numberOfUnits: 1, timestamp: local(2026, 9, 20 + index, 9))
        }

        XCTAssertNil(FastingLogMoments.coverageStart(events: events, capacity: 4))
        XCTAssertEqual(FastingLogMoments.coverageStart(events: events, capacity: 3), local(2026, 9, 20, 9))
    }
}

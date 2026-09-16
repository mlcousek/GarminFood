import XCTest
@testable import Gamification
import FoodLogCore

final class StreakHistoryTests: XCTestCase {
    private let calendar = TestClock.calendar

    private func day(_ dayOfMonth: Int) -> Date {
        calendar.startOfDay(for: TestClock.date(2026, 1, dayOfMonth))
    }

    private func days(_ list: [Int]) -> Set<Date> {
        Set(list.map(day))
    }

    private func mark(on dayOfMonth: Int, in summary: StreakHistory.Summary) -> StreakHistory.Mark? {
        summary.days.first { $0.date == day(dayOfMonth) }?.mark
    }

    // MARK: - Longest streak and grace

    func testTheLongestStreakBridgesAGraceDay() {
        let logged = days([1, 2, 3, 4, 5, 7, 8, 9, 10])

        let summary = StreakHistory.summary(loggedDays: logged, today: day(10), calendar: calendar)

        XCTAssertEqual(summary.currentLength, 9)
        XCTAssertEqual(summary.longestLength, 9)
        XCTAssertEqual(mark(on: 6, in: summary), .grace)
        XCTAssertEqual(mark(on: 5, in: summary), .logged)
    }

    func testASecondMissInTheSameWeekEndsTheStreakAndIsNotBridged() {
        let logged = days([1, 2, 3, 4, 5, 7, 9, 10])

        let summary = StreakHistory.summary(loggedDays: logged, today: day(10), calendar: calendar)

        XCTAssertEqual(mark(on: 6, in: summary), .grace)
        XCTAssertEqual(mark(on: 8, in: summary), .missed)
        XCTAssertEqual(summary.longestLength, 6, "days 1-5 and 7 before the reset on day 8")
        XCTAssertEqual(summary.currentLength, 2)
    }

    func testTheCurrentStreakMatchesStreakEngine() {
        let logged = days([2, 3, 5, 6, 7])

        let summary = StreakHistory.summary(loggedDays: logged, today: day(8), calendar: calendar)
        let status = StreakEngine.status(loggedDays: logged, today: day(8), calendar: calendar)

        XCTAssertEqual(summary.currentLength, status.length)
        XCTAssertEqual(summary.loggedDayCount, 5)
    }

    // MARK: - Calendar grid

    func testTheGridCoversWholeWeeksEndingWithTodaysWeek() throws {
        let summary = StreakHistory.summary(loggedDays: days([12, 13]), today: day(14), weeks: 2, calendar: calendar)

        XCTAssertEqual(summary.days.count, 14)
        let first = try XCTUnwrap(summary.days.first)
        XCTAssertEqual(calendar.component(.weekday, from: first.date), calendar.firstWeekday)
        XCTAssertEqual(summary.days.filter(\.isToday).map(\.date), [day(14)])
        XCTAssertTrue(summary.days.contains { $0.date == day(14) })
    }

    func testMarksBeforeHistoryTodayAndFuture() {
        // Jan 14, 2026 is a Wednesday, so its week (Sunday-first) runs to Saturday the 17th.
        let summary = StreakHistory.summary(loggedDays: days([12, 13]), today: day(14), weeks: 1, calendar: calendar)

        XCTAssertEqual(mark(on: 11, in: summary), .beforeHistory)
        XCTAssertEqual(mark(on: 12, in: summary), .logged)
        XCTAssertEqual(mark(on: 14, in: summary), .pending)
        XCTAssertEqual(mark(on: 15, in: summary), .future)
    }

    func testTodayLoggedIsMarkedLogged() {
        let summary = StreakHistory.summary(loggedDays: days([13, 14]), today: day(14), weeks: 1, calendar: calendar)

        XCTAssertEqual(mark(on: 14, in: summary), .logged)
    }

    func testEmptyHistory() {
        let summary = StreakHistory.summary(loggedDays: [], today: day(14), weeks: 1, calendar: calendar)

        XCTAssertEqual(summary.currentLength, 0)
        XCTAssertEqual(summary.longestLength, 0)
        XCTAssertEqual(mark(on: 12, in: summary), .beforeHistory)
        XCTAssertEqual(mark(on: 14, in: summary), .pending)
    }

    // MARK: - An event's recorded day wins over its timestamp

    func testAnEventCountsTowardItsRecordedNutritionDay() {
        // Logged at 01:00 on Jan 5 for Jan 5. With the old 04:00 bucketing
        // the timestamp alone would count toward Jan 4.
        let event = UsageEvent(
            foodId: "f",
            servingId: "s",
            numberOfUnits: 1,
            timestamp: TestClock.date(2026, 1, 5, hour: 1),
            nutritionDay: "2026-01-05"
        )

        XCTAssertEqual(NutritionDayBoundary.nutritionDay(for: event, calendar: calendar), day(5))

        let status = StreakEngine.status(events: [event], now: TestClock.date(2026, 1, 5, hour: 12), calendar: calendar)
        XCTAssertTrue(status.hasLoggedToday)
        XCTAssertEqual(status.length, 1)
    }

    func testAnEventWithoutARecordedDayStillUsesItsTimestamp() {
        let event = UsageEvent(foodId: "f", servingId: "s", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, 5, hour: 1))

        XCTAssertEqual(NutritionDayBoundary.nutritionDay(for: event, calendar: calendar), day(4))
        XCTAssertEqual(
            NutritionDayBoundary.nutritionDay(for: event, boundaryHour: NutritionDayBoundary.loggedDateBoundaryHour, calendar: calendar),
            day(5)
        )
    }

    func testAnUnparseableRecordedDayFallsBackToTheTimestamp() {
        let event = UsageEvent(foodId: "f", servingId: "s", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, 5), nutritionDay: "not a date")

        XCTAssertEqual(NutritionDayBoundary.nutritionDay(for: event, calendar: calendar), day(5))
    }

    func testOlderUsageFilesWithoutTheFieldStillDecode() throws {
        let json = #"[{"foodId":"f","servingId":"s","numberOfUnits":1,"timestamp":"2026-01-05T12:00:00Z"}]"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let events = try decoder.decode([UsageEvent].self, from: Data(json.utf8))

        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events[0].nutritionDay)
    }
}

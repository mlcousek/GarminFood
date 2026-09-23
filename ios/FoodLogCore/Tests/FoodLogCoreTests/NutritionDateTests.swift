// NutritionDateTests.swift

import XCTest
@testable import FoodLogCore

final class NutritionDateTests: XCTestCase {
    func testFormatsAKnownDateAsYearMonthDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 14
        components.hour = 8
        let date = calendar.date(from: components)!

        XCTAssertEqual(NutritionDate.string(from: date, calendar: calendar), "2026-09-14")
    }

    func testTodayStringUsesTheSuppliedCalendarsTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 1
        components.hour = 0
        components.minute = 30
        let justAfterMidnightUTC = calendar.date(from: components)!

        XCTAssertEqual(NutritionDate.todayString(now: justAfterMidnightUTC, calendar: calendar), "2026-01-01")
    }

    // MARK: - Day rollover (the Today tab after midnight)

    private func utcDate(_ day: Int, _ hour: Int, _ minute: Int = 0) -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
        return (date, calendar)
    }

    func testTheShownTodayRollsOverOnceMidnightHasPassed() {
        let (yesterdayStart, calendar) = utcDate(22, 0)
        let (lastCheck, _) = utcDate(22, 23, 58)
        let (afterMidnight, _) = utcDate(23, 0, 1)

        XCTAssertTrue(NutritionDate.shouldRollOver(selectedDay: yesterdayStart, previousToday: lastCheck, now: afterMidnight, calendar: calendar))
    }

    func testNothingRollsOverBeforeMidnight() {
        let (todayStart, calendar) = utcDate(22, 0)
        let (lastCheck, _) = utcDate(22, 8)
        let (lateEvening, _) = utcDate(22, 23, 59)

        XCTAssertFalse(NutritionDate.shouldRollOver(selectedDay: todayStart, previousToday: lastCheck, now: lateEvening, calendar: calendar))
    }

    func testAPastDayPickedOnPurposeStaysPut() {
        let (pickedDay, calendar) = utcDate(20, 0)
        let (lastCheck, _) = utcDate(22, 23, 58)
        let (afterMidnight, _) = utcDate(23, 0, 1)

        XCTAssertFalse(NutritionDate.shouldRollOver(selectedDay: pickedDay, previousToday: lastCheck, now: afterMidnight, calendar: calendar))
    }

    func testAlreadyRolledOverIsANoOp() {
        // A second day-change signal for the same midnight (both
        // notifications fire, or foreground races the observer).
        let (todayStart, calendar) = utcDate(23, 0)
        let (lastCheck, _) = utcDate(23, 0, 1)
        let (now, _) = utcDate(23, 0, 2)

        XCTAssertFalse(NutritionDate.shouldRollOver(selectedDay: todayStart, previousToday: lastCheck, now: now, calendar: calendar))
    }
}

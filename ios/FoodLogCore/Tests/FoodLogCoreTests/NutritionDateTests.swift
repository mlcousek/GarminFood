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
}

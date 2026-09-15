import XCTest
@testable import Gamification

final class NutritionDayBoundaryTests: XCTestCase {
    private let calendar = TestClock.calendar

    func testATimestampAtTheBoundaryHourBelongsToThatCalendarDay() {
        let date = TestClock.date(2026, 1, 5, hour: 4)
        let day = NutritionDayBoundary.nutritionDay(for: date, calendar: calendar)
        XCTAssertEqual(day, TestClock.date(2026, 1, 5, hour: 0))
    }

    func testATimestampJustBeforeTheBoundaryHourBelongsToThePreviousDay() {
        let date = TestClock.date(2026, 1, 5, hour: 3, minute: 59)
        let day = NutritionDayBoundary.nutritionDay(for: date, calendar: calendar)
        XCTAssertEqual(day, TestClock.date(2026, 1, 4, hour: 0))
    }

    func testDayStringMatchesTheYYYYMMDDFormat() {
        let date = TestClock.date(2026, 1, 5, hour: 12)
        XCTAssertEqual(NutritionDayBoundary.dayString(for: date, calendar: calendar), "2026-01-05")
    }

    func testDayStringForAnEarlyMorningTimestampUsesThePreviousDay() {
        let date = TestClock.date(2026, 1, 5, hour: 1)
        XCTAssertEqual(NutritionDayBoundary.dayString(for: date, calendar: calendar), "2026-01-04")
    }
}

// MealTypeDefaultingTests.swift
//
// Meal-type-from-time-of-day defaulting tests (food-log-entry spec's
// "Logging at a typical mealtime" scenario, task 16.1).

import XCTest
@testable import FoodLogCore
import GarminKit

final class MealTypeDefaultingTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 14
        components.hour = hour
        return utcCalendar.date(from: components)!
    }

    func testEarlyMorningDefaultsToBreakfast() {
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 7), calendar: utcCalendar), .breakfast)
    }

    func testMiddayDefaultsToLunch() {
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 12), calendar: utcCalendar), .lunch)
    }

    func testAfternoonDefaultsToSnacks() {
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 16), calendar: utcCalendar), .snacks)
    }

    func testEveningDefaultsToDinner() {
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 19), calendar: utcCalendar), .dinner)
    }

    func testLateNightDefaultsToDinnerRatherThanBreakfast() {
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 2), calendar: utcCalendar), .dinner)
    }

    func testBoundaryHoursBelongToTheLaterWindow() {
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 4), calendar: utcCalendar), .breakfast)
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 11), calendar: utcCalendar), .lunch)
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 15), calendar: utcCalendar), .snacks)
        XCTAssertEqual(MealTypeDefaulting.defaultMealType(for: date(hour: 18), calendar: utcCalendar), .dinner)
    }
}

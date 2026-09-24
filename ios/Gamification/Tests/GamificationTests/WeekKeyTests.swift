// WeekKeyTests.swift
//
// add-gamification-signals 5.1: ISO-8601 weeks across year boundaries,
// raw-value round trip, day keys and the Codable string form.

import XCTest
@testable import Gamification

final class WeekKeyTests: XCTestCase {
    private let calendar = TestClock.calendar

    private func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        WeekKey(date: TestClock.date(year, month, day), calendar: calendar).rawValue
    }

    func testMidYearWeek() {
        XCTAssertEqual(key(2026, 9, 24), "2026-W39")
        XCTAssertEqual(key(2026, 9, 21), "2026-W39") // Monday
        XCTAssertEqual(key(2026, 9, 27), "2026-W39") // Sunday
        XCTAssertEqual(key(2026, 9, 28), "2026-W40")
    }

    func testYearBoundaries() {
        XCTAssertEqual(key(2026, 12, 31), "2026-W53")
        XCTAssertEqual(key(2027, 1, 1), "2026-W53")
        XCTAssertEqual(key(2027, 1, 3), "2026-W53")
        XCTAssertEqual(key(2027, 1, 4), "2027-W01")
        XCTAssertEqual(key(2020, 12, 31), "2020-W53")
        XCTAssertEqual(key(2021, 1, 3), "2020-W53")
        XCTAssertEqual(key(2025, 12, 29), "2026-W01") // Monday belongs to the next ISO year
    }

    func testFirstWeekdayOfTheCalendarDoesNotMatter() {
        var sundayFirst = TestClock.calendar
        sundayFirst.firstWeekday = 1
        sundayFirst.minimumDaysInFirstWeek = 1
        XCTAssertEqual(WeekKey(date: TestClock.date(2026, 9, 27), calendar: sundayFirst).rawValue, "2026-W39")
    }

    func testRawValueRoundTripAndOrdering() {
        XCTAssertEqual(WeekKey(rawValue: "2026-W05"), WeekKey(yearForWeek: 2026, week: 5))
        XCTAssertEqual(WeekKey(yearForWeek: 2026, week: 5).rawValue, "2026-W05")
        XCTAssertNil(WeekKey(rawValue: "2026-39"))
        XCTAssertNil(WeekKey(rawValue: "2026-W54"))
        XCTAssertNil(WeekKey(rawValue: "garbage"))
        XCTAssertLessThan(WeekKey(yearForWeek: 2026, week: 53), WeekKey(yearForWeek: 2027, week: 1))
        XCTAssertLessThan(WeekKey(yearForWeek: 2026, week: 9), WeekKey(yearForWeek: 2026, week: 10))
    }

    func testDayKeysAreMondayToSunday() {
        let week = WeekKey(yearForWeek: 2026, week: 53)
        XCTAssertEqual(week.dayKeys(calendar: calendar), [
            "2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31",
            "2027-01-01", "2027-01-02", "2027-01-03",
        ])
        XCTAssertEqual(WeekKey(dayKey: "2027-01-02", calendar: calendar), week)
        XCTAssertNil(WeekKey(dayKey: "nope", calendar: calendar))
    }

    func testAddingWeeksCrossesTheYear() {
        let week = WeekKey(yearForWeek: 2026, week: 52)
        XCTAssertEqual(week.adding(weeks: 1, calendar: calendar)?.rawValue, "2026-W53")
        XCTAssertEqual(week.adding(weeks: 2, calendar: calendar)?.rawValue, "2027-W01")
        XCTAssertEqual(week.adding(weeks: -52, calendar: calendar)?.rawValue, "2025-W52")
    }

    func testCodableIsTheRawString() throws {
        let data = try JSONEncoder().encode([WeekKey(yearForWeek: 2026, week: 39)])
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\"2026-W39\"]")
        XCTAssertEqual(try JSONDecoder().decode([WeekKey].self, from: data), [WeekKey(yearForWeek: 2026, week: 39)])
    }
}

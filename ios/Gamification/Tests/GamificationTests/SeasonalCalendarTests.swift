// SeasonalCalendarTests.swift
//
// add-seasonal-events design D1/D4/D7: the computus known-answer table,
// every Easter-derived date for 2026 and 2027, the civil-date arithmetic
// behind window boundaries, and the name-day lookups (incl. folding).

import XCTest
import FoodLogCore
@testable import Gamification

final class SeasonalCalendarTests: XCTestCase {
    private func date(_ key: String) -> SeasonalDate {
        guard let value = SeasonalDate(dayKey: key) else {
            XCTFail("bad day key \(key)")
            return SeasonalDate(year: 1970, month: 1, day: 1)
        }
        return value
    }

    func testEasterSundayKnownAnswers() {
        let table: [Int: String] = [
            2019: "2019-04-21", 2024: "2024-03-31", 2025: "2025-04-20", 2026: "2026-04-05",
            2027: "2027-03-28", 2028: "2028-04-16", 2029: "2029-04-01", 2030: "2030-04-21",
            2038: "2038-04-25"
        ]
        for (year, expected) in table {
            XCTAssertEqual(SeasonalCalendar.easterSunday(year: year).dayKey, expected, "Easter \(year)")
        }
        let components = SeasonalCalendar.easterSundayComponents(year: 2026)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 4)
        XCTAssertEqual(components.day, 5)
    }

    func testDerivedDates2026() {
        XCTAssertEqual(SeasonalCalendar.fatThursday(year: 2026).dayKey, "2026-02-12")
        XCTAssertEqual(SeasonalCalendar.shroveTuesday(year: 2026).dayKey, "2026-02-17")
        XCTAssertEqual(SeasonalCalendar.ashWednesday(year: 2026).dayKey, "2026-02-18")
        XCTAssertEqual(SeasonalCalendar.maundyThursday(year: 2026).dayKey, "2026-04-02")
        XCTAssertEqual(SeasonalCalendar.easterMonday(year: 2026).dayKey, "2026-04-06")
    }

    func testDerivedDates2027() {
        XCTAssertEqual(SeasonalCalendar.fatThursday(year: 2027).dayKey, "2027-02-04")
        XCTAssertEqual(SeasonalCalendar.shroveTuesday(year: 2027).dayKey, "2027-02-09")
        XCTAssertEqual(SeasonalCalendar.ashWednesday(year: 2027).dayKey, "2027-02-10")
        XCTAssertEqual(SeasonalCalendar.maundyThursday(year: 2027).dayKey, "2027-03-25")
        XCTAssertEqual(SeasonalCalendar.easterMonday(year: 2027).dayKey, "2027-03-29")
    }

    func testCivilArithmeticRoundTripsAndCrossesBoundaries() {
        XCTAssertEqual(date("1970-01-01").ordinal, 0)
        XCTAssertEqual(date("2026-12-31").adding(days: 1).dayKey, "2027-01-01")
        XCTAssertEqual(date("2028-02-28").adding(days: 1).dayKey, "2028-02-29")
        XCTAssertEqual(date("2027-02-28").adding(days: 1).dayKey, "2027-03-01")
        XCTAssertEqual(date("2026-03-01").adding(days: -1).dayKey, "2026-02-28")
        XCTAssertEqual(date("2026-11-08").days(until: date("2026-11-16")), 8)
        for offset in stride(from: -800, through: 800, by: 37) {
            let day = date("2026-09-24").adding(days: offset)
            XCTAssertEqual(SeasonalDate(dayKey: day.dayKey), day)
            XCTAssertEqual(day.adding(days: -offset).dayKey, "2026-09-24")
        }
    }

    func testDayKeyParsing() {
        XCTAssertEqual(SeasonalDate(dayKey: "2026-09-24"), SeasonalDate(year: 2026, month: 9, day: 24))
        XCTAssertNil(SeasonalDate(dayKey: ""))
        XCTAssertNil(SeasonalDate(dayKey: "2026-13-01"))
        XCTAssertNil(SeasonalDate(dayKey: "not-a-date"))
        XCTAssertTrue(date("2026-12-31") < date("2027-01-01"))
    }

    func testMonthDayExistence() {
        let leapDay = SeasonalCalendar.MonthDay(month: 2, day: 29)
        XCTAssertTrue(leapDay.exists(in: 2028))
        XCTAssertFalse(leapDay.exists(in: 2026))
        XCTAssertTrue(SeasonalCalendar.MonthDay(month: 4, day: 24).exists(in: 2026))
    }

    // MARK: - Name days (D4)

    func testNameDayKnownAnswers() {
        let expected: [String: SeasonalCalendar.MonthDay] = [
            "Jiří": .init(month: 4, day: 24),
            "Jan": .init(month: 6, day: 24),
            "Josef": .init(month: 3, day: 19),
            "Václav": .init(month: 9, day: 28),
            "Martin": .init(month: 11, day: 11),
            "Marie": .init(month: 9, day: 12),
            "Petr": .init(month: 2, day: 22),
            "Pavel": .init(month: 6, day: 29),
            "Eva": .init(month: 12, day: 24)
        ]
        for (name, day) in expected {
            XCTAssertEqual(CzechNameDays.nameDay(forFirstName: name), day, name)
        }
    }

    func testNameDayLookupFoldsDiacriticsAndCase() {
        let jiri = SeasonalCalendar.MonthDay(month: 4, day: 24)
        XCTAssertEqual(CzechNameDays.nameDay(forFirstName: "Jiri"), jiri)
        XCTAssertEqual(CzechNameDays.nameDay(forFirstName: "JIŘÍ"), jiri)
        XCTAssertEqual(CzechNameDays.nameDay(forFirstName: "  jiří "), jiri)
        let firstName = ProfileSignals.firstName(fromFullName: "Jiří Mlčoušek")
        XCTAssertEqual(CzechNameDays.nameDay(forFirstName: firstName), jiri)
    }

    func testUnknownOrBlankNameHasNoNameDay() {
        XCTAssertNil(CzechNameDays.nameDay(forFirstName: "Xyzzy"))
        XCTAssertNil(CzechNameDays.nameDay(forFirstName: ""))
        XCTAssertNil(CzechNameDays.nameDay(forFirstName: nil))
    }

    func testTableCoversEveryNonHolidayDay() {
        XCTAssertEqual(CzechNameDays.namedDayCount, 359)
        XCTAssertTrue(CzechNameDays.names(on: .init(month: 1, day: 1)).isEmpty)
        XCTAssertTrue(CzechNameDays.names(on: .init(month: 12, day: 25)).isEmpty)
        for month in 1...12 {
            for day in (CzechNameDays.rows[month] ?? [:]).keys {
                XCTAssertTrue(SeasonalCalendar.MonthDay(month: month, day: day).exists(in: 2028), "\(month)-\(day)")
            }
        }
    }
}


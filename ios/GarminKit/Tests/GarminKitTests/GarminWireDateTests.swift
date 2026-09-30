// GarminWireDateTests.swift
//
// fix-review-findings-2026-09-b, finding 1: every date Garmin sees (a
// request path's day, a write body's date/timestamp) and every date read
// back from it is Gregorian, whatever calendar the phone is set to. The
// non-Gregorian calendars are injected (never `Calendar.current` mutated):
// the first test proves they really would have produced another year
// through a formatter left on the device calendar, so the rest isn't
// passing by accident.

import XCTest
@testable import GarminKit

final class GarminWireDateTests: XCTestCase {
    private let prague = TimeZone(identifier: "Europe/Prague")!

    /// 2026-09-29T22:30:00Z = 2026-09-30 00:30 in Prague (CEST).
    private let justAfterMidnightInPrague = Date(timeIntervalSince1970: 1_790_721_000)

    private func calendar(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = prague
        return calendar
    }

    func testADeviceCalendarFormatterReallyWritesAnotherYear() {
        // The bug being fixed: a formatter on the device's calendar.
        for (identifier, year) in [(Calendar.Identifier.buddhist, "2569"), (.japanese, "0008")] {
            let deviceFormatter = DateFormatter()
            deviceFormatter.calendar = calendar(identifier)
            deviceFormatter.timeZone = prague
            deviceFormatter.dateFormat = "yyyy-MM-dd"
            XCTAssertEqual(deviceFormatter.string(from: justAfterMidnightInPrague), "\(year)-09-30", "\(identifier)")
        }
    }

    func testDayStringIsTheGregorianLocalDay() {
        XCTAssertEqual(GarminWireDate.dayString(from: justAfterMidnightInPrague, timeZone: prague), "2026-09-30",
                       "the local day in the given zone, one day ahead of the UTC instant")
        XCTAssertEqual(GarminWireDate.dayString(from: justAfterMidnightInPrague, timeZone: TimeZone(identifier: "UTC")!), "2026-09-29")
    }

    func testANonGregorianCalendarContributesOnlyItsTimeZone() {
        for identifier in [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura, .hebrew] {
            let deviceCalendar = calendar(identifier)
            XCTAssertEqual(GarminWireDate.dayString(from: justAfterMidnightInPrague, timeZone: deviceCalendar.timeZone), "2026-09-30", "\(identifier)")
            XCTAssertEqual(GarminWireDate.calendar(timeZone: deviceCalendar.timeZone).identifier, .gregorian)
        }
    }

    func testDayKeysParseBackToTheSameLocalDay() throws {
        let start = try XCTUnwrap(GarminWireDate.startOfDay(fromDayString: "2026-09-30", timeZone: prague))
        XCTAssertEqual(start, Date(timeIntervalSince1970: 1_790_719_200), "2026-09-30 00:00 CEST")
        let noon = try XCTUnwrap(GarminWireDate.noon(ofDayString: "2026-09-30", timeZone: prague))
        XCTAssertEqual(noon, Date(timeIntervalSince1970: 1_790_762_400), "2026-09-30 12:00 CEST")
        XCTAssertNil(GarminWireDate.startOfDay(fromDayString: "not a day", timeZone: prague))
        XCTAssertNil(GarminWireDate.noon(ofDayString: "2026-09", timeZone: prague))
    }

    func testLocalTimestampsRoundTripAsGregorianWallClock() throws {
        let text = GarminWireDate.localTimestampString(justAfterMidnightInPrague, timeZone: prague)
        XCTAssertEqual(text, "2026-09-30T00:30:00.000")
        XCTAssertEqual(GarminWireDate.parseLocalTimestamp(text, timeZone: prague), justAfterMidnightInPrague)
        XCTAssertEqual(GarminWireDate.parseLocalTimestamp("2026-09-30T00:30:00", timeZone: prague), justAfterMidnightInPrague)
        XCTAssertNil(GarminWireDate.parseLocalTimestamp("30.09.2026 00:30", timeZone: prague))
    }

    func testISOTimestampsRoundTrip() {
        let text = GarminWireDate.isoTimestampString(justAfterMidnightInPrague)
        XCTAssertEqual(text, "2026-09-29T22:30:00.000Z")
        XCTAssertEqual(GarminWireDate.parseISOTimestamp(text), justAfterMidnightInPrague)
        XCTAssertEqual(GarminWireDate.parseISOTimestamp("2026-09-29T22:30:00Z"), justAfterMidnightInPrague)
    }

    func testWriteBodiesUseGregorianDates() {
        // The weigh-in / drink bodies take the device's time zone; with the
        // helper their year can't depend on the device calendar any more.
        let weighIn = WeighInWriteBody.make(for: AddWeighInRequest(weightKg: 80, loggedAt: justAfterMidnightInPrague), timeZone: calendar(.buddhist).timeZone)
        XCTAssertEqual(weighIn.dateTimestamp, "2026-09-30T00:30:00.000")
        XCTAssertEqual(weighIn.gmtTimestamp, "2026-09-29T22:30:00.000")

        let drink = HydrationWriteBody.make(for: AddHydrationRequest(valueInML: 250, loggedAt: justAfterMidnightInPrague), timeZone: calendar(.japanese).timeZone)
        XCTAssertEqual(drink.calendarDate, "2026-09-30")
        XCTAssertEqual(drink.timestampLocal, "2026-09-30T00:30:00.000")

        XCTAssertEqual(WeightSync.localCalendarDate(of: justAfterMidnightInPrague, timeZone: prague), "2026-09-30")
    }
}

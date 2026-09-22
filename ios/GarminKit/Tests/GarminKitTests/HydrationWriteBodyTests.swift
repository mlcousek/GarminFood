// HydrationWriteBodyTests.swift
//
// Pins `HydrationWriteBody`'s date/timestamp formatting to the exact shape
// python-garminconnect's `add_hydration_data` produces (see GarminModels
// .swift's doc comment for the citation): `calendarDate` is the LOCAL date
// of the entry, `timestampLocal` reuses `WeighInWriteBody.timestampString`'s
// naive-local-time, millisecond-precision format -- same idea as
// WeighInWriteBodyTests.swift, just for hydration's two fields instead of
// weight's `dateTimestamp`/`gmtTimestamp` pair.

import XCTest
@testable import GarminKit

final class HydrationWriteBodyTests: XCTestCase {
    private func instant(_ iso: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    func testMakeRendersCalendarDateAndTimestampInTheGivenLocalZone() {
        // Prague (CEST, UTC+2 in September) -- chosen for the same reason
        // WeighInWriteBodyTests.swift uses it: the owner's own timezone,
        // and it makes the local/UTC divergence obvious.
        let prague = TimeZone(identifier: "Europe/Prague")!
        let date = instant("2026-09-22T22:30:00.000Z") // 00:30 local in Prague, next calendar day

        let body = HydrationWriteBody.make(for: AddHydrationRequest(valueInML: 250, loggedAt: date), timeZone: prague)

        XCTAssertEqual(body.calendarDate, "2026-09-23", "the LOCAL date, one day ahead of the UTC instant")
        XCTAssertEqual(body.timestampLocal, "2026-09-23T00:30:00.000")
        XCTAssertEqual(body.valueInML, 250)
    }

    func testMakeInUTCLeavesCalendarDateMatchingTheInstantsOwnDate() {
        let utc = TimeZone(identifier: "UTC")!
        let date = instant("2026-09-22T08:30:00.000Z")

        let body = HydrationWriteBody.make(for: AddHydrationRequest(valueInML: 500, loggedAt: date), timeZone: utc)

        XCTAssertEqual(body.calendarDate, "2026-09-22")
        XCTAssertEqual(body.timestampLocal, "2026-09-22T08:30:00.000")
    }
}

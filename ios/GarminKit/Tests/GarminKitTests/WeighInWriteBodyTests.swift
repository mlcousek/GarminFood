// WeighInWriteBodyTests.swift
//
// Pins `WeighInWriteBody`'s timestamp formatting to the exact shape
// python-garminconnect's `_fmt_ts` produces (see GarminModels.swift's doc
// comment for the citation): naive local time, millisecond precision, no
// offset/`Z` suffix, and a `gmtTimestamp` that is the SAME instant
// converted to UTC rather than a second independent value.

import XCTest
@testable import GarminKit

final class WeighInWriteBodyTests: XCTestCase {
    private func instant(_ iso: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    func testTimestampStringFormatsMillisecondPrecisionWithNoOffset() {
        let date = instant("2026-09-22T08:30:00.123Z")
        let utc = TimeZone(identifier: "UTC")!

        let formatted = WeighInWriteBody.timestampString(date, timeZone: utc)

        XCTAssertEqual(formatted, "2026-09-22T08:30:00.123")
    }

    func testMakeRendersDateTimestampInTheGivenLocalZoneAndGmtTimestampInUTC() {
        // Prague (CEST, UTC+2 in September) -- chosen because it's the
        // owner's own timezone and makes the local/UTC divergence obvious.
        let prague = TimeZone(identifier: "Europe/Prague")!
        let date = instant("2026-09-22T08:30:00.000Z") // 10:30 local in Prague

        let body = WeighInWriteBody.make(for: AddWeighInRequest(weightKg: 75.5, loggedAt: date), timeZone: prague)

        XCTAssertEqual(body.dateTimestamp, "2026-09-22T10:30:00.000", "local wall-clock time, 2h ahead of UTC in September")
        XCTAssertEqual(body.gmtTimestamp, "2026-09-22T08:30:00.000", "the same instant, converted to UTC")
        XCTAssertEqual(body.unitKey, "kg")
        XCTAssertEqual(body.sourceType, "MANUAL")
        XCTAssertEqual(body.value, 75.5)
    }

    func testMakeInUTCLeavesBothTimestampsEqual() {
        let utc = TimeZone(identifier: "UTC")!
        let date = instant("2026-09-22T08:30:00.000Z")

        let body = WeighInWriteBody.make(for: AddWeighInRequest(weightKg: 80, loggedAt: date), timeZone: utc)

        XCTAssertEqual(body.dateTimestamp, body.gmtTimestamp)
    }
}

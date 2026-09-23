// DailyUserSummaryTests.swift
//
// Pins `DailyUserSummary`'s decoding to the payload shape observed live on
// 2026-09-23 (GET /usersummary-service/usersummary/daily?calendarDate=
// 2026-09-22, read-only probe via tools/garmin-get.mjs). The fixture keeps
// the real calorie values and a handful of the unrelated neighbouring
// fields (including the null `consumedKilocalories`) so a decode that
// accidentally depended on them would fail here, not on device. Exists
// because the home screen's "Active today" line hides itself on any decode
// failure -- a silent failure mode, so the shape is pinned here instead.

import XCTest
@testable import GarminKit

final class DailyUserSummaryTests: XCTestCase {
    /// Trimmed from the real 2026-09-22 response; values unchanged.
    private let probedPayload = """
    {
      "userProfileId": 12345678,
      "totalKilocalories": 3283,
      "activeKilocalories": 1031,
      "bmrKilocalories": 2252,
      "wellnessKilocalories": 3283,
      "burnedKilocalories": null,
      "consumedKilocalories": null,
      "remainingKilocalories": 3978,
      "totalSteps": 14210,
      "wellnessActiveKilocalories": 1031,
      "netRemainingKilocalories": 3978,
      "calendarDate": "2026-09-22"
    }
    """

    func testDecodesTheProbedCalorieFields() throws {
        let summary = try JSONDecoder().decode(DailyUserSummary.self, from: Data(probedPayload.utf8))

        XCTAssertEqual(summary.calendarDate, "2026-09-22")
        XCTAssertEqual(summary.activeKilocalories, 1031)
        XCTAssertEqual(summary.bmrKilocalories, 2252)
        XCTAssertEqual(summary.totalKilocalories, 3283)
    }

    func testMissingOrNullCalorieFieldsDecodeAsNilRatherThanFailing() throws {
        let sparse = """
        { "calendarDate": "2026-09-23", "activeKilocalories": null }
        """

        let summary = try JSONDecoder().decode(DailyUserSummary.self, from: Data(sparse.utf8))

        XCTAssertNil(summary.activeKilocalories)
        XCTAssertNil(summary.bmrKilocalories)
        XCTAssertNil(summary.totalKilocalories)
    }

    func testFractionalValuesAreKept() throws {
        let fractional = """
        { "activeKilocalories": 290.5 }
        """

        let summary = try JSONDecoder().decode(DailyUserSummary.self, from: Data(fractional.utf8))

        XCTAssertEqual(summary.activeKilocalories, 290.5)
    }
}

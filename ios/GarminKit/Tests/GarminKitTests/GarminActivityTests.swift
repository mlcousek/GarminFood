// GarminActivityTests.swift
//
// Pins `GarminActivity`'s decoding to the payload shape observed by the
// read-only probe of `/activitylist-service/activities/search/activities`
// on 2026-09-24 (docs/garmin-routes.json `activitiesSearch`). The real
// items carry ~78 keys; this fixture keeps the ones the project reads plus
// a few unrelated neighbours so a decode that accidentally depended on
// them (or choked on them) fails here, not on device. The mobility item
// has no `distance`, as observed.

import XCTest
@testable import GarminKit

final class GarminActivityTests: XCTestCase {
    private let trimmedPayload = """
    [
      {
        "activityId": 20512345678,
        "activityName": "Prague Walking",
        "startTimeLocal": "2026-09-23 19:22:08",
        "startTimeGMT": "2026-09-23 17:22:08",
        "activityType": { "typeId": 9, "typeKey": "walking", "parentTypeId": 17, "isHidden": false },
        "eventType": { "typeId": 9, "typeKey": "uncategorized" },
        "distance": 3210.5,
        "duration": 2400.123,
        "elapsedDuration": 2460.0,
        "calories": 180.0,
        "averageHR": 101.0,
        "hasPolyline": true
      },
      {
        "activityId": 20512345000,
        "activityName": "Prague Running",
        "startTimeLocal": "2026-09-23 07:10:00",
        "startTimeGMT": "2026-09-23 05:10:00",
        "activityType": { "typeId": 1, "typeKey": "running", "parentTypeId": 17 },
        "distance": 9000.0,
        "duration": 2700.0,
        "calories": 610.0,
        "vO2MaxValue": 54.0
      },
      {
        "activityId": 20511111111,
        "activityName": "Mobility",
        "startTimeLocal": "2026-09-22 21:00:00",
        "startTimeGMT": "2026-09-22 19:00:00",
        "activityType": { "typeId": 254, "typeKey": "mobility" },
        "duration": 900.0,
        "calories": 30.0
      }
    ]
    """

    func testDecodesTheProbedFieldsAndIgnoresUnknownKeys() throws {
        let activities = try JSONDecoder().decode([GarminActivity].self, from: Data(trimmedPayload.utf8))

        XCTAssertEqual(activities.count, 3)
        XCTAssertEqual(activities[0].activityId, 20512345678)
        XCTAssertEqual(activities[0].typeKey, "walking")
        XCTAssertEqual(activities[0].startTimeLocal, "2026-09-23 19:22:08")
        XCTAssertEqual(activities[0].startTimeGMT, "2026-09-23 17:22:08")
        XCTAssertEqual(activities[0].duration ?? 0, 2400.123, accuracy: 0.001)
        XCTAssertEqual(activities[0].calories, 180)
        XCTAssertEqual(activities[0].distance ?? 0, 3210.5, accuracy: 0.001)

        XCTAssertEqual(activities[1].typeKey, "running")
        XCTAssertEqual(activities[1].distance, 9000)
    }

    func testMissingDistanceDecodesAsNil() throws {
        let activities = try JSONDecoder().decode([GarminActivity].self, from: Data(trimmedPayload.utf8))

        XCTAssertEqual(activities[2].typeKey, "mobility")
        XCTAssertNil(activities[2].distance)
        XCTAssertEqual(activities[2].duration, 900)
    }

    func testAnEmptyItemStillDecodes() throws {
        let activities = try JSONDecoder().decode([GarminActivity].self, from: Data("[{}]".utf8))

        XCTAssertEqual(activities.count, 1)
        XCTAssertNil(activities[0].activityId)
        XCTAssertNil(activities[0].typeKey)
    }
}

// ActivityCacheStoreTests.swift
//
// add-gamification-signals 4.2: GMT start parsing, local-date day
// assignment, covered-days semantics (`[]` = read and none vs `nil` =
// never read), active kcal, the 120-day cap and reload from disk. Real
// store on a temp file (project convention).

import XCTest
@testable import FoodLogCore
import GarminKit

final class ActivityCacheStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("activitycache-\(UUID().uuidString).json")
    }

    func testAdapterUsesGMTInstantAndLocalDate() throws {
        // A late-evening run in UTC+2: local date is the 24th, GMT the 23rd.
        let garmin = GarminActivity(
            activityId: 42,
            startTimeLocal: "2026-09-24 00:30:00",
            startTimeGMT: "2026-09-23 22:30:00",
            activityType: GarminActivity.ActivityType(typeKey: "running"),
            duration: 1800,
            calories: 300,
            distance: 5000
        )
        let summary = try XCTUnwrap(ActivitySummary(garmin: garmin))
        XCTAssertEqual(summary.id, "42")
        XCTAssertEqual(summary.day, "2026-09-24")
        XCTAssertEqual(summary.start, ISO8601DateFormatter().date(from: "2026-09-23T22:30:00Z"))
        XCTAssertEqual(summary.typeKey, "running")
        XCTAssertEqual(summary.durationMinutes, 30)
        XCTAssertEqual(summary.distanceM, 5000)
    }

    func testAdapterDropsUnplaceableActivities() {
        XCTAssertNil(ActivitySummary(garmin: GarminActivity(activityId: 1, startTimeLocal: "2026-09-24 00:30:00")))
        XCTAssertNil(ActivitySummary(garmin: GarminActivity(startTimeLocal: "2026-09-24 00:30:00", startTimeGMT: "2026-09-23 22:30:00")))
        XCTAssertNil(ActivitySummary(garmin: GarminActivity(activityId: 1, startTimeLocal: "garbage", startTimeGMT: "2026-09-23 22:30:00")))
    }

    func testParseGMTAcceptsFractionAndTSeparator() {
        let expected = ISO8601DateFormatter().date(from: "2026-09-23T19:22:08Z")
        XCTAssertEqual(ActivityCacheStore.parseGMT("2026-09-23 19:22:08"), expected)
        XCTAssertEqual(ActivityCacheStore.parseGMT("2026-09-23T19:22:08.0"), expected)
        XCTAssertNil(ActivityCacheStore.parseGMT("yesterday"))
    }

    func testCoveredDaysGetEmptyListAndOthersStayUnknown() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ActivityCacheStore(fileURL: url)
        let walk = GarminActivity(activityId: 7, startTimeLocal: "2026-09-22 08:00:00", startTimeGMT: "2026-09-22 06:00:00",
                                  activityType: GarminActivity.ActivityType(typeKey: "walking"), duration: 2400)
        let outside = GarminActivity(activityId: 8, startTimeLocal: "2026-09-10 08:00:00", startTimeGMT: "2026-09-10 06:00:00",
                                     activityType: GarminActivity.ActivityType(typeKey: "running"), duration: 600)
        try await store.recordActivities(fromGarmin: [walk, walk, outside], coveringDays: ["2026-09-22", "2026-09-23"])

        let day22 = await store.day("2026-09-22")
        XCTAssertEqual(day22?.activities?.map(\.id), ["7"])
        let day23 = await store.day("2026-09-23")
        XCTAssertEqual(day23?.activities, [])
        let day10 = await store.day("2026-09-10")
        XCTAssertNil(day10)
    }

    func testActiveKcalIsKeptAlongsideActivitiesAndReloads() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ActivityCacheStore(fileURL: url)
        try await store.recordActiveKcal(640, day: "2026-09-22")
        try await store.recordActiveKcal(nil, day: "2026-09-22")
        try await store.recordActivities([], coveringDays: ["2026-09-22"])

        let reloaded = await ActivityCacheStore(fileURL: url).day("2026-09-22")
        XCTAssertEqual(reloaded?.activeKcal, 640)
        XCTAssertEqual(reloaded?.activities, [])
    }

    func testCapKeepsNewest120Days() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ActivityCacheStore(fileURL: url)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!
        let keys = (0..<130).map { NutritionDate.string(from: calendar.date(byAdding: .day, value: $0, to: start)!, calendar: calendar) }
        try await store.recordActivities([], coveringDays: keys)
        let all = await store.all()
        XCTAssertEqual(all.count, ActivityCacheStore.maxDays)
        XCTAssertEqual(all.first?.day, keys[10])
        XCTAssertEqual(all.last?.day, keys[129])
    }
}

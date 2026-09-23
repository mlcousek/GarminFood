// UsageMealBackfillTests.swift
//
// `UsageMealBackfill` fills the meal of pre-2026-09-23 usage events from
// Garmin's day logs, so "Usual for <meal>" isn't empty after the upgrade.
// Pure-function tests plus one store round trip (real file in a temp dir,
// same convention as LogEntryCoordinatorTests).

import XCTest
@testable import FoodLogCore
import GarminKit

final class UsageMealBackfillTests: XCTestCase {
    private var utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-09-20 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_789_905_600)

    private func event(
        _ foodId: String,
        day: String?,
        mealType: MealType? = nil,
        daysAgo: Double = 1
    ) -> UsageEvent {
        UsageEvent(
            foodId: foodId,
            servingId: "s-\(foodId)",
            numberOfUnits: 1,
            timestamp: now.addingTimeInterval(-daysAgo * 86_400),
            nutritionDay: day,
            mealType: mealType
        )
    }

    /// Oats at breakfast; soup at lunch; coffee at BOTH breakfast and
    /// snacks (ambiguous); a calories-only quick add with an empty id.
    private func log() throws -> DailyFoodLog {
        let json = """
        { "mealDetails": [
          { "meal": { "mealName": "BREAKFAST" }, "loggedFoods": [
            { "logId": "a", "foodMetaData": { "foodId": "oats" } },
            { "logId": "b", "foodMetaData": { "foodId": "coffee" } },
            { "logId": "c", "foodMetaData": { "foodId": "" } }
          ] },
          { "meal": { "mealName": "LUNCH" }, "loggedFoods": [
            { "logId": "d", "foodMetaData": { "foodId": "soup" } }
          ] },
          { "meal": { "mealName": "SNACKS" }, "loggedFoods": [
            { "logId": "e", "foodMetaData": { "foodId": "coffee" } }
          ] }
        ] }
        """
        return try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    func testFillsOnlyUnambiguousFoundFoods() throws {
        let events = [
            event("oats", day: "2026-09-19"),
            event("soup", day: "2026-09-19"),
            event("coffee", day: "2026-09-19"),
            event("pizza", day: "2026-09-19"),
        ]
        let result = UsageMealBackfill.apply(to: events, logs: ["2026-09-19": try log()], calendar: utc)

        XCTAssertEqual(result.filled, 2)
        XCTAssertEqual(result.events.map(\.mealType), [.breakfast, .lunch, nil, nil],
                       "coffee sits in two meals (ambiguous) and pizza isn't in the log: both stay nil")
        XCTAssertEqual(result.events.map(\.foodId), events.map(\.foodId), "order and identity kept")
        XCTAssertEqual(result.events.map(\.servingId), events.map(\.servingId))
        XCTAssertEqual(result.events.map(\.nutritionDay), events.map(\.nutritionDay))
    }

    func testNeverOverwritesAnExistingMeal() throws {
        let events = [event("oats", day: "2026-09-19", mealType: .dinner)]
        let result = UsageMealBackfill.apply(to: events, logs: ["2026-09-19": try log()], calendar: utc)
        XCTAssertEqual(result.filled, 0)
        XCTAssertEqual(result.events.first?.mealType, .dinner)
    }

    func testEventWithoutNutritionDayFallsBackToItsTimestampDay() throws {
        // Logged 1 day before `now` = 2026-09-19 (UTC).
        let events = [event("soup", day: nil, daysAgo: 1)]
        let result = UsageMealBackfill.apply(to: events, logs: ["2026-09-19": try log()], calendar: utc)
        XCTAssertEqual(result.events.first?.mealType, .lunch)
    }

    func testDayWithoutALogIsLeftAlone() throws {
        let events = [event("oats", day: "2026-09-18")]
        let result = UsageMealBackfill.apply(to: events, logs: ["2026-09-19": try log()], calendar: utc)
        XCTAssertEqual(result.filled, 0)
        XCTAssertNil(result.events.first?.mealType)
    }

    func testDaysNeedingBackfillAreRecentLegacyDaysNewestFirst() {
        let events = [
            event("a", day: "2026-09-17", daysAgo: 3),
            event("b", day: "2026-09-19", daysAgo: 1),
            event("c", day: "2026-09-19", daysAgo: 1),
            event("d", day: "2026-09-18", mealType: .lunch, daysAgo: 2),  // already has a meal
            event("e", day: "2026-08-01", daysAgo: 50),                    // beyond the lookback
        ]
        let days = UsageMealBackfill.daysNeedingBackfill(events, now: now, calendar: utc)
        XCTAssertEqual(days, ["2026-09-19", "2026-09-17"])
    }

    func testBackfilledEventsReachTheUsualShelf() throws {
        let events = (0..<3).map { _ in event("oats", day: "2026-09-19") }
        XCTAssertTrue(MealUsualRanker.rank(events: events, mealType: .breakfast, now: now).isEmpty,
                      "precondition: legacy events never count")
        let filled = UsageMealBackfill.apply(to: events, logs: ["2026-09-19": try log()], calendar: utc).events
        XCTAssertEqual(MealUsualRanker.rank(events: filled, mealType: .breakfast, now: now).map(\.foodId), ["oats"])
    }

    func testStorePersistsTheBackfillAndKeepsNewerEvents() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UsageMealBackfillTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("usage-history.json")

        let store = UsageHistoryStore(fileURL: fileURL)
        try await store.record(foodId: "soup", servingId: "s1", numberOfUnits: 1, nutritionDay: "2026-09-19")
        try await store.record(foodId: "tea", servingId: "s2", numberOfUnits: 1, nutritionDay: "2026-09-20", mealType: .snacks)

        let filled = try await store.applyMealBackfill(["2026-09-19": try log()])
        XCTAssertEqual(filled, 1)

        let reloaded = await UsageHistoryStore(fileURL: fileURL).all()
        XCTAssertEqual(reloaded.map(\.foodId), ["soup", "tea"])
        XCTAssertEqual(reloaded.map(\.mealType), [.lunch, .snacks])

        let again = try await store.applyMealBackfill(["2026-09-19": try log()])
        XCTAssertEqual(again, 0, "idempotent: nothing left to fill")
    }
}

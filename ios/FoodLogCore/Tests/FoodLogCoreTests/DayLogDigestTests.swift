// DayLogDigestTests.swift
//
// add-gamification-signals 4.1: the `DailyFoodLog` -> `DayLogDigest`
// adapter (fibre/sugar/goals, meal resolution, de-dup of an entry present
// both under its meal and in `loggedFoodsWithServingSizes`) and the store's
// 120-day cap and corrupt-file quarantine. Real store on a temp file, never
// mocked (project convention). All ids/names synthetic.

import XCTest
@testable import FoodLogCore
import GarminKit

final class DayLogDigestTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func decodeLog(_ json: String) throws -> DailyFoodLog {
        try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    private let sampleLog = """
    {
      "mealDate": "2026-09-23",
      "dailyNutritionGoals": { "calories": 2300, "adjustedCalories": 2900, "protein": 115, "carbs": 316, "fat": 64 },
      "dailyNutritionContent": { "calories": 850, "protein": 40, "carbs": 90, "fat": 30, "fiber": 12.5, "sugar": 33 },
      "mealDetails": [
        { "meal": { "mealId": 111, "mealName": "BREAKFAST" },
          "loggedFoods": [
            { "logId": "a1", "logTimestamp": "2026-09-23T06:30:00.000Z", "logSource": "GCW", "mealId": 111,
              "foodMetaData": { "foodId": "f-oat", "foodName": "Ovesné vločky", "brandName": "Emco" },
              "nutritionContent": { "calories": 350, "protein": 12, "carbs": 60, "fat": 6, "fiber": 9, "sugar": 1 } }
          ] },
        { "meal": { "mealId": 222, "mealName": "LUNCH" }, "loggedFoods": [] }
      ],
      "loggedFoodsWithServingSizes": [
        { "logId": "a1", "logTimestamp": "2026-09-23T06:30:00.000Z", "mealId": 111,
          "foodMetaData": { "foodId": "f-oat", "foodName": "Ovesné vločky" } },
        { "logId": "b2", "logTimestamp": "2026-09-23T11:05:00Z", "logSource": "GCM", "mealId": 222,
          "foodMetaData": { "foodId": "f-fish", "foodName": "Losos" },
          "nutritionContent": { "calories": 500, "protein": 28, "carbs": 30, "fat": 24 } }
      ]
    }
    """

    func testAdapterMapsTotalsFibreSugarAndGoals() throws {
        let digest = DayLogDigest(log: try decodeLog(sampleLog), day: "2026-09-23", fetchedAt: fetchedAt)
        XCTAssertEqual(digest.day, "2026-09-23")
        XCTAssertEqual(digest.fetchedAt, fetchedAt)
        XCTAssertEqual(digest.totals.calories, 850)
        XCTAssertEqual(digest.totals.fiber, 12.5)
        XCTAssertEqual(digest.totals.sugar, 33)
        // Base goal wins over the activity-adjusted one (same rule as
        // GamificationEngine.refreshGoalStatus).
        XCTAssertEqual(digest.goals, MacroGoals(calories: 2300, protein: 115, carbs: 316, fat: 64))
    }

    func testAdapterDeduplicatesAndResolvesMeals() throws {
        let digest = DayLogDigest(log: try decodeLog(sampleLog), day: "2026-09-23", fetchedAt: fetchedAt)
        XCTAssertEqual(digest.entries.map(\.foodId), ["f-oat", "f-fish"])

        let oat = digest.entries[0]
        XCTAssertEqual(oat.name, "Ovesné vločky")
        XCTAssertEqual(oat.brand, "Emco")
        XCTAssertEqual(oat.mealType, "BREAKFAST")
        XCTAssertEqual(oat.fiber, 9)
        XCTAssertEqual(oat.fromThisApp, true)
        XCTAssertEqual(oat.timestamp, ISO8601DateFormatter().date(from: "2026-09-23T06:30:00Z"))

        // A loose entry's meal comes from this day's meal instance id.
        let fish = digest.entries[1]
        XCTAssertEqual(fish.mealType, "LUNCH")
        XCTAssertNil(fish.fiber)
        XCTAssertEqual(fish.fromThisApp, false)
    }

    func testMissingFibreOnALoggedDayIsUnknownNotZero() throws {
        let json = """
        { "dailyNutritionContent": { "calories": 100, "protein": 1, "carbs": 2, "fat": 3 },
          "loggedFoodsWithServingSizes": [ { "logId": "x", "foodMetaData": { "foodId": "f1", "foodName": "Rohlík" } } ] }
        """
        let digest = DayLogDigest(log: try decodeLog(json), day: "2026-09-20", fetchedAt: fetchedAt)
        XCTAssertNil(digest.totals.fiber)
        XCTAssertNil(digest.totals.sugar)
        XCTAssertNil(digest.goals)
        XCTAssertNil(digest.entries.first?.mealType)
    }

    // MARK: - Store

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("daylogdigest-\(UUID().uuidString).json")
    }

    private func digest(_ day: String) -> DayLogDigest {
        DayLogDigest(day: day, fetchedAt: fetchedAt, totals: .zero, goals: nil, entries: [])
    }

    func testStoreRoundTripsThroughDisk() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = DayLogDigest(log: try decodeLog(sampleLog), day: "2026-09-23", fetchedAt: fetchedAt)
        try await DayLogDigestStore(fileURL: url).save(original)

        let reloaded = await DayLogDigestStore(fileURL: url).digest(for: "2026-09-23")
        XCTAssertEqual(reloaded, original)
    }

    func testStoreKeepsOnlyTheNewest120Days() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DayLogDigestStore(fileURL: url)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = ISO8601DateFormatter().date(from: "2026-01-01T12:00:00Z")!
        for offset in 0..<125 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            try await store.save(digest(NutritionDate.string(from: date, calendar: calendar)))
        }
        let all = await store.all()
        XCTAssertEqual(all.count, DayLogDigestStore.maxDays)
        XCTAssertEqual(all.first?.day, "2026-01-06")
        let reloaded = await DayLogDigestStore(fileURL: url).all()
        XCTAssertEqual(reloaded.count, 120)
    }

    func testUndecodableFileIsQuarantinedNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("daylogdigest-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("day-log-digests.json")
        let garbage = Data(#"[{"day":42}]"#.utf8)
        try garbage.write(to: url)

        let store = DayLogDigestStore(fileURL: url)
        let before = await store.all()
        XCTAssertTrue(before.isEmpty)
        try await store.save(digest("2026-09-23"))

        let quarantined = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("day-log-digests.unreadable-") && $0.pathExtension == "json" }
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, garbage)
    }
}

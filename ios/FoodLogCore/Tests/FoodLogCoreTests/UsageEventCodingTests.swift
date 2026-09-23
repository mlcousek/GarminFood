// UsageEventCodingTests.swift
//
// `usage-history.json` lives on the owner's phone and is also read by the
// Gamification package (UsageHistory.swift's STORAGE FORMAT header). Adding
// `UsageEvent.mealType` (improve-log-food-shelves task 1.1) must not break
// a file written by an older build: these tests pin the backward-compatible
// decode, the on-disk key/raw value, and a real store round-trip through a
// unique temp file (LogEntryCoordinatorTests' pattern -- never mocked).

import XCTest
@testable import FoodLogCore
import GarminKit

final class UsageEventCodingTests: XCTestCase {
    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    func testAFileWrittenBeforeMealTypeExistedStillDecodes() throws {
        // Both historical shapes: the original one, and the 2026-09-16 one
        // with `nutritionDay`.
        let json = #"""
        [
          {"foodId":"f1","servingId":"s1","numberOfUnits":1,"timestamp":"2026-01-05T12:00:00Z"},
          {"foodId":"f2","servingId":"s2","numberOfUnits":2.5,"timestamp":"2026-09-16T07:30:00Z","nutritionDay":"2026-09-16"}
        ]
        """#

        let events = try decoder().decode([UsageEvent].self, from: Data(json.utf8))

        XCTAssertEqual(events.count, 2)
        XCTAssertNil(events[0].mealType)
        XCTAssertNil(events[1].mealType)
        XCTAssertEqual(events[1].nutritionDay, "2026-09-16")
        XCTAssertEqual(events[1].numberOfUnits, 2.5)
    }

    func testMealTypeIsStoredAsGarminsRawValue() throws {
        let event = UsageEvent(
            foodId: "f1", servingId: "s1", numberOfUnits: 1,
            timestamp: Date(timeIntervalSince1970: 1_790_000_000),
            nutritionDay: "2026-09-23", mealType: .breakfast
        )

        let data = try encoder().encode([event])
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(text.contains(#""mealType":"BREAKFAST""#), text)
        XCTAssertEqual(try decoder().decode([UsageEvent].self, from: data), [event])
    }

    func testAnUnknownMealTypeIsOmittedNotWrittenAsNull() throws {
        let event = UsageEvent(foodId: "f1", servingId: "s1", numberOfUnits: 1, timestamp: Date(timeIntervalSince1970: 1_790_000_000))

        let data = try encoder().encode([event])
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(text.contains("mealType"), text)
    }

    func testTheStorePersistsMealTypeAcrossInstances() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-usage-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try await UsageHistoryStore(fileURL: fileURL).record(foodId: "f1", servingId: "s1", numberOfUnits: 1, mealType: .dinner)
        try await UsageHistoryStore(fileURL: fileURL).record(foodId: "f2", servingId: "s1", numberOfUnits: 1)

        let reloaded = await UsageHistoryStore(fileURL: fileURL).all()
        XCTAssertEqual(reloaded.map(\.mealType), [.dinner, nil])
    }
}

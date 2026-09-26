// UndeliveredFoodConversionTests.swift
//
// add-standalone-mode 5.4 (data-mode spec, "Keeping undelivered entries"):
// switching Garmin -> standalone with two undelivered entries and "Keep on
// this phone" puts both in the local food log on their day and meal, with
// nutrients from the food cache, and empties the outbox. Real `Outbox`
// (unique process name), `LocalFoodLogStore` and `FoodCacheStore` on temp
// files -- no mocks.

import XCTest
@testable import FoodLogCore
import GarminKit

final class UndeliveredFoodConversionTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeStores() -> (Outbox, LocalFoodLogStore, FoodCacheStore) {
        let tmp = FileManager.default.temporaryDirectory
        return (
            Outbox(processName: "undelivered-conversion-\(UUID().uuidString)"),
            LocalFoodLogStore(directoryURL: tmp.appendingPathComponent("undelivered-log-\(UUID().uuidString)")),
            FoodCacheStore(fileURL: tmp.appendingPathComponent("undelivered-cache-\(UUID().uuidString).json"))
        )
    }

    private let rohlik = Food(
        id: "rohlik", name: "Rohlík", source: .garmin,
        servings: [Serving(id: "kus", unit: "kus", numberOfUnits: 1, calories: 150, carbs: 28, protein: 5, fat: 2)]
    )

    func testKeepingTwoUndeliveredEntriesMovesThemIntoTheLocalLog() async throws {
        let (outbox, log, cache) = makeStores()
        await cache.upsert([rohlik])
        try await outbox.logFood(date: "2026-09-24", mealType: .breakfast, foodId: "rohlik", servingId: "kus", numberOfUnits: 2, createdAt: createdAt)
        try await outbox.logFood(date: "2026-09-25", mealType: .dinner, foodId: "rohlik", servingId: "kus", numberOfUnits: 1, createdAt: createdAt)

        let result = try await UndeliveredFoodConversion.keepOnPhone(outbox: outbox, localLog: log, foodCache: cache)

        XCTAssertEqual(result, UndeliveredFoodConversion.Result(kept: 2, leftInGarmin: 0))
        let remaining = await outbox.allEntries()
        XCTAssertTrue(remaining.isEmpty, "the outbox no longer contains them")
        let breakfast = try await log.entries(forDay: "2026-09-24")
        let dinner = try await log.entries(forDay: "2026-09-25")
        XCTAssertEqual(breakfast.map(\.mealType), [.breakfast])
        XCTAssertEqual(dinner.map(\.mealType), [.dinner])
        XCTAssertEqual(breakfast.first?.amount(.calories), 300, "serving x quantity from the food cache")
        XCTAssertEqual(breakfast.first?.amount(.protein), 10)
        XCTAssertEqual(breakfast.first?.food.name, "Rohlík")
        XCTAssertEqual(breakfast.first?.loggedAt, createdAt)
    }

    func testAnEntryWhoseFoodIsNotCachedIsKeptWithoutNutrients() async throws {
        let (outbox, log, cache) = makeStores()
        try await outbox.logFood(date: "2026-09-25", mealType: .lunch, foodId: "17926789", servingId: "s9", numberOfUnits: 1.5, source: .fatSecret, createdAt: createdAt)

        let result = try await UndeliveredFoodConversion.keepOnPhone(outbox: outbox, localLog: log, foodCache: cache)

        XCTAssertEqual(result.kept, 1)
        let entries = try await log.entries(forDay: "2026-09-25")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.food.id, "17926789")
        XCTAssertEqual(entry.food.source, .fatSecret)
        XCTAssertEqual(entry.quantity, 1.5)
        XCTAssertNil(entry.amount(.calories), "never an invented number")
    }

    func testOnlyEntriesGarminHasNotAcceptedAreConverted() {
        func entry(_ state: OutboxEntryState) -> OutboxEntry {
            OutboxEntry(date: "2026-09-25", mealType: .lunch, foodId: "f", servingId: "s", numberOfUnits: 1, state: state)
        }
        let all = [entry(.pending), entry(.failed), entry(.sent), entry(.createdAwaitingDelete)]
        XCTAssertEqual(UndeliveredFoodConversion.undelivered(all).map(\.state), [.pending, .failed])
    }

    func testNothingToKeepIsANoOp() async throws {
        let (outbox, log, cache) = makeStores()
        let result = try await UndeliveredFoodConversion.keepOnPhone(outbox: outbox, localLog: log, foodCache: cache)
        XCTAssertEqual(result, UndeliveredFoodConversion.Result(kept: 0, leftInGarmin: 0))
    }
}

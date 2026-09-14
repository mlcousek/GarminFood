// LogEntryCoordinatorTests.swift
//
// Confirm-and-commit flow tests (tasks 16.1-16.2; food-log-entry spec's
// three core requirements). Uses a REAL `GarminKit.Outbox` via its public
// `processName:` initializer (a uniquely-named process per test, so runs
// never collide or leak state into each other) rather than reaching into
// GarminKit's internal test-only `Outbox(store:)` initializer across a
// package boundary -- this keeps the test exercising exactly the same
// public API surface the app itself calls. `Outbox.logFood` never touches
// the network (GarminKit's own doc comment: "no network call is made or
// waited on by this method"), so this is still a fast, offline unit test.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LogEntryCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> (coordinator: LogEntryCoordinator, outbox: Outbox, usageHistory: UsageHistoryStore, servingDefaults: ServingDefaultStore) {
        let outbox = Outbox(processName: "foodlogcore-test-\(UUID().uuidString)")
        let usageHistory = UsageHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-usage-\(UUID().uuidString).json"))
        let servingDefaults = ServingDefaultStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-servingdefaults-\(UUID().uuidString).json"))
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults)
        return (coordinator, outbox, usageHistory, servingDefaults)
    }

    private let food = Food(id: "food-1", name: "Test food", source: .garmin, servings: [Serving(id: "serving-1", unit: "g", numberOfUnits: 100)])

    func testConfirmEnqueuesTheEntryDurably() async throws {
        let (coordinator, outbox, _, _) = makeCoordinator()

        let entry = try await coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1.5, mealType: .breakfast, date: "2026-09-14")

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(stored.first?.foodId, "food-1")
        XCTAssertEqual(stored.first?.servingId, "serving-1")
        XCTAssertEqual(stored.first?.numberOfUnits, 1.5)
        XCTAssertEqual(stored.first?.state, .pending, "confirming does not itself deliver -- that's the outbox drain's job")
    }

    func testConfirmUpdatesUsageHistoryInTheSameAction() async throws {
        let (coordinator, _, usageHistory, _) = makeCoordinator()

        _ = try await coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 2, mealType: .lunch, date: "2026-09-14")

        let events = await usageHistory.all()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.foodId, "food-1")
        XCTAssertEqual(events.first?.numberOfUnits, 2)
    }

    func testConfirmSetsTheServingDefaultForThatFood() async throws {
        let (coordinator, _, _, servingDefaults) = makeCoordinator()

        _ = try await coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .dinner, date: "2026-09-14")

        let remembered = await servingDefaults.defaultServing(forFoodId: "food-1")
        XCTAssertEqual(remembered?.servingId, "serving-1")
    }

    func testConfirmCustomFoodLogsTheBackingFoodNotTheCustomId() async throws {
        let (coordinator, outbox, usageHistory, _) = makeCoordinator()
        let customFood = CustomFoodDraft(
            name: "Domácí tvaroh",
            servingUnit: "bowl",
            numberOfUnits: 1,
            backingFoodId: "garmin-42",
            backingFoodName: "Cottage cheese",
            backingServingId: "garmin-serving-7",
            backingQuantityMultiplier: 2
        )

        let (entry, note) = try await coordinator.confirmCustomFood(customFood, quantity: 1, mealType: .snacks, date: "2026-09-14")

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(stored.first?.foodId, "garmin-42", "the outbox entry must carry a real, Garmin-recognised foodId")
        XCTAssertEqual(stored.first?.numberOfUnits, 2)
        XCTAssertTrue(note.contains("Cottage cheese"))

        let events = await usageHistory.all()
        XCTAssertEqual(events.first?.foodId, customFood.id.uuidString, "usage history tracks the custom food's OWN identity, not the backing food's")
    }
}

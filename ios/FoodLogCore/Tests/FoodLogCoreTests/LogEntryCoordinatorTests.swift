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

    func testConfirmCarriesTheFoodsNamespaceAndLoggingTimeIntoTheEntry() async throws {
        let (coordinator, outbox, _, _) = makeCoordinator()
        let fatSecretFood = Food(id: "17926789", name: "Oats", source: .fatSecret, servings: [Serving(id: "serving-9", unit: "g", numberOfUnits: 40)])
        let loggedAt = Date(timeIntervalSince1970: 1_789_000_000)

        _ = try await coordinator.confirm(food: fatSecretFood, serving: fatSecretFood.servings[0], numberOfUnits: 1, mealType: .breakfast, date: "2026-09-14", now: loggedAt)
        _ = try await coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .breakfast, date: "2026-09-14", now: loggedAt)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.source, .fatSecret, "Garmin 400s a write that names the wrong namespace")
        XCTAssertNil(stored.last?.source, "a `.garmin` Food may be the fallback for a missing source string, so it is inferred instead")
        XCTAssertEqual(stored.first?.createdAt, loggedAt, "sent as logTimestamp: the moment of logging, not of delivery")
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

    // MARK: - Meal presets

    func testConfirmMealPresetEnqueuesOneEntryPerIngredient() async throws {
        let (coordinator, outbox, _, _) = makeCoordinator()
        let secondFood = Food(id: "food-2", name: "Banana", source: .garmin, servings: [Serving(id: "serving-2", unit: "medium", numberOfUnits: 1, calories: 105)])
        let preset = MealPreset(name: "Breakfast bowl", ingredients: [
            MealPresetIngredient(food: food, serving: food.servings[0], quantity: 1.5),
            MealPresetIngredient(food: secondFood, serving: secondFood.servings[0], quantity: 1),
        ])

        let entries = try await coordinator.confirmMealPreset(preset, mealType: .breakfast, date: "2026-09-22")

        XCTAssertEqual(entries.count, 2)
        let stored = await outbox.allEntries()
        XCTAssertEqual(Set(stored.map(\.foodId)), ["food-1", "food-2"])
        XCTAssertTrue(stored.allSatisfy { $0.mealType == .breakfast && $0.date == "2026-09-22" })
        XCTAssertEqual(stored.first { $0.foodId == "food-1" }?.numberOfUnits, 1.5)
    }

    func testConfirmMealPresetScalesEveryIngredientByTheServingsMultiplier() async throws {
        let (coordinator, outbox, _, _) = makeCoordinator()
        let preset = MealPreset(name: "Soup", ingredients: [
            MealPresetIngredient(food: food, serving: food.servings[0], quantity: 2),
        ])

        _ = try await coordinator.confirmMealPreset(preset, servingsMultiplier: 0.5, mealType: .lunch, date: "2026-09-22")

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.numberOfUnits, 1, "2 units x 0.5 servingsMultiplier = 1")
    }

    func testConfirmMealPresetLogsACustomFoodIngredientAsItsBackingFood() async throws {
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
        let preset = MealPreset(name: "Breakfast bowl", ingredients: [
            MealPresetIngredient(food: customFood.asFood(), serving: customFood.asFood().servings[0], quantity: 1, customFoodDraft: customFood),
            MealPresetIngredient(food: food, serving: food.servings[0], quantity: 1),
        ])

        let entries = try await coordinator.confirmMealPreset(preset, mealType: .snacks, date: "2026-09-22")

        XCTAssertEqual(entries.count, 2)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.contains { $0.foodId == "garmin-42" }, "the custom-food ingredient must log as its backing food, not its own id")
        XCTAssertTrue(stored.contains { $0.foodId == "food-1" })

        let events = await usageHistory.all()
        XCTAssertTrue(events.contains { $0.foodId == customFood.id.uuidString }, "usage history still tracks the custom food's own identity")
    }
}

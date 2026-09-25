// StandaloneMealPresetTests.swift
//
// add-standalone-mode 3.4 (design D5, standalone-food-catalog spec "Meal
// presets, quick picks, Siri and Controls log through the current mode"):
// a preset may hold ingredients of any origin in standalone mode and logs
// locally; Garmin mode refuses (before writing anything) an ingredient
// Garmin can't take, and only Garmin mode offers "Sync to Garmin". Real
// stores and a real Outbox on unique temp files (LogEntryCoordinatorTests
// convention).

import XCTest
@testable import FoodLogCore
import GarminKit

final class StandaloneMealPresetTests: XCTestCase {
    private let day = "2026-09-25"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("standalone-preset-\(name)-\(UUID().uuidString)")
    }

    private let rohlik = Food(id: "g-1", name: "Rohlík", source: .fatSecret, servings: [Serving(id: "s", unit: "piece", numberOfUnits: 1, calories: 145, carbs: 28, protein: 5, fat: 1.5)])

    private func tvaroh(calories: Double? = 67) -> Food {
        Food(id: "8594003963391", name: "Tvaroh odtučněný", source: .openFoodFacts, servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100, calories: calories, carbs: 4, protein: 12, fat: 0.5)])
    }

    private func buchty() -> CustomFoodDraft {
        CustomFoodDraft(name: "Babiččiny buchty", servingUnit: "kus", numberOfUnits: 1, calories: 280, carbs: 40, protein: 6, fat: 10, createdAt: now)
    }

    /// Garmin food + Open Food Facts product + backing-less custom food.
    private func mixedPreset(offCalories: Double? = 67) -> MealPreset {
        let off = tvaroh(calories: offCalories)
        let draft = buchty()
        let custom = draft.asFood()
        return MealPreset(name: "Snídaně", ingredients: [
            MealPresetIngredient(food: rohlik, serving: rohlik.servings[0], quantity: 2),
            MealPresetIngredient(food: off, serving: off.servings[0], quantity: 1.5),
            MealPresetIngredient(food: custom, serving: custom.servings[0], quantity: 1, customFoodDraft: draft),
        ])
    }

    // MARK: Pure rules

    func testNeedsGarminMatch() {
        let preset = mixedPreset()
        XCTAssertEqual(preset.ingredients.map(\.needsGarminMatch), [false, true, true])
    }

    func testBlockingIngredientsPerMode() {
        XCTAssertEqual(mixedPreset().blockingIngredients(in: .standalone), [])
        XCTAssertEqual(mixedPreset().blockingIngredients(in: .garminConnected).map(\.food.name), ["Tvaroh odtučněný", "Babiččiny buchty"])
        XCTAssertEqual(mixedPreset(offCalories: nil).blockingIngredients(in: .standalone).map(\.food.name), ["Tvaroh odtučněný"])
    }

    func testSyncToGarminIsNeverOfferedStandalone() {
        let garminOnly = MealPreset(name: "Svačina", ingredients: [MealPresetIngredient(food: rohlik, serving: rohlik.servings[0], quantity: 1)])
        XCTAssertTrue(garminOnly.offersGarminSync(in: .garminConnected), "the owner's presets keep the action")
        XCTAssertFalse(garminOnly.offersGarminSync(in: .standalone))
        XCTAssertFalse(mixedPreset().offersGarminSync(in: .garminConnected))
        XCTAssertTrue(mixedPreset().hasUnsyncableIngredients)
    }

    // MARK: Logging

    func testStandaloneLogsEveryOriginWithItsOwnNutrients() async throws {
        let log = LocalFoodLogStore(directoryURL: tempURL("log"))
        let coordinator = LocalLogEntryCoordinator(store: log, usageHistory: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")))

        _ = try await coordinator.confirmMealPreset(mixedPreset(), mealType: .breakfast, date: day, now: now)

        let entries = try await log.entries(forDay: day)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.food.name), ["Rohlík", "Tvaroh odtučněný", "Babiččiny buchty"])
        let calories = entries.compactMap { $0.amount(.calories) }
        XCTAssertEqual(calories.count, 3)
        XCTAssertEqual(calories[0], 290, accuracy: 0.001)
        XCTAssertEqual(calories[1], 100.5, accuracy: 0.001)
        XCTAssertEqual(calories[2], 280, accuracy: 0.001)
    }

    func testGarminModeRefusesAnOpenFoodFactsIngredientBeforeWritingAnything() async throws {
        let outbox = Outbox(processName: "standalone-preset-\(UUID().uuidString)")
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")))
        let off = tvaroh()
        let preset = MealPreset(name: "Svačina", ingredients: [
            MealPresetIngredient(food: rohlik, serving: rohlik.servings[0], quantity: 1),
            MealPresetIngredient(food: off, serving: off.servings[0], quantity: 1),
        ])

        do {
            _ = try await coordinator.confirmMealPreset(preset, mealType: .snacks, date: day)
            XCTFail("expected needsGarminMatch")
        } catch {
            XCTAssertEqual(error as? CustomFoodLoggingError, .needsGarminMatch)
        }
        let queued = await outbox.allEntries()
        XCTAssertTrue(queued.isEmpty, "the Garmin ingredient before it must not be queued either")
    }
}

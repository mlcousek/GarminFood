// MealPresetTests.swift
//
// Meal preset logic (MealPreset.swift) and its JSON-file-backed store --
// same pattern as CustomFoodTests.swift.

import XCTest
@testable import FoodLogCore

final class MealPresetTests: XCTestCase {
    private func makeIngredient(calories: Double, quantity: Double = 1) -> MealPresetIngredient {
        MealPresetIngredient(
            food: Food(id: "food-\(calories)", name: "Ingredient", source: .garmin, servings: []),
            serving: Serving(id: "serving-1", unit: "g", numberOfUnits: 100, calories: calories, carbs: 10, protein: 5, fat: 2),
            quantity: quantity
        )
    }

    // MARK: - Pure logic

    func testTotalsSumsEveryIngredientAtItsOwnQuantity() {
        let preset = MealPreset(name: "Breakfast bowl", ingredients: [
            makeIngredient(calories: 150, quantity: 1.5),
            makeIngredient(calories: 105, quantity: 1),
        ])

        let totals = preset.totals()

        XCTAssertEqual(totals.calories, 150 * 1.5 + 105)
        XCTAssertEqual(totals.carbs, 10 * 1.5 + 10)
        XCTAssertEqual(totals.protein, 5 * 1.5 + 5)
        XCTAssertEqual(totals.fat, 2 * 1.5 + 2)
    }

    func testTotalsScalesByTheServingsMultiplier() {
        let preset = MealPreset(name: "Soup", ingredients: [makeIngredient(calories: 200, quantity: 1)])

        let totals = preset.totals(servingsMultiplier: 0.5)

        XCTAssertEqual(totals.calories, 100, "half the preset is half the calories")
    }

    func testIngredientCaloriesIsNilWhenTheServingHasNone() {
        let ingredient = MealPresetIngredient(
            food: Food(id: "f1", name: "Mystery", source: .garmin, servings: []),
            serving: Serving(id: "s1", unit: "g", numberOfUnits: 100),
            quantity: 1
        )
        XCTAssertNil(ingredient.calories)
    }

    // MARK: - Store

    private func makeStore() -> MealPresetStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-mealpresets-test-\(UUID().uuidString).json")
        return MealPresetStore(fileURL: url)
    }

    func testUpsertThenAllReturnsTheStoredPreset() async throws {
        let store = makeStore()
        let preset = MealPreset(name: "Breakfast bowl", ingredients: [makeIngredient(calories: 150)])

        try await store.upsert(preset)
        let all = await store.all()

        XCTAssertEqual(all.map(\.id), [preset.id])
        XCTAssertEqual(all.first?.name, "Breakfast bowl")
    }

    func testDeleteRemovesThePreset() async throws {
        let store = makeStore()
        let preset = MealPreset(name: "Soup", ingredients: [makeIngredient(calories: 200)])
        try await store.upsert(preset)

        try await store.delete(id: preset.id)

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testPresetsSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-mealpresets-persist-\(UUID().uuidString).json")
        let preset = MealPreset(name: "Breakfast bowl", ingredients: [makeIngredient(calories: 150)])

        let store1 = MealPresetStore(fileURL: url)
        try await store1.upsert(preset)

        let store2 = MealPresetStore(fileURL: url)
        let all = await store2.all()

        XCTAssertEqual(all.map(\.id), [preset.id])
        XCTAssertEqual(all.first?.ingredients.count, 1)
    }
}

// FavoriteFoodTests.swift
//
// FavoriteFoodStore (add-favorite-foods, FavoriteFood.swift) -- mirrors
// CustomFoodTests.swift's own store-testing shape: real store instances at
// unique temp-file paths, never mocked.

import XCTest
@testable import FoodLogCore

final class FavoriteFoodTests: XCTestCase {
    private func makeFood(id: String = "garmin-food-1", name: String = "Rohlík") -> Food {
        Food(
            id: id,
            name: name,
            source: .garmin,
            servings: [Serving(id: "serving-1", unit: "1 roll", numberOfUnits: 1, calories: 140)]
        )
    }

    private func makeStore() -> FavoriteFoodStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-favoritefoods-test-\(UUID().uuidString).json")
        return FavoriteFoodStore(fileURL: url)
    }

    // MARK: - Toggle

    func testTogglingAnUnfavoritedFoodMarksItFavoriteAndReturnsTrue() async throws {
        let store = makeStore()
        let food = makeFood()

        let isNowFavorite = try await store.toggle(food)

        XCTAssertTrue(isNowFavorite)
        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [food.id])
        XCTAssertEqual(all.first?.food.name, "Rohlík")
    }

    func testTogglingAnAlreadyFavoritedFoodRemovesItAndReturnsFalse() async throws {
        let store = makeStore()
        let food = makeFood()
        try await store.toggle(food)

        let isNowFavorite = try await store.toggle(food)

        XCTAssertFalse(isNowFavorite)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - isFavorite

    func testIsFavoriteReflectsCurrentState() async throws {
        let store = makeStore()
        let food = makeFood()

        var isFavorite = await store.isFavorite(foodId: food.id)
        XCTAssertFalse(isFavorite)

        try await store.toggle(food)
        isFavorite = await store.isFavorite(foodId: food.id)
        XCTAssertTrue(isFavorite)
    }

    // MARK: - remove

    func testRemoveDropsAFavoriteEvenIfNeverToggledThroughToggle() async throws {
        let store = makeStore()
        let food = makeFood()
        try await store.toggle(food)

        try await store.remove(foodId: food.id)

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Ordering

    func testAllOrdersNewestFavoritedFirst() async throws {
        let store = makeStore()
        try await store.toggle(makeFood(id: "food-a", name: "A"))
        try await store.toggle(makeFood(id: "food-b", name: "B"))

        let all = await store.all()

        XCTAssertEqual(all.map(\.id), ["food-b", "food-a"])
    }

    // MARK: - Persistence

    func testFavoritesSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-favoritefoods-persist-\(UUID().uuidString).json")
        let food = makeFood()

        let store1 = FavoriteFoodStore(fileURL: url)
        try await store1.toggle(food)

        let store2 = FavoriteFoodStore(fileURL: url)
        let all = await store2.all()

        XCTAssertEqual(all.map(\.id), [food.id])
        XCTAssertEqual(all.first?.food.servings.first?.calories, 140)
    }
}

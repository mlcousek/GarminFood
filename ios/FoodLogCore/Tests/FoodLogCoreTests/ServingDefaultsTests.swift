// ServingDefaultsTests.swift
//
// Serving-default memory tests (design.md D2, task 13.3): both the pure
// resolution logic (`ServingResolution.resolve`) and the JSON-file-backed
// store's persistence, same "fresh instance, same file" pattern GarminKit's
// OutboxTests uses for its own store.

import XCTest
@testable import FoodLogCore

final class ServingDefaultsTests: XCTestCase {
    private func makeFood(servingIds: [String]) -> Food {
        Food(
            id: "food-1",
            name: "Test food",
            source: .garmin,
            servings: servingIds.map { Serving(id: $0, unit: "g", numberOfUnits: 100) }
        )
    }

    // MARK: - Pure resolution logic

    func testNoRememberedDefaultResolvesToNil() {
        let food = makeFood(servingIds: ["100g"])
        XCTAssertNil(ServingResolution.resolve(nil, in: food))
    }

    func testRememberedDefaultResolvesToTheMatchingServing() {
        let food = makeFood(servingIds: ["100g", "1-medium"])
        let remembered = ServingDefault(foodId: "food-1", servingId: "1-medium", numberOfUnits: 1, updatedAt: Date())

        let resolved = ServingResolution.resolve(remembered, in: food)

        XCTAssertEqual(resolved?.id, "1-medium")
    }

    func testStaleRememberedServingIdResolvesToNilRatherThanGuessing() {
        // design.md's named risk: "Garmin changes a servingId" -> re-resolve
        // from a fresh search, not fail silently or pick something at random.
        let food = makeFood(servingIds: ["100g"])
        let remembered = ServingDefault(foodId: "food-1", servingId: "a-servingId-that-no-longer-exists", numberOfUnits: 1, updatedAt: Date())

        XCTAssertNil(ServingResolution.resolve(remembered, in: food))
    }

    // MARK: - Store persistence

    private func makeStore() -> (store: ServingDefaultStore, url: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-serving-defaults-test-\(UUID().uuidString).json")
        return (ServingDefaultStore(fileURL: url), url)
    }

    func testSetDefaultThenReadBackReturnsTheSameValue() async throws {
        let (store, _) = makeStore()
        try await store.setDefault(foodId: "food-1", servingId: "100g", numberOfUnits: 2)

        let result = await store.defaultServing(forFoodId: "food-1")

        XCTAssertEqual(result?.servingId, "100g")
        XCTAssertEqual(result?.numberOfUnits, 2)
    }

    func testSettingANewDefaultOverwritesThePreviousOne() async throws {
        // food-catalog spec: "the new selection becomes the remembered
        // default for that food going forward".
        let (store, _) = makeStore()
        try await store.setDefault(foodId: "food-1", servingId: "100g", numberOfUnits: 1)
        try await store.setDefault(foodId: "food-1", servingId: "1-medium", numberOfUnits: 1)

        let result = await store.defaultServing(forFoodId: "food-1")

        XCTAssertEqual(result?.servingId, "1-medium")
    }

    func testUnknownFoodIdReturnsNil() async {
        let (store, _) = makeStore()
        let result = await store.defaultServing(forFoodId: "never-logged")
        XCTAssertNil(result)
    }

    func testDefaultsSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-serving-defaults-persist-\(UUID().uuidString).json")
        let store1 = ServingDefaultStore(fileURL: url)
        try await store1.setDefault(foodId: "food-1", servingId: "100g", numberOfUnits: 1)

        let store2 = ServingDefaultStore(fileURL: url)
        let result = await store2.defaultServing(forFoodId: "food-1")

        XCTAssertEqual(result?.servingId, "100g")
    }
}

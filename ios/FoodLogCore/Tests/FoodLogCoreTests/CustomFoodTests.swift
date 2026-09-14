// CustomFoodTests.swift
//
// Custom food logic (design.md D4, task 15) and its JSON-file-backed store.

import XCTest
@testable import FoodLogCore

final class CustomFoodTests: XCTestCase {
    private func makeDraft(multiplier: Double = 1) -> CustomFoodDraft {
        CustomFoodDraft(
            name: "Domácí tvaroh",
            servingUnit: "bowl",
            numberOfUnits: 1,
            calories: 220,
            protein: 18,
            backingFoodId: "garmin-food-42",
            backingFoodName: "Cottage cheese, plain",
            backingServingId: "garmin-serving-7",
            backingQuantityMultiplier: multiplier
        )
    }

    // MARK: - Pure logic

    func testAsFoodProducesASingleServingWithTheDraftsOwnValues() {
        let draft = makeDraft()
        let food = draft.asFood()

        XCTAssertEqual(food.id, draft.id.uuidString)
        XCTAssertEqual(food.source, .custom)
        XCTAssertEqual(food.servings.count, 1)
        XCTAssertEqual(food.servings.first?.id, CustomFoodDraft.servingId)
        XCTAssertEqual(food.servings.first?.calories, 220)
    }

    func testResolvedLoggingTargetScalesQuantityByTheBackingMultiplier() {
        let draft = makeDraft(multiplier: 0.5)

        let target = draft.resolvedLoggingTarget(quantity: 2)

        XCTAssertEqual(target.foodId, "garmin-food-42")
        XCTAssertEqual(target.servingId, "garmin-serving-7")
        XCTAssertEqual(target.numberOfUnits, 1, "0.5 multiplier x 2 units = 1 backing unit")
    }

    func testDiscrepancyNoteNamesTheBackingFood() {
        let draft = makeDraft()
        XCTAssertTrue(draft.discrepancyNote.contains("Cottage cheese, plain"))
    }

    // MARK: - Store

    private func makeStore() -> CustomFoodStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-customfoods-test-\(UUID().uuidString).json")
        return CustomFoodStore(fileURL: url)
    }

    func testUpsertThenAllReturnsTheStoredDraft() async throws {
        let store = makeStore()
        let draft = makeDraft()

        try await store.upsert(draft)
        let all = await store.all()

        XCTAssertEqual(all.map(\.id), [draft.id])
    }

    func testDeleteRemovesTheDraft() async throws {
        let store = makeStore()
        let draft = makeDraft()
        try await store.upsert(draft)

        try await store.delete(id: draft.id)

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testDraftsSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-customfoods-persist-\(UUID().uuidString).json")
        let draft = makeDraft()

        let store1 = CustomFoodStore(fileURL: url)
        try await store1.upsert(draft)

        let store2 = CustomFoodStore(fileURL: url)
        let all = await store2.all()

        XCTAssertEqual(all.map(\.id), [draft.id])
    }
}

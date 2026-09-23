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

    // MARK: - Unreadable file (openspec/changes/fix-silent-store-wipe)

    /// The actual bug: an undecodable custom-foods file used to start the
    /// store empty and then get overwritten by the next `upsert`, wiping
    /// every custom food permanently. Now the original bytes must survive,
    /// moved aside next to the store's file.
    func testUndecodableFileIsQuarantinedNotOverwrittenByTheNextUpsert() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("foodlogcore-customfoods-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-foods.json")
        let garbage = Data(#"[{"id":"not-a-uuid","name":42}]"#.utf8)
        try garbage.write(to: url)

        let store = CustomFoodStore(fileURL: url)
        let before = await store.all()
        XCTAssertTrue(before.isEmpty)

        let draft = makeDraft()
        try await store.upsert(draft)

        let after = await store.all()
        XCTAssertEqual(after.map(\.id), [draft.id])
        let quarantined = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("custom-foods.unreadable-") && $0.pathExtension == "json" }
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, garbage)
    }

    /// `Dictionary(uniqueKeysWithValues:)` used to TRAP on a duplicate id,
    /// crashing on every launch; a duplicate now loads (last one wins).
    func testDuplicateIdsInThePersistedFileDoNotCrashTheLoad() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-customfoods-dupes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let draft = makeDraft()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([draft, draft]).write(to: url)

        let store = CustomFoodStore(fileURL: url)
        let all = await store.all()

        XCTAssertEqual(all.map(\.id), [draft.id])
    }
}

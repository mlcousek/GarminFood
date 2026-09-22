// WeightTrackingTests.swift
//
// WeightEntry's JSON-file-backed store (same pattern as MealPresetTests.swift)
// plus WeightHistory's pure trend logic.

import XCTest
@testable import FoodLogCore

final class WeightTrackingTests: XCTestCase {
    private func makeStore() -> WeightStore {
        WeightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("weight-store-test-\(UUID().uuidString).json"))
    }

    // MARK: - Store CRUD

    func testUpsertThenAllReturnsTheEntry() async throws {
        let store = makeStore()
        let entry = WeightEntry(weightKg: 75.5)

        try await store.upsert(entry)

        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [entry.id])
        XCTAssertEqual(all.first?.weightKg, 75.5)
    }

    func testAllIsSortedNewestFirst() async throws {
        let store = makeStore()
        let older = WeightEntry(weightKg: 76, loggedAt: Date(timeIntervalSince1970: 1_000))
        let newer = WeightEntry(weightKg: 75, loggedAt: Date(timeIntervalSince1970: 2_000))

        try await store.upsert(older)
        try await store.upsert(newer)

        let all = await store.all()
        XCTAssertEqual(all.map(\.id), [newer.id, older.id])
    }

    func testUpsertWithSameIdReplacesTheEntry() async throws {
        let store = makeStore()
        let id = UUID()
        try await store.upsert(WeightEntry(id: id, weightKg: 75, note: "before"))
        try await store.upsert(WeightEntry(id: id, weightKg: 74.5, note: "after"))

        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.weightKg, 74.5)
        XCTAssertEqual(all.first?.note, "after")
    }

    func testDeleteRemovesTheEntry() async throws {
        let store = makeStore()
        let entry = WeightEntry(weightKg: 75)
        try await store.upsert(entry)

        try await store.delete(id: entry.id)

        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testEntriesSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weight-store-persist-\(UUID().uuidString).json")
        let store1 = WeightStore(fileURL: url)
        let entry = WeightEntry(weightKg: 75)
        try await store1.upsert(entry)

        let store2 = WeightStore(fileURL: url)
        let reloaded = await store2.all()

        XCTAssertEqual(reloaded.map(\.id), [entry.id])
    }

    // MARK: - WeightHistory.delta

    func testDeltaIsNilWithoutAPreviousEntry() {
        let latest = WeightEntry(weightKg: 75)
        XCTAssertNil(WeightHistory.delta(latest: latest, previous: nil))
    }

    func testDeltaIsPositiveWhenLatestIsHeavier() {
        let previous = WeightEntry(weightKg: 74)
        let latest = WeightEntry(weightKg: 75.5)
        XCTAssertEqual(WeightHistory.delta(latest: latest, previous: previous), 1.5, accuracy: 0.0001)
    }

    func testDeltaIsNegativeWhenLatestIsLighter() {
        let previous = WeightEntry(weightKg: 80)
        let latest = WeightEntry(weightKg: 78.2)
        XCTAssertEqual(WeightHistory.delta(latest: latest, previous: previous), -1.8, accuracy: 0.0001)
    }
}

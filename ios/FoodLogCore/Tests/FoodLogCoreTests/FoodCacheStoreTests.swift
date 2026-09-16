// FoodCacheStoreTests.swift
//
// Durable food-display cache tests -- exists so the quick-pick shelf can
// show a name/macros without a network call (see FoodCache.swift's header).

import XCTest
@testable import FoodLogCore

final class FoodCacheStoreTests: XCTestCase {
    private func makeStore() -> FoodCacheStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-foodcache-\(UUID().uuidString).json")
        return FoodCacheStore(fileURL: url)
    }

    private func makeFood(id: String, name: String) -> Food {
        Food(id: id, name: name, source: .garmin, servings: [Serving(id: "s1", unit: "g", numberOfUnits: 100)])
    }

    func testUpsertThenLookupById() async {
        let store = makeStore()
        await store.upsert([makeFood(id: "1", name: "Rohlik")])

        let found = await store.food(forId: "1")

        XCTAssertEqual(found?.name, "Rohlik")
    }

    func testLookupOfAnUnknownIdReturnsNilRatherThanCrashing() async {
        let store = makeStore()
        let found = await store.food(forId: "never-seen")
        XCTAssertNil(found)
    }

    func testUpsertMergesRatherThanReplacingTheWholeCache() async {
        let store = makeStore()
        await store.upsert([makeFood(id: "1", name: "Rohlik")])
        await store.upsert([makeFood(id: "2", name: "Chleba")])

        let all = await store.all()

        XCTAssertEqual(Set(all.keys), ["1", "2"])
    }

    func testCacheSurvivesAFreshStoreInstanceAtTheSameFile() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-foodcache-persist-\(UUID().uuidString).json")
        let store1 = FoodCacheStore(fileURL: url)
        await store1.upsert([makeFood(id: "1", name: "Rohlik")])

        let store2 = FoodCacheStore(fileURL: url)
        let found = await store2.food(forId: "1")

        XCTAssertEqual(found?.name, "Rohlik")
    }
}

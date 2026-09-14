// FoodCatalogSearchTests.swift
//
// `FoodCatalog.search(term:)` tests (task 12.1): in-memory term cache and
// the durable food-cache back-fill, using a fake `FoodSearching` so no
// network access is exercised.

import XCTest
@testable import FoodLogCore
import GarminKit

final class FoodCatalogSearchTests: XCTestCase {
    private actor FakeSearcher: FoodSearching {
        private(set) var callCount = 0
        private let json: String

        init(json: String) {
            self.json = json
        }

        func searchFood(term: String) async throws -> FoodSearchResponse {
            callCount += 1
            return try JSONDecoder().decode(FoodSearchResponse.self, from: Data(json.utf8))
        }
    }

    private let rohlikResponseJSON = """
    {
      "results": [
        { "foodMetaData": { "foodId": "1", "foodName": "Rohlik" }, "nutritionContents": [ { "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100 } ] }
      ],
      "moreDataAvailable": false
    }
    """

    func testSearchReturnsAdaptedFoods() async throws {
        let searcher = FakeSearcher(json: rohlikResponseJSON)
        let catalog = FoodCatalogSearch(searcher: searcher)

        let foods = try await catalog.search(term: "rohlik")

        XCTAssertEqual(foods.map(\.name), ["Rohlik"])
    }

    func testRepeatedSearchForTheSameTermUsesTheInMemoryCacheNotANewCall() async throws {
        let searcher = FakeSearcher(json: rohlikResponseJSON)
        let catalog = FoodCatalogSearch(searcher: searcher)

        _ = try await catalog.search(term: "rohlik")
        _ = try await catalog.search(term: "ROHLIK ") // same term, different case/whitespace

        let callCount = await searcher.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testEmptySearchTermReturnsEmptyWithoutCallingTheSearcher() async throws {
        let searcher = FakeSearcher(json: rohlikResponseJSON)
        let catalog = FoodCatalogSearch(searcher: searcher)

        let foods = try await catalog.search(term: "   ")

        XCTAssertTrue(foods.isEmpty)
        let callCount = await searcher.callCount
        XCTAssertEqual(callCount, 0)
    }

    func testSuccessfulSearchBackFillsTheDurableFoodCache() async throws {
        let searcher = FakeSearcher(json: rohlikResponseJSON)
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-foodcache-test-\(UUID().uuidString).json")
        let cache = FoodCacheStore(fileURL: cacheURL)
        let catalog = FoodCatalogSearch(searcher: searcher, foodCache: cache)

        _ = try await catalog.search(term: "rohlik")

        let cached = await cache.food(forId: "1")
        XCTAssertEqual(cached?.name, "Rohlik")
    }
}

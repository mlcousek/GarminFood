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

    /// Task 12.3: "Verify Czech-language search terms return usable results
    /// as part of test coverage (`rohlik`, `chleba`, `tvaroh`) -- confirmed
    /// reachable 2026-09-14, but pin it with a test rather than trusting the
    /// one-off probe forever." This pins the DECODING side (a Czech-shaped
    /// response adapts into usable `Food` values) with a fixture matching
    /// the confirmed real response shape from docs/garmin-routes.json --
    /// it cannot re-verify Garmin's server still returns results for these
    /// terms without a live network call, which this test suite deliberately
    /// never makes (see this file's header).
    func testCzechLanguageSearchTermsProduceUsableFoods() async throws {
        for term in ["rohlik", "chleba", "tvaroh"] {
            let json = """
            {
              "results": [
                {
                  "foodMetaData": { "foodId": "cz-\(term)", "foodName": "\(term)", "source": "FATSECRET", "regionCode": "CZ", "languageCode": "cs" },
                  "nutritionContents": [ { "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100, "calories": 250 } ]
                }
              ],
              "moreDataAvailable": false
            }
            """
            let searcher = FakeSearcher(json: json)
            let catalog = FoodCatalogSearch(searcher: searcher)

            let foods = try await catalog.search(term: term)

            XCTAssertEqual(foods.count, 1, "expected a usable result for Czech term '\(term)'")
            XCTAssertEqual(foods.first?.name, term)
        }
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

// OpenFoodFactsClientTests.swift
//
// Task 27.4: "Unit test the response-decoding against a captured fixture
// from the real 2026-09-16 'tvaroh' response... pure decoding logic, no
// network needed for the test itself." `OpenFoodFactsClient.decode(_:)` is
// exercised directly, matching `GarminModels`/`FoodTests`'s existing
// convention of decoding hand-written JSON fixtures rather than mocking
// `URLSession`.

import XCTest
@testable import FoodLogCore

final class OpenFoodFactsClientTests: XCTestCase {
    /// The real captured shape from design.md's Context section
    /// (2026-09-16 "tvaroh" search), field-for-field.
    private let capturedResponseJSON = """
    {
      "count": 134,
      "products": [{
        "code": "8594001565627",
        "product_name": "Rohlíky Krehké Celozrné 250G Active Bonavita",
        "brands": "Bonavita",
        "nutriments": {
          "energy-kcal_100g": 350,
          "carbohydrates_100g": 70.1,
          "proteins_100g": 10,
          "fat_100g": 4.6,
          "fiber_100g": 6.1,
          "sugars_100g": 4.1,
          "sodium_100g": 0,
          "saturated-fat_100g": 0.6
        }
      }]
    }
    """

    func testDecodesTheRealCapturedResponseShapeIntoAUsableFood() throws {
        let foods = try OpenFoodFactsClient.decode(Data(capturedResponseJSON.utf8))

        XCTAssertEqual(foods.count, 1)
        let food = try XCTUnwrap(foods.first)
        XCTAssertEqual(food.id, "8594001565627")
        XCTAssertEqual(food.name, "Rohlíky Krehké Celozrné 250G Active Bonavita")
        XCTAssertEqual(food.brandName, "Bonavita")
        XCTAssertEqual(food.source, .openFoodFacts)

        let serving = try XCTUnwrap(food.servings.first)
        XCTAssertEqual(serving.unit, "g")
        XCTAssertEqual(serving.numberOfUnits, 100)
        XCTAssertEqual(serving.calories, 350)
        XCTAssertEqual(serving.carbs, 70.1)
        XCTAssertEqual(serving.protein, 10)
        XCTAssertEqual(serving.fat, 4.6)
        XCTAssertEqual(serving.fiber, 6.1)
        XCTAssertEqual(serving.sugar, 4.1)
        XCTAssertEqual(serving.sodium, 0)
        XCTAssertEqual(serving.saturatedFat, 0.6)
    }

    func testProductMissingNutrimentsEntirelyDecodesWithAllMacrosNil() throws {
        let json = """
        { "products": [{ "code": "1", "product_name": "Mystery item" }] }
        """

        let foods = try OpenFoodFactsClient.decode(Data(json.utf8))

        XCTAssertEqual(foods.count, 1)
        let serving = try XCTUnwrap(foods.first?.servings.first)
        XCTAssertNil(serving.calories)
        XCTAssertNil(serving.protein)
        XCTAssertNil(serving.carbs)
        XCTAssertNil(serving.fat)
    }

    func testProductMissingCodeOrNameIsSkippedRatherThanFailingTheWholeDecode() throws {
        let json = """
        { "products": [
          { "product_name": "No code" },
          { "code": "999" },
          { "code": "1", "product_name": "Valid" }
        ]}
        """

        let foods = try OpenFoodFactsClient.decode(Data(json.utf8))

        XCTAssertEqual(foods.map(\.name), ["Valid"])
    }

    func testEmptyStringNutrientValueDecodesAsNilRatherThanFailing() throws {
        // Open Food Facts is known to sometimes send "" for a missing
        // numeric field instead of omitting the key or sending null.
        let json = """
        { "products": [{
          "code": "1", "product_name": "Weird but real",
          "nutriments": { "energy-kcal_100g": "", "proteins_100g": 5 }
        }]}
        """

        let foods = try OpenFoodFactsClient.decode(Data(json.utf8))

        let serving = try XCTUnwrap(foods.first?.servings.first)
        XCTAssertNil(serving.calories)
        XCTAssertEqual(serving.protein, 5)
    }

    func testNoProductsReturnsAnEmptyArray() throws {
        let json = """
        { "count": 0, "products": [] }
        """

        let foods = try OpenFoodFactsClient.decode(Data(json.utf8))

        XCTAssertTrue(foods.isEmpty)
    }

    func testBlankSearchTermReturnsEmptyWithoutBuildingARequest() async throws {
        let client = OpenFoodFactsClient()

        let foods = try await client.search(term: "   ")

        XCTAssertTrue(foods.isEmpty)
    }
}

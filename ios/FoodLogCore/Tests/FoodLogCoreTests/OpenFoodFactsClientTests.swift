// OpenFoodFactsClientTests.swift
//
// Task 27.4: "Unit test the response-decoding against a captured fixture
// from the real 2026-09-16 'tvaroh' response... pure decoding logic, no
// network needed for the test itself." `OpenFoodFactsClient.decode(_:)` is
// exercised directly, matching `GarminModels`/`FoodTests`'s existing
// convention of decoding hand-written JSON fixtures rather than mocking
// `URLSession`.
//
// 2026-09-22 (implement-micronutrients): added coverage for the new
// vitamin/mineral fields and their gram->mg/µg conversion. The
// `richNutrientsResponseJSON` fixture below reproduces a REAL captured
// `search.pl` response for a fortified breakfast cereal (2026-09-22,
// via this project's own research for that change) field-for-field --
// same convention as `capturedResponseJSON`'s existing "tvaroh" capture.
// Also locks in a real bug fix: `sodium` used to pass OFF's raw gram value
// straight through instead of converting to mg like the rest of this app
// assumes (`MealDashboard.NutrientKind.unit`).
//
// 2026-09-23 (rebuild-food-search): the client-side `rerank` and its tests
// are gone -- brand-vs-name ranking now lives in `SearchRanker` for every
// source (SearchRankerTests / SearchRelevanceTests cover the "Rohlík" brand
// case). Added Search-a-licious decoding, from a real 2026-09-23 capture.

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

    /// Real `search.pl` capture (2026-09-22, fields=`...,nutriments,...`,
    /// same query shape this client sends), a fortified breakfast cereal --
    /// field-for-field, including the raw gram values OFF actually returns
    /// for vitamin fields (e.g. `vitamin-d_100g: 3.4e-06`, i.e. 3.4µg/100g).
    private let richNutrientsResponseJSON = """
    {
      "products": [{
        "code": "3387390123210",
        "product_name": "Chocapic",
        "brands": "Nestlé, Chocapic",
        "nutriments": {
          "energy-kcal_100g": 384,
          "carbohydrates_100g": 73.8,
          "proteins_100g": 8.5,
          "fat_100g": 4.4,
          "fiber_100g": 7.7,
          "sugars_100g": 19.9,
          "saturated-fat_100g": 1.1,
          "sodium_100g": 0.08,
          "calcium_100g": 0.501,
          "iron_100g": 0.012,
          "pantothenic-acid_100g": 0.0058,
          "vitamin-b1_100g": 0.001,
          "vitamin-b2_100g": 0.0014,
          "vitamin-b6_100g": 0.0014,
          "vitamin-d_100g": 3.4e-06,
          "vitamin-pp_100g": 0.015
        }
      }]
    }
    """

    func testDecodesTheRealVitaminAndMineralFieldsConvertingGramsToMgOrMicrograms() throws {
        let foods = try OpenFoodFactsClient.decode(Data(richNutrientsResponseJSON.utf8))
        let serving = try XCTUnwrap(foods.first?.servings.first)

        // Fixed 2026-09-22: sodium used to pass OFF's raw grams straight
        // through; 0.08 g/100g must now read as 80 mg, matching this app's
        // existing mg convention for this field (`NutrientKind.unit`).
        XCTAssertEqual(try XCTUnwrap(serving.sodium), 80, accuracy: 0.0001)

        // mg-scale vitamins (x1000 from OFF's raw grams).
        XCTAssertEqual(try XCTUnwrap(serving.vitaminB1), 1.0, accuracy: 0.0001, "1mg/100g")
        XCTAssertEqual(try XCTUnwrap(serving.vitaminB2), 1.4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.vitaminB3), 15, accuracy: 0.0001, "niacin/vitamin-pp")
        XCTAssertEqual(try XCTUnwrap(serving.vitaminB5), 5.8, accuracy: 0.0001, "pantothenic acid")

        // µg-scale vitamin (x1,000,000 from OFF's raw grams).
        XCTAssertEqual(try XCTUnwrap(serving.vitaminD), 3.4, accuracy: 0.0001)

        // calcium/iron are deliberately NOT populated from OFF (Serving's
        // own header comment: those fields are Garmin/FatSecret %DV only,
        // and OFF's absolute-gram values would silently conflict with that
        // unit under the same field name) even though OFF's response
        // carries real values for them.
        XCTAssertNil(serving.calcium)
        XCTAssertNil(serving.iron)
    }

    func testFieldsOnlyConfirmedByOFFsTaxonomySchemaStillDecodeAndConvertCorrectly() throws {
        // Not a live capture (OFF's anonymous rate limit was hit while
        // researching this change) -- values are synthetic but the field
        // ids/units are real, taken from OFF's own published nutrients
        // taxonomy (static.openfoodfacts.org/data/taxonomies/nutrients.json).
        let json = """
        { "products": [{
          "code": "1", "product_name": "Synthetic taxonomy-only fixture",
          "nutriments": {
            "cholesterol_100g": 0.0008,
            "potassium_100g": 0.5,
            "vitamin-b9_100g": 0.00004,
            "vitamin-b12_100g": 0.0000005,
            "vitamin-e_100g": 0.005,
            "vitamin-k_100g": 0.000002,
            "magnesium_100g": 0.065,
            "zinc_100g": 0.001,
            "phosphorus_100g": 0.156,
            "selenium_100g": 0.0000068,
            "copper_100g": 0.0005,
            "manganese_100g": 0.0007,
            "iodine_100g": 0.0000036,
            "omega-3-fat_100g": 0.01,
            "omega-6-fat_100g": 0.75
          }
        }]}
        """

        let foods = try OpenFoodFactsClient.decode(Data(json.utf8))
        let serving = try XCTUnwrap(foods.first?.servings.first)

        XCTAssertEqual(try XCTUnwrap(serving.cholesterol), 0.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.potassium), 500, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.vitaminB9), 40, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.vitaminB12), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.vitaminE), 5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.vitaminK), 2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.magnesium), 65, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.zinc), 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.phosphorus), 156, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.selenium), 6.8, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.copper), 0.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.manganese), 0.7, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.iodine), 3.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.omega3), 10, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(serving.omega6), 750, accuracy: 0.0001)
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

    // MARK: - Search-a-licious (rebuild-food-search, probed 2026-09-23)

    /// Field-for-field the shape of a real 2026-09-23 Search-a-licious hit
    /// for `q=kefir countries_tags:"en:czech-republic"` (trimmed to the
    /// requested fields): `brands` is an ARRAY, `product_name` is the
    /// main-language (Czech) name, `product_name_en` a translation.
    private let searchALiciousJSON = """
    {
      "hits": [
        {
          "code": "8595671300044",
          "brands": ["Mlékárna Kunín"],
          "lang": "cs",
          "quantity": "750 g",
          "product_name": "Kefírové mléko",
          "product_name_en": "Kefir velky",
          "nutriments": { "energy-kcal_100g": 42, "proteins_100g": 3.1 }
        },
        {
          "code": "8594003024269",
          "lang": "en",
          "product_name": "Kefir low fat",
          "product_name_en": "Kefir low fat",
          "nutriments": { "energy-kcal_100g": 39 }
        },
        { "code": "5902170005456", "brands": ["Mleczna Dolina"], "product_name": "" }
      ],
      "page": 1, "page_size": 50, "page_count": 1, "count": 3, "took": 6, "timed_out": false,
      "aggregations": {}, "facets": {}, "charts": {}, "debug": {}, "is_count_exact": true, "warnings": null
    }
    """

    func testDecodesSearchALiciousHitsWithArrayBrandsAndAlternateNames() throws {
        let hits = try OpenFoodFactsClient.decodeSearchALicious(Data(searchALiciousJSON.utf8))

        // The nameless third hit is skipped, not fatal.
        XCTAssertEqual(hits.map(\.food.id), ["8595671300044", "8594003024269"])
        let kefir = hits[0]
        XCTAssertEqual(kefir.food.name, "Kefírové mléko")
        XCTAssertEqual(kefir.food.brandName, "Mlékárna Kunín")
        XCTAssertEqual(kefir.food.source, .openFoodFacts)
        XCTAssertEqual(kefir.food.servings.first?.calories, 42)
        XCTAssertEqual(kefir.alternateNames, ["Kefir velky"])
        // Identical names aren't repeated as aliases.
        XCTAssertEqual(hits[1].alternateNames, [])
    }

    /// czech-food-catalog spec "Czech-only name field".
    func testCzechNameIsPreferredOverAnEnglishMainName() throws {
        let json = """
        { "hits": [{ "code": "1", "lang": "en", "product_name": "Kefir drink", "product_name_cs": "Kefírové mléko", "generic_name_cs": "Zakysaný mléčný výrobek" }] }
        """

        let hit = try XCTUnwrap(OpenFoodFactsClient.decodeSearchALicious(Data(json.utf8)).first)

        XCTAssertEqual(hit.food.name, "Kefírové mléko")
        XCTAssertEqual(hit.alternateNames, ["Zakysaný mléčný výrobek", "Kefir drink"])
    }

    func testGenericCzechNameIsUsedWhenThereIsNoCzechProductName() throws {
        let json = """
        { "hits": [{ "code": "1", "lang": "de", "product_name": "Quark", "generic_name_cs": "Tvaroh" }] }
        """

        let hit = try XCTUnwrap(OpenFoodFactsClient.decodeSearchALicious(Data(json.utf8)).first)

        XCTAssertEqual(hit.food.name, "Tvaroh")
        XCTAssertEqual(hit.alternateNames, ["Quark"])
    }

    func testLegacyStringBrandsAndNumericCodesStillDecode() throws {
        let json = """
        { "products": [{ "code": 8594001565627, "product_name": "Rohlík", "brands": "Hollandia, Pilos" }] }
        """

        let hits = try OpenFoodFactsClient.decodeLegacy(Data(json.utf8))

        XCTAssertEqual(hits.first?.food.id, "8594001565627")
        XCTAssertEqual(hits.first?.food.brandName, "Hollandia, Pilos")
    }

    func testSearchALiciousQueryAddsTheCzechFilterAndStripsLuceneOperators() {
        XCTAssertEqual(
            OpenFoodFactsClient.searchALiciousQuery(term: "tvaroh", czechOnly: true),
            "tvaroh countries_tags:\"en:czech-republic\""
        )
        XCTAssertEqual(OpenFoodFactsClient.searchALiciousQuery(term: "tvaroh", czechOnly: false), "tvaroh")
        XCTAssertEqual(OpenFoodFactsClient.searchALiciousQuery(term: "brands:\"x\" (a) b*", czechOnly: false), "brands x a b")
    }

    func testMalformedSearchALiciousBodyThrowsADecodingError() {
        XCTAssertThrowsError(try OpenFoodFactsClient.decodeSearchALicious(Data("<html>503</html>".utf8))) { error in
            guard case OpenFoodFactsError.decodingFailed = error else {
                return XCTFail("expected decodingFailed, got \(error)")
            }
        }
    }
}

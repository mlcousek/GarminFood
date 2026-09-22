// CreateCustomMealRequestTests.swift
//
// Pins the guessed request shape for POST /nutrition-service/customMeal
// (see CreateCustomMealRequest's own doc comment in GarminModels.swift for
// why this is a guess, and what evidence backs it) so a future edit can't
// silently change the field names/nesting without a CI failure -- the same
// role CreateCustomFoodRequestTests.swift plays for its sibling route.

import XCTest
@testable import GarminKit

final class CreateCustomMealRequestTests: XCTestCase {
    private struct DecodedRequest: Decodable {
        struct Item: Decodable {
            let foodId: String
            let servingId: String
            let source: String
            let regionCode: String
            let languageCode: String
            let numberOfUnits: Double
        }
        let mealName: String
        let foodItems: [Item]
    }

    func testEncodesMealNameAndFoodItemsUsingFoodLogWriteBodysConfirmedVocabulary() throws {
        let request = CreateCustomMealRequest(
            mealName: "Breakfast bowl",
            foodItems: [
                CreateCustomMealRequest.Item(
                    foodId: "food-1",
                    servingId: "serving-1",
                    source: "FATSECRET",
                    regionCode: FoodLogWriteBody.regionCode,
                    languageCode: FoodLogWriteBody.languageCode,
                    numberOfUnits: 1.5
                ),
            ]
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DecodedRequest.self, from: data)

        XCTAssertEqual(decoded.mealName, "Breakfast bowl")
        XCTAssertEqual(decoded.foodItems.count, 1)
        XCTAssertEqual(decoded.foodItems.first?.foodId, "food-1")
        XCTAssertEqual(decoded.foodItems.first?.source, "FATSECRET")
        XCTAssertEqual(decoded.foodItems.first?.regionCode, "US")
        XCTAssertEqual(decoded.foodItems.first?.numberOfUnits, 1.5)
    }

    func testDecodesThePresumedResponseShape() throws {
        let json = #"{"customMealId": 185179}"#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(CreateCustomMealResponse.self, from: json)

        XCTAssertEqual(decoded.customMealId, 185179)
    }
}

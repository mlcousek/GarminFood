// CreateCustomFoodRequestTests.swift
//
// 2026-09-21 real-device bug: `createCustomFood` 400'd with "custom food
// nutrition information is missing for the provided food id with region
// code and language code" -- this pins the fix (regionCode/languageCode
// now sent, using the same confirmed constants FoodLogWriteBody's proven
// write contract already uses) so a future edit can't silently drop them
// again without a CI failure.

import XCTest
@testable import GarminKit

final class CreateCustomFoodRequestTests: XCTestCase {
    private struct DecodedRequest: Decodable {
        let foodName: String
        let servingUnit: String
        let numberOfUnits: Double
        let regionCode: String
        let languageCode: String
    }

    func testEncodesRegionAndLanguageCodeMatchingTheConfirmedFoodLogWriteConstants() throws {
        let request = CreateCustomFoodRequest(
            foodName: "Tvaroh",
            servingUnit: "g",
            numberOfUnits: 100,
            regionCode: FoodLogWriteBody.regionCode,
            languageCode: FoodLogWriteBody.languageCode,
            nutritionContent: CreateCustomFoodNutritionContent(calories: 98, protein: 12, carbs: 4, fat: 0.5)
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DecodedRequest.self, from: data)

        XCTAssertEqual(decoded.regionCode, "US")
        XCTAssertEqual(decoded.languageCode, "en")
        XCTAssertEqual(decoded.regionCode, FoodLogWriteBody.regionCode)
        XCTAssertEqual(decoded.languageCode, FoodLogWriteBody.languageCode)
    }
}

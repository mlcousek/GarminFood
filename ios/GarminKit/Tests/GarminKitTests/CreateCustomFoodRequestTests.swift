// CreateCustomFoodRequestTests.swift
//
// Pins CustomFoodWriteBody.make's corrected shape (2026-09-22): the
// nested foodMetaData/nutritionContents envelope, numbers encoded as
// strings, and foodId/servingId omitted for a create -- the fix for the
// real device 400 ("custom food nutrition information is missing for the
// provided food id with region code and language code") a flatter,
// earlier guess produced even after a first attempted fix. See
// CustomFoodWriteBody's own doc comment (GarminModels.swift) for the full
// evidence trail (tamcore/garmin-mcp's nutritionwritefood.go).

import XCTest
@testable import GarminKit

final class CreateCustomFoodRequestTests: XCTestCase {
    private struct DecodedNutritionContent: Decodable {
        let servingId: String?
        let servingUnit: String
        let numberOfUnits: String
        let calories: String
        let carbs: String?
        let protein: String?
        let fat: String?
    }

    private struct DecodedFoodMetaData: Decodable {
        let foodId: String?
        let foodName: String
        let foodType: String
        let source: String
        let regionCode: String
        let languageCode: String
        let brandName: String?
    }

    private struct DecodedRequest: Decodable {
        let foodMetaData: DecodedFoodMetaData
        let nutritionContents: [DecodedNutritionContent]
    }

    private func decode(_ body: CustomFoodWriteBody) throws -> DecodedRequest {
        let data = try JSONEncoder().encode(body)
        return try JSONDecoder().decode(DecodedRequest.self, from: data)
    }

    func testMakeNestsIdentityUnderFoodMetaDataWithConfirmedConstants() throws {
        let body = CustomFoodWriteBody.make(
            foodName: "Tvaroh",
            servingUnit: "g",
            numberOfUnits: 100,
            calories: 98,
            protein: 12,
            carbs: 4,
            fat: 0.5
        )

        let decoded = try decode(body)

        XCTAssertEqual(decoded.foodMetaData.foodName, "Tvaroh")
        XCTAssertEqual(decoded.foodMetaData.foodType, "GENERIC")
        XCTAssertEqual(decoded.foodMetaData.source, "GARMIN")
        XCTAssertEqual(decoded.foodMetaData.regionCode, FoodLogWriteBody.regionCode)
        XCTAssertEqual(decoded.foodMetaData.languageCode, FoodLogWriteBody.languageCode)
    }

    func testMakeOmitsFoodIdAndServingIdForACreate() throws {
        let body = CustomFoodWriteBody.make(foodName: "Rohlík", servingUnit: "g", numberOfUnits: 43, calories: 140, protein: nil, carbs: nil, fat: nil)

        let decoded = try decode(body)

        XCTAssertNil(decoded.foodMetaData.foodId, "Garmin assigns the real id on create; sending one would be wrong")
        XCTAssertNil(decoded.nutritionContents.first?.servingId)
    }

    func testMakeSendsNutritionContentsAsAOneElementArrayWithStringNumbers() throws {
        let body = CustomFoodWriteBody.make(foodName: "Rohlík", servingUnit: "g", numberOfUnits: 43, calories: 140, protein: 5, carbs: 27, fat: 1)

        let decoded = try decode(body)

        XCTAssertEqual(decoded.nutritionContents.count, 1)
        let content = try XCTUnwrap(decoded.nutritionContents.first)
        XCTAssertEqual(content.servingUnit, "g")
        XCTAssertEqual(content.numberOfUnits, "43", "a whole number must drop its trailing .0")
        XCTAssertEqual(content.calories, "140")
        XCTAssertEqual(content.protein, "5")
        XCTAssertEqual(content.carbs, "27")
        XCTAssertEqual(content.fat, "1")
    }

    func testMakeOmitsNilOptionalMacrosEntirelyRatherThanSendingNull() throws {
        let body = CustomFoodWriteBody.make(foodName: "Rohlík", servingUnit: "g", numberOfUnits: 43, calories: 140, protein: nil, carbs: nil, fat: nil)

        let data = try JSONEncoder().encode(body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contents = try XCTUnwrap((json["nutritionContents"] as? [[String: Any]])?.first)

        XCTAssertNil(contents["protein"], "an omitted macro must not appear in the JSON at all")
        XCTAssertNil(contents["carbs"])
        XCTAssertNil(contents["fat"])
    }

    func testNumberStringDropsTrailingZeroForWholeNumbersButKeepsDecimalsOtherwise() {
        XCTAssertEqual(CustomFoodWriteBody.numberString(160), "160")
        XCTAssertEqual(CustomFoodWriteBody.numberString(100.0), "100")
        XCTAssertEqual(CustomFoodWriteBody.numberString(12.5), "12.5")
        XCTAssertEqual(CustomFoodWriteBody.numberString(0.5), "0.5")
    }
}

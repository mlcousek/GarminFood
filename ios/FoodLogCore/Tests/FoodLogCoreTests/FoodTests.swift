// FoodTests.swift
//
// `Food.init(searchResult:)` adapter tests (task 12.2). `FoodSearchResult`
// and friends (GarminKit) have no public memberwise initializer (their
// synthesized init is internal, since none of GarminModels.swift declares
// an explicit public one) -- so, same as GarminKit's own ReconciliationTests,
// fixtures here are built by decoding hand-written JSON shaped exactly like
// docs/garmin-routes.json's confirmed `foodSearch` response.

import XCTest
@testable import FoodLogCore
import GarminKit

final class FoodTests: XCTestCase {
    private func decodeSearchResult(_ json: String) throws -> FoodSearchResult {
        try JSONDecoder().decode(FoodSearchResult.self, from: Data(json.utf8))
    }

    func testAdaptsAConfirmedShapeSearchResultIntoADomainFood() throws {
        let json = """
        {
          "type": "FOOD",
          "foodMetaData": {
            "foodId": "17926789",
            "foodName": "Rohlik",
            "foodType": "GENERIC",
            "source": "FATSECRET",
            "regionCode": "CZ",
            "languageCode": "cs"
          },
          "nutritionContents": [
            { "servingId": "16904392", "servingUnit": "g", "numberOfUnits": 100, "calories": 290, "carbs": 55, "protein": 9, "fat": 3 }
          ],
          "isFavorite": true,
          "isRecent": false
        }
        """

        let food = try Food(searchResult: decodeSearchResult(json))

        XCTAssertEqual(food?.id, "17926789")
        XCTAssertEqual(food?.name, "Rohlik")
        XCTAssertEqual(food?.source, .fatSecret)
        XCTAssertEqual(food?.servings.count, 1)
        XCTAssertEqual(food?.servings.first?.id, "16904392")
        XCTAssertEqual(food?.servings.first?.calories, 290)
        XCTAssertEqual(food?.garminIsFavorite, true)
        XCTAssertEqual(food?.garminIsRecent, false)
        XCTAssertNil(food?.imageURL, "Garmin's confirmed response shape carries no image field")
    }

    func testAResultWithNoServingsIsNotRepresentable() throws {
        let json = """
        {
          "foodMetaData": { "foodId": "1", "foodName": "No servings" },
          "nutritionContents": []
        }
        """

        let food = try Food(searchResult: decodeSearchResult(json))

        XCTAssertNil(food, "a food with no loggable serving isn't useful to show at all")
    }

    func testUnrecognisedSourceStringFallsBackToGarminRatherThanFailingTheWholeDecode() throws {
        let json = """
        {
          "foodMetaData": { "foodId": "1", "foodName": "Mystery source", "source": "SOMETHING_NEW" },
          "nutritionContents": [ { "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100 } ]
        }
        """

        let food = try Food(searchResult: decodeSearchResult(json))

        XCTAssertEqual(food?.source, .garmin)
    }

    func testServingDisplayLabelFormatsWholeAndFractionalQuantities() {
        let whole = Serving(id: "1", unit: "g", numberOfUnits: 100)
        let fractional = Serving(id: "2", unit: "medium banana", numberOfUnits: 1)

        XCTAssertEqual(whole.displayLabel, "100 g")
        XCTAssertEqual(fractional.displayLabel, "medium banana")
    }
}

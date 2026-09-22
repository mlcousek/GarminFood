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

    // MARK: detailedNutrients (implement-micronutrients, 2026-09-22)

    /// Only nutrients the serving actually carries appear -- same
    /// "never a fabricated zero" rule `MealDashboard.nutrients` already
    /// follows, now reused for a single food/serving via `NutrientKind`/
    /// `NutrientAmount` (Food.swift's header comment on `Serving` explains
    /// why this lives separately from the Garmin-fed day/meal dashboard).
    func testDetailedNutrientsOnlyIncludesWhatsActuallyPresent() {
        let serving = Serving(
            id: "100g", unit: "g", numberOfUnits: 100,
            calories: 384, carbs: 73.8, protein: 8.5, fat: 4.4,
            sodium: 80,
            vitaminB1: 1.0, vitaminD: 3.4
        )

        let kinds = serving.detailedNutrients.map(\.kind)

        XCTAssertEqual(kinds, [.calories, .carbs, .protein, .fat, .sodium, .vitaminB1, .vitaminD], "enum order, nils skipped")
        XCTAssertEqual(serving.detailedNutrients.first { $0.kind == .vitaminD }?.value, 3.4)
    }

    func testDetailedNutrientsIsEmptyForAServingWithNoNutrientDataAtAll() {
        let serving = Serving(id: "s1", unit: "serving", numberOfUnits: 1)

        XCTAssertTrue(serving.detailedNutrients.isEmpty)
    }

    /// Garmin/FatSecret's %DV fields (vitaminA/vitaminC/calcium/iron) and
    /// Open-Food-Facts-only absolute mg/µg fields (e.g. vitaminD, zinc) can
    /// coexist on the same serving's `detailedNutrients` without the reader
    /// needing to guess which is which -- `NutrientKind.unit` already
    /// disambiguates ("%", "mg", "µg") independent of `Food.source`.
    func testDetailedNutrientsCanMixGarminPercentDVAndOFFAbsoluteFieldsWithoutConflating() {
        let serving = Serving(id: "1", unit: "g", numberOfUnits: 100, calcium: 20, zinc: 1.2)

        let calcium = try? XCTUnwrap(serving.detailedNutrients.first { $0.kind == .calcium })
        let zinc = try? XCTUnwrap(serving.detailedNutrients.first { $0.kind == .zinc })

        XCTAssertEqual(calcium?.kind.unit, "%")
        XCTAssertEqual(zinc?.kind.unit, "mg")
    }
}

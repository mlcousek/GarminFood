// ServingAmountTests.swift
//
// `MetricServingSize` / `ServingQuantityInput` -- typing a food's amount in
// grams whatever its serving shape. Unit strings below are the real shapes
// a live read-only Garmin `food/search` and the owner's own food log
// returned on 2026-09-24 (see ServingAmount.swift's header).

import XCTest
@testable import FoodLogCore

final class MetricServingSizeTests: XCTestCase {
    private func size(_ unit: String, _ units: Double = 1) -> MetricServingSize? {
        MetricServingSize(unit: unit, numberOfUnits: units)
    }

    func testBothShapesOfA100GramServingAre100Grams() {
        XCTAssertEqual(size("100g", 1)?.amountPerServing, 100)
        XCTAssertEqual(size("g", 100)?.amountPerServing, 100)
        XCTAssertEqual(size("G", 100)?.amountPerServing, 100)
        XCTAssertEqual(size("100 g")?.amountPerServing, 100)
        XCTAssertEqual(size("100g")?.unit, .grams)
    }

    func testCyrillicAndMillilitreSpellings() {
        XCTAssertEqual(size("100г")?.amountPerServing, 100)
        XCTAssertEqual(size("100г")?.unit, .grams)
        XCTAssertEqual(size("100ml")?.unit, .milliliters)
        XCTAssertEqual(size("100мл")?.amountPerServing, 100)
        XCTAssertEqual(size("100мл")?.unit, .milliliters)
        XCTAssertEqual(size("ML", 100)?.unit, .milliliters)
        XCTAssertEqual(size("ML", 100)?.amountPerServing, 100)
    }

    func testANamedServingWithItsWeightInParentheses() {
        XCTAssertEqual(size("serving (118 g)")?.amountPerServing, 118)
        XCTAssertEqual(size("serving (50 g)")?.amountPerServing, 50)
        XCTAssertEqual(size("cup (240 ml)")?.unit, .milliliters)
    }

    func testAMultiUnitGramServing() {
        XCTAssertEqual(size("G", 30)?.amountPerServing, 30)
        XCTAssertEqual(size("100g", 2)?.amountPerServing, 200)
    }

    func testLargerUnitsAndADecimalComma() {
        XCTAssertEqual(size("0,5 l")?.amountPerServing, 500)
        XCTAssertEqual(size("0,5 l")?.unit, .milliliters)
        XCTAssertEqual(size("1 kg")?.amountPerServing, 1000)
    }

    func testServingsWithNoMetricSizeHaveNone() {
        XCTAssertNil(size("medium (7\" to 7-7/8\" long)"))
        XCTAssertNil(size("can (12 fl oz)"))
        XCTAssertNil(size("1/4 cup dry"))
        XCTAssertNil(size("oz"))
        XCTAssertNil(size("serving"))
        XCTAssertNil(size("piece"))
        XCTAssertNil(size(""))
        XCTAssertNil(size("5 mg"), "milligrams are not grams")
        XCTAssertNil(size("(5 mg)"))
        XCTAssertNil(MetricServingSize(unit: nil, numberOfUnits: 1))
    }

    func testANonPositiveOrNonFiniteUnitCountHasNoSize() {
        XCTAssertNil(size("g", 0))
        XCTAssertNil(size("g", -5))
        XCTAssertNil(size("g", .nan))
        XCTAssertNil(size("0g"))
    }

    func testAMissingUnitCountMeansOne() {
        XCTAssertEqual(MetricServingSize(unit: "100g", numberOfUnits: nil)?.amountPerServing, 100)
    }

    func testPerUnitOnlyForExactlyOneGramPerServing() {
        XCTAssertEqual(size("g", 1)?.isPerUnit, true)
        XCTAssertEqual(size("ml", 1)?.isPerUnit, true)
        XCTAssertEqual(size("g", 100)?.isPerUnit, false)
        XCTAssertEqual(size("100g", 1)?.isPerUnit, false)
    }

    func testServingExposesItsSize() {
        let serving = Serving(id: "50519029", unit: "100g", numberOfUnits: 1, calories: 63)
        XCTAssertEqual(serving.metricSize?.amountPerServing, 100)
        XCTAssertNil(Serving(id: "19134", unit: "medium", numberOfUnits: 1).metricSize)
    }
}

final class ServingQuantityInputTests: XCTestCase {
    private let hundredGrams = ServingQuantityInput(serving: Serving(id: "a", unit: "100g", numberOfUnits: 1, calories: 63))
    private let gramsTimes100 = ServingQuantityInput(serving: Serving(id: "b", unit: "g", numberOfUnits: 100, calories: 63))
    private let perGram = ServingQuantityInput(serving: Serving(id: "c", unit: "g", numberOfUnits: 1, calories: 0.63))
    private let piece = ServingQuantityInput(serving: Serving(id: "d", unit: "medium", numberOfUnits: 1, calories: 105))
    private let named118 = ServingQuantityInput(serving: Serving(id: "e", unit: "serving (118 g)", numberOfUnits: 1, calories: 105))

    // MARK: The owner's report

    func test150GramsOnA100GramServingIsOneAndAHalfServings() {
        XCTAssertEqual(hundredGrams.quantity(fromText: "150", mode: .amount), 1.5)
        XCTAssertEqual(gramsTimes100.quantity(fromText: "150", mode: .amount), 1.5)
    }

    func testTheCzechDecimalCommaWorksInBothModes() {
        XCTAssertEqual(hundredGrams.quantity(fromText: "1,5", mode: .servings), 1.5)
        XCTAssertEqual(hundredGrams.quantity(fromText: "12,5", mode: .amount), 0.125)
    }

    func testServingsModeKeepsTheMultiplierAsTyped() {
        XCTAssertEqual(hundredGrams.quantity(fromText: "1.5", mode: .servings), 1.5)
        XCTAssertEqual(hundredGrams.quantity(fromText: "0.3333", mode: .servings), 0.3333)
    }

    // MARK: Per-gram and unknown sizes

    func testAPerGramServingIsAlwaysEnteredInGramsAndUnitsEqualGrams() {
        XCTAssertFalse(perGram.offersModeChoice)
        XCTAssertEqual(perGram.resolvedMode(.servings), .amount)
        XCTAssertEqual(perGram.quantity(fromText: "150", mode: .servings), 150)
        XCTAssertEqual(perGram.quantity(fromText: "150", mode: .amount), 150)
    }

    func testAnUnknownSizeHasNoGramMode() {
        XCTAssertNil(piece.size)
        XCTAssertFalse(piece.offersModeChoice)
        XCTAssertEqual(piece.resolvedMode(.amount), .servings)
        XCTAssertEqual(piece.quantity(fromText: "2", mode: .amount), 2, "treated as servings")
        XCTAssertNil(piece.amountLabel(forQuantity: 2))
        XCTAssertEqual(piece.text(forQuantity: 1.5, mode: .amount), "1.5")
    }

    func testAMetricServingOffersTheChoiceAndHonoursThePreference() {
        XCTAssertTrue(hundredGrams.offersModeChoice)
        XCTAssertTrue(gramsTimes100.offersModeChoice)
        XCTAssertEqual(hundredGrams.resolvedMode(.amount), .amount)
        XCTAssertEqual(hundredGrams.resolvedMode(.servings), .servings)
    }

    // MARK: Rounding and round trips

    func testAGramDerivedMultiplierIsRoundedToThreeDecimals() {
        // 130 / 118 = 1.10169...
        XCTAssertEqual(named118.quantity(fromText: "130", mode: .amount), 1.102)
        XCTAssertEqual(hundredGrams.quantity(fromText: "33.33", mode: .amount), 0.333)
    }

    func testRoundTripsBetweenTextAndQuantity() {
        for grams in ["1", "12.5", "70", "150", "999.9", "5000"] {
            let quantity = hundredGrams.quantity(fromText: grams, mode: .amount)
            XCTAssertNotNil(quantity, grams)
            XCTAssertEqual(quantity.map { hundredGrams.text(forQuantity: $0, mode: .amount) }, grams)
        }
        for servings in ["1", "1.5", "0.333", "2.25"] {
            let quantity = hundredGrams.quantity(fromText: servings, mode: .servings)
            XCTAssertEqual(quantity.map { hundredGrams.text(forQuantity: $0, mode: .servings) }, servings)
        }
    }

    func testTextForAQuantityInEachMode() {
        XCTAssertEqual(hundredGrams.text(forQuantity: 1.5, mode: .amount), "150")
        XCTAssertEqual(hundredGrams.text(forQuantity: 1.5, mode: .servings), "1.5")
        XCTAssertEqual(hundredGrams.text(forQuantity: 1, mode: .servings), "1")
        XCTAssertEqual(hundredGrams.text(forQuantity: 1.5, mode: .servings, decimalSeparator: ","), "1,5")
        XCTAssertEqual(hundredGrams.text(forQuantity: 0.125, mode: .amount, decimalSeparator: ","), "12,5")
        // Garmin's float32 read-back of 0.7 still shows as a clean 70 g.
        XCTAssertEqual(gramsTimes100.text(forQuantity: 0.699999988079071, mode: .amount), "70")
    }

    func testAmountLabel() {
        XCTAssertEqual(hundredGrams.amountLabel(forQuantity: 1.5), "150 g")
        XCTAssertEqual(ServingQuantityInput(serving: Serving(id: "m", unit: "100ml", numberOfUnits: 1)).amountLabel(forQuantity: 2), "200 ml")
    }

    // MARK: Validation (LogQuantity limits)

    func testInvalidTextIsRejected() {
        for text in ["", "abc", "0", "-50", "1e5", "1,2,3"] {
            XCTAssertNil(hundredGrams.quantity(fromText: text, mode: .amount), text)
            XCTAssertNil(hundredGrams.quantity(fromText: text, mode: .servings), text)
        }
    }

    func testAnAmountTooSmallToRoundAboveZeroIsRejected() {
        XCTAssertNil(hundredGrams.quantity(fromText: "0.01", mode: .amount))
    }

    func testLimitsFollowLogQuantityInServings() {
        XCTAssertEqual(perGram.quantity(fromText: "10000", mode: .amount), LogQuantity.maximum)
        XCTAssertNil(perGram.quantity(fromText: "10000,1", mode: .amount))
        XCTAssertEqual(hundredGrams.quantity(fromText: "1000000", mode: .amount), LogQuantity.maximum)
        XCTAssertNil(hundredGrams.quantity(fromText: "1000100", mode: .amount))
        XCTAssertNil(hundredGrams.quantity(fromText: "10001", mode: .servings))
    }

    func testInvalidMessageNamesTheLimitInTheTypedUnit() {
        XCTAssertEqual(hundredGrams.invalidMessage(mode: .amount), "Enter an amount greater than zero and at most 1000000 g.")
        XCTAssertEqual(perGram.invalidMessage(mode: .servings), "Enter an amount greater than zero and at most 10000 g.")
        XCTAssertEqual(hundredGrams.invalidMessage(mode: .servings), LogQuantity.invalidMessage)
        XCTAssertEqual(piece.invalidMessage(mode: .amount), LogQuantity.invalidMessage)
    }

    func testInputTextTrimsTrailingZeros() {
        XCTAssertEqual(ServingQuantityInput.inputText(150, maxFractionDigits: 1), "150")
        XCTAssertEqual(ServingQuantityInput.inputText(12.5, maxFractionDigits: 1), "12.5")
        XCTAssertEqual(ServingQuantityInput.inputText(0.1, maxFractionDigits: 3), "0.1")
        XCTAssertEqual(ServingQuantityInput.inputText(100, maxFractionDigits: 0), "100")
        XCTAssertEqual(ServingQuantityInput.inputText(.nan, maxFractionDigits: 1), "")
    }
}

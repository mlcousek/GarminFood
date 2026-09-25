// LogQuantityTests.swift
//
// `LogQuantity.isValid` -- the one bound every confirm/edit path enforces --
// and `NumberDisplay`, which must never trap (`Int(_:)` did, for any value
// past ~9.2e18 or non-finite, crashing the Today screen on every launch).

import XCTest
@testable import FoodLogCore

final class LogQuantityTests: XCTestCase {
    func testOrdinaryQuantitiesAreValid() {
        XCTAssertTrue(LogQuantity.isValid(0.25))
        XCTAssertTrue(LogQuantity.isValid(1))
        XCTAssertTrue(LogQuantity.isValid(5000), "a 1 g serving logged by weight")
        XCTAssertTrue(LogQuantity.isValid(LogQuantity.maximum))
    }

    func testZeroNegativeHugeAndNonFiniteAreInvalid() {
        XCTAssertFalse(LogQuantity.isValid(0))
        XCTAssertFalse(LogQuantity.isValid(-1))
        XCTAssertFalse(LogQuantity.isValid(LogQuantity.maximum + 0.01))
        XCTAssertFalse(LogQuantity.isValid(1e19))
        XCTAssertFalse(LogQuantity.isValid(.infinity))
        XCTAssertFalse(LogQuantity.isValid(.nan))
    }

    func testTheMessageNamesTheLimit() {
        XCTAssertTrue(LogQuantity.invalidMessage.contains("10000"))
        XCTAssertEqual(LogQuantityError.outOfRange.errorDescription, LogQuantity.invalidMessage)
    }
}

final class NumberDisplayTests: XCTestCase {
    func testQuantityMatchesTheOldFormattingForOrdinaryValues() {
        XCTAssertEqual(NumberDisplay.quantity(2), "2")
        XCTAssertEqual(NumberDisplay.quantity(0.7), "0.70")
        XCTAssertEqual(NumberDisplay.quantity(1.25), "1.25")
        XCTAssertEqual(NumberDisplay.quantity(1.5, fractionDigits: 1), "1.5")
        XCTAssertEqual(NumberDisplay.quantity(100, fractionDigits: 1), "100")
        XCTAssertEqual(NumberDisplay.quantity(-3), "-3")
    }

    func testQuantityNeverTraps() {
        XCTAssertEqual(NumberDisplay.quantity(1e19), "10000000000000000000")
        XCTAssertEqual(NumberDisplay.quantity(-1e19), "-10000000000000000000")
        XCTAssertFalse(NumberDisplay.quantity(Double.greatestFiniteMagnitude).isEmpty)
        XCTAssertEqual(NumberDisplay.quantity(.infinity), NumberDisplay.placeholder)
        XCTAssertEqual(NumberDisplay.quantity(-.infinity), NumberDisplay.placeholder)
        XCTAssertEqual(NumberDisplay.quantity(.nan), NumberDisplay.placeholder)
    }

    func testNegativeZeroReadsAsZero() {
        XCTAssertEqual(NumberDisplay.quantity(-0.0), "0")
        XCTAssertEqual(NumberDisplay.whole(-0.4), "0")
    }

    func testWholeRoundsLikeIntOfRounded() {
        XCTAssertEqual(NumberDisplay.whole(289.6), "290")
        XCTAssertEqual(NumberDisplay.whole(289.4), "289")
        XCTAssertEqual(NumberDisplay.whole(0.5), "1")
        XCTAssertEqual(NumberDisplay.whole(-2.5), "-3")
        XCTAssertEqual(NumberDisplay.whole(0), "0")
    }

    func testWholeNeverTraps() {
        XCTAssertEqual(NumberDisplay.whole(1e21), "1000000000000000000000")
        XCTAssertEqual(NumberDisplay.whole(.infinity), NumberDisplay.placeholder)
        XCTAssertEqual(NumberDisplay.whole(.nan), NumberDisplay.placeholder)
    }

    // MARK: Locale (add-localization 6.1)

    private let english = Locale(identifier: "en_US")
    private let czech = Locale(identifier: "cs_CZ")

    func testQuantityUsesTheLocalesDecimalSeparator() {
        XCTAssertEqual(NumberDisplay.quantity(0.7, locale: english), "0.70")
        XCTAssertEqual(NumberDisplay.quantity(0.7, locale: czech), "0,70", "spec: a serving of 0.7 cups reads 0,70 in Czech")
        XCTAssertEqual(NumberDisplay.quantity(1.5, fractionDigits: 1, locale: english), "1.5")
        XCTAssertEqual(NumberDisplay.quantity(1.5, fractionDigits: 1, locale: czech), "1,5")
        XCTAssertEqual(NumberDisplay.quantity(1.25, locale: czech), "1,25")
    }

    func testWholeNumbersReadTheSameInBothLanguages() {
        for locale in [english, czech] {
            XCTAssertEqual(NumberDisplay.quantity(2, locale: locale), "2")
            XCTAssertEqual(NumberDisplay.quantity(10000, locale: locale), "10000")
            XCTAssertEqual(NumberDisplay.quantity(1e19, locale: locale), "10000000000000000000")
        }
    }

    /// No grouping in either language: "12345,50", never "12 345,50" --
    /// a number in a validation message must look like what can be typed.
    func testDecimalsAreNeverGrouped() {
        XCTAssertEqual(NumberDisplay.quantity(12345.5, locale: english), "12345.50")
        XCTAssertEqual(NumberDisplay.quantity(12345.5, locale: czech), "12345,50")
    }

    func testANegativeValueThatRoundsToZeroHasNoSign() {
        XCTAssertEqual(NumberDisplay.quantity(-0.001, locale: english), "0.00")
        XCTAssertEqual(NumberDisplay.quantity(-0.001, locale: czech), "0,00")
    }

    func testTrimmedDropsTrailingZeros() {
        XCTAssertEqual(NumberDisplay.trimmed(150, maxFractionDigits: 1, locale: czech), "150")
        XCTAssertEqual(NumberDisplay.trimmed(12.5, maxFractionDigits: 1, locale: english), "12.5")
        XCTAssertEqual(NumberDisplay.trimmed(12.5, maxFractionDigits: 1, locale: czech), "12,5")
        XCTAssertEqual(NumberDisplay.trimmed(0.333, maxFractionDigits: 3, locale: czech), "0,333")
        XCTAssertEqual(NumberDisplay.trimmed(149.96, maxFractionDigits: 1, locale: english), "150")
        XCTAssertEqual(NumberDisplay.trimmed(.nan, maxFractionDigits: 1, locale: czech), NumberDisplay.placeholder)
    }

    func testServingLabelsNoLongerTrapOnAHugeTypedServingSize() {
        let serving = Serving(id: "custom", unit: "bowl", numberOfUnits: 1e19)
        XCTAssertEqual(serving.displayLabel, "10000000000000000000 bowl")
    }
}

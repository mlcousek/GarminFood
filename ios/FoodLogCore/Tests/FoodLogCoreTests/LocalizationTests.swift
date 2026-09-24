// LocalizationTests.swift
//
// Proves FoodLogCore's localized resources actually ship and resolve
// (add-localization design.md D3/D9.3). This is the only automated check
// that Czech works without a device: the package keeps its translations in
// Resources/<lang>.lproj/Localizable.strings precisely so that plain
// `swift test` can load them (it can't compile .xcstrings catalogs).
//
// The Czech lookup goes through the cs.lproj sub-bundle explicitly, because
// the test process itself runs in English on CI; the English assertions pin
// that adding localization changed nothing for an English phone.

import XCTest
@testable import FoodLogCore

final class LocalizationTests: XCTestCase {
    private func czechBundle() throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.module.path(forResource: "cs", ofType: "lproj"),
            "cs.lproj missing from FoodLogCore's resource bundle -- check Package.swift's resources/defaultLocalization"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    func testPackageDeclaresEnglishAndCzech() {
        let localizations = Bundle.module.localizations
        XCTAssertTrue(localizations.contains("en"), "found: \(localizations)")
        XCTAssertTrue(localizations.contains("cs"), "found: \(localizations)")
    }

    func testInvalidQuantityMessageResolvesInCzech() throws {
        let format = try czechBundle().localizedString(
            forKey: "Enter an amount greater than zero and at most %@.",
            value: "<missing>",
            table: nil
        )
        XCTAssertEqual(
            String(format: format, NumberDisplay.quantity(LogQuantity.maximum)),
            "Zadej množství větší než nula a nejvýše 10000."
        )
    }

    func testEnglishTextIsUnchanged() {
        XCTAssertEqual(LogQuantity.invalidMessage, "Enter an amount greater than zero and at most 10000.")
    }
}

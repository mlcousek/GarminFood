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

    /// Meal reminders are one full sentence per meal (design.md D5) -- the
    /// Czech accusative ("snídani") only works because nothing is inserted.
    func testMealReminderResolvesInCzech() throws {
        let title = try czechBundle().localizedString(forKey: "Log your breakfast", value: "<missing>", table: nil)
        XCTAssertEqual(title, "Zapiš si snídani")
    }

    /// The first FoodLogCore `.stringsdict` entry: proves the plural table
    /// ships in cs.lproj and formats. 5 is deliberately a count whose form
    /// is `other` under both English and Czech rules, so the assertion
    /// doesn't depend on which locale's plural rules the formatter picks.
    func testFastingEndsBodyPluralResolvesInCzech() throws {
        let format = try czechBundle().localizedString(
            forKey: "Your fast ends at %@ -- eating opens in %lld minutes.",
            value: "<missing>",
            table: nil
        )
        XCTAssertNotEqual(format, "<missing>", "stringsdict key missing from cs.lproj")
        XCTAssertEqual(
            String(format: format, locale: Locale(identifier: "cs_CZ"), "12:00", 5),
            "Tvůj půst končí v 12:00 – jíst můžeš za 5 minut."
        )
    }

    func testEnglishTextIsUnchanged() {
        XCTAssertEqual(LogQuantity.invalidMessage, "Enter an amount greater than zero and at most 10000.")
    }
}

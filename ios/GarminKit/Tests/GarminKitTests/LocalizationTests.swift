// LocalizationTests.swift
//
// Proves GarminKit's localized resources ship and resolve under plain
// `swift test` (add-localization design.md D3/D9.3, task 3.4). GarminKit has
// exactly one user-facing string -- `PersistedJSONUnreadFileError`'s
// message, shown as-is on the confirm screen -- and this is the only
// automated check that its Czech text exists without a device.
//
// The Czech lookup goes through the cs.lproj sub-bundle explicitly, because
// the test process itself runs in English on CI; the English assertion pins
// that adding localization changed nothing for an English phone.

import XCTest
@testable import GarminKit

final class LocalizationTests: XCTestCase {
    private func czechBundle() throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.module.path(forResource: "cs", ofType: "lproj"),
            "cs.lproj missing from GarminKit's resource bundle -- check Package.swift's resources/defaultLocalization"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    func testPackageDeclaresEnglishAndCzech() {
        let localizations = Bundle.module.localizations
        XCTAssertTrue(localizations.contains("en"), "found: \(localizations)")
        XCTAssertTrue(localizations.contains("cs"), "found: \(localizations)")
    }

    func testUnreadFileErrorResolvesInCzech() throws {
        let format = try czechBundle().localizedString(
            forKey: "%@ exists but could not be read yet (is the device still locked?), so it was not overwritten. Try again.",
            value: "<missing>",
            table: nil
        )
        XCTAssertEqual(
            String(format: format, "outbox.json"),
            "Soubor outbox.json zatím nejde přečíst (není telefon ještě zamčený?), a tak nebyl přepsán. Zkus to znovu."
        )
    }

    func testEnglishTextIsUnchanged() {
        XCTAssertEqual(
            PersistedJSONUnreadFileError(fileName: "outbox.json").errorDescription,
            "outbox.json exists but could not be read yet (is the device still locked?), so it was not overwritten. Try again."
        )
    }
}

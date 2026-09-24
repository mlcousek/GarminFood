// AppearanceSettingsTests — task 1.4: lenient decoding (D7). A stored look
// must survive a missing field, an unknown enum value from a newer build,
// extra fields and a garbled value, each falling back per field; only a
// payload that isn't a JSON object is reported undecodable (for quarantine).

import XCTest
@testable import AppearanceKit

final class AppearanceSettingsTests: XCTestCase {

    private func load(_ json: String) -> AppearanceSettings.LoadResult {
        AppearanceSettings.load(from: Data(json.utf8))
    }

    func testAbsentGivesDefaults() {
        let result = AppearanceSettings.load(from: nil)
        XCTAssertEqual(result.status, .absent)
        XCTAssertEqual(result.settings, .default)
        XCTAssertEqual(result.settings.themeID, AppearanceSettings.defaultThemeID)
        XCTAssertEqual(result.settings.macroSet, .theme)
        XCTAssertNil(result.settings.customAccent)
        XCTAssertEqual(result.settings.style, .default)
        XCTAssertEqual(result.settings.appearance, .system)
    }

    func testEmptyObjectGivesDefaults() {
        let result = load("{}")
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.settings, .default)
    }

    func testRoundTrip() throws {
        let settings = AppearanceSettings(
            themeID: "ocean",
            appearance: .dark,
            macroSet: .colorBlindSafe,
            customAccent: RGBA(hex: 0x15808C),
            style: AppearanceStyle(cardStyle: .outlined, cornerShape: .round, density: .compact,
                                   numberFont: .serif, gradientHeader: true)
        )
        let result = AppearanceSettings.load(from: try settings.encoded())
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.settings, settings)
        XCTAssertEqual(result.settings.appearance, .dark)
    }

    func testMissingFieldsFallBackIndividually() {
        let result = load(#"{"version":1,"themeID":"forest"}"#)
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.settings.themeID, "forest")
        XCTAssertEqual(result.settings.macroSet, .theme)
        XCTAssertEqual(result.settings.style, .default)
        XCTAssertEqual(result.settings.appearance, .system)
    }

    func testUnknownEnumValuesFallBackPerField() {
        let json = #"""
        {"version":1,"themeID":"ocean","macroSet":"ultraviolet",
         "appearance":"sepia",
         "style":{"cardStyle":"neon","cornerShape":"round","density":"tiny","numberFont":"serif"}}
        """#
        let settings = load(json).settings
        XCTAssertEqual(settings.themeID, "ocean")
        XCTAssertEqual(settings.macroSet, .theme)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.style.cardStyle, .filled)
        XCTAssertEqual(settings.style.cornerShape, .round)
        XCTAssertEqual(settings.style.density, .comfortable)
        XCTAssertEqual(settings.style.numberFont, .serif)
    }

    func testUnknownThemeIDIsKeptVerbatim() {
        // A newer build's theme: kept, so a later upgrade finds it again;
        // PaletteResolver falls back to the default theme meanwhile.
        XCTAssertEqual(load(#"{"themeID":"aurora"}"#).settings.themeID, "aurora")
    }

    func testExtraFieldsAreIgnored() {
        let result = load(#"{"themeID":"slate","futureThing":{"a":[1,2,3]},"layout":"x"}"#)
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.settings.themeID, "slate")
    }

    func testWrongTypesFallBackPerField() {
        let json = ##"{"version":"one","themeID":42,"macroSet":7,"customAccent":"#nothex","style":"fancy","appearance":[1]}"##
        let result = load(json)
        XCTAssertEqual(result.status, .loaded)
        XCTAssertEqual(result.settings, .default)
    }

    func testEmptyThemeIDFallsBack() {
        XCTAssertEqual(load(#"{"themeID":""}"#).settings.themeID, AppearanceSettings.defaultThemeID)
    }

    func testGarbageIsUndecodable() {
        for garbage in ["", "not json", "[1,2,3]", "\"teal\"", "42", "{\"themeID\":"] {
            let result = load(garbage)
            XCTAssertEqual(result.status, .undecodable, garbage)
            XCTAssertEqual(result.settings, .default, garbage)
        }
        let binary = AppearanceSettings.load(from: Data([0xFF, 0xFE, 0x00, 0x01]))
        XCTAssertEqual(binary.status, .undecodable)
    }

    func testMigrationIsNoOpAtV1AndStampsVersion() {
        let settings = AppearanceSettings(version: 0, themeID: "gold", macroSet: .legible)
        let migrated = AppearanceMigration.migrate(settings)
        XCTAssertEqual(migrated.version, AppearanceSchema.currentVersion)
        XCTAssertEqual(migrated.themeID, "gold")
        XCTAssertEqual(migrated.macroSet, .legible)
        XCTAssertEqual(load(#"{"version":99,"themeID":"gold"}"#).settings.version, AppearanceSchema.currentVersion)
    }

    func testAppearanceIsOneGlobalChoice() {
        XCTAssertEqual(load(#"{"appearance":"dark"}"#).settings.appearance, .dark)
        XCTAssertEqual(load(#"{"appearance":"light","themeID":"forest"}"#).settings.appearance, .light)
    }
}

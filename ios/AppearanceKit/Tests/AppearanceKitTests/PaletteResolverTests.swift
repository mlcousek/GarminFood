// PaletteResolverTests — D4 resolution order. Task 1.5: Classic resolves to
// today's values in both schemes, untouched.

import XCTest
@testable import AppearanceKit

final class PaletteResolverTests: XCTestCase {

    func testClassicResolvesToTodaysValuesInBothSchemes() {
        for scheme in ThemeColorScheme.allCases {
            let palette = PaletteResolver.resolve(theme: ClassicTheme.spec, requestedScheme: scheme)
            XCTAssertEqual(palette.themeID, "classic")
            XCTAssertEqual(palette.scheme, scheme)
            XCTAssertFalse(palette.usesIncreasedContrast)
            XCTAssertEqual(palette.table, ClassicTheme.table, "\(scheme)")
            XCTAssertEqual(palette[.accent], .rgb(RGBA(red: 0.96, green: 0.42, blue: 0.29)))
            XCTAssertEqual(palette[.onAccent], .rgb(.white))
            XCTAssertEqual(palette[.danger], .system(.systemRed))
            XCTAssertTrue(palette.adjustedRoles.isEmpty)
            XCTAssertTrue(palette.unfittableRoles.isEmpty)
        }
    }

    func testReferenceValueApproximatesSystemColorsPerScheme() {
        let light = PaletteResolver.resolve(theme: ClassicTheme.spec, requestedScheme: .light)
        let dark = PaletteResolver.resolve(theme: ClassicTheme.spec, requestedScheme: .dark)
        XCTAssertEqual(light.referenceValue(.surface), RGBA(hex: 0xFFFFFF))
        XCTAssertEqual(dark.referenceValue(.surface), RGBA(hex: 0x1C1C1E))
        XCTAssertEqual(dark.referenceValue(.accent), ClassicTheme.Literal.accent)
    }

    func testSingleSchemeThemeForcesItsScheme() {
        let darkOnly = ThemeSpec(id: "night", iconName: "Default", light: nil, dark: ClassicTheme.table)
        let palette = PaletteResolver.resolve(theme: darkOnly, requestedScheme: .light)
        XCTAssertEqual(palette.scheme, .dark)
    }

    func testThemeWithoutTablesFallsBackToClassic() {
        let empty = ThemeSpec(id: "broken", iconName: "Default", light: nil, dark: nil)
        let palette = PaletteResolver.resolve(theme: empty, requestedScheme: .light)
        XCTAssertEqual(palette.table, ClassicTheme.table)
        XCTAssertEqual(palette.scheme, .light)
    }
}

// AccentAdjusterTests — task 2.3: the hue-keeping lightness walk (D5), the
// custom accent through the resolver (D4 step 3), and the macro-collision
// warning shown by the accent picker.

import XCTest
@testable import AppearanceKit

final class AccentAdjusterTests: XCTestCase {

    private let white = RGBA.white
    private let darkCard = RGBA(hex: 0x1C1C1E)

    // MARK: fit

    func testPassingColorIsUnchanged() {
        let blue = RGBA(hex: 0x0040DD)
        let result = AccentAdjuster.fit(blue, against: [white], minRatio: 3.0, scheme: .light)
        XCTAssertFalse(result.wasAdjusted)
        XCTAssertFalse(result.gaveUp)
        XCTAssertEqual(result.color, blue)
    }

    func testCoralInLightIsFittedKeepingHue() {
        let coral = ClassicTheme.Literal.accent
        let result = AccentAdjuster.fit(coral, against: [white, RGBA(hex: 0xF2F2F7)], minRatio: 3.0, scheme: .light)
        XCTAssertTrue(result.wasAdjusted)
        XCTAssertFalse(result.gaveUp)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(result.color, white), 3.0)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(result.color, RGBA(hex: 0xF2F2F7)), 3.0)
        XCTAssertEqual(ColorMath.oklch(result.color).hue, ColorMath.oklch(coral).hue, accuracy: 2)
        XCTAssertLessThan(ColorMath.oklch(result.color).lightness, ColorMath.oklch(coral).lightness)
        // First passing step: one step lighter would fail.
        XCTAssertLessThan(ColorMath.oklch(coral).lightness - ColorMath.oklch(result.color).lightness, 0.15)
    }

    func testYellowTerminatesAndPasses() {
        let result = AccentAdjuster.fit(RGBA(hex: 0xFFFF00), against: [white], minRatio: 3.0, scheme: .light)
        XCTAssertTrue(result.wasAdjusted)
        XCTAssertFalse(result.gaveUp)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(result.color, white), 3.0)
    }

    func testImpossibleRequirementGivesUpWithBestCandidate() {
        // Nothing reaches 22:1 against white; the walk must still end.
        let result = AccentAdjuster.fit(RGBA(hex: 0xFFFF00), against: [white], minRatio: 22, scheme: .light)
        XCTAssertTrue(result.gaveUp)
        XCTAssertTrue(result.wasAdjusted)
        XCTAssertGreaterThan(ColorMath.contrastRatio(result.color, white), 20)
    }

    func testLimeIsDarkened() {
        let lime = RGBA(hex: 0x00FF00)
        let result = AccentAdjuster.fit(lime, against: [white], minRatio: 3.0, scheme: .light)
        XCTAssertTrue(result.wasAdjusted)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(result.color, white), 3.0)
        XCTAssertLessThan(ColorMath.relativeLuminance(result.color), ColorMath.relativeLuminance(lime))
        XCTAssertEqual(ColorMath.oklch(result.color).hue, ColorMath.oklch(lime).hue, accuracy: 2)
        XCTAssertTrue(ColorMath.isInGamut(result.color))
    }

    func testDarkSchemeLightens() {
        let navy = RGBA(hex: 0x0000FF)
        let result = AccentAdjuster.fit(navy, against: [darkCard], minRatio: 4.5, scheme: .dark)
        XCTAssertTrue(result.wasAdjusted)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(result.color, darkCard), 4.5)
        XCTAssertGreaterThan(ColorMath.oklch(result.color).lightness, ColorMath.oklch(navy).lightness)
    }

    func testNoRequirementsMeansUnchanged() {
        let color = RGBA(hex: 0x123456)
        XCTAssertEqual(AccentAdjuster.fit(color, requirements: [], direction: .darken).color, color)
    }

    func testDeepenedIsDarkerWithSameHue() {
        let accent = RGBA(hex: 0x15808C)
        let deep = AccentAdjuster.deepened(accent)
        XCTAssertEqual(ColorMath.oklch(accent).lightness - ColorMath.oklch(deep).lightness, 0.12, accuracy: 0.01)
        XCTAssertEqual(ColorMath.oklch(deep).hue, ColorMath.oklch(accent).hue, accuracy: 2)
    }

    // MARK: Custom accent through the resolver (D4 step 3)

    func testCustomAccentIsFittedAndDerivesItsCompanions() {
        let palette = PaletteResolver.resolve(
            theme: BuiltInTheme.teal.spec, requestedScheme: .light, customAccent: RGBA(hex: 0xFFFF00)
        )
        let accent = palette.referenceValue(.accent)
        XCTAssertTrue(palette.adjustedRoles.contains(.accent))
        XCTAssertTrue(palette.unfittableRoles.isEmpty)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(accent, palette.referenceValue(.surface)), 3.0)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(accent, palette.referenceValue(.background)), 3.0)
        XCTAssertEqual(palette[.onAccent], .rgb(ContrastPolicy.preferredOnAccent(for: accent)))
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(palette.referenceValue(.onAccent), accent), 4.5)
        XCTAssertEqual(palette[.accentDeep], .rgb(AccentAdjuster.deepened(accent)))
        XCTAssertEqual(palette[.headerGradientStart], .rgb(accent))
        XCTAssertEqual(palette[.headerGradientEnd], palette[.accentDeep])
    }

    func testPassingCustomAccentIsKeptExactly() {
        let pick = RGBA(hex: 0x0040DD)
        let palette = PaletteResolver.resolve(theme: BuiltInTheme.teal.spec, requestedScheme: .light, customAccent: pick)
        XCTAssertEqual(palette[.accent], .rgb(pick))
        XCTAssertFalse(palette.adjustedRoles.contains(.accent))
        XCTAssertEqual(palette[.onAccent], .rgb(.white))
    }

    func testOnePickIsFittedPerScheme() {
        let pick = RGBA(hex: 0x203080)
        let light = PaletteResolver.resolve(theme: BuiltInTheme.teal.spec, requestedScheme: .light, customAccent: pick)
        let dark = PaletteResolver.resolve(theme: BuiltInTheme.teal.spec, requestedScheme: .dark, customAccent: pick)
        XCTAssertEqual(light[.accent], .rgb(pick))
        XCTAssertTrue(dark.adjustedRoles.contains(.accent))
        XCTAssertGreaterThan(ColorMath.oklch(dark.referenceValue(.accent)).lightness, ColorMath.oklch(pick).lightness)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(dark.referenceValue(.accent), dark.referenceValue(.surface)), 3.0)
    }

    func testCustomAccentIgnoresPickAlpha() {
        let palette = PaletteResolver.resolve(
            theme: BuiltInTheme.teal.spec, requestedScheme: .light, customAccent: RGBA(hex: 0x0040DD, alpha: 0.3)
        )
        XCTAssertEqual(palette.referenceValue(.accent).alpha, 1)
    }

    func testCustomAccentMeetsIncreasedThresholds() {
        let palette = PaletteResolver.resolve(
            theme: ClassicTheme.spec, requestedScheme: .light,
            customAccent: RGBA(hex: 0x00FF00), increasedContrast: true
        )
        let failures = PolicyChecker.contrastFailures(palette.table, scheme: .light, level: .increased)
        XCTAssertTrue(failures.isEmpty, "\(failures)")
    }

    func testCustomAccentFromSettings() {
        let settings = AppearanceSettings(themeID: "slate", customAccent: RGBA(hex: 0x0040DD))
        let palette = PaletteResolver.resolve(settings: settings, environment: AppearanceEnvironment(systemScheme: .light))
        XCTAssertEqual(palette[.accent], .rgb(RGBA(hex: 0x0040DD)))
    }

    // MARK: Collision warning

    func testAccentLikeProteinIsFlagged() {
        let protein = RGBA(hex: 0x7A52C7) // Legible light protein, as used by GF Teal
        let palette = PaletteResolver.resolve(theme: BuiltInTheme.teal.spec, requestedScheme: .light, customAccent: protein)
        XCTAssertEqual(AccentAdjuster.collidingMacro(in: palette), .protein)
    }

    func testBuiltInAccentsDoNotCollide() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                let palette = PaletteResolver.resolve(theme: theme, requestedScheme: scheme)
                XCTAssertNil(AccentAdjuster.collidingMacro(in: palette), "\(theme.id) \(scheme)")
            }
        }
    }

    func testClosestCollisionWins() {
        let accent = RGBA(hex: 0x4A8FE3)
        let macros: [ThemeRole: RGBA] = [
            .carbs: RGBA(hex: 0x4A8FE4),   // nearly identical
            .water: RGBA(hex: 0x4F92E0),   // close too, but farther
            .fat: RGBA(hex: 0xEDB033)
        ]
        XCTAssertEqual(AccentAdjuster.collidingMacro(accent, macros: macros), .carbs)
        XCTAssertNil(AccentAdjuster.collidingMacro(RGBA(hex: 0xC62828), macros: macros))
    }
}

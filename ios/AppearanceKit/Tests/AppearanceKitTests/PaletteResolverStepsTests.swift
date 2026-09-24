// PaletteResolverStepsTests — task 2.2: D4 steps 2–5 and the full D5
// matrix on *resolved* palettes: every built-in theme × requested scheme ×
// {normal, increased} × {theme, Legible, Colour-blind safe} meets the policy
// at its level (Classic at normal contrast only within its exemption list),
// and the fitter never gives up on a built-in.

import XCTest
@testable import AppearanceKit

final class PaletteResolverStepsTests: XCTestCase {

    // MARK: The matrix

    func testEveryResolvedPaletteMeetsTheContrastPolicy() {
        for theme in ThemeCatalog.all {
            for requested in ThemeColorScheme.allCases {
                for increased in [false, true] {
                    for macroSet in MacroSetOption.allCases {
                        let palette = PaletteResolver.resolve(
                            theme: theme, requestedScheme: requested,
                            macroSet: macroSet, increasedContrast: increased
                        )
                        let label = "\(theme.id) \(requested)->\(palette.scheme) increased=\(increased) \(macroSet)"
                        XCTAssertTrue(palette.unfittableRoles.isEmpty, "\(label): \(palette.unfittableRoles)")
                        let level: ContrastLevel = palette.usesIncreasedContrast ? .increased : .normal
                        let failures = PolicyChecker.contrastFailures(palette.table, scheme: palette.scheme, level: level)
                        if theme.id == ClassicTheme.id && level == .normal {
                            let unexpected = Set(failures.map(\.role)).subtracting(BuiltInThemeContrastTests.classicExemptions)
                            XCTAssertTrue(unexpected.isEmpty, "\(label): \(failures)")
                        } else {
                            XCTAssertTrue(failures.isEmpty, "\(label): \(failures)")
                        }
                    }
                }
            }
        }
    }

    func testThemeMacrosStayDistinctAtBothContrastLevels() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                for increased in [false, true] {
                    let palette = PaletteResolver.resolve(theme: theme, requestedScheme: scheme, increasedContrast: increased)
                    let failures = PolicyChecker.distinctnessFailures(palette.table, scheme: palette.scheme)
                    XCTAssertTrue(failures.isEmpty, "\(theme.id) \(scheme) increased=\(increased): \(failures)")
                }
            }
        }
    }

    func testColorBlindSafeSetSurvivesSimulationAfterFitting() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                for increased in [false, true] {
                    let palette = PaletteResolver.resolve(
                        theme: theme, requestedScheme: scheme,
                        macroSet: .colorBlindSafe, increasedContrast: increased
                    )
                    let failures = PolicyChecker.cvdFailures(palette.table, scheme: palette.scheme)
                    XCTAssertTrue(failures.isEmpty, "\(theme.id) \(scheme) increased=\(increased): \(failures)")
                }
            }
        }
    }

    // MARK: Step 2

    func testLegibleSetOverridesClassicMacros() {
        let palette = PaletteResolver.resolve(theme: ClassicTheme.spec, requestedScheme: .light, macroSet: .legible)
        XCTAssertEqual(palette[.carbs], .rgb(RGBA(hex: 0x2F74C8)))
        XCTAssertEqual(palette[.danger], .rgb(RGBA(hex: 0xC62828)))
        // Brand untouched at normal contrast.
        XCTAssertEqual(palette[.accent], ClassicTheme.table[.accent])
        XCTAssertEqual(palette[.onAccent], .rgb(.white))
    }

    func testDifferentiateWithoutColorForcesColorBlindSafe() {
        for macroSet in MacroSetOption.allCases {
            let palette = PaletteResolver.resolve(
                theme: BuiltInTheme.teal.spec, requestedScheme: .dark,
                macroSet: macroSet, differentiateWithoutColor: true
            )
            XCTAssertEqual(palette[.carbs], .rgb(RGBA(hex: 0x56B4E9)), "\(macroSet)")
            XCTAssertEqual(palette[.protein], .rgb(RGBA(hex: 0xF28A3C)), "\(macroSet)")
            XCTAssertEqual(palette[.fat], .rgb(RGBA(hex: 0xF0E442)), "\(macroSet)")
        }
    }

    // MARK: Step 4 + 5

    func testIncreasedContrastFitsClassicLightAccentKeepingHue() {
        let palette = PaletteResolver.resolve(theme: ClassicTheme.spec, requestedScheme: .light, increasedContrast: true)
        let accent = palette.referenceValue(.accent)
        XCTAssertTrue(palette.usesIncreasedContrast)
        XCTAssertTrue(palette.adjustedRoles.contains(.accent))
        XCTAssertEqual(palette[.onAccent], .rgb(.white))
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(.white, accent), 7.0)
        XCTAssertEqual(ColorMath.oklch(accent).hue, ColorMath.oklch(ClassicTheme.Literal.accent).hue, accuracy: 10)
        // System colors are left to iOS's own increased-contrast variants.
        XCTAssertEqual(palette[.danger], .system(.systemRed))
        XCTAssertFalse(palette.adjustedRoles.contains(.danger))
    }

    func testIncreasedContrastClassicDarkKeepsAccentAndFlipsLabelToBlack() {
        let palette = PaletteResolver.resolve(theme: ClassicTheme.spec, requestedScheme: .dark, increasedContrast: true)
        XCTAssertEqual(palette[.accent], ClassicTheme.table[.accent])
        XCTAssertFalse(palette.adjustedRoles.contains(.accent))
        XCTAssertEqual(palette[.onAccent], .rgb(.black))
    }

    func testNormalContrastLeavesBuiltInsUntouched() {
        for theme in ThemeCatalog.all where !theme.isHighContrast {
            for scheme in theme.supportedSchemes {
                let palette = PaletteResolver.resolve(theme: theme, requestedScheme: scheme)
                XCTAssertEqual(palette.table, theme.table(for: scheme), "\(theme.id) \(scheme)")
                XCTAssertTrue(palette.adjustedRoles.isEmpty, "\(theme.id) \(scheme)")
            }
        }
    }

    func testHighContrastThemeUsesIncreasedThresholdsWithoutTheSystemSetting() {
        let palette = PaletteResolver.resolve(theme: BuiltInTheme.highContrast.spec, requestedScheme: .light)
        XCTAssertTrue(palette.usesIncreasedContrast)
        XCTAssertTrue(palette.adjustedRoles.isEmpty, "\(palette.adjustedRoles)")
    }

    // MARK: resolve(settings:environment:)

    func testSettingsPickThemeAndAppearance() {
        let settings = AppearanceSettings(themeID: "ocean", appearance: .dark)
        let palette = PaletteResolver.resolve(settings: settings, environment: AppearanceEnvironment(systemScheme: .light))
        XCTAssertEqual(palette.themeID, "ocean")
        XCTAssertEqual(palette.scheme, .dark)
    }

    func testSystemAppearanceFollowsTheEnvironment() {
        let settings = AppearanceSettings(themeID: "forest")
        let palette = PaletteResolver.resolve(settings: settings, environment: AppearanceEnvironment(systemScheme: .dark))
        XCTAssertEqual(palette.scheme, .dark)
    }

    func testUnknownThemeResolvesAsDefault() {
        let settings = AppearanceSettings(themeID: "aurora")
        let palette = PaletteResolver.resolve(settings: settings, environment: AppearanceEnvironment(systemScheme: .light))
        XCTAssertEqual(palette.themeID, ThemeCatalog.defaultThemeID)
    }

    func testDarkOnlyThemeIgnoresALightSystem() {
        let settings = AppearanceSettings(themeID: "gold")
        let palette = PaletteResolver.resolve(settings: settings, environment: AppearanceEnvironment(systemScheme: .light))
        XCTAssertEqual(palette.scheme, .dark)
    }

    func testEnvironmentFlagsReachTheResolver() {
        let settings = AppearanceSettings(themeID: "classic")
        let palette = PaletteResolver.resolve(
            settings: settings,
            environment: AppearanceEnvironment(systemScheme: .light, increasedContrast: true, differentiateWithoutColor: true)
        )
        XCTAssertTrue(palette.usesIncreasedContrast)
        XCTAssertGreaterThanOrEqual(ColorMath.contrastRatio(palette.referenceValue(.protein), .white), 4.5)
        XCTAssertEqual(ColorMath.oklch(palette.referenceValue(.carbs)).hue,
                       ColorMath.oklch(RGBA(hex: 0x0072B2)).hue, accuracy: 10)
    }
}

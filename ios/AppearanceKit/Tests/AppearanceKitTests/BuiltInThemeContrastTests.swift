// BuiltInThemeContrastTests — design.md D5: every built-in theme × each
// supported scheme meets the contrast policy (High Contrast at the
// increased thresholds). Classic is exempt only through the explicit list
// below; if Classic's failures change in either direction the test fails,
// so the list can neither silently grow nor go stale.
//
// The increased-contrast half of the matrix (resolved palettes) lives in
// PaletteResolverTests, since fitting is the resolver's job (D4 step 4).

import XCTest
@testable import AppearanceKit

final class BuiltInThemeContrastTests: XCTestCase {

    /// Classic's known gaps (light mode; dark only fails onAccent). Mapping
    /// to design.md D5's list: "ember" appears as the bands that use it
    /// (bandBuilding, bandSlightlyOver); grace/success likewise cover
    /// bandLow/bandOnTarget. "water-as-carbs" is a distinctness exemption
    /// that no longer applies (water isn't compared pairwise, see ThemeRole).
    static let classicExemptions: Set<ThemeRole> = [
        .accent, .onAccent, .fat, .success, .warning, .grace,
        .bandLow, .bandBuilding, .bandApproaching, .bandOnTarget, .bandSlightlyOver
    ]

    func testEveryNonClassicThemePassesInEverySupportedScheme() {
        for theme in ThemeCatalog.all where theme.id != ClassicTheme.id {
            let level: ContrastLevel = theme.isHighContrast ? .increased : .normal
            for scheme in theme.supportedSchemes {
                guard let table = theme.table(for: scheme) else {
                    XCTFail("\(theme.id) declares \(scheme) but has no table")
                    continue
                }
                let failures = PolicyChecker.contrastFailures(table, scheme: scheme, level: level)
                XCTAssertTrue(failures.isEmpty, "\(theme.id) \(scheme): \(failures)")
            }
        }
    }

    func testClassicFailsExactlyItsExemptionList() {
        var failing: Set<ThemeRole> = []
        for scheme in ClassicTheme.spec.supportedSchemes {
            let failures = PolicyChecker.contrastFailures(ClassicTheme.table, scheme: scheme, level: .normal)
            failing.formUnion(failures.map(\.role))
        }
        XCTAssertEqual(failing, Self.classicExemptions)
    }

    func testClassicDarkOnlyFailsOnAccent() {
        let failures = PolicyChecker.contrastFailures(ClassicTheme.table, scheme: .dark, level: .normal)
        XCTAssertEqual(Set(failures.map(\.role)), [.onAccent])
    }

    func testSharedSetsPassOnSystemSurfaces() {
        // The Legible and colour-blind-safe sets on Classic's system surfaces.
        for scheme in ThemeColorScheme.allCases {
            for set in [MacroStateSets.legible(scheme), MacroStateSets.colorBlindSafe(scheme)] {
                let surface = ClassicTheme.table.referenceValue(.surface, in: scheme)
                for (role, value) in set where role.group != .streak {
                    let ratio = ColorMath.contrastRatio(value.referenceValue(in: scheme), surface)
                    XCTAssertGreaterThanOrEqual(ratio, ContrastPolicy.minimumGraphicOnSurface(.normal),
                                                "\(scheme) \(role)")
                }
            }
        }
    }
}

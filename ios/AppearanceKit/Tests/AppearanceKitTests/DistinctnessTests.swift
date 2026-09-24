// DistinctnessTests — design.md D5 in OKLab ΔE: carbs/protein/fat stay
// ≥ 0.10 apart, the accent stays ≥ 0.06 from every macro, and the
// colour-blind-safe set (and the High Contrast theme built on it) stays
// ≥ 0.10 apart under protan, deutan and tritan simulation.

import XCTest
@testable import AppearanceKit

final class DistinctnessTests: XCTestCase {

    func testEveryThemeKeepsMacrosAndAccentApart() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                guard let table = theme.table(for: scheme) else { continue }
                let failures = PolicyChecker.distinctnessFailures(table, scheme: scheme)
                XCTAssertTrue(failures.isEmpty, "\(theme.id) \(scheme): \(failures)")
            }
        }
    }

    func testColorBlindSafeSetSurvivesSimulation() {
        for scheme in ThemeColorScheme.allCases {
            let table = ClassicTheme.table.overriding(MacroStateSets.colorBlindSafe(scheme))
            XCTAssertTrue(PolicyChecker.distinctnessFailures(table, scheme: scheme)
                .filter { $0.hasPrefix("normal") }.isEmpty, "\(scheme)")
            let failures = PolicyChecker.cvdFailures(table, scheme: scheme)
            XCTAssertTrue(failures.isEmpty, "\(scheme): \(failures)")
        }
    }

    func testHighContrastThemeSurvivesSimulation() {
        let theme = BuiltInTheme.highContrast.spec
        for scheme in theme.supportedSchemes {
            guard let table = theme.table(for: scheme) else { continue }
            let failures = PolicyChecker.cvdFailures(table, scheme: scheme)
            XCTAssertTrue(failures.isEmpty, "\(scheme): \(failures)")
        }
    }
}

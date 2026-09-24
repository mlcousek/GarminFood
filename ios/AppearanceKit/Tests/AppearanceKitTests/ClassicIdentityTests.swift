// ClassicIdentityTests — task 1.3: the Classic theme must be today's app,
// value for value. Every expected value below is copied from the literal in
// ios/Shared/Theme.swift or ios/GarminFood/DesignSystem/Components.swift
// (not from ClassicTheme.Literal), so a typo in either place fails here.

import XCTest
@testable import AppearanceKit

final class ClassicIdentityTests: XCTestCase {

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> TokenValue {
        .rgb(RGBA(red: r, green: g, blue: b))
    }

    private var expected: [ThemeRole: TokenValue] {
        [
            // Theme.swift
            .accent: rgb(0.96, 0.42, 0.29),
            .accentDeep: rgb(0.80, 0.27, 0.18),
            .carbs: rgb(0.29, 0.56, 0.89),
            .protein: rgb(0.55, 0.40, 0.86),
            .fat: rgb(0.93, 0.69, 0.20),
            .grace: rgb(0.55, 0.62, 0.70),
            .success: rgb(0.20, 0.68, 0.45),
            .warning: rgb(0.90, 0.60, 0.13),
            .ember: rgb(0.98, 0.55, 0.16),
            .over: rgb(0.78, 0.32, 0.48),
            // flameGradient: [ember, accent]
            .flameTip: rgb(0.96, 0.42, 0.29),
            // Theme.groupedBackground / heroBackground / cardBackground
            .background: .system(.systemGroupedBackground),
            .surface: .system(.secondarySystemGroupedBackground),
            .surfaceRaised: .system(.secondarySystemBackground),
            .stroke: .system(.separator),
            // Button labels on the accent are white today.
            .onAccent: .rgb(.white),
            .accentSecondary: rgb(0.98, 0.55, 0.16),
            .headerGradientStart: rgb(0.96, 0.42, 0.29),
            .headerGradientEnd: rgb(0.80, 0.27, 0.18),
            // Hydration uses Theme.carbs today.
            .water: rgb(0.29, 0.56, 0.89),
            // Error text is `.red`.
            .danger: .system(.systemRed),
            // Components.swift CalorieBand.tint
            .bandLow: rgb(0.55, 0.62, 0.70),
            .bandBuilding: rgb(0.98, 0.55, 0.16),
            .bandApproaching: rgb(0.96, 0.79, 0.18),
            .bandOnTarget: rgb(0.20, 0.68, 0.45),
            .bandSlightlyOver: rgb(0.98, 0.55, 0.16),
            .bandOver: rgb(0.86, 0.24, 0.23)
        ]
    }

    func testExpectationCoversEveryRole() {
        XCTAssertEqual(Set(expected.keys), Set(ThemeRole.allCases))
    }

    func testClassicMatchesTodaysLiteralsInBothSchemes() {
        for scheme in ThemeColorScheme.allCases {
            guard let table = ClassicTheme.spec.table(for: scheme) else {
                return XCTFail("Classic must support \(scheme)")
            }
            XCTAssertTrue(table.isComplete, "\(scheme)")
            for role in ThemeRole.allCases {
                XCTAssertEqual(table[role], expected[role], "\(scheme) \(role)")
            }
        }
    }

    func testClassicMetadata() {
        XCTAssertEqual(ClassicTheme.spec.id, "classic")
        XCTAssertEqual(ClassicTheme.spec.iconName, "AppIcon-Coral")
        XCTAssertFalse(ClassicTheme.spec.isHighContrast)
        XCTAssertEqual(ClassicTheme.spec.supportedSchemes, [.light, .dark])
    }

    func testEveryRoleHasAGroup() {
        let macros = ThemeRole.allCases.filter { $0.group == .macros }
        XCTAssertEqual(macros, [.carbs, .protein, .fat, .water])
        XCTAssertEqual(ThemeRole.graphicRoles.count, 4 + 5 + 6)
    }

    func testMissingRoleFallsBackWithoutTrapping() {
        let partial = ThemeTable([.accent: .rgb(.white)])
        XCTAssertFalse(partial.isComplete)
        XCTAssertEqual(partial[.carbs], ThemeTable.missingRoleFallback)
        XCTAssertEqual(partial.overriding([.carbs: .rgb(.black)])[.carbs], .rgb(.black))
    }

    func testEffectiveSchemeFallsBackToTheOnlySupportedOne() {
        let darkOnly = ThemeSpec(id: "x", iconName: "Default", light: nil, dark: ClassicTheme.table)
        XCTAssertEqual(darkOnly.supportedSchemes, [.dark])
        XCTAssertEqual(darkOnly.effectiveScheme(for: .light), .dark)
        XCTAssertEqual(darkOnly.effectiveScheme(for: .dark), .dark)
        XCTAssertEqual(ClassicTheme.spec.effectiveScheme(for: .light), .light)
    }
}

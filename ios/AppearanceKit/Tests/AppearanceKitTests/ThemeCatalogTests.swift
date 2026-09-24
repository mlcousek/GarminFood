// ThemeCatalogTests — task 2.1: the catalog's shape. 13 themes with stable
// ids, each paired with its app icon (the app's AppIconOption raw values),
// declared color schemes, complete tables, and onAccent already the better
// of white/black.

import XCTest
@testable import AppearanceKit

final class ThemeCatalogTests: XCTestCase {

    /// AppIconOption raw values in the app (ios/GarminFood/Profile/AppIconOption.swift).
    private let knownIconNames: Set<String> = [
        "Default", "AppIcon-Coral", "AppIcon-Ocean", "AppIcon-Forest", "AppIcon-Sunset", "AppIcon-Slate",
        "AppIcon-Indigo", "AppIcon-Berry", "AppIcon-Graphite", "AppIcon-Gold", "AppIcon-Pastel", "AppIcon-Citrus"
    ]

    func testThirteenThemesWithUniqueIDsInPickerOrder() {
        XCTAssertEqual(ThemeCatalog.all.count, 13)
        XCTAssertEqual(ThemeCatalog.all.map(\.id), BuiltInTheme.allCases.map(\.rawValue))
        XCTAssertEqual(Set(ThemeCatalog.all.map(\.id)).count, 13)
    }

    func testDefaultIsGFTeal() {
        XCTAssertEqual(ThemeCatalog.defaultThemeID, "teal")
        XCTAssertEqual(AppearanceSettings.defaultThemeID, ThemeCatalog.defaultThemeID)
        XCTAssertEqual(ThemeCatalog.themeOrDefault(id: "no-such-theme").id, "teal")
        XCTAssertEqual(ThemeCatalog.themeOrDefault(id: "gold").id, "gold")
        XCTAssertNil(ThemeCatalog.theme(id: "no-such-theme"))
    }

    func testIconNames() {
        let expected: [BuiltInTheme: String] = [
            .teal: "Default", .classic: "AppIcon-Coral", .ocean: "AppIcon-Ocean", .forest: "AppIcon-Forest",
            .sunset: "AppIcon-Sunset", .slate: "AppIcon-Slate", .indigo: "AppIcon-Indigo",
            .berry: "AppIcon-Berry", .graphite: "AppIcon-Graphite", .gold: "AppIcon-Gold",
            .pastel: "AppIcon-Pastel", .citrus: "AppIcon-Citrus", .highContrast: "Default"
        ]
        for theme in BuiltInTheme.allCases {
            XCTAssertEqual(theme.spec.iconName, expected[theme], theme.rawValue)
            XCTAssertTrue(knownIconNames.contains(theme.spec.iconName), theme.rawValue)
        }
    }

    func testSupportedSchemes() {
        let darkOnly: Set<BuiltInTheme> = [.indigo, .berry, .graphite, .gold]
        let lightOnly: Set<BuiltInTheme> = [.pastel, .citrus]
        for theme in BuiltInTheme.allCases {
            let expected: [ThemeColorScheme]
            if darkOnly.contains(theme) {
                expected = [.dark]
            } else if lightOnly.contains(theme) {
                expected = [.light]
            } else {
                expected = [.light, .dark]
            }
            XCTAssertEqual(theme.spec.supportedSchemes, expected, theme.rawValue)
        }
    }

    func testOnlyHighContrastIsHighContrast() {
        XCTAssertEqual(ThemeCatalog.all.filter(\.isHighContrast).map(\.id), ["highContrast"])
    }

    func testClassicCoralIsTheClassicSpec() {
        XCTAssertEqual(BuiltInTheme.classic.spec, ClassicTheme.spec)
    }

    func testEveryTableIsComplete() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                XCTAssertEqual(theme.table(for: scheme)?.isComplete, true, "\(theme.id) \(scheme)")
            }
        }
    }

    func testOnAccentIsTheBetterOfWhiteAndBlack() {
        for theme in ThemeCatalog.all where theme.id != ClassicTheme.id {
            for scheme in theme.supportedSchemes {
                guard let table = theme.table(for: scheme) else { continue }
                let accent = table.referenceValue(.accent, in: scheme)
                XCTAssertEqual(table[.onAccent], .rgb(ContrastPolicy.preferredOnAccent(for: accent)),
                               "\(theme.id) \(scheme)")
            }
        }
    }

    func testFlameBurnsToTheAccent() {
        for theme in ThemeCatalog.all {
            for scheme in theme.supportedSchemes {
                guard let table = theme.table(for: scheme) else { continue }
                XCTAssertEqual(table[.flameTip], table[.accent], "\(theme.id) \(scheme)")
            }
        }
    }
}

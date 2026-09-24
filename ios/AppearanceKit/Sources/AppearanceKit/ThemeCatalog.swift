// ThemeCatalog — the 13 built-in themes as data (design.md D3, D10), each
// paired with the app icon of the same look (`iconName` == the app's
// `AppIconOption` raw value). Brand colors come from the icon gradients'
// corners; accents are those colors moved in lightness (hue kept) until they
// pass the D5 policy, which `BuiltInThemeContrastTests` and
// `DistinctnessTests` enforce for every theme × scheme.
//
// Every table is Classic (complete) overridden by the Legible set and then
// the theme's own brand/surface values, so every table defines every role.
//
// Nudges made to pass the tests (as D3 asks us to record):
//   - Ocean: carbs deepened to #2F5FC8 / #6F9CF0 so it reads clearly bluer
//     than the teal accent (a style choice; Legible carbs also passes).
//   - Forest: success / on-target band shifted to teal-green (#12808A /
//     #3CC4C0): Legible success was only ΔE 0.05 from the green accent, so
//     "on target" would read as a button.
//   - Indigo Night: protein overridden to orchid #E07AC8 (Classic's violet
//     protein was ΔE 0.074 from the indigo accent, barely above 0.06).
//   - Gold: fat overridden to amber-orange #F58A4B (Classic's fat yellow was
//     ΔE 0.050 from the gold accent, below the 0.06 floor).
//   - High Contrast light: fat #4F3E00 (not #6E5700) so protein and fat stay
//     ≥ 0.10 apart under protan simulation.
//   - Accents: Sunset light #C92C45 (from the icon's #E9354C), Slate light
//     #4E5D70, Pastel #A4579B (from #DA9ED2), Citrus #5E7A00 (from lime
//     #CADD4E), Indigo #9B7BFF, Berry #E0609F — each the icon hue at a
//     lightness that passes accent-on-surface and onAccent.
//
// Depended on by: PaletteResolver.resolve(settings:environment:), the app's
// theme picker (maps `BuiltInTheme` -> localized name) and icon suggestion.

import Foundation

/// Stable ids of the built-in themes, in picker order.
public enum BuiltInTheme: String, CaseIterable, Sendable {
    case teal
    case classic
    case ocean
    case forest
    case sunset
    case slate
    case indigoNight
    case berry
    case graphite
    case gold
    case pastel
    case citrus
    case highContrast

    public var spec: ThemeSpec {
        switch self {
        case .teal: return ThemeCatalog.teal
        case .classic: return ClassicTheme.spec
        case .ocean: return ThemeCatalog.ocean
        case .forest: return ThemeCatalog.forest
        case .sunset: return ThemeCatalog.sunset
        case .slate: return ThemeCatalog.slate
        case .indigoNight: return ThemeCatalog.indigoNight
        case .berry: return ThemeCatalog.berry
        case .graphite: return ThemeCatalog.graphite
        case .gold: return ThemeCatalog.gold
        case .pastel: return ThemeCatalog.pastel
        case .citrus: return ThemeCatalog.citrus
        case .highContrast: return ThemeCatalog.highContrast
        }
    }
}

public enum ThemeCatalog {

    /// GF Teal — matches the primary app icon.
    public static let defaultThemeID = BuiltInTheme.teal.rawValue

    /// Every built-in theme, in picker order.
    public static let all: [ThemeSpec] = BuiltInTheme.allCases.map(\.spec)

    public static func theme(id: String) -> ThemeSpec? {
        BuiltInTheme(rawValue: id)?.spec
    }

    /// The theme for `id`, or the default theme for an unknown id (e.g. one
    /// saved by a newer build).
    public static func themeOrDefault(id: String) -> ThemeSpec {
        theme(id: id) ?? teal
    }

    // MARK: - Builders

    private struct Surfaces {
        let background: UInt32
        let surface: UInt32
        let raised: UInt32
        let stroke: UInt32
    }

    private static func brand(
        accent: UInt32,
        deep: UInt32,
        secondary: UInt32,
        gradient: (start: UInt32, end: UInt32),
        onAccent: RGBA,
        surfaces: Surfaces? = nil,
        extra: [ThemeRole: UInt32] = [:]
    ) -> [ThemeRole: TokenValue] {
        var values: [ThemeRole: TokenValue] = [
            .accent: .rgb(RGBA(hex: accent)),
            .accentDeep: .rgb(RGBA(hex: deep)),
            .onAccent: .rgb(onAccent),
            .accentSecondary: .rgb(RGBA(hex: secondary)),
            .headerGradientStart: .rgb(RGBA(hex: gradient.start)),
            .headerGradientEnd: .rgb(RGBA(hex: gradient.end)),
            // As in Classic, the flame burns from ember up to the accent.
            .flameTip: .rgb(RGBA(hex: accent))
        ]
        if let surfaces {
            values[.background] = .rgb(RGBA(hex: surfaces.background))
            values[.surface] = .rgb(RGBA(hex: surfaces.surface))
            values[.surfaceRaised] = .rgb(RGBA(hex: surfaces.raised))
            values[.stroke] = .rgb(RGBA(hex: surfaces.stroke))
        }
        for (role, hex) in extra {
            values[role] = .rgb(RGBA(hex: hex))
        }
        return values
    }

    /// Classic -> Legible(scheme) -> theme values.
    private static func legibleTable(_ scheme: ThemeColorScheme, _ overrides: [ThemeRole: TokenValue]) -> ThemeTable {
        ClassicTheme.table
            .overriding(MacroStateSets.legible(scheme))
            .overriding(overrides)
    }

    // MARK: - Themes

    static let teal = ThemeSpec(
        id: BuiltInTheme.teal.rawValue,
        iconName: "Default",
        light: legibleTable(.light, brand(
            accent: 0x15808C, deep: 0x11466B, secondary: 0x1A9FB0,
            gradient: (0x11466B, 0x24DDDD), onAccent: .white
        )),
        dark: legibleTable(.dark, brand(
            accent: 0x3CC8D4, deep: 0x1B6E93, secondary: 0x24DDDD,
            gradient: (0x11466B, 0x24DDDD), onAccent: .black
        ))
    )

    static let ocean = ThemeSpec(
        id: BuiltInTheme.ocean.rawValue,
        iconName: "AppIcon-Ocean",
        light: legibleTable(.light, brand(
            accent: 0x135F7A, deep: 0x0D4A60, secondary: 0x1C95A1,
            gradient: (0x135F7A, 0x1ECAC6), onAccent: .white,
            surfaces: Surfaces(background: 0xEEF5F7, surface: 0xFFFFFF, raised: 0xE4EFF2, stroke: 0xC3D5DB),
            extra: [.carbs: 0x2F5FC8]
        )),
        dark: legibleTable(.dark, brand(
            accent: 0x1ECAC6, deep: 0x13707F, secondary: 0x1C95A1,
            gradient: (0x135F7A, 0x1ECAC6), onAccent: .black,
            surfaces: Surfaces(background: 0x04141A, surface: 0x0B2129, raised: 0x12303A, stroke: 0x1E4350),
            extra: [.carbs: 0x6F9CF0]
        ))
    )

    static let forest = ThemeSpec(
        id: BuiltInTheme.forest.rawValue,
        iconName: "AppIcon-Forest",
        light: legibleTable(.light, brand(
            accent: 0x047A52, deep: 0x034F3A, secondary: 0x6E7F24,
            gradient: (0x034F3A, 0x03A266), onAccent: .white,
            surfaces: Surfaces(background: 0xF3F5F1, surface: 0xFFFFFF, raised: 0xE9EEE6, stroke: 0xCDD6C9),
            extra: [.success: 0x12808A, .bandOnTarget: 0x12808A]
        )),
        dark: legibleTable(.dark, brand(
            accent: 0x2FC98A, deep: 0x047A52, secondary: 0xA3B55A,
            gradient: (0x034F3A, 0x03A266), onAccent: .black,
            surfaces: Surfaces(background: 0x07120D, surface: 0x111F18, raised: 0x192B22, stroke: 0x27392F),
            extra: [.success: 0x3CC4C0, .bandOnTarget: 0x3CC4C0]
        ))
    )

    static let sunset = ThemeSpec(
        id: BuiltInTheme.sunset.rawValue,
        iconName: "AppIcon-Sunset",
        light: legibleTable(.light, brand(
            accent: 0xC92C45, deep: 0x8F1E33, secondary: 0xD9480F,
            gradient: (0xE9354C, 0xFB9433), onAccent: .white
        )),
        dark: legibleTable(.dark, brand(
            accent: 0xF46B3D, deep: 0xC4452A, secondary: 0xFB9433,
            gradient: (0xE9354C, 0xFB9433), onAccent: .black
        ))
    )

    static let slate = ThemeSpec(
        id: BuiltInTheme.slate.rawValue,
        iconName: "AppIcon-Slate",
        light: legibleTable(.light, brand(
            accent: 0x4E5D70, deep: 0x3B4456, secondary: 0x687788,
            gradient: (0x3B4456, 0x8FA4B4), onAccent: .white,
            surfaces: Surfaces(background: 0xF1F3F5, surface: 0xFFFFFF, raised: 0xE7EBEF, stroke: 0xC9D0D8)
        )),
        dark: legibleTable(.dark, brand(
            accent: 0x9FB3C3, deep: 0x59687A, secondary: 0x687788,
            gradient: (0x3B4456, 0x8FA4B4), onAccent: .black,
            surfaces: Surfaces(background: 0x0D1014, surface: 0x171B21, raised: 0x20262E, stroke: 0x2F3742)
        ))
    )

    static let indigoNight = ThemeSpec(
        id: BuiltInTheme.indigoNight.rawValue,
        iconName: "AppIcon-Indigo",
        light: nil,
        dark: legibleTable(.dark, brand(
            accent: 0x9B7BFF, deep: 0x312EC5, secondary: 0xA548F5,
            gradient: (0x312EC5, 0xA548F5), onAccent: .black,
            surfaces: Surfaces(background: 0x0B0A1A, surface: 0x17142E, raised: 0x201C3D, stroke: 0x2E2952),
            extra: [.protein: 0xE07AC8]
        ))
    )

    static let berry = ThemeSpec(
        id: BuiltInTheme.berry.rawValue,
        iconName: "AppIcon-Berry",
        light: nil,
        dark: legibleTable(.dark, brand(
            accent: 0xE0609F, deep: 0x942872, secondary: 0xC03376,
            gradient: (0x661D6E, 0xC03376), onAccent: .black,
            surfaces: Surfaces(background: 0x120812, surface: 0x211020, raised: 0x2C1729, stroke: 0x402238)
        ))
    )

    /// Grey to black, like its icon.
    static let graphite = ThemeSpec(
        id: BuiltInTheme.graphite.rawValue,
        iconName: "AppIcon-Graphite",
        light: nil,
        dark: legibleTable(.dark, brand(
            accent: 0xC3C9D3, deep: 0x40444C, secondary: 0x848A96,
            gradient: (0x40444C, 0x08090C), onAccent: .black,
            surfaces: Surfaces(background: 0x08090C, surface: 0x16181C, raised: 0x202329, stroke: 0x30343B)
        ))
    )

    /// Warm gold on near-black.
    static let gold = ThemeSpec(
        id: BuiltInTheme.gold.rawValue,
        iconName: "AppIcon-Gold",
        light: nil,
        dark: legibleTable(.dark, brand(
            accent: 0xECC460, deep: 0x966E24, secondary: 0xF0A64A,
            gradient: (0x966E24, 0xECC460), onAccent: .black,
            surfaces: Surfaces(background: 0x0E0B06, surface: 0x1A1610, raised: 0x241E15, stroke: 0x3A3122),
            extra: [.fat: 0xF58A4B]
        ))
    )

    static let pastel = ThemeSpec(
        id: BuiltInTheme.pastel.rawValue,
        iconName: "AppIcon-Pastel",
        light: legibleTable(.light, brand(
            accent: 0xA4579B, deep: 0x6E5FC0, secondary: 0xC98BA8,
            gradient: (0xDA9ED2, 0xA49CE6), onAccent: .white,
            surfaces: Surfaces(background: 0xFAF5FA, surface: 0xFFFFFF, raised: 0xF3EAF3, stroke: 0xDCCFE0)
        )),
        dark: nil
    )

    static let citrus = ThemeSpec(
        id: BuiltInTheme.citrus.rawValue,
        iconName: "AppIcon-Citrus",
        light: legibleTable(.light, brand(
            accent: 0x5E7A00, deep: 0x3F6B1F, secondary: 0xE0B800,
            gradient: (0xCADD4E, 0x89D76F), onAccent: .white,
            surfaces: Surfaces(background: 0xF8FAEC, surface: 0xFFFFFF, raised: 0xEEF3D6, stroke: 0xD5DDB4)
        )),
        dark: nil
    )

    /// AA text-level contrast (≥ 4.5:1) for every graphic, colour-blind-safe
    /// macros. Built on Classic directly (not Legible): every graphic role is
    /// overridden here.
    static let highContrast = ThemeSpec(
        id: BuiltInTheme.highContrast.rawValue,
        iconName: "Default",
        isHighContrast: true,
        light: ClassicTheme.table.overriding(highContrastGraphics(.light)).overriding(brand(
            accent: 0x0040DD, deep: 0x002C99, secondary: 0x0060A0,
            gradient: (0x0040DD, 0x002C99), onAccent: .white
        )),
        dark: ClassicTheme.table.overriding(highContrastGraphics(.dark)).overriding(brand(
            accent: 0x409CFF, deep: 0x0A64C8, secondary: 0x56B4E9,
            gradient: (0x0A64C8, 0x409CFF), onAccent: .black
        ))
    )

    private static func highContrastGraphics(_ scheme: ThemeColorScheme) -> [ThemeRole: TokenValue] {
        let hex: [ThemeRole: UInt32]
        switch scheme {
        case .light:
            hex = [
                .carbs: 0x0060A0, .protein: 0xB24E00, .fat: 0x4F3E00, .water: 0x00658F,
                .success: 0x0B7040, .warning: 0x8F5500, .danger: 0xB71C1C, .over: 0x94335A, .grace: 0x55657A,
                .ember: 0xC75A00,
                .bandLow: 0x55657A, .bandBuilding: 0x00659E, .bandApproaching: 0x6E5700,
                .bandOnTarget: 0x0060A0, .bandSlightlyOver: 0x8A5A00, .bandOver: 0xB24E00
            ]
        case .dark:
            hex = [
                .carbs: 0x56B4E9, .protein: 0xF28A3C, .fat: 0xF0E442, .water: 0x5AC8FA,
                .success: 0x4CD08A, .warning: 0xF5B34A, .danger: 0xFF6B6B, .over: 0xF07AA5, .grace: 0xA9B8C8,
                .bandLow: 0xA9B8C8, .bandBuilding: 0x56B4E9, .bandApproaching: 0xF0E442,
                .bandOnTarget: 0x56B4E9, .bandSlightlyOver: 0xF5B34A, .bandOver: 0xF28A3C
            ]
        }
        return hex.mapValues { TokenValue.rgb(RGBA(hex: $0)) }
    }
}

// ClassicTheme — today's look (coral accent) expressed as a `ThemeSpec`
// (openspec/changes/add-themes-and-layout/design.md D3, "Classic"). The
// values are the exact literals from `ios/Shared/Theme.swift` and
// `ios/GarminFood/DesignSystem/Components.swift` (`CalorieBand.tint`), so
// selecting Classic is pixel-identical to the pre-theming app.
// `ClassicIdentityTests` pins every value against those literals — change
// one here only together with the app's.
//
// Classic is also the complete base every other built-in table overrides
// (ThemeCatalog), which is what guarantees every table defines every role.
//
// Classic is exempt from the contrast thresholds only through the explicit
// list in `BuiltInThemeContrastTests` (D5).

import Foundation

public enum ClassicTheme {
    public static let id = "classic"
    public static let iconName = "AppIcon-Coral"

    /// Today's literals, named as in `Theme.swift` / `Components.swift`.
    public enum Literal {
        public static let accent = RGBA(red: 0.96, green: 0.42, blue: 0.29)
        public static let accentDeep = RGBA(red: 0.80, green: 0.27, blue: 0.18)
        public static let carbs = RGBA(red: 0.29, green: 0.56, blue: 0.89)
        public static let protein = RGBA(red: 0.55, green: 0.40, blue: 0.86)
        public static let fat = RGBA(red: 0.93, green: 0.69, blue: 0.20)
        public static let grace = RGBA(red: 0.55, green: 0.62, blue: 0.70)
        public static let success = RGBA(red: 0.20, green: 0.68, blue: 0.45)
        public static let warning = RGBA(red: 0.90, green: 0.60, blue: 0.13)
        public static let ember = RGBA(red: 0.98, green: 0.55, blue: 0.16)
        public static let over = RGBA(red: 0.78, green: 0.32, blue: 0.48)
        /// `CalorieBand.approaching` in Components.swift.
        public static let bandApproaching = RGBA(red: 0.96, green: 0.79, blue: 0.18)
        /// `CalorieBand.over` in Components.swift.
        public static let bandOver = RGBA(red: 0.86, green: 0.24, blue: 0.23)
    }

    /// Classic uses the same values in light and dark (as the app does today;
    /// only the system surfaces adapt).
    public static let table = ThemeTable([
        .background: .system(.systemGroupedBackground),
        .surface: .system(.secondarySystemGroupedBackground),
        .surfaceRaised: .system(.secondarySystemBackground),
        .stroke: .system(.separator),

        .accent: .rgb(Literal.accent),
        .accentDeep: .rgb(Literal.accentDeep),
        .onAccent: .rgb(.white),
        .accentSecondary: .rgb(Literal.ember),
        .headerGradientStart: .rgb(Literal.accent),
        .headerGradientEnd: .rgb(Literal.accentDeep),

        // flameGradient = ember -> accent (bottom to top).
        .ember: .rgb(Literal.ember),
        .flameTip: .rgb(Literal.accent),

        .carbs: .rgb(Literal.carbs),
        .protein: .rgb(Literal.protein),
        .fat: .rgb(Literal.fat),
        // Hydration draws in the carbs color today.
        .water: .rgb(Literal.carbs),

        .success: .rgb(Literal.success),
        .warning: .rgb(Literal.warning),
        // Today's error text is SwiftUI `.red`, i.e. systemRed.
        .danger: .system(.systemRed),
        .over: .rgb(Literal.over),
        .grace: .rgb(Literal.grace),

        // CalorieBand.tint in Components.swift.
        .bandLow: .rgb(Literal.grace),
        .bandBuilding: .rgb(Literal.ember),
        .bandApproaching: .rgb(Literal.bandApproaching),
        .bandOnTarget: .rgb(Literal.success),
        .bandSlightlyOver: .rgb(Literal.ember),
        .bandOver: .rgb(Literal.bandOver)
    ])

    public static let spec = ThemeSpec(
        id: id,
        iconName: iconName,
        isHighContrast: false,
        light: table,
        dark: table
    )
}

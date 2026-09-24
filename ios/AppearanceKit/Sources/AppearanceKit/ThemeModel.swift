// ThemeModel — the vocabulary of the theme system
// (openspec/changes/add-themes-and-layout/design.md D3): the semantic color
// roles views ask for (`ThemeRole`), what a role can hold (`TokenValue`: a
// fixed sRGB value or a named iOS system color that stays dynamic), a full
// role -> value table for one color scheme (`ThemeTable`), and a theme
// (`ThemeSpec`: one table per supported scheme plus icon/contrast metadata).
//
// Why data, not SwiftUI `Color`s: the tables must be checkable by
// `swift test` on a CI host with no UIKit (contrast/distinctness policy,
// D5), and must be shareable between the app and the widget extension. The
// app maps `TokenValue` -> `Color` in one place (DesignSystem/Theming).
//
// Depended on by: ClassicTheme, ThemeCatalog, PaletteResolver, AccentAdjuster.

import Foundation

// MARK: - Scheme

/// Light or dark. Named to avoid colliding with SwiftUI's `ColorScheme` in
/// app files that import both modules.
public enum ThemeColorScheme: String, CaseIterable, Codable, Sendable {
    case light
    case dark
}

// MARK: - Roles

public enum ThemeRoleGroup: String, CaseIterable, Sendable {
    case surfaces
    case brand
    case streak
    case macros
    case states
    case calorieBands
}

/// A semantic color slot. Views ask for a role, never a literal color.
/// Text stays on the system `.primary/.secondary/.tertiary` styles and is
/// deliberately not a role (D3).
public enum ThemeRole: String, CaseIterable, Codable, Sendable {
    // Surfaces
    case background
    case surface
    case surfaceRaised
    case stroke
    // Brand
    case accent
    case accentDeep
    case onAccent
    case accentSecondary
    case headerGradientStart
    case headerGradientEnd
    // Streak
    case ember
    case flameTip
    // Macros
    case carbs
    case protein
    case fat
    case water
    // States
    case success
    case warning
    case danger
    case over
    case grace
    // Calorie bands
    case bandLow
    case bandBuilding
    case bandApproaching
    case bandOnTarget
    case bandSlightlyOver
    case bandOver

    public var group: ThemeRoleGroup {
        switch self {
        case .background, .surface, .surfaceRaised, .stroke:
            return .surfaces
        case .accent, .accentDeep, .onAccent, .accentSecondary, .headerGradientStart, .headerGradientEnd:
            return .brand
        case .ember, .flameTip:
            return .streak
        case .carbs, .protein, .fat, .water:
            return .macros
        case .success, .warning, .danger, .over, .grace:
            return .states
        case .bandLow, .bandBuilding, .bandApproaching, .bandOnTarget, .bandSlightlyOver, .bandOver:
            return .calorieBands
        }
    }

    /// The macro bars drawn side by side — the set that must stay pairwise
    /// distinguishable (D5). `water` is drawn on its own card, so it is only
    /// checked against the accent, not against these three.
    public static let comparedMacros: [ThemeRole] = [.carbs, .protein, .fat]

    /// Every role whose value is drawn as a graphic on a surface and is held
    /// to the "≥ 3:1 (≥ 4.5:1 increased)" rule of D5: macros, water, states
    /// and calorie bands.
    public static let graphicRoles: [ThemeRole] = ThemeRole.allCases.filter {
        switch $0.group {
        case .macros, .states, .calorieBands: return true
        case .surfaces, .brand, .streak: return false
        }
    }
}

// MARK: - System colors

/// The iOS system colors a theme may reference. The app renders the real
/// dynamic `UIColor` (so Increased Contrast etc. keep working for these);
/// `referenceValue(in:)` is only an approximation of the iOS 17 default,
/// used for contrast arithmetic in this package.
public enum SystemColorName: String, CaseIterable, Codable, Sendable {
    case systemGroupedBackground
    case secondarySystemGroupedBackground
    case secondarySystemBackground
    case separator
    case systemRed

    public func referenceValue(in scheme: ThemeColorScheme) -> RGBA {
        switch (self, scheme) {
        case (.systemGroupedBackground, .light): return RGBA(hex: 0xF2F2F7)
        case (.systemGroupedBackground, .dark): return RGBA(hex: 0x000000)
        case (.secondarySystemGroupedBackground, .light): return RGBA(hex: 0xFFFFFF)
        case (.secondarySystemGroupedBackground, .dark): return RGBA(hex: 0x1C1C1E)
        case (.secondarySystemBackground, .light): return RGBA(hex: 0xF2F2F7)
        case (.secondarySystemBackground, .dark): return RGBA(hex: 0x1C1C1E)
        case (.separator, .light): return RGBA(red: 60 / 255, green: 60 / 255, blue: 67 / 255, alpha: 0.29)
        case (.separator, .dark): return RGBA(red: 84 / 255, green: 84 / 255, blue: 88 / 255, alpha: 0.6)
        case (.systemRed, .light): return RGBA(hex: 0xFF3B30)
        case (.systemRed, .dark): return RGBA(hex: 0xFF453A)
        }
    }
}

// MARK: - Token value

/// What a role resolves to.
public enum TokenValue: Hashable, Sendable {
    /// A fixed sRGB color.
    case rgb(RGBA)
    /// A dynamic iOS system color, rendered by the app as the real `UIColor`.
    case system(SystemColorName)

    /// The fixed color, or `nil` for a system color.
    public var rgbValue: RGBA? {
        switch self {
        case .rgb(let color): return color
        case .system: return nil
        }
    }

    /// A concrete color for arithmetic: the fixed color, or the system
    /// color's reference approximation for `scheme`.
    public func referenceValue(in scheme: ThemeColorScheme) -> RGBA {
        switch self {
        case .rgb(let color): return color
        case .system(let name): return name.referenceValue(in: scheme)
        }
    }
}

// MARK: - Table

/// Role -> value for one color scheme.
///
/// Every built-in table is built by overriding a complete base (Classic), so
/// it defines every role; `ThemeCatalogTests` asserts that. The subscript's
/// fallback for a missing role therefore never triggers for built-ins — it
/// exists so a malformed table degrades to a visible-but-harmless color
/// instead of trapping.
public struct ThemeTable: Hashable, Sendable {
    public private(set) var values: [ThemeRole: TokenValue]

    public init(_ values: [ThemeRole: TokenValue]) {
        self.values = values
    }

    /// Unreachable for complete tables; see the type's comment.
    public static let missingRoleFallback: TokenValue = .system(.systemRed)

    public subscript(role: ThemeRole) -> TokenValue {
        get { values[role] ?? ThemeTable.missingRoleFallback }
        set { values[role] = newValue }
    }

    /// Whether every `ThemeRole` has a value.
    public var isComplete: Bool {
        ThemeRole.allCases.allSatisfy { values[$0] != nil }
    }

    /// A copy with `overrides` applied on top.
    public func overriding(_ overrides: [ThemeRole: TokenValue]) -> ThemeTable {
        var copy = self
        for (role, value) in overrides {
            copy.values[role] = value
        }
        return copy
    }

    /// `self[role]` as a concrete color for arithmetic (see
    /// `TokenValue.referenceValue(in:)`).
    public func referenceValue(_ role: ThemeRole, in scheme: ThemeColorScheme) -> RGBA {
        self[role].referenceValue(in: scheme)
    }
}

// MARK: - Theme

/// One theme: a table per supported color scheme plus metadata.
public struct ThemeSpec: Identifiable, Hashable, Sendable {
    /// Stable, persisted identifier (e.g. `"teal"`). Never shown to the user;
    /// the app maps it to a localized display name.
    public let id: String
    /// The matching app icon, exactly the app's `AppIconOption` raw value
    /// (`"Default"` for the primary icon, `"AppIcon-…"` for alternates).
    public let iconName: String
    /// High Contrast theme: held to the increased-contrast thresholds even
    /// when the system setting is off (D5).
    public let isHighContrast: Bool
    public let light: ThemeTable?
    public let dark: ThemeTable?

    public init(id: String, iconName: String, isHighContrast: Bool = false, light: ThemeTable?, dark: ThemeTable?) {
        self.id = id
        self.iconName = iconName
        self.isHighContrast = isHighContrast
        self.light = light
        self.dark = dark
    }

    /// The schemes this theme has a table for, light first. A dark-only
    /// theme returns `[.dark]`, so the appearance picker can hide Light and
    /// System for it.
    public var supportedSchemes: [ThemeColorScheme] {
        ThemeColorScheme.allCases.filter { table(for: $0) != nil }
    }

    public func supports(_ scheme: ThemeColorScheme) -> Bool {
        table(for: scheme) != nil
    }

    public func table(for scheme: ThemeColorScheme) -> ThemeTable? {
        switch scheme {
        case .light: return light
        case .dark: return dark
        }
    }

    /// `requested` if supported, otherwise the theme's only scheme (the app
    /// then forces that scheme with `.preferredColorScheme`).
    public func effectiveScheme(for requested: ThemeColorScheme) -> ThemeColorScheme {
        if supports(requested) {
            return requested
        }
        return supportedSchemes.first ?? requested
    }
}

// PaletteResolver — turns (theme, scheme, user settings, accessibility
// settings) into the one `ResolvedPalette` the app injects into the SwiftUI
// environment (design.md D2, D4). Pure function, so the whole resolution
// order is unit-tested here rather than eyeballed on a device.
//
// Resolution order (D4):
//   1. the theme's table for the effective scheme;
//   (steps 2–5 — macro set, custom accent, increased contrast, onAccent —
//   land with task 2.2.)
//
// Depended on by: the app's theme store (DesignSystem/Theming).

import Foundation

/// The accessibility / system inputs to resolution, read by the app from
/// SwiftUI's environment (`colorScheme`, `colorSchemeContrast`,
/// `accessibilityDifferentiateWithoutColor`).
public struct AppearanceEnvironment: Hashable, Sendable {
    public var systemScheme: ThemeColorScheme
    public var increasedContrast: Bool
    public var differentiateWithoutColor: Bool

    public init(systemScheme: ThemeColorScheme, increasedContrast: Bool = false, differentiateWithoutColor: Bool = false) {
        self.systemScheme = systemScheme
        self.increasedContrast = increasedContrast
        self.differentiateWithoutColor = differentiateWithoutColor
    }
}

/// The final role -> value table for the current screen.
public struct ResolvedPalette: Hashable, Sendable {
    public let themeID: String
    /// The scheme the palette was resolved for. For a single-scheme theme
    /// this can differ from the system's; the app must then force it with
    /// `.preferredColorScheme(_:)`.
    public let scheme: ThemeColorScheme
    /// Whether increased-contrast thresholds were applied (the system
    /// setting, or a High Contrast theme).
    public let usesIncreasedContrast: Bool
    public let table: ThemeTable
    /// Roles whose value was changed from the theme's to meet a contrast
    /// threshold (the picker shows "Adjusted for dark mode" etc.).
    public let adjustedRoles: Set<ThemeRole>
    /// Roles the fitter gave up on (best candidate used). Empty for every
    /// built-in theme — tested.
    public let unfittableRoles: Set<ThemeRole>

    public init(
        themeID: String,
        scheme: ThemeColorScheme,
        usesIncreasedContrast: Bool,
        table: ThemeTable,
        adjustedRoles: Set<ThemeRole> = [],
        unfittableRoles: Set<ThemeRole> = []
    ) {
        self.themeID = themeID
        self.scheme = scheme
        self.usesIncreasedContrast = usesIncreasedContrast
        self.table = table
        self.adjustedRoles = adjustedRoles
        self.unfittableRoles = unfittableRoles
    }

    public subscript(role: ThemeRole) -> TokenValue {
        table[role]
    }

    /// A concrete color for arithmetic (system colors approximated).
    public func referenceValue(_ role: ThemeRole) -> RGBA {
        table.referenceValue(role, in: scheme)
    }
}

public enum PaletteResolver {

    /// Resolve `theme` for `requestedScheme` (D4).
    public static func resolve(
        theme: ThemeSpec,
        requestedScheme: ThemeColorScheme
    ) -> ResolvedPalette {
        // Step 1: the theme's table for the effective scheme. A theme with
        // no tables at all (not a built-in; defensive) falls back to Classic.
        let scheme = theme.effectiveScheme(for: requestedScheme)
        let table = theme.table(for: scheme) ?? ClassicTheme.table
        return ResolvedPalette(
            themeID: theme.id,
            scheme: scheme,
            usesIncreasedContrast: theme.isHighContrast,
            table: table
        )
    }
}

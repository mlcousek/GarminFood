// PaletteResolver — turns (theme, scheme, user settings, accessibility
// settings) into the one `ResolvedPalette` the app injects into the SwiftUI
// environment (design.md D2, D4). Pure function, so the whole resolution
// order is unit-tested here rather than eyeballed on a device.
//
// Resolution order (D4):
//   1. the theme's table for the effective scheme;
//   2. the macro set override (user's Legible / Colour-blind safe choice,
//      or Colour-blind safe forced by Differentiate Without Color);
//   3. the custom accent, fitted per scheme (AccentAdjuster), with
//      accentDeep and the header gradient derived from it;
//   4. increased contrast (system setting or High Contrast theme): every
//      `.rgb` accent/graphic role below its increased threshold is fitted,
//      Classic included — an explicit accessibility request overrides the
//      zero-change rule; then the accent is pushed until a white or black
//      label reaches 7:1;
//   5. onAccent = white or black, whichever contrasts more — only when the
//      accent changed or thresholds are increased, so Classic's white label
//      stays exactly as today at normal contrast.
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

    /// Resolve the user's settings against the current system state. An
    /// unknown theme id (from a newer build) resolves as the default theme.
    public static func resolve(settings: AppearanceSettings, environment: AppearanceEnvironment) -> ResolvedPalette {
        let theme = ThemeCatalog.themeOrDefault(id: settings.themeID)
        let requested: ThemeColorScheme
        switch settings.appearance(for: theme.id) {
        case .system: requested = environment.systemScheme
        case .light: requested = .light
        case .dark: requested = .dark
        }
        return resolve(
            theme: theme,
            requestedScheme: requested,
            macroSet: settings.macroSet,
            customAccent: settings.customAccent,
            increasedContrast: environment.increasedContrast,
            differentiateWithoutColor: environment.differentiateWithoutColor
        )
    }

    /// Resolve `theme` for `requestedScheme` (D4).
    public static func resolve(
        theme: ThemeSpec,
        requestedScheme: ThemeColorScheme,
        macroSet: MacroSetOption = .theme,
        customAccent: RGBA? = nil,
        increasedContrast: Bool = false,
        differentiateWithoutColor: Bool = false
    ) -> ResolvedPalette {
        // Step 1: the theme's table for the effective scheme. A theme with
        // no tables at all (not a built-in; defensive) falls back to Classic.
        let scheme = theme.effectiveScheme(for: requestedScheme)
        var table = theme.table(for: scheme) ?? ClassicTheme.table
        let level: ContrastLevel = (increasedContrast || theme.isHighContrast) ? .increased : .normal
        let direction = AccentAdjuster.Direction(for: scheme)
        var adjusted: Set<ThemeRole> = []
        var unfittable: Set<ThemeRole> = []
        var accentChanged = false

        // Step 2: macro set override.
        switch differentiateWithoutColor ? MacroSetOption.colorBlindSafe : macroSet {
        case .theme:
            break
        case .legible:
            table = table.overriding(MacroStateSets.legible(scheme))
        case .colorBlindSafe:
            table = table.overriding(MacroStateSets.colorBlindSafe(scheme))
        }

        let surface = table.referenceValue(.surface, in: scheme)
        let background = table.referenceValue(.background, in: scheme)
        let accentMinimum = ContrastPolicy.minimumAccentOnSurface(level)

        // Step 3: custom accent.
        if let custom = customAccent {
            let result = AccentAdjuster.fit(
                custom.withAlpha(1),
                requirements: [
                    ContrastRequirement(against: surface, minimumRatio: accentMinimum),
                    ContrastRequirement(against: background, minimumRatio: accentMinimum)
                ],
                direction: direction
            )
            let deep = AccentAdjuster.deepened(result.color)
            table[.accent] = .rgb(result.color)
            table[.accentDeep] = .rgb(deep)
            table[.headerGradientStart] = .rgb(result.color)
            table[.headerGradientEnd] = .rgb(deep)
            accentChanged = true
            if result.wasAdjusted { adjusted.insert(.accent) }
            if result.gaveUp { unfittable.insert(.accent) }
        }

        // Step 4: increased contrast.
        if level == .increased {
            let graphicMinimum = ContrastPolicy.minimumGraphicOnSurface(.increased)
            for role in [ThemeRole.accent] + ThemeRole.graphicRoles {
                guard let value = table[role].rgbValue else { continue }
                var requirements = [
                    ContrastRequirement(against: surface, minimumRatio: role == .accent ? accentMinimum : graphicMinimum)
                ]
                if role == .accent {
                    requirements.append(ContrastRequirement(against: background, minimumRatio: accentMinimum))
                }
                let result = AccentAdjuster.fit(value, requirements: requirements, direction: direction)
                if result.wasAdjusted {
                    table[role] = .rgb(result.color)
                    adjusted.insert(role)
                    if role == .accent { accentChanged = true }
                }
                if result.gaveUp { unfittable.insert(role) }
            }

            let accent = table.referenceValue(.accent, in: scheme)
            let labelMinimum = ContrastPolicy.minimumOnAccent(.increased)
            let bestLabel = max(ColorMath.contrastRatio(.white, accent), ColorMath.contrastRatio(.black, accent))
            if bestLabel < labelMinimum {
                // Light scheme: darken under a white label; dark: lighten under black.
                let label: RGBA = scheme == .light ? .white : .black
                let result = AccentAdjuster.fit(
                    accent,
                    requirements: [
                        ContrastRequirement(against: label, minimumRatio: labelMinimum),
                        ContrastRequirement(against: surface, minimumRatio: accentMinimum),
                        ContrastRequirement(against: background, minimumRatio: accentMinimum)
                    ],
                    direction: direction
                )
                table[.accent] = .rgb(result.color)
                adjusted.insert(.accent)
                accentChanged = true
                if result.gaveUp { unfittable.insert(.accent) }
            }
        }

        // Step 5: onAccent.
        if accentChanged || level == .increased {
            table[.onAccent] = .rgb(ContrastPolicy.preferredOnAccent(for: table.referenceValue(.accent, in: scheme)))
        }

        return ResolvedPalette(
            themeID: theme.id,
            scheme: scheme,
            usesIncreasedContrast: level == .increased,
            table: table,
            adjustedRoles: adjusted,
            unfittableRoles: unfittable
        )
    }
}

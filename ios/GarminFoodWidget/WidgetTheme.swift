// WidgetTheme.swift
//
// Per-widget themes (add-themes-and-layout design.md D13, task 5.6): each
// Home Screen widget picks its own built-in theme through Edit Widget. This
// fits the free-account constraints: the choice is stored by WidgetKit with
// the widget instance and handed to this extension's own timeline provider
// as a `WidgetThemeIntent` -- no App Group, no shared file, no reading the
// app's settings (which this process can't do, CLAUDE.md). The flip side,
// said on the Appearance page: widgets don't follow the app's theme, and a
// custom accent can't reach them.
//
// Default: GF Teal -- what every widget has shown since the theme wiring
// (R1 made teal the default everywhere, R4 made the widget render it), so
// widgets already on the Home Screen look the same after this update.
// (D13 predates R1 and said Classic; Classic Coral is one pick away.)
//
// Colors come straight from AppearanceKit (`ThemeCatalog` +
// `PaletteResolver`) for the scheme WidgetKit renders in. The label is the
// theme's `onAccent`, which the contrast policy guarantees on `accent`.
//
// Used by GarminFoodHomeWidget and GarminFoodStreakWidget.

import AppIntents
import SwiftUI
import WidgetKit
import AppearanceKit

/// The built-in themes, as an Edit Widget option. Raw values are
/// `BuiltInTheme` ids (asserted in `builtInTheme`).
enum WidgetThemeOption: String, AppEnum {
    case teal
    case classic
    case ocean
    case forest
    case sunset
    case slate
    case indigo
    case berry
    case graphite
    case gold
    case pastel
    case citrus
    case highContrast

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Theme"
    static var caseDisplayRepresentations: [WidgetThemeOption: DisplayRepresentation] = [
        .teal: DisplayRepresentation(title: "GF Teal"),
        .classic: DisplayRepresentation(title: "Classic Coral"),
        .ocean: DisplayRepresentation(title: "Ocean"),
        .forest: DisplayRepresentation(title: "Forest"),
        .sunset: DisplayRepresentation(title: "Sunset"),
        .slate: DisplayRepresentation(title: "Slate"),
        .indigo: DisplayRepresentation(title: "Indigo Night"),
        .berry: DisplayRepresentation(title: "Berry"),
        .graphite: DisplayRepresentation(title: "Graphite"),
        .gold: DisplayRepresentation(title: "Gold"),
        .pastel: DisplayRepresentation(title: "Pastel"),
        .citrus: DisplayRepresentation(title: "Citrus"),
        .highContrast: DisplayRepresentation(title: "High Contrast")
    ]

    /// The default for a widget nobody has edited (see header).
    static let standard: WidgetThemeOption = .teal

    var builtInTheme: BuiltInTheme {
        let theme = BuiltInTheme(rawValue: rawValue)
        assert(theme != nil, "WidgetThemeOption.\(rawValue) is not a ThemeCatalog theme")
        return theme ?? .teal
    }

    /// This theme resolved for `colorScheme` (or its only scheme).
    func palette(for colorScheme: ColorScheme) -> ResolvedPalette {
        let spec = builtInTheme.spec
        let requested: ThemeColorScheme = colorScheme == .dark ? .dark : .light
        return PaletteResolver.resolve(theme: spec, requestedScheme: spec.effectiveScheme(for: requested))
    }
}

/// Edit Widget's configuration: just the theme.
struct WidgetThemeIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Widget theme"
    static var description = IntentDescription("Choose the colors of this widget.")

    @Parameter(title: "Theme", default: .teal)
    var theme: WidgetThemeOption

    init() {}
}

/// The colors one widget draws with.
struct WidgetThemeColors {
    let palette: ResolvedPalette

    init(option: WidgetThemeOption, colorScheme: ColorScheme) {
        palette = option.palette(for: colorScheme)
    }

    func color(_ role: ThemeRole) -> Color {
        ThemePalette.previewColor(palette, role)
    }

    /// Text and glyphs on the accent (white or black per theme and scheme).
    var label: Color { color(.onAccent) }

    /// The Log Food background: accent -> accentDeep under a white label
    /// (the deep end only adds contrast); plain accent under a black one,
    /// where the deep end would be too dark for it.
    var accentBackground: LinearGradient {
        let accent = color(.accent)
        let end = palette[.onAccent] == .rgb(.white) ? color(.accentDeep) : accent
        return LinearGradient(colors: [accent, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The streak flame: ember at the bottom up to the flame tip, as in
    /// the app's `Theme.flameGradient`.
    var flameBackground: LinearGradient {
        LinearGradient(colors: [color(.ember), color(.flameTip)], startPoint: .bottom, endPoint: .top)
    }
}

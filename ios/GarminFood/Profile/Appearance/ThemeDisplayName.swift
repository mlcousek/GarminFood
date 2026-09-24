// ThemeDisplayName.swift
//
// Localized names for AppearanceKit's built-in themes. AppearanceKit keeps
// no user-facing text (it persists ids only, per the localization rules in
// CLAUDE.md), so the app maps `BuiltInTheme` ids to names here, with the
// Czech in Resources/Localizable.xcstrings. Several names are shared with
// the app icons (AppIconOption.title) and reuse the same catalog keys.
//
// Depended on by: AppearanceSettingsView (gallery), ThemeGalleryView.

import Foundation
import AppearanceKit

extension BuiltInTheme {
    var displayName: String {
        switch self {
        case .teal: return String(localized: "GF Teal")
        case .classic: return String(localized: "Classic Coral")
        case .ocean: return String(localized: "Ocean")
        case .forest: return String(localized: "Forest")
        case .sunset: return String(localized: "Sunset")
        case .slate: return String(localized: "Slate")
        case .indigo: return String(localized: "Indigo Night")
        case .berry: return String(localized: "Berry")
        case .graphite: return String(localized: "Graphite")
        case .gold: return String(localized: "Gold")
        case .pastel: return String(localized: "Pastel")
        case .citrus: return String(localized: "Citrus")
        case .highContrast: return String(localized: "High Contrast")
        }
    }
}

extension ThemeSpec {
    /// The localized name, or the raw id for a theme this build doesn't
    /// know (never shown for built-ins).
    var displayName: String {
        BuiltInTheme(rawValue: id)?.displayName ?? id
    }
}

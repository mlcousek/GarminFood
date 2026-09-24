// AppIconOption.swift
//
// The 12 selectable Home Screen icons: the default (asset-catalog-driven,
// `CFBundleIconName: AppIcon` in project.yml, the teal "GF / by Jirka" from
// PR #37) plus 11 alternates in the same gradient style, one per theme
// (add-themes-and-layout design.md R5, 2026-09-24). They replaced the
// original add-app-icon-picker set (Streak, Macro, Midnight, Mint, Pastel),
// which was drawn around the old coral primary. The alternates are loose
// `CFBundleAlternateIcons` entries (project.yml's own comment explains why
// loose files, not an asset catalog -- there is no local Xcode to catch a
// wrong guess against Info.plist keys, which `xcodebuild` in CI would NOT
// catch either).
//
// This type is the single place a case's raw value, its
// `UIApplication.setAlternateIconName` argument, and its
// `CFBundleAlternateIcons` key in project.yml all have to agree -- change
// one, change the other two, or icon switching silently no-ops on device.
// `ThemeCatalog` (AppearanceKit) names each theme's icon by the same raw
// value, so `AppIconOption(rawValue: spec.iconName)` maps a theme to its icon.
//
// Depended on by: AppIconSwitcher (below), AppearanceSettingsView.

import Foundation
import UIKit
import GarminKit

enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case coral = "AppIcon-Coral"
    case ocean = "AppIcon-Ocean"
    case forest = "AppIcon-Forest"
    case sunset = "AppIcon-Sunset"
    case slate = "AppIcon-Slate"
    case indigo = "AppIcon-Indigo"
    case berry = "AppIcon-Berry"
    case graphite = "AppIcon-Graphite"
    case gold = "AppIcon-Gold"
    case pastel = "AppIcon-Pastel"
    case citrus = "AppIcon-Citrus"

    var id: String { rawValue }

    /// What `UIApplication.setAlternateIconName(_:)` expects -- `nil` resets
    /// to the primary icon; every other case's argument is exactly its
    /// project.yml `CFBundleAlternateIcons` key.
    var alternateIconName: String? {
        self == .default ? nil : rawValue
    }

    var title: String {
        switch self {
        case .default: return String(localized: "GF Teal")
        case .coral: return String(localized: "Coral")
        case .ocean: return String(localized: "Ocean")
        case .forest: return String(localized: "Forest")
        case .sunset: return String(localized: "Sunset")
        case .slate: return String(localized: "Slate")
        case .indigo: return String(localized: "Indigo")
        case .berry: return String(localized: "Berry")
        case .graphite: return String(localized: "Graphite")
        case .gold: return String(localized: "Gold")
        case .pastel: return String(localized: "Pastel")
        case .citrus: return String(localized: "Citrus")
        }
    }

    /// The bundle image name for this option's preview thumbnail --
    /// `UIImage(named:)` resolves both loose bundle files (the alternates,
    /// `GarminFood/AppIcons/`) and asset-catalog entries (the default's own
    /// `AppIcon` set) by the same name lookup, so one property covers both
    /// sources.
    var previewImageName: String {
        self == .default ? "AppIcon" : rawValue
    }

    /// Maps a theme's `iconName` (AppearanceKit `ThemeSpec.iconName`, `nil`
    /// for themes that use the primary icon) to its option.
    init(themeIconName: String?) {
        guard let themeIconName else {
            self = .default
            return
        }
        self = AppIconOption(rawValue: themeIconName) ?? .default
    }
}

/// The one place the app calls `setAlternateIconName`, shared by the icon
/// grid and "Match app icon to theme".
@MainActor
enum AppIconSwitcher {
    /// Alternate icon names shipped by earlier builds (add-app-icon-picker)
    /// and removed by design.md R5. `Pastel` kept its name, so it isn't
    /// here: iOS simply shows the new Pastel artwork.
    static let removedAlternateNames: Set<String> = [
        "AppIcon-Streak", "AppIcon-Macro", "AppIcon-Midnight", "AppIcon-Mint",
    ]

    /// `UIApplication.shared.alternateIconName` is `nil` for the default
    /// icon; matched back to its `AppIconOption` by raw value, falling back
    /// to `.default` for a name this enum doesn't recognise.
    static var current: AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .default }
        return AppIconOption(rawValue: name) ?? .default
    }

    /// Switches the Home Screen icon. iOS shows its own "You have changed
    /// the icon" alert; that can't (and shouldn't) be suppressed. The
    /// completion runs on the main actor with `nil` on success.
    static func set(_ option: AppIconOption, completion: @escaping @MainActor (Error?) -> Void) {
        guard option != current else {
            completion(nil)
            return
        }
        guard UIApplication.shared.supportsAlternateIcons else {
            completion(AppIconSwitchError.unsupported)
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            Task { @MainActor in completion(error) }
        }
    }

    /// Launch check (design.md R5): an icon removed from this build would
    /// otherwise stay on the Home Screen with no way to pick it again, and
    /// the grid would show nothing selected. Only a *removed* name is
    /// reset; any other current value is left alone, so this never fights
    /// a choice the user made.
    static func resetRemovedAlternateIfNeeded() {
        guard let name = UIApplication.shared.alternateIconName,
              removedAlternateNames.contains(name)
        else { return }
        guard UIApplication.shared.supportsAlternateIcons else { return }
        UIApplication.shared.setAlternateIconName(nil) { error in
            if let error {
                DiagnosticsLog.log(.warning, category: "appearance", "Couldn't reset removed app icon \(name): \(error.localizedDescription)")
            }
        }
    }
}

enum AppIconSwitchError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unsupported: return String(localized: "This device doesn't support alternate app icons.")
        }
    }
}

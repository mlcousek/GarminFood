// AppIconOption.swift
//
// The 6 selectable Home Screen icons (add-app-icon-picker): the default
// (asset-catalog-driven, `CFBundleIconName: AppIcon` in project.yml,
// unchanged) plus 5 alternates registered as loose `CFBundleAlternateIcons`
// entries (project.yml's own comment there explains why loose files, not
// an asset catalog, and cites the two sources that confirmed the mechanism
// -- there being no local Xcode to catch a wrong guess against Info.plist
// keys, which `xcodebuild` in CI would NOT catch either).
//
// This type is the single place a case's raw value, its
// `UIApplication.setAlternateIconName` argument, and its
// `CFBundleAlternateIcons` key in project.yml all have to agree -- change
// one, change the other two, or icon switching silently no-ops on device.

import Foundation

enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "Default"
    case streak = "AppIcon-Streak"
    case macro = "AppIcon-Macro"
    case midnight = "AppIcon-Midnight"
    case mint = "AppIcon-Mint"
    case pastel = "AppIcon-Pastel"

    var id: String { rawValue }

    /// What `UIApplication.setAlternateIconName(_:)` expects -- `nil` resets
    /// to the primary icon; every other case's argument is exactly its
    /// project.yml `CFBundleAlternateIcons` key.
    var alternateIconName: String? {
        self == .default ? nil : rawValue
    }

    var title: String {
        switch self {
        case .default: return "Classic"
        case .streak: return "Streak"
        case .macro: return "Macro"
        case .midnight: return "Midnight"
        case .mint: return "Mint"
        case .pastel: return "Pastel"
        }
    }

    /// The bundle image name for this option's preview thumbnail --
    /// `UIImage(named:)` resolves both loose bundle files (the 5
    /// alternates, `GarminFood/AppIcons/`) and asset-catalog entries (the
    /// default's own `AppIcon` set) by the same name lookup, so one
    /// property covers both sources.
    var previewImageName: String {
        self == .default ? "AppIcon" : rawValue
    }
}

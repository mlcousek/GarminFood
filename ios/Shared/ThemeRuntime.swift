// ThemeRuntime.swift
//
// The live half of add-themes-and-layout's token mechanism (design.md R4):
// `Theme.*` (Theme.swift) keeps every token name, but each token is now a
// computed property that reads `ThemeRuntime.shared`. `ThemeRuntime` is
// `@Observable`, and Observation records any read of a tracked property
// during a view's `body` -- even through a static getter -- so every view
// that draws a token re-renders when the theme changes, without an `.id()`
// reset (navigation state survives a theme switch).
//
// Each color in a `ThemePalette` is a dynamic `UIColor` holding the light
// and the dark resolution of the theme, so the system scheme and
// `.preferredColorScheme` pick the right one without re-resolving anything.
// System-colored roles (surfaces, Classic's red) stay real system colors,
// so iOS's own Increase Contrast variants still apply to them.
//
// Deliberately not `@MainActor`: tokens are read from non-isolated helpers
// too (e.g. `CalorieBand.tint`). Writes happen only from `ThemeStore` on the
// main actor; reads are plain value copies.
//
// Lives in Shared/ because the widget extension draws `Theme.*` as well.
// The widget never loads settings (no shared state, CLAUDE.md), so there it
// always shows the default theme (GF Teal).
//
// Depends on AppearanceKit (resolution, catalog). Written by
// GarminFood/App/ThemeStore.swift; read by Theme.swift.

import SwiftUI
import UIKit
import Observation
import AppearanceKit

/// Every `ThemeRole` as a SwiftUI `Color`, dynamic over light/dark.
struct ThemePalette {
    private let colors: [ThemeRole: Color]

    /// `light` and `dark` are the same theme resolved for each scheme. A
    /// single-scheme theme passes the same palette twice (the root forces
    /// that scheme anyway).
    init(light: ResolvedPalette, dark: ResolvedPalette) {
        var colors: [ThemeRole: Color] = [:]
        for role in ThemeRole.allCases {
            colors[role] = ThemePalette.color(light: light[role], dark: dark[role])
        }
        self.colors = colors
    }

    subscript(role: ThemeRole) -> Color {
        colors[role] ?? Color.accentColor
    }

    private static func color(light: TokenValue, dark: TokenValue) -> Color {
        // The same system color in both: hand iOS the real dynamic color.
        if case .system(let lightName) = light, case .system(let darkName) = dark, lightName == darkName {
            return Color(uiColor: uiColor(lightName))
        }
        let provider = UIColor { traits in
            let token = traits.userInterfaceStyle == .dark ? dark : light
            switch token {
            case .rgb(let rgba):
                return uiColor(rgba)
            case .system(let name):
                return uiColor(name).resolvedColor(with: traits)
            }
        }
        return Color(uiColor: provider)
    }

    static func uiColor(_ rgba: RGBA) -> UIColor {
        let c = rgba.clamped
        return UIColor(red: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: CGFloat(c.alpha))
    }

    static func uiColor(_ name: SystemColorName) -> UIColor {
        switch name {
        case .systemGroupedBackground: return .systemGroupedBackground
        case .secondarySystemGroupedBackground: return .secondarySystemGroupedBackground
        case .secondarySystemBackground: return .secondarySystemBackground
        case .separator: return .separator
        case .systemRed: return .systemRed
        }
    }

    /// `role` of an already-resolved palette as a plain (non-dynamic) color,
    /// for previews that draw a theme other than the active one.
    static func previewColor(_ palette: ResolvedPalette, _ role: ThemeRole) -> Color {
        switch palette[role] {
        case .rgb(let rgba): return Color(uiColor: uiColor(rgba))
        case .system(let name):
            let style: UIUserInterfaceStyle = palette.scheme == .dark ? .dark : .light
            return Color(uiColor: uiColor(name).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
        }
    }
}

@Observable
final class ThemeRuntime: @unchecked Sendable {
    static let shared = ThemeRuntime()

    private(set) var palette: ThemePalette
    private(set) var style: AppearanceStyle

    private init() {
        let theme = ThemeCatalog.themeOrDefault(id: ThemeCatalog.defaultThemeID)
        palette = ThemePalette(
            light: PaletteResolver.resolve(theme: theme, requestedScheme: .light),
            dark: PaletteResolver.resolve(theme: theme, requestedScheme: .dark)
        )
        style = .default
    }

    /// Called by `ThemeStore` (main actor) whenever settings or the
    /// accessibility inputs change.
    func update(palette: ThemePalette, style: AppearanceStyle) {
        self.palette = palette
        self.style = style
    }

    var numberDesign: Font.Design {
        switch style.numberFont {
        case .rounded: return .rounded
        case .default: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

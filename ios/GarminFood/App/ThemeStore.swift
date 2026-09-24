// ThemeStore.swift
//
// The app's owner of the look (add-themes-and-layout design.md R4, D4, D7):
// holds the persisted `AppearanceSettings`, the accessibility inputs the
// root reads from the environment (Increase Contrast, Differentiate Without
// Color), and pushes the resolved palette + style into
// `ThemeRuntime.shared`, which every `Theme.*` token reads. Changes write
// through to UserDefaults immediately (no Save button) and apply live.
//
// Also owns "Match app icon to theme" (design R5): with it on, picking a
// theme switches the app icon to the theme's `iconName`.
//
// One instance per process, created in AppEnvironment. Resolution itself is
// AppearanceKit's (PaletteResolver) and unit-tested there; this class only
// glues it to SwiftUI.

import SwiftUI
import Observation
import AppearanceKit
import GarminKit

@MainActor
@Observable
final class ThemeStore {
    private(set) var settings: AppearanceSettings
    /// The stored look was unreadable and got reset (shown once on the
    /// Appearance page).
    private(set) var showsResetNotice: Bool
    private(set) var increasedContrast = false
    private(set) var differentiateWithoutColor = false

    /// Default on (design R5).
    var matchesAppIcon: Bool {
        get { storedMatchesAppIcon }
        set {
            storedMatchesAppIcon = newValue
            defaults.set(newValue, forKey: Self.matchIconKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private var storedMatchesAppIcon: Bool
    private static let matchIconKey = "appearance.matchAppIcon"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AppPreferences.loadAppearance(from: defaults)
        showsResetNotice = defaults.bool(forKey: AppPreferences.Key.appearanceResetNotice)
        storedMatchesAppIcon = defaults.object(forKey: Self.matchIconKey) as? Bool ?? true
        applyToRuntime()
    }

    // MARK: Reading

    var theme: ThemeSpec {
        ThemeCatalog.themeOrDefault(id: settings.themeID)
    }

    /// The scheme the root must force, or `nil` to follow the system:
    /// a single-scheme theme forces its scheme; otherwise the user's
    /// Light/Dark choice (R7).
    var forcedColorScheme: ColorScheme? {
        let supported = theme.supportedSchemes
        if supported.count == 1, let only = supported.first {
            return only == .dark ? .dark : .light
        }
        switch settings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// `theme` resolved for `scheme` with the current settings and
    /// accessibility inputs (what the Appearance page previews and checks).
    func resolved(_ theme: ThemeSpec, scheme: ThemeColorScheme, customAccent: RGBA?? = nil) -> ResolvedPalette {
        PaletteResolver.resolve(
            theme: theme,
            requestedScheme: scheme,
            macroSet: settings.macroSet,
            customAccent: customAccent ?? settings.customAccent,
            increasedContrast: increasedContrast,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }

    // MARK: Writing

    func update(_ change: (inout AppearanceSettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        AppPreferences.saveAppearance(copy, to: defaults)
        applyToRuntime()
    }

    /// Picks a theme, and (with Match app icon on) its icon.
    func selectTheme(_ id: String) {
        update { $0.themeID = id }
        matchAppIconIfNeeded()
    }

    /// Back to the defaults -- including the default theme's icon when
    /// "Match app icon to theme" is on, like any other theme change.
    func resetAll() {
        update { $0 = .default }
        matchAppIconIfNeeded()
    }

    /// With Match app icon on, switches the Home Screen icon to the current
    /// theme's (a no-op when it's already showing).
    private func matchAppIconIfNeeded() {
        guard matchesAppIcon else { return }
        let option = AppIconOption(themeIconName: theme.iconName)
        AppIconSwitcher.set(option) { error in
            if let error {
                DiagnosticsLog.log(.warning, category: "appearance", "Match app icon to theme failed for \(option.rawValue): \(error)")
            }
        }
    }

    func dismissResetNotice() {
        showsResetNotice = false
        defaults.removeObject(forKey: AppPreferences.Key.appearanceResetNotice)
    }

    /// From the root's environment (ThemeRootModifier).
    func setAccessibility(increasedContrast: Bool, differentiateWithoutColor: Bool) {
        guard increasedContrast != self.increasedContrast
            || differentiateWithoutColor != self.differentiateWithoutColor else { return }
        self.increasedContrast = increasedContrast
        self.differentiateWithoutColor = differentiateWithoutColor
        applyToRuntime()
    }

    private func applyToRuntime() {
        let theme = self.theme
        let light = resolved(theme, scheme: .light)
        let dark = resolved(theme, scheme: .dark)
        ThemeRuntime.shared.update(palette: ThemePalette(light: light, dark: dark), style: settings.style)
    }
}

/// The root of the themed view tree (design R4): tint, forced scheme for
/// single-scheme themes / the user's Light-Dark choice, and the
/// accessibility inputs handed to the store.
@MainActor
struct ThemeRootModifier: ViewModifier {
    let store: ThemeStore
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    func body(content: Content) -> some View {
        content
            .tint(Theme.accent)
            .preferredColorScheme(store.forcedColorScheme)
            .onAppear(perform: syncAccessibility)
            .onChange(of: contrast) { _, _ in syncAccessibility() }
            .onChange(of: differentiateWithoutColor) { _, _ in syncAccessibility() }
    }

    private func syncAccessibility() {
        store.setAccessibility(
            increasedContrast: contrast == .increased,
            differentiateWithoutColor: differentiateWithoutColor
        )
    }
}

extension View {
    /// Applies the app's theme root. Once at the root; also on any presenter
    /// found not to inherit it (design 2.7).
    func themed(_ store: ThemeStore) -> some View {
        modifier(ThemeRootModifier(store: store))
    }
}

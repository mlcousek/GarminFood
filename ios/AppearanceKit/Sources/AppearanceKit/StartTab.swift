// StartTab — which tab the app opens on (add-themes-and-layout design.md
// D8 "Start tab", task 4.3). Stored as `LayoutConfig.startTab`, a plain
// string like every other layout id, so a value written by a newer build
// (a tab this build doesn't offer) reads as the default instead of failing
// the whole layout.
//
// Why it lives here and not in the app: the parse/default/"store nothing
// for the default" rules are the part worth testing, and the app can't be
// unit-tested (no Mac). The app's AppRouter only maps the result to its own
// tab enum at launch; deep links and widget routes then override it there.
//
// rebrand-to-jirkas-arc D8 adds `.plan`, a tab only the training experience
// shows. Which start tabs an experience offers, and the fallback to Today
// for one it doesn't show, are AppShell's rules
// (`AppShell.resolvedStartTab(stored:experience:)`); `resolvedStartTab`
// below only parses the stored value.
//
// Depended on by: LayoutConfig (this file's extension), AppShell, the app's
// AppEnvironment/AppRouter (initial tab) and AppearanceSettingsView (picker).

import Foundation

/// A tab the app can open on. Tabs themselves are never reordered or hidden
/// (proposal non-goals); Profile is deliberately not offered. `.plan` only
/// in the training experience (`AppShell.startTabs(for:)`).
public enum StartTab: String, CaseIterable, Sendable {
    case today
    case plan
    case progress

    public static let `default`: StartTab = .today
}

public extension LayoutConfig {
    /// The stored start tab, or Today when none is stored or the stored
    /// value is unknown to this build. Not experience-aware: the app opens
    /// on `resolvedStartTab(for:)` (AppShell.swift).
    var resolvedStartTab: StartTab {
        startTab.flatMap(StartTab.init(rawValue:)) ?? .default
    }

    /// Stores `tab`; the default is stored as nothing, so a config that was
    /// never customised stays byte-identical to `LayoutConfig.default`.
    mutating func setStartTab(_ tab: StartTab) {
        startTab = tab == .default ? nil : tab.rawValue
    }

    /// Whether `screen` renders exactly its default order, visibility and
    /// variants -- what the Appearance page shows as "Default" vs "Custom"
    /// for screens without presets.
    func isDefaultLayout(_ screen: LayoutScreen, experience: AppExperience = .foodFirst) -> Bool {
        resolved(screen, experience: experience) == LayoutConfig.default.resolved(screen, experience: experience)
    }
}

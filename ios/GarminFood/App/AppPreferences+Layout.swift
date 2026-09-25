// AppPreferences+Layout.swift
//
// Persistence of the screen layouts (add-themes-and-layout design.md D7):
// one JSON blob under `layout.v1`, decoded leniently by AppearanceKit's
// `LayoutConfig.load`. Same contract as AppPreferences+Appearance.swift: a
// blob that can't be read at all is quarantined, never silently wiped (the
// lesson of fix-silent-store-wipe) -- moved to `layout.v1.quarantine`, a
// warning goes to the DiagnosticsLog, and a one-time notice flag is set for
// the Appearance page.
//
// Kept out of AppPreferences.swift so that file stays free of an
// AppearanceKit import. Used only by LayoutStore.

import Foundation
import AppearanceKit
import GarminKit

extension AppPreferences.Key {
    static let layout = "layout.v1"
    static let layoutQuarantine = "layout.v1.quarantine"
    /// Set when a quarantine happened and the user hasn't seen the notice yet.
    static let layoutResetNotice = "layout.v1.resetNotice"
}

extension AppPreferences {
    /// Reads the stored layouts; quarantines an unreadable blob.
    static func loadLayout(from defaults: UserDefaults) -> LayoutConfig {
        let data = defaults.data(forKey: Key.layout)
        let result = LayoutConfig.load(from: data)
        if result.status == .undecodable, let data {
            defaults.set(data, forKey: Key.layoutQuarantine)
            defaults.removeObject(forKey: Key.layout)
            defaults.set(true, forKey: Key.layoutResetNotice)
            DiagnosticsLog.log(
                .warning,
                category: "appearance",
                "Stored layout (\(data.count) bytes) could not be decoded; moved to \(Key.layoutQuarantine) and reset to the default layout."
            )
        }
        return result.config
    }

    static func saveLayout(_ config: LayoutConfig, to defaults: UserDefaults) {
        do {
            defaults.set(try config.encoded(), forKey: Key.layout)
        } catch {
            DiagnosticsLog.log(.error, category: "appearance", "Could not encode the layout: \(error)")
        }
    }
}

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
            let quarantineKey = freeQuarantineKey(Key.layoutQuarantine, in: defaults)
            defaults.set(data, forKey: quarantineKey)
            defaults.removeObject(forKey: Key.layout)
            defaults.set(true, forKey: Key.layoutResetNotice)
            DiagnosticsLog.log(
                .warning,
                category: "appearance",
                "Stored layout (\(data.count) bytes) could not be decoded; moved to \(quarantineKey) and reset to the default layout."
            )
        }
        return result.config
    }

    /// `base` if nothing is quarantined there yet, else `base` plus a
    /// timestamp suffix, so a second quarantine never overwrites the first
    /// blob. Shared with AppPreferences+Appearance.swift.
    static func freeQuarantineKey(_ base: String, in defaults: UserDefaults, now: Date = Date()) -> String {
        guard defaults.object(forKey: base) != nil else { return base }
        let stamp = Int(now.timeIntervalSince1970)
        var key = "\(base).\(stamp)"
        var attempt = 1
        while defaults.object(forKey: key) != nil {
            key = "\(base).\(stamp)-\(attempt)"
            attempt += 1
        }
        return key
    }

    static func saveLayout(_ config: LayoutConfig, to defaults: UserDefaults) {
        do {
            defaults.set(try config.encoded(), forKey: Key.layout)
        } catch {
            DiagnosticsLog.log(.error, category: "appearance", "Could not encode the layout: \(error)")
        }
    }
}

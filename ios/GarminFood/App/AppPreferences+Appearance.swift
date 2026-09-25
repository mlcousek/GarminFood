// AppPreferences+Appearance.swift
//
// Persistence of the user's look (add-themes-and-layout design.md D7): one
// JSON blob under `appearance.v1`, decoded leniently by AppearanceKit's
// `AppearanceSettings.load`. A blob that can't be read at all is
// quarantined, never silently wiped (the lesson of fix-silent-store-wipe):
// it is moved to `appearance.v1.quarantine`, a warning goes to the
// DiagnosticsLog, and a one-time notice flag is set for the Appearance page.
//
// Same split as AppPreferences+Goals.swift: AppPreferences.swift stays free
// of an AppearanceKit import. Used only by ThemeStore.

import Foundation
import AppearanceKit
import GarminKit

extension AppPreferences.Key {
    static let appearance = "appearance.v1"
    static let appearanceQuarantine = "appearance.v1.quarantine"
    /// Set when a quarantine happened and the user hasn't seen the notice yet.
    static let appearanceResetNotice = "appearance.v1.resetNotice"
}

extension AppPreferences {
    /// Reads the stored look; quarantines an unreadable blob.
    static func loadAppearance(from defaults: UserDefaults) -> AppearanceSettings {
        let data = defaults.data(forKey: Key.appearance)
        let result = AppearanceSettings.load(from: data)
        if result.status == .undecodable, let data {
            // Never overwrite an earlier quarantined blob (see
            // AppPreferences+Layout.swift's freeQuarantineKey).
            let quarantineKey = freeQuarantineKey(Key.appearanceQuarantine, in: defaults)
            defaults.set(data, forKey: quarantineKey)
            defaults.removeObject(forKey: Key.appearance)
            defaults.set(true, forKey: Key.appearanceResetNotice)
            DiagnosticsLog.log(
                .warning,
                category: "appearance",
                "Stored appearance (\(data.count) bytes) could not be decoded; moved to \(quarantineKey) and reset to defaults."
            )
        }
        return result.settings
    }

    static func saveAppearance(_ settings: AppearanceSettings, to defaults: UserDefaults) {
        do {
            defaults.set(try settings.encoded(), forKey: Key.appearance)
        } catch {
            DiagnosticsLog.log(.error, category: "appearance", "Could not encode appearance settings: \(error)")
        }
    }
}

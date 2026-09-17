// AppPreferences.swift
//
// The few settings that survive a relaunch (profile-and-settings spec,
// design D9). Standard `UserDefaults`: there is no App Group, and nothing in
// an extension needs these values.

import Foundation
import Observation

@MainActor
@Observable
final class AppPreferences {
    enum Key {
        static let haptics = "preferences.haptics"
        static let celebrations = "preferences.celebrations"
        static let garminMealWindows = "preferences.garminMealWindows"
        static let czechOnlySearch = "preferences.czechOnlySearch"
    }

    @ObservationIgnored private let defaults: UserDefaults

    // Stored, tracked values; the public properties below write through to
    // UserDefaults on every change.
    private var storedHaptics: Bool
    private var storedCelebrations: Bool
    private var storedGarminMealWindows: Bool
    private var storedCzechOnlySearch: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedHaptics = defaults.object(forKey: Key.haptics) as? Bool ?? true
        storedCelebrations = defaults.object(forKey: Key.celebrations) as? Bool ?? true
        storedGarminMealWindows = defaults.object(forKey: Key.garminMealWindows) as? Bool ?? true
        // On by default, as the catalog's toggle always was.
        storedCzechOnlySearch = defaults.object(forKey: Key.czechOnlySearch) as? Bool ?? true
    }

    var hapticsEnabled: Bool {
        get { storedHaptics }
        set {
            storedHaptics = newValue
            defaults.set(newValue, forKey: Key.haptics)
        }
    }

    /// Celebratory animations (level-up, streak milestone, challenge done).
    /// Reduce Motion always wins over this.
    var celebrationsEnabled: Bool {
        get { storedCelebrations }
        set {
            storedCelebrations = newValue
            defaults.set(newValue, forKey: Key.celebrations)
        }
    }

    /// Pre-select the meal from Garmin's meal windows (design D4).
    var useGarminMealWindows: Bool {
        get { storedGarminMealWindows }
        set {
            storedGarminMealWindows = newValue
            defaults.set(newValue, forKey: Key.garminMealWindows)
        }
    }

    var czechOnlySearch: Bool {
        get { storedCzechOnlySearch }
        set {
            storedCzechOnlySearch = newValue
            defaults.set(newValue, forKey: Key.czechOnlySearch)
        }
    }
}

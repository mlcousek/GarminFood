// DataMode.swift
//
// Which system of record this install writes to (add-standalone-mode D1):
// Garmin Connect (the owner's phone, everything to date) or a purely local
// food log (a second person with no Garmin account, waves 2+). Lives in
// FoodLogCore so pure logic -- the routing proxy, gamification, readers --
// can depend on it without the app target.
//
// Stored per install in `UserDefaults` under `dataMode.v1` by the app's
// `AppPreferences`; this file never touches storage. `DataModeMigration`
// is the one-time, silent classification of an install that predates the
// key: any Garmin token or any local history means it is the existing
// user's phone and becomes `.garminConnected` with no onboarding. Only a
// genuinely fresh install stays unset (onboarding asks, wave 5).
//
// Wave 2 adds the EFFECTIVE mode every routing seam reads on each call
// (`DataMode.effective`): the hidden "Force standalone mode (testing)"
// Diagnostics toggle wins, then the stored mode, and an unclassified
// install is Garmin -- so standalone stays unreachable for a normal user
// until onboarding (wave 5) can store it. The `UserDefaults` keys live
// here, not in the app's `AppPreferences`, because `AppServices` (Shared/,
// also compiled into the widget) reads them without the app target.
//
// Depended on by: AppPreferences (raw value, keys), AppEnvironment (launch
// classification), AppServices (the mode closure handed to
// ModeRoutingFoodLogging and ModeRoutingNutritionReader). Tests:
// DataModeMigrationTests, ModeRoutingTests.

import Foundation

public enum DataMode: String, Codable, Sendable, CaseIterable {
    case garminConnected
    case standalone

    /// `UserDefaults` key of the stored mode (absent = not yet classified).
    public static let storageKey = "dataMode.v1"
    /// `UserDefaults` key of the developer-only "Force standalone mode
    /// (testing)" toggle (add-standalone-mode 1.5).
    public static let forceStandaloneStorageKey = "developer.forceStandaloneMode.v1"

    /// The mode the app routes by right now. The testing toggle wins; an
    /// unclassified install (`stored == nil`) behaves as Garmin-connected,
    /// exactly as every install did before standalone mode existed.
    public static func effective(stored: DataMode?, forceStandalone: Bool) -> DataMode {
        if forceStandalone { return .standalone }
        return stored ?? .garminConnected
    }

    /// `effective(stored:forceStandalone:)` from the two stored keys.
    public static func effective(in defaults: UserDefaults) -> DataMode {
        effective(
            stored: defaults.string(forKey: storageKey).flatMap(DataMode.init(rawValue:)),
            forceStandalone: defaults.bool(forKey: forceStandaloneStorageKey)
        )
    }
}

public enum DataModeMigration {
    /// The mode an install should run in, or `nil` while it is still
    /// undecided (a fresh install -- onboarding will ask).
    ///
    /// - A mode already stored always wins: classification runs once.
    /// - `hasGarminToken`: an OAuth1 token is in the Keychain.
    /// - `hasLocalHistory`: any outbox, usage-history, weight or hydration
    ///   entry exists on this install.
    /// Either of the two means the install predates standalone mode and is
    /// the owner's Garmin-connected phone.
    public static func decide(storedMode: DataMode?, hasGarminToken: Bool, hasLocalHistory: Bool) -> DataMode? {
        if let storedMode { return storedMode }
        if hasGarminToken || hasLocalHistory { return .garminConnected }
        return nil
    }
}

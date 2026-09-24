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
// Depended on by: AppPreferences (raw value), AppEnvironment (launch
// classification), ModeRoutingFoodLogging (AppServices). Tests:
// DataModeMigrationTests.

import Foundation

public enum DataMode: String, Codable, Sendable, CaseIterable {
    case garminConnected
    case standalone
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

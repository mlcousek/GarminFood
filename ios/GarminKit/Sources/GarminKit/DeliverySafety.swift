// DeliverySafety.swift
//
// fix-review-findings-2026-09 findings 9 and 16: two rules every outbox
// (food `Outbox`, `WeightOutbox`, `HydrationOutbox`) applies before it
// sends anything to Garmin.
//
// 1. ACCOUNT SCOPE (finding 9). Entries used to carry no account, and
//    signing out kept them queued "to deliver after the next sign-in" --
//    so signing in as a DIFFERENT Garmin account delivered the first
//    account's pending food, weigh-ins and water to the second. Now each
//    entry is stamped at enqueue with the account it was logged under
//    (`accountKey`, a SHA-256 of the Garmin profile's stable identifier --
//    never the identifier itself), and a drain only sends an entry whose
//    stamp matches the account signed in right now. An entry of another
//    account is HELD, not deleted (non-destructive default): it stays in
//    the queue and in the sync queue screen, and goes out if that account
//    signs in again. An unstamped entry (logged while no account was known,
//    or by an older build) goes to whoever is signed in; signing out stamps
//    every unstamped undelivered entry with the account being signed out
//    (`assignUnscopedEntries`), so those can't cross over either.
//
//    "The account signed in right now" is only trusted for the token it
//    was learned with: `GarminAccountKey` stores the key next to a
//    fingerprint of the OAuth1 token, and `current(...)` answers `nil`
//    once the token changed (a new sign-in, even through the "sign in
//    again" banner without an explicit sign-out) until the profile has been
//    read again. While it is `nil`, every stamped entry is held.
//
// 2. SEND MARKER (finding 16). A drain used to ignore a failure to persist
//    `.sent` after Garmin's 2xx; after the process died, the entry reloaded
//    as `.pending` and was POSTed again -- a second weigh-in, a second
//    drink in Garmin's day total. Now each outbox durably records
//    `sendStartedAt` BEFORE the request goes out (and doesn't send if that
//    write fails), and clears it with the outcome. An entry that reloads
//    with the marker still set is "possibly delivered" and is never
//    blindly re-sent: food is handed to Reconciliation as `.sent` (the
//    day's re-read finds it, or re-queues it as missing); a weigh-in add is
//    looked up in Garmin's day view first; a drink -- Garmin keeps only a
//    day total, so nothing can prove it either way -- is marked failed with
//    a note, for the user to check before retrying.
//
// Depended on by: Outbox.swift, WeightSync.swift, HydrationSync.swift,
// Reconciliation.swift, and the app (AppServices, ProfileLoader,
// AppEnvironment.signOut). Tests: DeliverySafetyTests.

import Foundation
import CryptoKit

/// Whether an entry may be delivered to the account signed in now.
public enum AccountScope {
    /// An unstamped entry goes anywhere; a stamped one only to its own
    /// account, and nowhere while the current account is unknown.
    public static func mayDeliver(entryKey: String?, currentKey: String?) -> Bool {
        guard let entryKey else { return true }
        return entryKey == currentKey
    }

    /// Supplies the current account's key (`nil` = unknown) to an outbox.
    public typealias Provider = @Sendable () async -> String?
}

/// The signed-in Garmin account's key, remembered on this device.
public enum GarminAccountKey {
    static let keyDefaultsKey = "garminAccountKey"
    static let fingerprintDefaultsKey = "garminAccountTokenFingerprint"

    /// SHA-256 hex of `value` -- what is stored and stamped, so the
    /// profile's identifier itself never lands in an outbox file.
    public static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The account key for a profile: its user name, else its display name
    /// (a stable id on Garmin accounts), hashed. `nil` when it has neither.
    public static func key(for profile: SocialProfile) -> String? {
        let candidates = [profile.userName, profile.displayName]
        guard let raw = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        return hash(raw.lowercased())
    }

    /// Remembers `profile`'s account as the one `tokenFingerprint` belongs to.
    public static func record(profile: SocialProfile, tokenFingerprint: String?, defaults: UserDefaults = .standard) {
        guard let key = key(for: profile), let tokenFingerprint else { return }
        defaults.set(key, forKey: keyDefaultsKey)
        defaults.set(tokenFingerprint, forKey: fingerprintDefaultsKey)
    }

    /// The remembered account key, but only while `tokenFingerprint` is the
    /// token it was learned with -- `nil` after any new sign-in until the
    /// profile is read again.
    public static func current(tokenFingerprint: String?, defaults: UserDefaults = .standard) -> String? {
        guard let tokenFingerprint,
              let stored = defaults.string(forKey: fingerprintDefaultsKey),
              stored == tokenFingerprint
        else { return nil }
        return defaults.string(forKey: keyDefaultsKey)
    }

    /// The last remembered account key, whatever the token -- what signing
    /// out stamps unstamped entries with.
    public static func lastRecorded(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: keyDefaultsKey)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: keyDefaultsKey)
        defaults.removeObject(forKey: fingerprintDefaultsKey)
    }

    /// A fingerprint of the stored OAuth1 token, `nil` when signed out or
    /// the Keychain can't be read.
    public static func tokenFingerprint(tokenProvider: TokenProvider = .shared) async -> String? {
        guard let token = try? await tokenProvider.loadOAuth1Token() else { return nil }
        return hash(token.oauthToken)
    }

    /// The account signed in right now, as far as this device knows.
    public static func currentKey(tokenProvider: TokenProvider = .shared) async -> String? {
        current(tokenFingerprint: await tokenFingerprint(tokenProvider: tokenProvider))
    }
}

/// What a "possibly delivered" drink is marked with (finding 16): Garmin
/// keeps only a day total, so the app can't tell whether it arrived.
enum PossiblyDelivered {
    static let note = "possibly delivered already (the app stopped before recording Garmin's answer): check the day's water in Garmin Connect before retrying"
}

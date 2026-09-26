// BackupExclusions.swift
//
// add-data-safety D3/D5/D8: what a snapshot or an exported backup may
// contain. Deliberately a DENY list over a generic walk of Application
// Support, not an allow list of known stores: a store added later (the
// supplements stores being built in parallel, a future goals store) is
// backed up the day it ships, with no registration. The cost of that
// choice is that anything secret-looking must be caught generically too --
// hence the name rules and `BackupSecretPolicy`'s content scan on top of the
// fixed exclusions. Garmin tokens themselves live in the Keychain
// (TokenProvider.swift), never in a file; these checks are defense in depth.
//
// Also decides which UserDefaults keys travel with a backup (`includesPreference`).
//
// Depended on by: BackupVault, PreferencesBackup, StoreCatalogTests.

import Foundation

public enum BackupExclusions {
    /// The top-level directory holding snapshots, the staged restore and
    /// `status.json` -- never inside a backup.
    public static let backupsDirectoryName = "Backups"

    /// Whole files left out on purpose (design D3): the diagnostics log is
    /// copied from Diagnostics instead, the health cache is re-read from
    /// Garmin, the donation ledger is device-local Siri state.
    static let excludedFiles: Set<String> = [
        "GarminKit/diagnostics-log.json",
        "FoodLogCore/garmin-health-cache.json",
        "GarminFood/donations.json"
    ]

    /// Directories left out: the offline index is large and re-downloadable.
    static let excludedDirectories: [String] = [
        "FoodLogCore/OfflineIndex"
    ]

    /// A path component containing one of these (case-insensitive) is
    /// never backed up. `outbox` is design D8 (per-device delivery state;
    /// replaying it would send entries to Garmin twice); the rest look like
    /// credentials. Deliberately not "secret": the secret-achievements
    /// feature's directory is `Gamification/features/secrets/`, and a
    /// credential secret is caught by `BackupSecretPolicy`'s content scan
    /// (`"oauth_token_secret"`, `"consumer_secret"`) instead.
    static let excludedNameFragments: [String] = [
        "outbox", "token", "oauth", "cookie", "credential", "password"
    ]

    /// UserDefaults key prefixes that never travel: the backup's own
    /// bookkeeping (restoring it would lie about when the last export was),
    /// developer switches, and keys iOS or frameworks write into the app's
    /// domain.
    static let excludedPreferencePrefixes: [String] = [
        "dataSafety.", "developer.", "Apple", "NS", "com.apple.", "WebKit"
    ]

    /// Whether a file at `relativePath` (relative to Application Support,
    /// `/`-separated) belongs in a snapshot or export.
    public static func includesFile(relativePath: String) -> Bool {
        guard BackupPath.isSafe(relativePath) else { return false }
        guard relativePath.lowercased().hasSuffix(".json") else { return false }
        let components = relativePath.split(separator: "/").map(String.init)
        if components.first == backupsDirectoryName { return false }
        if excludedFiles.contains(relativePath) { return false }
        if excludedDirectories.contains(where: { relativePath.hasPrefix($0 + "/") }) { return false }
        for component in components {
            let lowered = component.lowercased()
            if excludedNameFragments.contains(where: { lowered.contains($0) }) { return false }
        }
        return true
    }

    /// Whether a UserDefaults key belongs in a backup.
    public static func includesPreference(key: String) -> Bool {
        if key.isEmpty { return false }
        if excludedPreferencePrefixes.contains(where: { key.hasPrefix($0) }) { return false }
        let lowered = key.lowercased()
        // `outbox` isn't a preference concern; only the credential words.
        let credentialWords = excludedNameFragments.filter { $0 != "outbox" }
        return !credentialWords.contains(where: { lowered.contains($0) })
    }
}

/// Rules for relative paths read from a backup, which may come from an
/// arbitrary file the user picked: no escaping the data directory.
public enum BackupPath {
    public static func isSafe(_ relativePath: String) -> Bool {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\") else { return false }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component.isEmpty || component == "." || component == ".." { return false }
        }
        return true
    }
}

/// add-data-safety D3/D5: a last line of defense -- a file whose CONTENT
/// carries an OAuth/token key is skipped even if its name looked harmless.
public enum BackupSecretPolicy {
    /// JSON keys (with their quotes) that only credentials use. Matched as
    /// raw UTF-8 bytes, so the check costs one scan per file.
    public static let secretKeys: [String] = [
        "\"oauth_token\"",
        "\"oauth_token_secret\"",
        "\"access_token\"",
        "\"refresh_token\"",
        "\"consumer_secret\"",
        "\"oauthToken\"",
        "\"oauthTokenSecret\"",
        "\"accessToken\"",
        "\"refreshToken\""
    ]

    public static func containsSecret(_ data: Data) -> Bool {
        for key in secretKeys {
            if data.range(of: Data(key.utf8)) != nil { return true }
        }
        return false
    }
}

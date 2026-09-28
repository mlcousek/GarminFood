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

    /// Directories left out: the offline index is large and re-downloadable;
    /// VaultKit's files are device-local (add-vault-connection D12 -- the
    /// device identity must never reach another phone, and the rest is
    /// delivery state or a re-fetchable copy of vault data).
    static let excludedDirectories: [String] = [
        "FoodLogCore/OfflineIndex",
        "VaultKit"
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

    /// Review note 23: the marker GarminKit's store quarantine puts in a
    /// file it moved aside (`<name>.unreadable-<stamp>.json`,
    /// `PersistedJSON.quarantineDestination`). Such a file is a diagnostic
    /// of a past decode failure, not data: no store reads it, so backing it
    /// up would only restore it as a stray file (and list it under "Other
    /// files" in the import preview). Excluded files are also left alone by
    /// a restore, so the phone keeps its own quarantined copies.
    static let quarantineMarker = ".unreadable-"

    /// UserDefaults keys that never travel (review note 22): the data mode
    /// belongs to the phone, not the data. Restoring the owner's
    /// Garmin-mode backup onto a standalone phone (or the reverse) must keep
    /// the phone's current mode; switching stays an explicit Settings
    /// action. The testing toggle's key is also covered by `developer.`.
    static let excludedPreferenceKeys: Set<String> = [
        DataMode.storageKey,
        DataMode.forceStandaloneStorageKey
    ]

    /// Whether a file at `relativePath` (relative to Application Support,
    /// `/`-separated) belongs in a snapshot or export.
    public static func includesFile(relativePath: String) -> Bool {
        guard BackupPath.isSafe(relativePath) else { return false }
        guard relativePath.lowercased().hasSuffix(".json") else { return false }
        let components = relativePath.split(separator: "/").map(String.init)
        if components.first == backupsDirectoryName { return false }
        if let fileName = components.last, fileName.lowercased().contains(quarantineMarker) { return false }
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
        if excludedPreferenceKeys.contains(key) { return false }
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
///
/// add-vault-connection D3/D12: also any GitHub token, by its prefix
/// (`github_pat_`, `ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`). The vault token
/// itself lives only in the Keychain, but one pasted into a day note, a
/// custom food's name or a preference would otherwise travel inside a
/// backup. A prefix counts only as a token: at the start of the data or
/// after a character that can't be part of a word, or after a JSON escape
/// such as a backslash-n (so `thighs_x` is not `ghs_`), and followed by at
/// least `minimumTokenTail` token characters (so a stray `ghp_` in prose
/// is not one either) -- a false positive drops
/// a whole store file from the backup, so the shape check matters.
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

    /// GitHub token prefixes (VaultKit's `VaultToken.knownPrefixes`; kept
    /// here too because FoodLogCore does not depend on VaultKit).
    public static let githubTokenPrefixes: [String] = [
        "github_pat_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_"
    ]

    /// Real tokens carry 36 (classic) to 82 (fine-grained) characters
    /// after the prefix; 16 is far below both and far above prose.
    public static let minimumTokenTail = 16

    public static func containsSecret(_ data: Data) -> Bool {
        for key in secretKeys {
            if data.range(of: Data(key.utf8)) != nil { return true }
        }
        return containsGitHubToken(data)
    }

    /// Whether `data` holds something shaped like a GitHub token (see the
    /// type's header for the shape).
    public static func containsGitHubToken(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        for prefix in githubTokenPrefixes {
            let needle = [UInt8](prefix.utf8)
            guard bytes.count >= needle.count else { continue }
            var start = 0
            while start <= bytes.count - needle.count {
                guard let found = firstIndex(of: needle, in: bytes, from: start) else { break }
                // A JSON escape (backslash-n, backslash-t) before the token
                // is a boundary too: a note with the token on its own line
                // stores a backslash, an `n`, then the token.
                let precededByEscape = found > 1 && bytes[found - 2] == 0x5C
                let precededByWordCharacter = found > 0 && isTokenByte(bytes[found - 1]) && !precededByEscape
                if !precededByWordCharacter {
                    var tail = 0
                    var index = found + needle.count
                    while index < bytes.count, isTokenByte(bytes[index]) {
                        tail += 1
                        index += 1
                    }
                    if tail >= minimumTokenTail { return true }
                }
                start = found + 1
            }
        }
        return false
    }

    /// `[A-Za-z0-9_]`, the characters a GitHub token is made of.
    private static func isTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: return true
        default: return false
        }
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8], from start: Int) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count, start <= haystack.count - needle.count else { return nil }
        var index = start
        while index <= haystack.count - needle.count {
            if haystack[index] == needle[0] {
                var matches = true
                for offset in 1..<needle.count where haystack[index + offset] != needle[offset] {
                    matches = false
                    break
                }
                if matches { return index }
            }
            index += 1
        }
        return nil
    }
}

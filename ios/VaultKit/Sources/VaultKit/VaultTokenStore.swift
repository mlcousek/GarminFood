// VaultTokenStore.swift
//
// The GitHub token (add-vault-connection design D3). The token can write
// ANYWHERE in the vault -- GitHub's fine-grained tokens can be limited to
// one repository but not to a path -- so it is handled as the most
// sensitive value this app holds:
//
//   - Only fine-grained tokens (`github_pat_`), which can be limited to one
//     repository with Contents read/write. Classic `ghp_` tokens are refused
//     (owner decision A26 / tasks 0.2 default) because they cannot.
//   - Stored ONLY in the Keychain: generic password, service
//     `com.mlcousek.garminfood.vault` (its own, apart from GarminKit's),
//     account `github.token`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
//     and no access group -- the same shape as GarminKit's `KeychainStore`
//     after its 2026-09-21 fix. `ThisDeviceOnly` keeps it out of device
//     backups and off a restored phone; no access group because Keychain
//     Sharing is blocked on a free account.
//   - `VaultToken` never prints itself: `description`, `debugDescription`
//     and its mirror are all "<redacted>", so an accidental
//     `"\(token)"` or `dump(...)` in a log line leaks nothing. Only
//     `authorizationHeaderValue` (used by `GitHubContentsClient` when it
//     builds a request) and `lastFour` (shown in Settings) read it.
//
// Depended on by: GitHubContentsClient (via its credentials provider), the
// app's VaultController. Tests: VaultTokenTests (prefix rules always; the
// Keychain round trip where the macOS runner's Keychain allows it),
// RedactionTests.

import Foundation
import Security

public enum VaultTokenProblem: Error, Equatable, Sendable {
    case empty
    /// A classic `ghp_` token: can't be limited to one repository.
    case classicToken
    /// Another GitHub prefix (`gho_`, `ghu_`, `ghs_`, `ghr_`) or no prefix.
    case notFineGrained
    /// `github_pat_` but not the shape of a real token.
    case malformed
}

public struct VaultToken: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The one accepted prefix.
    public static let fineGrainedPrefix = "github_pat_"
    /// Every GitHub token prefix -- what the backup secret scan looks for
    /// too (FoodLogCore's `BackupSecretPolicy`).
    public static let knownPrefixes = ["github_pat_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_"]

    private let value: String

    /// Validates a pasted token. Surrounding whitespace (a paste often
    /// carries a newline) is trimmed; anything else wrong is refused.
    public init(validating raw: String) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultTokenProblem.empty }
        guard trimmed.hasPrefix(Self.fineGrainedPrefix) else {
            throw trimmed.hasPrefix("ghp_") ? VaultTokenProblem.classicToken : VaultTokenProblem.notFineGrained
        }
        let body = trimmed.dropFirst(Self.fineGrainedPrefix.count)
        guard (20...255).contains(body.count),
              body.unicodeScalars.allSatisfy(Self.isTokenCharacter)
        else { throw VaultTokenProblem.malformed }
        self.value = trimmed
    }

    private static func isTokenCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: return true // 0-9 A-Z a-z _
        default: return false
        }
    }

    /// The last four characters, the only part Settings ever shows.
    public var lastFour: String {
        String(value.suffix(4))
    }

    /// `Bearer <token>` for the `Authorization` header. Internal: only the
    /// client that builds requests reads the raw value.
    var authorizationHeaderValue: String {
        "Bearer \(value)"
    }

    var data: Data { Data(value.utf8) }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "VaultToken(<redacted>)" }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child](), displayStyle: .struct) }
}

public enum VaultTokenStoreError: Error, Equatable, Sendable {
    case writeFailed(status: Int32)
    case readFailed(status: Int32)
    /// The Keychain held something that isn't a valid token any more.
    case storedValueInvalid
}

/// The seam the app and tests share: the real Keychain, or an in-memory
/// store in tests.
public protocol VaultTokenStoring: Sendable {
    func load() throws -> VaultToken?
    func save(_ token: VaultToken) throws
    func delete()
}

public struct VaultTokenStore: VaultTokenStoring {
    public static let defaultService = "com.mlcousek.garminfood.vault"
    public static let account = "github.token"

    private let service: String

    /// `service` is a test seam (a unique name per test run); the app
    /// always uses the default.
    public init(service: String = VaultTokenStore.defaultService) {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    public func save(_ token: VaultToken) throws {
        // Upsert: clear any old value first; "nothing to delete" is fine.
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = token.data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultTokenStoreError.writeFailed(status: status)
        }
    }

    public func load() throws -> VaultToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw VaultTokenStoreError.readFailed(status: status)
        }
        guard let raw = String(data: data, encoding: .utf8),
              let token = try? VaultToken(validating: raw)
        else { throw VaultTokenStoreError.storedValueInvalid }
        return token
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

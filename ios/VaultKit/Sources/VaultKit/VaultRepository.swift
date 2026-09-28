// VaultRepository.swift
//
// Which GitHub repository the vault is, as typed in on the phone
// (add-vault-connection design D10), and the connection settings stored
// under `vault.connection.v1`. No repository is ever compiled into the app:
// this repository is public, and so are its CI logs and build artifacts
// (proposal "Why"). Validation follows GitHub's naming rules closely enough
// that nothing typed here can inject a path segment or a query into the
// request URL `GitHubContentsClient` builds.
//
// `VaultConnectionSettings` is the preferences record (enabled, owner, name,
// branch -- never the token, which is Keychain-only). It travels with
// backups (design D12, owner decision 0.4 default): after a restore on a
// new phone the connection is configured but has no token, and the banner
// asks for it again. Stored as a property-list dictionary rather than JSON
// data so it reads as plain text inside a backup file, where the secret
// scan can see it.
//
// Depended on by: GitHubContentsClient (URL building), the app's
// VaultController (settings screen). Tests: VaultRepositoryTests.

import Foundation

public enum VaultRepositoryProblem: Error, Equatable, Sendable {
    case invalidOwner
    case invalidName
    case invalidBranch
}

public struct VaultRepository: Codable, Equatable, Hashable, Sendable {
    public let owner: String
    public let name: String
    public let branch: String

    public static let defaultBranch = "main"

    /// Validates and builds a repository. Leading/trailing whitespace is
    /// trimmed (a paste often carries it); anything else that is not valid
    /// is refused, never "fixed". An empty branch means `main`.
    public init(owner: String, name: String, branch: String = VaultRepository.defaultBranch) throws {
        let owner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var branch = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.isEmpty { branch = Self.defaultBranch }
        guard Self.isValidOwner(owner) else { throw VaultRepositoryProblem.invalidOwner }
        guard Self.isValidName(name) else { throw VaultRepositoryProblem.invalidName }
        guard Self.isValidBranch(branch) else { throw VaultRepositoryProblem.invalidBranch }
        self.owner = owner
        self.name = name
        self.branch = branch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            owner: try container.decode(String.self, forKey: .owner),
            name: try container.decode(String.self, forKey: .name),
            branch: try container.decodeIfPresent(String.self, forKey: .branch) ?? Self.defaultBranch
        )
    }

    private enum CodingKeys: String, CodingKey {
        case owner, name, branch
    }

    // MARK: - Rules

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: return true
        default: return false
        }
    }

    /// GitHub user/organisation: 1-39 of `[A-Za-z0-9-]`, no leading or
    /// trailing hyphen.
    static func isValidOwner(_ owner: String) -> Bool {
        let scalars = Array(owner.unicodeScalars)
        guard (1...39).contains(scalars.count) else { return false }
        guard scalars.first != "-", scalars.last != "-" else { return false }
        return scalars.allSatisfy { isASCIIAlphanumeric($0) || $0 == "-" }
    }

    /// GitHub repository: 1-100 of `[A-Za-z0-9._-]`, and not `.` or `..`.
    static func isValidName(_ name: String) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard (1...100).contains(scalars.count) else { return false }
        guard name != ".", name != ".." else { return false }
        return scalars.allSatisfy { isASCIIAlphanumeric($0) || $0 == "." || $0 == "_" || $0 == "-" }
    }

    /// A conservative subset of git's ref-name rules: 1-200 of
    /// `[A-Za-z0-9._/-]`, no empty, `.`-leading or `..` segment, no leading
    /// `-` or `/`, no trailing `/` or `.lock`. (Stricter than git, which is
    /// fine: the owner picks the branch, and `main` passes.)
    static func isValidBranch(_ branch: String) -> Bool {
        let scalars = Array(branch.unicodeScalars)
        guard (1...200).contains(scalars.count) else { return false }
        guard scalars.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "." || $0 == "_" || $0 == "/" || $0 == "-" }) else { return false }
        guard !branch.hasPrefix("-"), !branch.hasSuffix(".lock") else { return false }
        let segments = branch.split(separator: "/", omittingEmptySubsequences: false)
        for segment in segments {
            if segment.isEmpty || segment.hasPrefix(".") || segment.contains("..") { return false }
        }
        return true
    }
}

/// The connection's preferences record, `vault.connection.v1` in
/// `UserDefaults` (design D10/D12). `owner`/`name`/`branch` are kept as
/// typed so the settings screen can show a half-finished entry; `repository`
/// is the validated form every request uses.
public struct VaultConnectionSettings: Equatable, Sendable {
    public static let storageKey = "vault.connection.v1"

    public var enabled: Bool
    public var owner: String
    public var name: String
    public var branch: String

    public init(enabled: Bool = false, owner: String = "", name: String = "", branch: String = VaultRepository.defaultBranch) {
        self.enabled = enabled
        self.owner = owner
        self.name = name
        self.branch = branch
    }

    /// The validated repository, or `nil` while the fields aren't valid yet.
    public var repository: VaultRepository? {
        try? VaultRepository(owner: owner, name: name, branch: branch)
    }

    public var isConfigured: Bool { repository != nil }

    /// The property-list form stored in `UserDefaults` (and so in backups).
    public var propertyList: [String: Any] {
        ["enabled": enabled, "owner": owner, "name": name, "branch": branch]
    }

    /// Reads the property-list form; unknown or missing keys fall back to
    /// the defaults, so a newer build's extra keys never break an older one.
    public init(propertyList: [String: Any]) {
        self.init(
            enabled: propertyList["enabled"] as? Bool ?? false,
            owner: propertyList["owner"] as? String ?? "",
            name: propertyList["name"] as? String ?? "",
            branch: propertyList["branch"] as? String ?? VaultRepository.defaultBranch
        )
    }

    public static func load(from defaults: UserDefaults) -> VaultConnectionSettings {
        guard let stored = defaults.dictionary(forKey: storageKey) else { return VaultConnectionSettings() }
        return VaultConnectionSettings(propertyList: stored)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(propertyList, forKey: Self.storageKey)
    }
}

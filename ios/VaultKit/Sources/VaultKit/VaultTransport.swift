// VaultTransport.swift
//
// The seam between everything that reads or writes the vault and HOW it
// reaches the vault (add-vault-connection design D9, spec "Training code
// depends on a transport, not on GitHub"). Paths are hub-relative
// (`projection/projection.v1.json`, `events/ios-.../...`). The GitHub
// implementation prefixes the hub root and talks to the contents API; a
// later iCloud bridge transport (add-mcp-server D2, harden-vault-transport)
// would map the same paths into the bridge folder, and then the phone would
// hold no vault credential at all -- without any change to
// `ConditionalFileSync`, `CreateOnlyFileUploader` or TrainingCore.
//
// The path allow-lists (`VaultPathPolicy`) apply to hub-relative paths, so
// every transport enforces them; `GitHubVaultTransport` does so inside
// `GitHubContentsClient`.
//
// Result types carry the token's expiry when the response reported it, so
// the status can show the countdown (design D10) whichever call saw it last.
//
// Depended on by: ConditionalFileSync, CreateOnlyFileUploader,
// VaultSyncCoordinator, (next) TrainingCore. Tests exercise both this file's
// GitHub implementation and an in-memory one.

import Foundation

public enum VaultFetchOutcome: Equatable, Sendable {
    case fetched(bytes: Data, etag: String?)
    case notModified
    case failed(VaultOutcome)
}

public struct VaultFetchResult: Equatable, Sendable {
    public let outcome: VaultFetchOutcome
    public let tokenExpiresAt: Date?

    public init(_ outcome: VaultFetchOutcome, tokenExpiresAt: Date? = nil) {
        self.outcome = outcome
        self.tokenExpiresAt = tokenExpiresAt
    }

    /// The outcome in status terms (`fetched`/`notModified` are success).
    public var statusOutcome: VaultOutcome {
        switch outcome {
        case .fetched, .notModified: return .success
        case .failed(let outcome): return outcome
        }
    }
}

public enum VaultWriteOutcome: Equatable, Sendable {
    case created
    /// Something already exists at the path (GitHub's 422 for a create).
    case alreadyExists
    case failed(VaultOutcome)
}

public struct VaultWriteResult: Equatable, Sendable {
    public let outcome: VaultWriteOutcome
    public let tokenExpiresAt: Date?

    public init(_ outcome: VaultWriteOutcome, tokenExpiresAt: Date? = nil) {
        self.outcome = outcome
        self.tokenExpiresAt = tokenExpiresAt
    }
}

/// "Test connection" (design D10): the repository, then the projection.
public struct VaultProbeResult: Equatable, Sendable {
    public enum FileState: Equatable, Sendable {
        case found(byteCount: Int)
        /// Reachable repository, no projection yet: information, not an error.
        case notFound
        case failed(VaultOutcome)
    }

    /// `.success` or the failure that stopped the probe.
    public let repository: VaultOutcome
    /// `nil` when the repository step already failed.
    public let projection: FileState?
    public let tokenExpiresAt: Date?

    public init(repository: VaultOutcome, projection: FileState?, tokenExpiresAt: Date?) {
        self.repository = repository
        self.projection = projection
        self.tokenExpiresAt = tokenExpiresAt
    }

    /// The single outcome the status records for this probe.
    public var statusOutcome: VaultOutcome {
        guard repository == .success else { return repository }
        switch projection {
        case .found?, nil: return .success
        case .notFound?: return .fileNotFound
        case .failed(let outcome)?: return outcome
        }
    }
}

public protocol VaultTransport: Sendable {
    /// Reads one hub-relative file, conditionally when `ifNoneMatch` is set.
    func fetch(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult
    /// Creates `file.path` with `file.bytes`; never overwrites.
    func createOnly(_ file: SealedFile) async -> VaultWriteResult
    /// Read-only reachability check for "Test connection".
    func probe() async -> VaultProbeResult
}

/// The GitHub implementation: a thin adapter over `GitHubContentsAPI`,
/// which builds every URL and enforces the path policy.
public struct GitHubVaultTransport: VaultTransport {
    private let api: GitHubContentsAPI

    public init(api: GitHubContentsAPI) {
        self.api = api
    }

    public func fetch(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult {
        await api.getFile(path, ifNoneMatch: ifNoneMatch)
    }

    public func createOnly(_ file: SealedFile) async -> VaultWriteResult {
        await api.createFile(file.path, bytes: file.bytes, message: file.commitMessage)
    }

    public func probe() async -> VaultProbeResult {
        let repository = await api.getRepository()
        guard repository.outcome == .success else {
            return VaultProbeResult(repository: repository.outcome, projection: nil, tokenExpiresAt: repository.tokenExpiresAt)
        }
        let file = await api.getFile(VaultHub.projectionPath, ifNoneMatch: nil)
        let state: VaultProbeResult.FileState
        switch file.outcome {
        case .fetched(let bytes, _): state = .found(byteCount: bytes.count)
        case .notModified: state = .found(byteCount: 0)
        case .failed(.fileNotFound): state = .notFound
        case .failed(let outcome): state = .failed(outcome)
        }
        return VaultProbeResult(repository: .success, projection: state, tokenExpiresAt: file.tokenExpiresAt ?? repository.tokenExpiresAt)
    }
}

// VaultStatus.swift
//
// What the app knows about the vault connection's health, and the pure
// rules that turn it into "may we call GitHub now?" and "does the user need
// a banner?" (add-vault-connection design D6, D10; spec "Failures that need
// the user are loud; everything else is quiet").
//
// Three pieces:
//   - `VaultStatus`: the persisted part (`VaultKit/status.json`): last
//     success, last outcome and when, the loud problem blocking requests,
//     the rate-limit pause, the token's expiry and save date. Device-local
//     state, excluded from backups (design D12).
//   - `VaultConnectionState`: the persisted status plus the inputs that are
//     NOT persisted here (enabled and configured come from the settings,
//     `hasToken` from the Keychain), with the derived `requestGate`,
//     `bannerReason` and `needsAttention`. Pure; table-tested.
//   - `VaultStatusStore`: the actor owning status.json, loaded through
//     `PersistedJSON` like every other store.
//
// A loud outcome blocks every vault request until the user acts -- saves a
// token, edits the repository, or taps "Try again" (`clearAuthBlock`) -- so
// a revoked token does not produce a request per foreground. A rate limit
// blocks until its reset time. Offline, server errors and "no plan data
// yet" never block and never show a banner.
//
// Depended on by: VaultSyncCoordinator, the app's VaultController and
// VaultBannerView. Tests: VaultStatusTests, StoreFixtureTests.

import Foundation
import GarminKit

public struct VaultStatus: Codable, Equatable, Sendable {
    public var lastSuccessAt: Date?
    public var lastOutcome: VaultOutcome?
    public var lastOutcomeAt: Date?
    /// The loud problem that stops vault requests until the user acts.
    public var blockedBy: VaultAuthProblem?
    /// No request is sent before this (a 429 or a rate-limited 403).
    public var rateLimitedUntil: Date?
    /// From the token-expiry header on the last response that carried it.
    public var tokenExpiresAt: Date?
    /// When the current token was saved, shown in Settings.
    public var tokenSavedAt: Date?
    /// Queued vault writes; always 0 until add-training-checkins.
    public var pendingWrites: Int?

    public init(
        lastSuccessAt: Date? = nil,
        lastOutcome: VaultOutcome? = nil,
        lastOutcomeAt: Date? = nil,
        blockedBy: VaultAuthProblem? = nil,
        rateLimitedUntil: Date? = nil,
        tokenExpiresAt: Date? = nil,
        tokenSavedAt: Date? = nil,
        pendingWrites: Int? = nil
    ) {
        self.lastSuccessAt = lastSuccessAt
        self.lastOutcome = lastOutcome
        self.lastOutcomeAt = lastOutcomeAt
        self.blockedBy = blockedBy
        self.rateLimitedUntil = rateLimitedUntil
        self.tokenExpiresAt = tokenExpiresAt
        self.tokenSavedAt = tokenSavedAt
        self.pendingWrites = pendingWrites
    }

    /// Folds one request's outcome into the status. `tokenExpiresAt` is the
    /// expiry the response reported, if any (kept when a response omits it).
    public mutating func record(_ outcome: VaultOutcome, at now: Date, tokenExpiresAt reportedExpiry: Date? = nil) {
        lastOutcome = outcome
        lastOutcomeAt = now
        if let reportedExpiry { tokenExpiresAt = reportedExpiry }
        switch outcome {
        case .success, .fileNotFound, .alreadyExists:
            // GitHub answered and the token worked.
            lastSuccessAt = now
            blockedBy = nil
            rateLimitedUntil = nil
        case .authFailed(let problem):
            blockedBy = problem
        case .rateLimited(let until):
            rateLimitedUntil = until
        case .conflict, .serverError, .offline, .refusedByPolicy, .redirectRefused, .notConfigured, .unexpected, .transportError:
            break
        }
    }

    /// The last outcome, when it was a problem worth showing in Settings.
    public var lastProblem: VaultOutcome? {
        guard let lastOutcome else { return nil }
        switch lastOutcome {
        case .success, .fileNotFound, .alreadyExists: return nil
        default: return lastOutcome
        }
    }
}

/// Why the banner shows (design D10). Only ever while the connection is
/// enabled.
public enum VaultBannerReason: Equatable, Sendable {
    case authProblem(VaultAuthProblem)
    /// Enabled, but no token in this device's Keychain -- typically after a
    /// restore on a new phone.
    case tokenMissing
    /// The token expires in `days` whole days (0 = today or already).
    case tokenExpiring(days: Int)
}

/// Whether a vault request may be sent now, and if not, why.
public enum VaultRequestGate: Equatable, Sendable {
    case allowed
    case disabled
    case notConfigured
    case noToken
    case blockedByAuth(VaultAuthProblem)
    case rateLimited(until: Date)

    public var isAllowed: Bool { self == .allowed }
}

public struct VaultConnectionState: Equatable, Sendable {
    /// Banner from this many days before the token expires (owner decision
    /// A26: the last 14 days).
    public static let expiryWarningDays = 14

    public var enabled: Bool
    public var configured: Bool
    public var hasToken: Bool
    public var status: VaultStatus

    public init(enabled: Bool, configured: Bool, hasToken: Bool, status: VaultStatus) {
        self.enabled = enabled
        self.configured = configured
        self.hasToken = hasToken
        self.status = status
    }

    public func requestGate(now: Date) -> VaultRequestGate {
        guard enabled else { return .disabled }
        guard configured else { return .notConfigured }
        guard hasToken else { return .noToken }
        if let problem = status.blockedBy { return .blockedByAuth(problem) }
        if let until = status.rateLimitedUntil, until > now { return .rateLimited(until: until) }
        return .allowed
    }

    /// Whole days until `tokenExpiresAt` (rounded down, never negative), or
    /// `nil` when the expiry is unknown.
    public func daysUntilTokenExpiry(now: Date) -> Int? {
        guard let expiry = status.tokenExpiresAt else { return nil }
        let seconds = expiry.timeIntervalSince(now)
        return max(0, Int((seconds / 86_400).rounded(.down)))
    }

    /// The banner to show, most urgent first; `nil` when there is none.
    /// Never for offline, rate limits, server errors or "no plan data yet".
    public func bannerReason(now: Date) -> VaultBannerReason? {
        guard enabled else { return nil }
        if configured, !hasToken { return .tokenMissing }
        if let problem = status.blockedBy { return .authProblem(problem) }
        if hasToken, let days = daysUntilTokenExpiry(now: now), days <= Self.expiryWarningDays {
            return .tokenExpiring(days: days)
        }
        return nil
    }

    public func needsAttention(now: Date) -> Bool {
        bannerReason(now: now) != nil
    }
}

public actor VaultStatusStore {
    public static let fileName = "status.json"

    private let fileURL: URL
    private var status = VaultStatus()
    private var loaded = false

    public init(directory: URL = VaultStorage.defaultDirectory()) {
        self.fileURL = directory.appendingPathComponent("status.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load(VaultStatus.self, from: fileURL, decoder: VaultStorage.makeDecoder(), category: VaultLog.category)
        status = result.value ?? VaultStatus()
        loaded = !result.isUnreadable
    }

    public func current() -> VaultStatus {
        loadIfNeeded()
        return status
    }

    /// Applies `change` and persists the result; the in-memory copy changes
    /// only once the write succeeded.
    @discardableResult
    public func update(_ change: (inout VaultStatus) -> Void) throws -> VaultStatus {
        loadIfNeeded()
        var updated = status
        change(&updated)
        guard updated != status else { return status }
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: VaultLog.category)
        try VaultStorage.write(try VaultStorage.makeEncoder().encode(updated), to: fileURL)
        status = updated
        return updated
    }

    /// `record` + persist. A failed write is logged, never thrown: status
    /// is bookkeeping, and the request it describes already happened.
    @discardableResult
    public func record(_ outcome: VaultOutcome, at now: Date, tokenExpiresAt: Date?) -> VaultStatus {
        do {
            return try update { $0.record(outcome, at: now, tokenExpiresAt: tokenExpiresAt) }
        } catch {
            VaultLog.log(.warning, "status could not be saved (\(type(of: error)))")
            loadIfNeeded()
            return status
        }
    }

    /// The user acted (saved a token, edited the repository, tapped "Try
    /// again"): lift a loud block so the next request may go out.
    public func clearAuthBlock() throws {
        try update { $0.blockedBy = nil }
    }

    /// Disconnect (design D3): forget everything about the connection.
    public func reset() throws {
        loadIfNeeded()
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: VaultLog.category)
        try VaultStorage.write(try VaultStorage.makeEncoder().encode(VaultStatus()), to: fileURL)
        status = VaultStatus()
    }
}

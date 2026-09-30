// VaultSetupRefresh.swift
//
// When finishing the vault setup starts the first projection fetch
// (polish-training-today design D1). Before this, saving the repository,
// the token or turning the switch on only re-read local state: the first
// fetch waited for the next foreground, pull to refresh or "Try again", so
// a freshly configured owner could open Today or Plan and sit on
// "Fetching your plan..." indefinitely.
//
// Pure and in the package (not the app) so the rule is tested without a
// Mac: the app's VaultController asks `request(_:before:after:hasSynced:)`
// after each settings action and a successful "Test connection", launches
// ONE unstructured refresh when it answers true, and calls `finish()` when
// that refresh is over. The rule:
//
//   - nothing unless the connection is now usable (on, configured, token);
//   - the switch turned on: fetch when that made it usable, or when it has
//     never synced;
//   - a repository or token saved: fetch (new credentials, new answer);
//   - a successful test: fetch only when it has never synced;
//   - one at a time: a credential change while a fetch runs is coalesced
//     into exactly one follow-up (the running fetch may have used the old
//     credentials); anything else while one runs is dropped.
//
// The fetch itself still goes through `VaultSyncCoordinator`, so its gate
// (loud blocks, rate limits) is never bypassed.
//
// Depended on by: the app's VaultController. Tests: VaultSetupRefreshTests,
// and TrainingCore's SetupRefreshTests (the whole chain to the cached
// projection).

import Foundation

public extension VaultSyncInputs {
    /// On, with a repository and a token: a request may be built.
    var isUsable: Bool { enabled && configured && hasToken }
}

public struct VaultSetupRefresh: Equatable, Sendable {
    /// The settings action that just completed.
    public enum Trigger: Equatable, Sendable {
        case switchedOn
        case repositorySaved
        case tokenSaved
        case testSucceeded

        var changesCredentials: Bool {
            self == .repositorySaved || self == .tokenSaved
        }
    }

    /// A setup fetch has been started and not finished.
    public private(set) var isRunning = false
    private var needsFollowUp = false

    public init() {}

    /// Whether to start a setup fetch now. `before`/`after` are the inputs
    /// around the action; `hasSynced` is whether any fetch ever succeeded
    /// (`VaultStatus.lastSuccessAt != nil`).
    public mutating func request(_ trigger: Trigger, before: VaultSyncInputs, after: VaultSyncInputs, hasSynced: Bool) -> Bool {
        guard after.isUsable else { return false }
        let wanted: Bool
        switch trigger {
        case .switchedOn:
            wanted = !before.isUsable || !hasSynced
        case .repositorySaved, .tokenSaved:
            wanted = true
        case .testSucceeded:
            wanted = !hasSynced
        }
        guard wanted else { return false }
        if isRunning {
            if trigger.changesCredentials { needsFollowUp = true }
            return false
        }
        isRunning = true
        return true
    }

    /// The running setup fetch is over. `true`: start the one coalesced
    /// follow-up now (still running afterwards).
    public mutating func finish() -> Bool {
        guard isRunning else { return false }
        if needsFollowUp {
            needsFollowUp = false
            return true
        }
        isRunning = false
        return false
    }

    /// Disconnect: forget any pending follow-up.
    public mutating func reset() {
        isRunning = false
        needsFollowUp = false
    }
}

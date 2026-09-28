// VaultSyncCoordinator.swift
//
// When the app talks to GitHub, and what it records afterwards
// (add-vault-connection design D6, D11). Pure orchestration over the other
// VaultKit pieces, in the package (not the app) so every rule is tested:
//
//   refreshProjection  foreground / pull to refresh. Only while the
//                      connection is enabled, configured, has a token and is
//                      not blocked by a loud outcome or a rate limit; at most
//                      once per 60 s unless forced (pull to refresh); one at
//                      a time. One conditional GET of the projection through
//                      ConditionalFileSync. A 404 on the file is followed,
//                      the first time, by the probe's repository GET, to
//                      tell "no plan data yet" (quiet) from "repository not
//                      found" (loud).
//   testConnection     the Settings button: lifts a loud block (the user
//                      acted), probes read-only, records the result, and on
//                      a reachable repository creates the device identity
//                      (design D5). Never writes to the repository.
//   disconnect         clears the fetch cache and the status (the token is
//                      the app's to delete; the device identity is kept).
//
// Every call records its outcome (and the token expiry, when reported) in
// `VaultStatusStore`, which is what the banner and Settings read.
//
// The app launches `refreshProjection` unstructured, so nothing on screen
// ever waits for it, and never from a confirm or save path.
//
// Depended on by: the app's VaultController. Tests: VaultSyncCoordinatorTests.

import Foundation

/// The inputs that live outside VaultKit's files: the settings switch and
/// fields, and whether the Keychain holds a token.
public struct VaultSyncInputs: Equatable, Sendable {
    public var enabled: Bool
    public var configured: Bool
    public var hasToken: Bool

    public init(enabled: Bool, configured: Bool, hasToken: Bool) {
        self.enabled = enabled
        self.configured = configured
        self.hasToken = hasToken
    }
}

public enum VaultRefreshSkip: Equatable, Sendable {
    case gate(VaultRequestGate)
    /// Less than the minimum interval since the last automatic refresh.
    case tooSoon
    case alreadyRunning
}

public enum VaultRefreshReport: Equatable, Sendable {
    case skipped(VaultRefreshSkip)
    case ran(FetchReport)
}

public struct VaultConnectionTestResult: Equatable, Sendable {
    /// `nil` when the test could not run (not configured, no token).
    public let probe: VaultProbeResult?
    public let gate: VaultRequestGate
    public let deviceID: VaultDeviceID?
}

public actor VaultSyncCoordinator {
    public static let minimumRefreshInterval: TimeInterval = 60

    private let transport: VaultTransport
    private let fetchSync: ConditionalFileSync
    private let statusStore: VaultStatusStore
    private let identityStore: DeviceIdentityStore
    private let minimumInterval: TimeInterval
    private var lastRefreshAt: Date?
    private var isRefreshing = false

    public init(
        transport: VaultTransport,
        fetchSync: ConditionalFileSync,
        statusStore: VaultStatusStore,
        identityStore: DeviceIdentityStore,
        minimumInterval: TimeInterval = VaultSyncCoordinator.minimumRefreshInterval
    ) {
        self.transport = transport
        self.fetchSync = fetchSync
        self.statusStore = statusStore
        self.identityStore = identityStore
        self.minimumInterval = minimumInterval
    }

    public func connectionState(_ inputs: VaultSyncInputs) async -> VaultConnectionState {
        VaultConnectionState(enabled: inputs.enabled, configured: inputs.configured, hasToken: inputs.hasToken, status: await statusStore.current())
    }

    /// See this file's header. `force` is pull to refresh: it skips the
    /// interval, never the gate.
    public func refreshProjection(
        _ inputs: VaultSyncInputs,
        force: Bool = false,
        now: Date = Date(),
        validate: @Sendable (Data) throws -> Void
    ) async -> VaultRefreshReport {
        let state = await connectionState(inputs)
        let gate = state.requestGate(now: now)
        guard gate.isAllowed else { return .skipped(.gate(gate)) }
        guard !isRefreshing else { return .skipped(.alreadyRunning) }
        if !force, let last = lastRefreshAt, now.timeIntervalSince(last) < minimumInterval {
            return .skipped(.tooSoon)
        }
        isRefreshing = true
        lastRefreshAt = now
        defer { isRefreshing = false }

        let path = VaultHub.projectionPath
        let result = await fetchSync.refresh(path, now: now, validate: validate)
        var outcome = result.statusOutcome
        var expiry = result.tokenExpiresAt

        if case .failed(.fileNotFound) = result.report, state.status.lastOutcome != .fileNotFound {
            // design D6: tell a missing repository from a missing file.
            let probe = await transport.probe()
            outcome = probe.statusOutcome
            expiry = probe.tokenExpiresAt ?? expiry
        }
        await statusStore.record(outcome, at: now, tokenExpiresAt: expiry)
        return .ran(result.report)
    }

    /// "Test connection" (design D10). Read-only.
    public func testConnection(_ inputs: VaultSyncInputs, now: Date = Date()) async -> VaultConnectionTestResult {
        guard inputs.configured else {
            return VaultConnectionTestResult(probe: nil, gate: .notConfigured, deviceID: await identityStore.currentID())
        }
        guard inputs.hasToken else {
            return VaultConnectionTestResult(probe: nil, gate: .noToken, deviceID: await identityStore.currentID())
        }
        // The user tapped the button: that is the action a loud block waits for.
        try? await statusStore.clearAuthBlock()
        let probe = await transport.probe()
        await statusStore.record(probe.statusOutcome, at: now, tokenExpiresAt: probe.tokenExpiresAt)
        var deviceID = await identityStore.currentID()
        if probe.repository == .success, deviceID == nil {
            do {
                deviceID = try await identityStore.ensureIdentity(now: now).deviceId
            } catch {
                VaultLog.log(.error, "device identity could not be created (\(type(of: error)))")
            }
        }
        VaultLog.log(probe.statusOutcome.isLoud ? .error : .info, "test connection: \(probe.statusOutcome.logLabel)")
        let gate = await connectionState(inputs).requestGate(now: now)
        return VaultConnectionTestResult(probe: probe, gate: gate, deviceID: deviceID)
    }

    /// The user changed the token or the repository, or tapped "Try again".
    public func userActed() async {
        try? await statusStore.clearAuthBlock()
        lastRefreshAt = nil
    }

    /// Disconnect (design D3): forget the cached copy and the status. The
    /// device identity stays, so reconnecting keeps writing into the same
    /// folder.
    public func disconnect() async throws {
        try await fetchSync.clear()
        try await statusStore.reset()
        lastRefreshAt = nil
        VaultLog.log(.info, "disconnected; cache and status cleared")
    }
}

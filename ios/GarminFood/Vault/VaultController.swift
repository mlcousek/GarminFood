// VaultController.swift
//
// What the vault screens show and the actions they take
// (add-vault-connection tasks 4.2-4.5, design D10/D11). A thin
// `@MainActor @Observable` layer over `VaultServices`: every rule --
// when a request may go out, when the banner shows, what a response means
// -- lives in VaultKit (`VaultSyncCoordinator`, `VaultConnectionState`) and
// is tested there. This only holds the latest snapshot for SwiftUI and
// turns taps into coordinator calls.
//
// Local-first: `refreshInBackground` launches the foreground fetch in an
// unstructured task, so no screen and no confirm/save path ever waits on
// GitHub. The fetch runs only on Garmin-connected installs (the caller
// passes `allowed`; standalone installs never see the vault, owner decision
// A26 / tasks 0.3) and only while the connection is on.
//
// The token is read from the Keychain to answer "is there one?" and to
// show its last four characters; it is never stored in a property.
//
// add-training-today-and-plan task 4.1: the refresh validates with
// TrainingCore's decoder (`ProjectionStore.validate`), so an invalid or
// too-new projection never replaces the last good one; the report is
// folded into the store and `onProjectionRefresh` lets TrainingModel
// rebuild what Today and Plan show.
//
// polish-training-today D1: finishing the setup (the switch on, a
// repository or token saved, a successful "Test connection") starts the
// first fetch itself, once, through VaultKit's `VaultSetupRefresh` rule --
// before, only a later foreground, pull to refresh or "Try again" did, so a
// configured owner could sit on "Fetching your plan..." indefinitely.
// `isSyncingPlan` and `lastSetupReport` show its progress in Settings.
//
// Owned by AppEnvironment (`environment.vault`). Depends on VaultServices.

import Foundation
import Observation
import GarminKit
import VaultKit
import TrainingCore

@MainActor
@Observable
final class VaultController {
    private(set) var settings: VaultConnectionSettings
    private(set) var status = VaultStatus()
    private(set) var hasToken = false
    private(set) var tokenLastFour: String?
    private(set) var deviceID: VaultDeviceID?
    private(set) var lastTest: VaultConnectionTestResult?
    private(set) var isTesting = false
    /// polish-training-today D1: the setup fetch is running.
    private(set) var isSyncingPlan = false
    /// The setup fetch's answer, for Settings' status row.
    private(set) var lastSetupReport: VaultRefreshReport?

    @ObservationIgnored private let services: VaultServices
    @ObservationIgnored private let defaults: UserDefaults
    /// Called on the main actor after every projection refresh and after a
    /// disconnect (AppEnvironment wires it to `TrainingModel.reload`).
    @ObservationIgnored var onProjectionRefresh: (@MainActor () async -> Void)?
    /// Whether this install may talk to the vault at all (Garmin-connected,
    /// out of onboarding); AppEnvironment wires it (owner decision A26).
    @ObservationIgnored var isRefreshAllowed: @MainActor () -> Bool = { true }
    @ObservationIgnored private var setupRefresh = VaultSetupRefresh()

    init(services: VaultServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        self.settings = VaultConnectionSettings.load(from: defaults)
        readToken()
    }

    // MARK: - Derived

    var inputs: VaultSyncInputs {
        VaultSyncInputs(enabled: settings.enabled, configured: settings.isConfigured, hasToken: hasToken)
    }

    var connectionState: VaultConnectionState {
        VaultConnectionState(enabled: settings.enabled, configured: settings.isConfigured, hasToken: hasToken, status: status)
    }

    /// The loud banner's reason right now, or `nil` (design D10).
    func bannerReason(now: Date = Date()) -> VaultBannerReason? {
        connectionState.bannerReason(now: now)
    }

    // MARK: - Loading

    /// Re-reads settings, the Keychain, the status and the device id.
    func reload() async {
        settings = VaultConnectionSettings.load(from: defaults)
        readToken()
        status = await services.statusStore.current()
        deviceID = await services.identityStore.currentID()
    }

    /// A Keychain read that fails (e.g. before first unlock) keeps the
    /// previous answer rather than claiming the token is gone.
    private func readToken() {
        do {
            let token = try services.tokenStore.load()
            hasToken = token != nil
            tokenLastFour = token?.lastFour
        } catch {
            VaultLog.log(.warning, "token could not be read from the Keychain (\(type(of: error)))")
        }
    }

    // MARK: - Foreground refresh (design D11)

    /// One conditional GET of the projection, never awaited by the caller.
    /// `force` is pull to refresh (skips the 60 s interval, never the gate).
    func refreshInBackground(force: Bool, allowed: Bool) {
        guard allowed, settings.enabled else { return }
        let store = services.projectionStore
        let coordinator = services.coordinator
        let inputs = self.inputs
        Task { [weak self] in
            // add-training-today-and-plan D5: TrainingCore's decoder is the
            // validator (header gates + the full v1 decode, 5 MB cap).
            await store.refresh(via: coordinator, inputs: inputs, force: force)
            await self?.reload()
            await self?.onProjectionRefresh?()
        }
    }

    // MARK: - Setup fetch (polish-training-today D1)

    /// After a settings action: start the first fetch when VaultKit's rule
    /// says so. Unstructured; the action never waits for GitHub.
    private func requestSetupRefresh(_ trigger: VaultSetupRefresh.Trigger, before: VaultSyncInputs) {
        guard isRefreshAllowed() else { return }
        let hasSynced = status.lastSuccessAt != nil
        guard setupRefresh.request(trigger, before: before, after: inputs, hasSynced: hasSynced) else { return }
        runSetupRefresh()
    }

    private func runSetupRefresh() {
        isSyncingPlan = true
        lastSetupReport = nil
        VaultLog.log(.info, "setup finished: first projection fetch")
        let store = services.projectionStore
        let coordinator = services.coordinator
        let inputs = self.inputs
        Task { [weak self] in
            let report = await store.refresh(via: coordinator, inputs: inputs, force: true)
            guard let self else { return }
            await self.reload()
            self.lastSetupReport = report
            await self.onProjectionRefresh?()
            if self.setupRefresh.finish() {
                self.runSetupRefresh()
            } else {
                self.isSyncingPlan = false
            }
        }
    }

    // MARK: - Settings actions

    func setEnabled(_ enabled: Bool) async {
        let before = inputs
        var updated = VaultConnectionSettings.load(from: defaults)
        updated.enabled = enabled
        updated.save(to: defaults)
        VaultLog.log(.info, enabled ? "connection turned on" : "connection turned off")
        if enabled { await services.coordinator.userActed() }
        await reload()
        if enabled { requestSetupRefresh(.switchedOn, before: before) }
    }

    /// Validates and saves the repository; `nil` on success. Never logs the
    /// owner or the name.
    func saveRepository(owner: String, name: String, branch: String) async -> VaultRepositoryProblem? {
        let repository: VaultRepository
        do {
            repository = try VaultRepository(owner: owner, name: name, branch: branch)
        } catch let problem as VaultRepositoryProblem {
            return problem
        } catch {
            return .invalidName
        }
        let before = inputs
        var updated = VaultConnectionSettings.load(from: defaults)
        updated.owner = repository.owner
        updated.name = repository.name
        updated.branch = repository.branch
        updated.save(to: defaults)
        VaultLog.log(.info, "repository settings saved")
        // The user acted: lift a loud block (design D6).
        await services.coordinator.userActed()
        await reload()
        requestSetupRefresh(.repositorySaved, before: before)
        return nil
    }

    enum TokenSaveError: Error, Equatable {
        case invalid(VaultTokenProblem)
        case keychain
    }

    /// Validates and stores a pasted token; `nil` on success.
    func saveToken(_ raw: String) async -> TokenSaveError? {
        let token: VaultToken
        do {
            token = try VaultToken(validating: raw)
        } catch let problem as VaultTokenProblem {
            return .invalid(problem)
        } catch {
            return .invalid(.malformed)
        }
        let before = inputs
        do {
            try services.tokenStore.save(token)
        } catch {
            VaultLog.log(.error, "token could not be saved to the Keychain (\(type(of: error)))")
            return .keychain
        }
        let now = Date()
        _ = try? await services.statusStore.update { status in
            status.tokenSavedAt = now
            // A new token: the old one's expiry no longer applies.
            status.tokenExpiresAt = nil
        }
        VaultLog.log(.info, "token saved")
        await services.coordinator.userActed()
        await reload()
        requestSetupRefresh(.tokenSaved, before: before)
        return nil
    }

    func removeToken() async {
        services.tokenStore.delete()
        _ = try? await services.statusStore.update { status in
            status.tokenSavedAt = nil
            status.tokenExpiresAt = nil
        }
        VaultLog.log(.info, "token removed")
        await reload()
    }

    /// "Test connection" (design D10): read-only; creates the device id on
    /// the first success.
    func testConnection() async {
        guard !isTesting else { return }
        isTesting = true
        defer { isTesting = false }
        readToken()
        let result = await services.coordinator.testConnection(inputs)
        lastTest = result
        await reload()
        if result.probe?.repository == .success {
            requestSetupRefresh(.testSucceeded, before: inputs)
        }
    }

    /// The banner's and Settings' "Try again" after a loud problem.
    func tryAgain() async {
        await services.coordinator.userActed()
        await reload()
        refreshInBackground(force: true, allowed: true)
    }

    /// Disconnect (design D3): token deleted, cache and status cleared,
    /// switch off; the device id stays.
    func disconnect() async {
        services.tokenStore.delete()
        do {
            try await services.coordinator.disconnect()
        } catch {
            VaultLog.log(.warning, "disconnect could not clear everything (\(type(of: error)))")
        }
        var updated = VaultConnectionSettings.load(from: defaults)
        updated.enabled = false
        updated.save(to: defaults)
        lastTest = nil
        setupRefresh.reset()
        lastSetupReport = nil
        await services.projectionStore.clear()
        await reload()
        await onProjectionRefresh?()
    }
}

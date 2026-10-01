// TrainingEventsService.swift
//
// The app's one recorder of training events (add-training-checkins design
// D3, D4, D7) -- the process-wide owner of TrainingCore's
// `TrainingRecorder`, its local log and VaultKit's write queue, exactly
// one instance per process like `VaultServices` (two queue actors over one
// file would lose writes).
//
// Who calls it:
//   - TrainingModel's actions (Today's check-in and habit toggles, the
//     session detail's RPE and note);
//   - the lock-screen Controls, through `MorningCheckInControlAction.handler`
//     (Shared/MorningCheckInIntents.swift), which `GarminFoodApp.init()`
//     points at `handleControlCheckIn` before any scene exists: the
//     Controls' intent runs in the app's process (`openAppWhenRun`), but
//     Shared/ is compiled into the widget too and can't import TrainingCore.
//     A Control records the light only; afterwards `onControlCheckIn`
//     brings Today's today forward, where the pain step asks the rest
//     (add-checkin-pain-score D7).
//
// Rules:
//   - Recording is local and durable; nothing awaits the network. It
//     refuses when the vault connection is off, unconfigured, the install is
//     standalone, or it has no device id yet ("Test connection" never
//     succeeded).
//   - Delivery (`drainNow`) runs only when VaultKit's request gate is open
//     (enabled, configured, token, no loud block, not rate limited), on
//     foreground and backgrounding (AppEnvironment) and 120 s after an
//     action (debounced, tasks 0.3). A rate limit is recorded in the vault
//     status; an auth stop forces a projection refresh, whose response
//     names the exact loud problem for the banner.
//   - Settings -> Vault's "Pending writes" is the count of events not yet
//     uploaded (`VaultStatus.pendingWrites`).
//
// App target only. Depends on VaultServices, TrainingCore.

import Foundation
import FoodLogCore
import VaultKit
import TrainingCore

@MainActor
final class TrainingEventsService {
    static let shared = TrainingEventsService()

    /// Seconds between an action and its delivery (tasks 0.3, defaulted).
    static let deliveryDelay: Double = 120

    let recorder: TrainingRecorder
    private let services: VaultServices
    private var drainTask: Task<Void, Never>?
    private var isDraining = false

    /// Set by TrainingModel: the phone's events changed (reload the overlay).
    var onChange: (@MainActor () async -> Void)?
    /// Set by AppEnvironment: a drain stopped on auth; refresh the
    /// projection so the vault banner names the problem.
    var onAuthStop: (@MainActor () -> Void)?
    /// Set by AppEnvironment (add-checkin-pain-score D7): a Control's
    /// check-in was recorded; show Today's today, where the pain step
    /// waits (the Controls stay light-only).
    var onControlCheckIn: (@MainActor () -> Void)?

    enum RecordError: Error, LocalizedError, Equatable {
        case vaultOff
        case notTested

        var errorDescription: String? {
            switch self {
            case .vaultOff:
                return String(localized: "Nothing recorded: turn on the vault connection first.", comment: "Training check-in error: the vault connection is off.")
            case .notTested:
                return String(localized: "Nothing recorded: test the vault connection in Settings first.", comment: "Training check-in error: the vault connection has no device id yet.")
            }
        }
    }

    private init() {
        let services = VaultServices.shared
        self.services = services
        self.recorder = TrainingRecorder(
            log: TrainingEventLog.make(),
            identity: services.identityStore,
            queue: VaultWriteQueue.make()
        )
    }

    // MARK: Guards

    /// The connection is on, configured, and this is a Garmin-connected
    /// install (standalone installs never talk to the vault).
    func isConnectionOn() -> Bool {
        let settings = VaultConnectionSettings.load(from: .standard)
        return settings.enabled && settings.isConfigured && AppServices.currentDataMode() == .garminConnected
    }

    /// Whether Today and the detail may offer recording.
    func canRecord() async -> Bool {
        guard isConnectionOn() else { return false }
        return await recorder.hasDeviceIdentity()
    }

    // MARK: Recording

    /// Records `payload` on the phone (durable on return), then schedules
    /// delivery and tells the screens.
    func record(_ payload: HubEventPayload) async throws {
        guard isConnectionOn() else { throw RecordError.vaultOff }
        do {
            try await recorder.record(payload)
        } catch TrainingRecorderError.noDeviceIdentity {
            throw RecordError.notTested
        }
        await updatePendingCount()
        scheduleDrain()
        await onChange?()
    }

    /// The Controls' check-in: today's training day and session from the
    /// cached plan (no network), recorded like a tap on Today.
    func handleControlCheckIn(_ rawLight: String) async throws {
        guard let light = MorningLight(rawValue: rawLight) else {
            throw MorningCheckInControlAction.ActionError.notAvailable
        }
        let cached = await services.projectionStore.loadCached()
        let payload = CheckInPlanning.morningCheckIn(
            light: light,
            projection: cached?.projection,
            now: Date(),
            deviceTimeZone: .current
        )
        do {
            try await record(.morningCheckIn(payload))
            onControlCheckIn?()
        } catch RecordError.vaultOff {
            throw MorningCheckInControlAction.ActionError.vaultOff
        } catch RecordError.notTested {
            throw MorningCheckInControlAction.ActionError.notTested
        }
    }

    // MARK: Delivery

    /// Delivery `deliveryDelay` seconds from now; a newer action restarts
    /// the wait, so a burst of ticks becomes one file.
    func scheduleDrain(after seconds: Double = TrainingEventsService.deliveryDelay) {
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.drainNow()
        }
    }

    /// Seal and upload now, if the connection's gate is open.
    func drainNow() async {
        guard !isDraining, isConnectionOn() else { return }
        isDraining = true
        defer { isDraining = false }

        let settings = VaultConnectionSettings.load(from: .standard)
        let tokenStore = services.tokenStore
        let hasToken: Bool = {
            do { return try tokenStore.load() != nil } catch { return false }
        }()
        let inputs = VaultSyncInputs(enabled: settings.enabled, configured: settings.isConfigured, hasToken: hasToken)
        let now = Date()
        let gate = await services.coordinator.connectionState(inputs).requestGate(now: now)
        guard gate.isAllowed else {
            await updatePendingCount()
            return
        }

        let result = await recorder.drain(transport: services.transport, now: now)
        if !result.delivered.isEmpty {
            await services.statusStore.record(.success, at: now, tokenExpiresAt: nil)
        }
        switch result.stoppedBy {
        case .rateLimited(let until)?:
            await services.statusStore.record(.rateLimited(until: until), at: now, tokenExpiresAt: nil)
        case .auth?:
            onAuthStop?()
        case .offline?, nil:
            break
        }
        await updatePendingCount()
        await onChange?()
    }

    // MARK: Failed writes (Settings -> Vault, add-training-checkins 4.9)

    /// Segments the queue gave up on; they wait until retried by hand.
    func failedWrites() async -> [FailedWrite] {
        await recorder.failedWrites()
    }

    /// The user's Retry: makes the segment pending again and delivers now
    /// (if the connection's gate is open; otherwise on the next drain).
    func retryFailedWrite(_ id: UUID) async {
        do {
            try await recorder.retryFailedWrite(id: id)
        } catch {
            VaultLog.log(.warning, "training events: retry not saved (\(type(of: error)))")
        }
        await drainNow()
        await updatePendingCount()
    }

    private func updatePendingCount() async {
        let waiting = await recorder.waitingCount()
        do {
            try await services.statusStore.update { $0.pendingWrites = waiting }
        } catch {
            VaultLog.log(.warning, "training events: pending count not saved (\(type(of: error)))")
        }
    }
}

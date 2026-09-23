// OfflineIndexLoader.swift
//
// The app's side of the Czech offline food database
// (add-offline-czech-food-index tasks 3.4-3.5). FoodLogCore's
// `OfflineIndexStore` does the real work: the daily manifest check, the
// Wi-Fi-only download, SHA-256 verification and the atomic swap. This
// class only:
//   - runs it at launch and on every foreground, in an unstructured task,
//     so nothing on screen waits for it. Search keeps working from the
//     installed index, or without one, meanwhile;
//   - runs it forced from Settings' "Download now";
//   - republishes the store's status for SettingsView's row. It is
//     @Observable, so the row updates when a download finishes.
// Failures are never modal. They show in the Settings row and go to
// DiagnosticsLog (the store logs them).
//
// Owned by AppEnvironment. Depends on AppServices' store and on
// AppPreferences' cellular switch.

import Foundation
import Observation
import FoodLogCore

@MainActor
@Observable
final class OfflineIndexLoader {
    private(set) var status = OfflineIndexStatus()
    private(set) var isUpdating = false
    /// The last "Download now" result, shown under the row until the next one.
    private(set) var lastManualOutcome: OfflineIndexUpdateOutcome?

    @ObservationIgnored private let store: OfflineIndexStore
    @ObservationIgnored private let preferences: AppPreferences

    init(store: OfflineIndexStore, preferences: AppPreferences) {
        self.store = store
        self.preferences = preferences
    }

    /// Launch and foreground: decode the installed index (on the store's
    /// actor, off the main thread) so search can use it, then the
    /// at-most-daily update check.
    func loadAndCheckIfDue() async {
        await store.loadInstalledIndexIfNeeded()
        status = await store.currentStatus()
        await runCheck(force: false)
    }

    /// Settings' "Download now": skips the 24 h throttle, still honours the
    /// cellular switch.
    func downloadNow() async {
        lastManualOutcome = nil
        lastManualOutcome = await runCheck(force: true)
    }

    /// Re-reads the status (e.g. when Settings appears).
    func refreshStatus() async {
        status = await store.currentStatus()
    }

    @discardableResult
    private func runCheck(force: Bool) async -> OfflineIndexUpdateOutcome {
        guard !isUpdating else { return .alreadyRunning }
        isUpdating = true
        defer { isUpdating = false }
        let outcome = await store.checkForUpdate(force: force, allowsCellular: preferences.offlineIndexAllowsCellular)
        status = await store.currentStatus()
        return outcome
    }
}

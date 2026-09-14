// AppEnvironment.swift
//
// The app's composition root: one place that owns every GarminKit/FoodLogCore
// object the UI needs, so views themselves stay thin and previewable
// (openspec/config.yaml's "clear module boundaries" + "previewable SwiftUI
// views" principles). `@Observable` (not `ObservableObject`) to match
// GarminKit's own `GarminAuthState`, which already commits this app to the
// Observation framework rather than mixing it with Combine's
// `ObservableObject`.
//
// Also owns the two pieces of app-lifecycle integration
// add-garmin-auth-and-sync's own tasks.md explicitly deferred to "Phase 2":
//   - task 11.1: wiring `GarminAuthState` to actual UI (see
//     `AuthBannerView.swift`, which reads `authState` from this object).
//   - task 9.5: draining the outbox "on foreground" (BGAppRefreshTask
//     registration itself is NOT done here -- see `refreshOnForeground()`'s
//     doc comment).

import Foundation
import Observation
import GarminKit
import FoodLogCore

@MainActor
@Observable
final class AppEnvironment {
    let garminClient: GarminClient
    let authState: GarminAuthState
    let outbox: Outbox
    let reconciliation: Reconciliation
    let usageHistory: UsageHistoryStore
    let servingDefaults: ServingDefaultStore
    let customFoodStore: CustomFoodStore
    let foodCache: FoodCacheStore
    let catalogSearch: FoodCatalogSearch
    let logEntryCoordinator: LogEntryCoordinator

    /// Non-nil while a foreground drain is in flight, purely so the UI can
    /// show a subtle "syncing" indicator rather than nothing at all -- never
    /// gates any user action, since per the food-log-entry spec confirming
    /// an entry must never wait on this.
    private(set) var isDraining = false

    init() {
        let client = GarminClient()
        let outbox = Outbox(processName: "app")
        let usageHistory = UsageHistoryStore()
        let servingDefaults = ServingDefaultStore()
        let foodCache = FoodCacheStore()

        self.garminClient = client
        self.authState = GarminAuthState()
        self.outbox = outbox
        self.reconciliation = Reconciliation(outbox: outbox)
        self.usageHistory = usageHistory
        self.servingDefaults = servingDefaults
        self.customFoodStore = CustomFoodStore()
        self.foodCache = foodCache
        self.catalogSearch = FoodCatalogSearch(searcher: client, foodCache: foodCache)
        self.logEntryCoordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults)
    }

    /// Called once on launch and again every time the app returns to the
    /// foreground (`ContentView`'s `.onChange(of: scenePhase)`). Refreshes
    /// auth state, then makes ONE best-effort attempt to drain and
    /// reconcile this process's own outbox.
    ///
    /// Deliberately NOT wired to `BGAppRefreshTask` -- that half of task 9.5
    /// (background execution while the app isn't even open) needs Info.plist
    /// registration and a `BGTaskScheduler` submission/handler pair this
    /// phase did not build, since it's meaningfully more surface area to get
    /// right without a device to test background wake-ups on. This covers
    /// only the "on foreground" half explicitly, and is a strict addition on
    /// top of what already existed -- delivery still also happens
    /// opportunistically right after a confirm (see
    /// `LogEntryConfirmView.swift`).
    func refreshOnForeground() async {
        await authState.refresh()
        await drainAndReconcile()
    }

    /// Fire-and-forget from a confirm action (never awaited by the confirm
    /// flow itself -- see `LogEntryConfirmView.swift` -- so this can never
    /// reintroduce a network wait into the log-entry-flow spec's "commits
    /// without waiting on the network" requirement).
    func drainAndReconcile() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        let result = await outbox.drain(using: garminClient)
        if !result.delivered.isEmpty {
            _ = await reconciliation.reconcile(delivered: result.delivered, using: garminClient)
        }
        switch result.authOutcome {
        case .longLivedTokenExpired:
            authState.report(GarminAuthError.longLivedTokenExpired)
        case .notSignedIn:
            authState.report(GarminAuthError.notSignedIn)
        case .none:
            break
        }
        let pending = await outbox.pendingCount()
        authState.updatePendingCount(pending)
    }
}

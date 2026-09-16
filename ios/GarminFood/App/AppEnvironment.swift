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
//
// `gamificationEngine` (add-gamification) is initialized here for the same
// reason everything else is: one composition root, thin views. See
// GamificationEngine.swift for why it is its own type rather than more
// properties/methods bolted directly onto this class.

import Foundation
import Observation
import GarminKit
import FoodLogCore
import Gamification

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
    /// The Czech (Open Food Facts) search source (add-czech-food-catalog) --
    /// a completely separate network client from `garminClient`/
    /// `catalogSearch`, per proposal.md's "two sources, never silently
    /// merged" design. See `FoodCatalogView`'s Czech results section.
    let openFoodFactsClient: OpenFoodFactsClient
    let logEntryCoordinator: LogEntryCoordinator
    let gamificationEngine: GamificationEngine
    /// Today's consumed-vs-goal calories for the home hero (HomeView /
    /// TodayHeroView). Refreshed on every foreground alongside everything
    /// else; see TodaySummary.swift for its last-known-good semantics.
    let todaySummary: TodaySummaryLoader

    /// Non-nil while a foreground drain is in flight, purely so the UI can
    /// show a subtle "syncing" indicator rather than nothing at all -- never
    /// gates any user action, since per the food-log-entry spec confirming
    /// an entry must never wait on this.
    private(set) var isDraining = false

    /// Why a queued entry did not reach Garmin, when that is not an auth
    /// problem (auth has its own loud banner, per design.md D7).
    ///
    /// Every write route in docs/garmin-routes.json is still recorded as
    /// "documented, not exercised" -- the create-food-log contract is
    /// inferred, never verified against a real write. So the first real
    /// failures are expected, and the only thing that turns one into a fix
    /// is seeing what Garmin actually said. Before this existed,
    /// `drainAndReconcile` discarded `DrainResult.failed` entirely: the
    /// entry sat in the outbox with its `lastError` recorded and shown to
    /// nobody, while the confirm screen said "saved". That is the same
    /// invisible-failure bug the ticket exchange had, in the write path.
    private(set) var lastDeliveryFailure: String?

    /// Queued entries Garmin has not accepted. Surfaced alongside
    /// `lastDeliveryFailure` so "saved" cannot keep meaning "saved locally,
    /// silently stuck".
    private(set) var undeliveredCount = 0

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
        self.openFoodFactsClient = OpenFoodFactsClient()
        self.logEntryCoordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults)
        self.gamificationEngine = GamificationEngine(usageHistory: usageHistory, garminClient: client)
        self.todaySummary = TodaySummaryLoader(client: client)
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
        // The hero number and the gamification state are refreshed AFTER
        // the drain so that anything just delivered to Garmin is already
        // reflected in the total the user sees. Run concurrently with each
        // other -- they're independent reads.
        async let summary: Void = todaySummary.refresh()
        async let gamification: Void = gamificationEngine.refresh()
        async let goals: Void = gamificationEngine.refreshGoalStatus()
        _ = await (summary, gamification, goals)
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
            // The hero total is READ BACK from Garmin's daily food log
            // (TodaySummary.swift), so a delivery is invisible until the day
            // is re-read. Without this, logging something from inside the
            // app left the number unchanged until the next foreground --
            // which never comes if the user simply stays in the app.
            await todaySummary.refresh()
        }
        switch result.authOutcome {
        case .longLivedTokenExpired:
            authState.report(GarminAuthError.longLivedTokenExpired)
            lastDeliveryFailure = nil
        case .notSignedIn:
            authState.report(GarminAuthError.notSignedIn)
            lastDeliveryFailure = nil
        case .none:
            // Auth failures own their own loud banner; repeating them here
            // would only say the same thing twice in different words. What
            // belongs here is the case that had no voice at all: signed in,
            // nothing expired, and Garmin still refused the write.
            lastDeliveryFailure = result.failed.compactMap(\.lastError).first
        }
        let pending = await outbox.pendingCount()
        undeliveredCount = pending
        authState.updatePendingCount(pending)
    }
}

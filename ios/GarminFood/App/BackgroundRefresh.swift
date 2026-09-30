// BackgroundRefresh.swift
//
// Delivers queued entries while the app isn't open (add-garmin-auth-and-sync
// 9.5, design D10). iOS decides when, and whether, a refresh actually runs.
// For a sideloaded app that is a device check, not an assumption. The
// foreground drain keeps working regardless. It also runs the Czech
// offline index's daily update check (add-offline-czech-food-index).

import BackgroundTasks
import Foundation
import GarminKit
import FoodLogCore

enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    static let identifier = "com.mlcousek.garminfood.refresh"

    /// Asks iOS for a refresh no sooner than `after`. Only worth doing while
    /// something is waiting to be delivered.
    static func schedule(after interval: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    /// The refresh itself: deliver, reconcile, and ask again if anything is
    /// still waiting.
    ///
    /// Drains all three outboxes, like `AppEnvironment.drainAndReconcile`
    /// (2026-09-23 review fix: this used to drain only the food outbox, so a
    /// queued weigh-in delete or a negative water correction never moved in
    /// the background and didn't even keep the refresh scheduled). Each
    /// drain stops itself on an auth failure without burning an attempt;
    /// there is no UI to report it to here, so it is logged, and the next
    /// foreground `drainAndReconcile` hits the same failure and raises the
    /// auth banner. Only `.pending` entries keep the refresh scheduled -- a
    /// `.failed` one waits for the user in the sync queue.
    @MainActor
    static func run() async {
        let services = AppServices.shared
        let allowsGarmin = GarminSyncPlan.for(AppServices.currentDataMode()).allows(.backgroundDelivery)
        if allowsGarmin {
            await deliver(services)
        }
        // add-offline-czech-food-index D3: the at-most-daily index check,
        // piggybacking on whatever background time iOS grants. Throttled
        // and Wi-Fi-gated by the store itself; a no-op most of the time.
        let allowsCellular = UserDefaults.standard.bool(forKey: AppPreferences.Key.offlineIndexAllowsCellular)
        _ = await services.offlineIndexStore.checkForUpdate(allowsCellular: allowsCellular)
    }

    /// The Garmin half of `run()`. Skipped in standalone mode
    /// (add-standalone-mode 5.3): nothing is delivered and nothing is
    /// scheduled again.
    @MainActor
    private static func deliver(_ services: AppServices) async {
        // fix-review-findings-2026-09 finding 3: the drains and the
        // "still waiting?" rule live in FoodLogCore's
        // `BackgroundOutboxDelivery`, tested with weight-only and
        // water-only queues.
        let outcome = await BackgroundOutboxDelivery.run(
            outbox: services.outbox,
            reconciliation: services.reconciliation,
            weightOutbox: services.weightOutbox,
            hydrationOutbox: services.hydrationOutbox,
            client: services.garminClient
        )
        if outcome.authOutcome != DrainAuthOutcome.none {
            DiagnosticsLog.log(.warning, category: "BackgroundRefresh", "background drain stopped on auth: \(outcome.authOutcome)")
        }
        if outcome.needsAnotherRefresh {
            schedule()
        }
    }
}

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
    @MainActor
    static func run() async {
        let services = AppServices.shared
        let result = await services.outbox.drain(using: services.garminClient)
        if !result.delivered.isEmpty {
            _ = await services.reconciliation.reconcile(delivered: result.delivered, using: services.garminClient)
        }
        // An unparked edit still owing its old entry's delete
        // (add-log-entry-editing) needs another drain just like a pending create.
        let waiting = await services.outbox.allEntries().contains {
            $0.state == .pending || ($0.state == .createdAwaitingDelete && !$0.isParkedReplace)
        }
        if waiting {
            schedule()
        }
        // add-offline-czech-food-index D3: the at-most-daily index check,
        // piggybacking on whatever background time iOS grants. Throttled
        // and Wi-Fi-gated by the store itself; a no-op most of the time.
        let allowsCellular = UserDefaults.standard.bool(forKey: AppPreferences.Key.offlineIndexAllowsCellular)
        _ = await services.offlineIndexStore.checkForUpdate(allowsCellular: allowsCellular)
    }
}

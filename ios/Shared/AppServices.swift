// AppServices.swift
//
// One set of local stores per process (add-app-shell-and-meal-dashboard 1.1).
//
// Every store here is a JSON file read once and then kept in memory. Before
// this existed, `AppEnvironment` and each in-app intent (Control, Siri)
// opened their OWN instances on the same files. So an entry logged from a
// Control while the app was running went into a second in-memory copy: the
// app's copy never saw it, and the app's next save rewrote the file without
// it. The two outboxes also drained independently, each with its own
// "already draining" guard. Sharing one instance fixes both: every write
// goes through the same actor, and the actor's drain guard covers every
// caller.
//
// Compiled into the widget extension too (via `Shared/`), where it is
// simply never touched: the extension shows no data and runs no intents
// (add-glanceable-surfaces D1/D2).

import Foundation
import GarminKit
import FoodLogCore

/// Told about every confirmed log, wherever it came from, so app-only
/// concerns (Siri donations, gamification) don't need to live in `Shared/`.
@MainActor
protocol LogObserving: AnyObject {
    func didLog(food: Food, date: String) async
}

@MainActor
final class AppServices {
    static let shared = AppServices()

    let garminClient: GarminClient
    let outbox: Outbox
    let reconciliation: Reconciliation
    let usageHistory: UsageHistoryStore
    let servingDefaults: ServingDefaultStore
    let customFoodStore: CustomFoodStore
    let mealPresetStore: MealPresetStore
    let foodCache: FoodCacheStore
    let logEntryCoordinator: LogEntryCoordinator

    /// Set by the app at launch. Stays `nil` in the widget extension.
    weak var logObserver: LogObserving?

    private init() {
        let client = GarminClient()
        let outbox = Outbox(processName: "app")
        let usageHistory = UsageHistoryStore()
        let servingDefaults = ServingDefaultStore()

        self.garminClient = client
        self.outbox = outbox
        self.reconciliation = Reconciliation(outbox: outbox)
        self.usageHistory = usageHistory
        self.servingDefaults = servingDefaults
        self.customFoodStore = CustomFoodStore()
        self.mealPresetStore = MealPresetStore()
        self.foodCache = FoodCacheStore()
        self.logEntryCoordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults)
    }

    /// Tries to deliver queued entries, but stops WAITING after `seconds`
    /// (add-garmin-auth-and-sync design D6: an intent's inline delivery is
    /// bounded). The drain itself is never cancelled: a cancelled request
    /// would count as a failed attempt against the entry, so it simply
    /// finishes in the background. Returns `nil` if it didn't finish in time.
    func briefDelivery(seconds: Double = 2) async -> DrainResult? {
        let outbox = self.outbox
        let client = self.garminClient
        let drain = Task { await outbox.drain(using: client) }
        return await withCheckedContinuation { continuation in
            let gate = ResumeOnce(continuation)
            Task {
                let result = await drain.value
                await gate.resume(result)
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await gate.resume(nil)
            }
        }
    }
}

/// Resumes a continuation exactly once, whichever side finishes first.
private actor ResumeOnce {
    private var continuation: CheckedContinuation<DrainResult?, Never>?

    init(_ continuation: CheckedContinuation<DrainResult?, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: DrainResult?) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}

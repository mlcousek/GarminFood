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
    /// add-favorite-foods: purely local (see FavoriteFood.swift's header for
    /// why there is no Garmin sync) -- included here, not just in the app's
    /// own `AppEnvironment`, for the same one-shared-instance-per-process
    /// reason `customFoodStore`/`mealPresetStore` are.
    let favoriteFoodStore: FavoriteFoodStore
    let logEntryCoordinator: LogEntryCoordinator
    /// add-weight-tracking: the weight domain's own store/outbox/coordinator
    /// pair, following the exact same one-instance-per-process shape as the
    /// food-logging ones above -- see WeightTracking.swift/
    /// WeightLogCoordinator.swift (FoodLogCore) and WeightSync.swift
    /// (GarminKit) for why this is a SEPARATE outbox rather than reusing
    /// `outbox` above.
    let weightStore: WeightStore
    let weightOutbox: WeightOutbox
    let weightLogCoordinator: WeightLogCoordinator
    /// add-hydration-tracking: same shape as the weight trio above, its own
    /// separate outbox for the same reason (HydrationSync.swift's header).
    let hydrationStore: HydrationStore
    let hydrationOutbox: HydrationOutbox
    let hydrationLogCoordinator: HydrationLogCoordinator
    /// sync-weight-hydration-with-garmin: the last good Garmin reads for
    /// weigh-ins, the daily water total and the weight goal
    /// (GarminHealthCache.swift), refreshed by `garminHealthSync`. One
    /// instance per process for the same reason as every store here.
    let garminHealthCache: GarminHealthCacheStore
    let garminHealthSync: GarminHealthSync
    /// Purely local, no Garmin route involved (see FastingSession.swift's
    /// header) -- included here anyway, not just in the app's own
    /// `AppEnvironment`, for the same reason `mealPresetStore` is: one
    /// shared instance per process, so a future widget/Control surface
    /// reading fasting state (there isn't one yet) wouldn't open a second,
    /// divergent copy of the file.
    let fastingStore: FastingSessionStore
    /// add-day-notes: purely local, no Garmin route exists (DayNote.swift's
    /// header) -- one shared instance per process, same reason as
    /// `fastingStore` above.
    let dayNoteStore: DayNoteStore

    /// Set by the app at launch. Stays `nil` in the widget extension.
    weak var logObserver: LogObserving?

    private init() {
        let client = GarminClient()
        let outbox = Outbox(processName: "app")
        let usageHistory = UsageHistoryStore()
        let servingDefaults = ServingDefaultStore()
        let weightStore = WeightStore()
        let weightOutbox = WeightOutbox(processName: "app")
        let hydrationStore = HydrationStore()
        let hydrationOutbox = HydrationOutbox(processName: "app")
        let garminHealthCache = GarminHealthCacheStore()
        let foodCache = FoodCacheStore()

        self.garminClient = client
        self.outbox = outbox
        self.reconciliation = Reconciliation(outbox: outbox)
        self.usageHistory = usageHistory
        self.servingDefaults = servingDefaults
        self.customFoodStore = CustomFoodStore()
        self.mealPresetStore = MealPresetStore()
        self.foodCache = foodCache
        self.favoriteFoodStore = FavoriteFoodStore()
        self.fastingStore = FastingSessionStore()
        self.dayNoteStore = DayNoteStore()
        // `foodCache` so an edited/duplicated/copied entry can be named in
        // its meal before Garmin reads it back (add-log-entry-editing).
        self.logEntryCoordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults, foodCache: foodCache)
        self.weightStore = weightStore
        self.weightOutbox = weightOutbox
        self.weightLogCoordinator = WeightLogCoordinator(store: weightStore, outbox: weightOutbox)
        self.hydrationStore = hydrationStore
        self.hydrationOutbox = hydrationOutbox
        self.hydrationLogCoordinator = HydrationLogCoordinator(store: hydrationStore, outbox: hydrationOutbox)
        self.garminHealthCache = garminHealthCache
        self.garminHealthSync = GarminHealthSync(cache: garminHealthCache, reader: client)
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

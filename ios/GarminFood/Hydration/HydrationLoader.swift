// HydrationLoader.swift
//
// The hydration equivalent of Weight/WeightLoader.swift -- same shape, same
// reasoning (one shared in-memory snapshot, `refresh()` never waits on the
// network).
//
// sync-weight-hydration-with-garmin (design.md D4): Garmin's daily total is
// the truth. `todayTotalML` is Garmin's cached `valueInML` plus whatever the
// app logged that Garmin's read can't include yet (FoodLogCore's
// `HydrationDayTotal`), so water logged on the watch or in Connect counts.
// Garmin has no per-drink list, so `entries`/`todayEntries` remain the
// drinks logged IN THIS APP. The goal is Garmin's `goalInML` unless
// overridden in Settings (D5). The Garmin read itself is
// `AppEnvironment.refreshGarminHealth(force:)`.
//
// add-standalone-mode D7 (task 4.4): in standalone mode the total is the
// sum of this phone's drinks and the goal the override or 2000 ml
// (`WeightAndWaterOverview.standalone*`); no row has a sync state.

import Foundation
import Observation
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class HydrationLoader {
    @ObservationIgnored private let store: HydrationStore
    @ObservationIgnored private let outbox: HydrationOutbox
    @ObservationIgnored private let cache: GarminHealthCacheStore
    @ObservationIgnored private let preferences: AppPreferences

    /// Newest first, matching `HydrationStore.all()` -- drinks logged here.
    private(set) var entries: [HydrationEntry] = []
    private(set) var outboxEntries: [HydrationOutboxEntry] = []
    private(set) var snapshot = GarminHealthSnapshot()
    /// Whether the last Garmin read for water failed (not auth).
    var lastGarminRefreshFailed = false

    init(store: HydrationStore, outbox: HydrationOutbox, cache: GarminHealthCacheStore, preferences: AppPreferences) {
        self.store = store
        self.outbox = outbox
        self.cache = cache
        self.preferences = preferences
    }

    /// Garmin's total + undelivered local drinks and corrections (D4).
    var todayTotalML: Double {
        if preferences.isStandalone {
            return WeightAndWaterOverview.standaloneWaterTotalML(entries: entries, on: Date())
        }
        return WeightAndWaterOverview.waterTotalML(snapshot: snapshot, outboxEntries: outboxEntries, on: Date())
    }

    var todayEntries: [HydrationEntry] { HydrationHistory.entries(for: entries, on: Date()) }

    /// Override, else Garmin's goal, else 2000 ml (D5).
    var goal: EffectiveWaterGoal {
        if preferences.isStandalone {
            return WeightAndWaterOverview.standaloneWaterGoal(overrideML: preferences.waterGoalOverrideML)
        }
        return WeightAndWaterOverview.waterGoal(snapshot: snapshot, source: preferences.waterGoalSource, on: NutritionDate.string(from: Date()))
    }

    var goalML: Double { goal.milliliters }

    /// Garmin's own goal, for Settings' "Use Garmin's goal" row.
    var garminGoalML: Double? {
        WeightAndWaterOverview.garminWaterGoalML(snapshot: snapshot, on: NutritionDate.string(from: Date()))
    }

    /// `true` once Garmin's total for today has been read at least once --
    /// lets the screen say the total includes water logged elsewhere.
    var hasGarminTotalToday: Bool {
        !preferences.isStandalone && snapshot.hydrationDays[NutritionDate.string(from: Date())] != nil
    }

    /// Same "no news defaults to synced" reasoning as before: a missing
    /// outbox entry means it was delivered.
    func outboxState(for entry: HydrationEntry) -> OutboxEntryState? {
        guard !preferences.isStandalone else { return nil }
        guard let outboxEntryId = entry.outboxEntryId else { return nil }
        return outboxEntries.first { $0.id == outboxEntryId }?.state
    }

    /// Local files only (store, outbox, Garmin cache) -- no network.
    func refresh() async {
        async let loadedEntries = store.all()
        async let loadedOutbox = outbox.allEntries()
        async let loadedSnapshot = cache.current()
        let (loaded, loadedOutboxEntries, cached) = await (loadedEntries, loadedOutbox, loadedSnapshot)
        entries = loaded
        outboxEntries = loadedOutboxEntries
        snapshot = cached
    }
}

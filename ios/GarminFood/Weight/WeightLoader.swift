// WeightLoader.swift
//
// The weight data every screen that shows it needs (the Today card, the
// Progress tab's summary card, the full Weight screen's hero/goal/chart/
// history list), kept in one place so they all read the same in-memory
// snapshot -- mirrors `ProfileLoader`'s shape (App/ProfileLoader.swift).
//
// sync-weight-hydration-with-garmin: Garmin is now the source of truth.
// `rows` is FoodLogCore's `WeightHistoryMerge` over the CACHED Garmin
// weigh-ins (`GarminHealthCacheStore`) plus the app's own not-yet-in-Garmin
// entries (design.md D1), and the goal/progress comes from
// `WeightAndWaterOverview` with the owner's override from `AppPreferences`
// (D5). `refresh()` still only reads local files -- it never waits on the
// network and is safe to call after every log/delete; the Garmin READ that
// fills the cache is `AppEnvironment.refreshGarminHealth(force:)`, which
// then calls `refresh()` and sets `lastGarminRefreshFailed` for the quiet
// "couldn't refresh" caption.
//
// add-standalone-mode D7 (task 4.4): in standalone mode the rows are the
// local weigh-ins only and the goal comes from the local overrides (start =
// the first weigh-in) -- `WeightAndWaterOverview.standalone*`. The Garmin
// cache and the outbox are ignored, so no "not in Garmin yet" badge shows.

import Foundation
import Observation
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class WeightLoader {
    @ObservationIgnored private let store: WeightStore
    @ObservationIgnored private let outbox: WeightOutbox
    @ObservationIgnored private let cache: GarminHealthCacheStore
    @ObservationIgnored private let preferences: AppPreferences

    /// The merged Garmin + local history, newest first.
    private(set) var rows: [WeighInDisplayEntry] = []
    private(set) var snapshot = GarminHealthSnapshot()
    /// This phone's own weigh-ins (standalone mode's whole history).
    private(set) var localEntries: [WeightEntry] = []
    /// Whether the last Garmin read for weight failed (not auth -- that has
    /// its own banner). Rows still render from the cache.
    var lastGarminRefreshFailed = false

    init(store: WeightStore, outbox: WeightOutbox, cache: GarminHealthCacheStore, preferences: AppPreferences) {
        self.store = store
        self.outbox = outbox
        self.cache = cache
        self.preferences = preferences
    }

    var latest: WeighInDisplayEntry? { rows.first }
    var previous: WeighInDisplayEntry? { rows.dropFirst().first }

    /// Override else Garmin's plan (D5); `nil` hides the goal bar. Reads
    /// `preferences`, so a Settings change re-renders the cards at once.
    var goal: EffectiveWeightGoal? {
        if preferences.isStandalone {
            return WeightAndWaterOverview.standaloneWeightGoal(
                targetOverrideKg: preferences.weightGoalOverrideKg,
                startOverrideKg: preferences.weightGoalStartKg,
                localEntries: localEntries
            )
        }
        return WeightAndWaterOverview.weightGoal(
            snapshot: snapshot,
            targetSource: preferences.weightGoalSource,
            startOverrideKg: preferences.weightGoalStartKg
        )
    }

    var progress: WeightGoalProgress? {
        WeightAndWaterOverview.weightProgress(rows: rows, goal: goal, now: Date())
    }

    /// Garmin's own target in kg, for Settings' "Use Garmin's goal" row.
    var garminTargetKg: Double? {
        snapshot.weightGoal?.targetWeightGrams.flatMap { $0 > 0 ? $0 / 1000 : nil }
    }

    var garminStartKg: Double? {
        snapshot.weightGoal?.startingWeightGrams.flatMap { $0 > 0 ? $0 / 1000 : nil }
    }

    /// Local files only (stores, outbox, Garmin cache) -- no network.
    func refresh() async {
        async let loadedEntries = store.all()
        async let loadedOutbox = outbox.allEntries()
        async let loadedSnapshot = cache.current()
        let (entries, outboxEntries, cached) = await (loadedEntries, loadedOutbox, loadedSnapshot)
        snapshot = cached
        localEntries = entries
        if preferences.isStandalone {
            rows = WeightAndWaterOverview.standaloneWeightRows(localEntries: entries)
            return
        }
        rows = WeightHistoryMerge.merge(
            garminWeighIns: cached.allWeighIns,
            garminDayFetchedAt: cached.weighInDayFetchTimes,
            localEntries: entries,
            outboxEntries: outboxEntries
        )
    }
}

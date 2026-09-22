// HydrationLoader.swift
//
// The hydration equivalent of Weight/WeightLoader.swift -- same shape, same
// reasoning (one shared in-memory snapshot, `refresh()` never waits on
// anything). `todayTotal`/`todayEntries` add what weight doesn't need:
// hydration is naturally a same-day cumulative metric (drink several times
// a day, care about "how much so far today"), not a trend-over-weeks one,
// so this loader also exposes `HydrationHistory.total`/`.entries` computed
// against `entries` for "today" specifically.

import Foundation
import Observation
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class HydrationLoader {
    @ObservationIgnored private let store: HydrationStore
    @ObservationIgnored private let outbox: HydrationOutbox

    /// Newest first, matching `HydrationStore.all()`.
    private(set) var entries: [HydrationEntry] = []
    private(set) var outboxEntries: [HydrationOutboxEntry] = []

    init(store: HydrationStore, outbox: HydrationOutbox) {
        self.store = store
        self.outbox = outbox
    }

    var todayTotalML: Double { HydrationHistory.total(for: entries, on: Date()) }
    var todayEntries: [HydrationEntry] { HydrationHistory.entries(for: entries, on: Date()) }

    /// Same "no news defaults to synced" reasoning as
    /// `WeightLoader.outboxState(for:)` -- this app doesn't reconcile
    /// hydration reads back from Garmin either.
    func outboxState(for entry: HydrationEntry) -> OutboxEntryState? {
        guard let outboxEntryId = entry.outboxEntryId else { return nil }
        return outboxEntries.first { $0.id == outboxEntryId }?.state
    }

    func refresh() async {
        async let loadedEntries = store.all()
        async let loadedOutbox = outbox.allEntries()
        entries = await loadedEntries
        outboxEntries = await loadedOutbox
    }
}

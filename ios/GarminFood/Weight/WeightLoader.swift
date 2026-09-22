// WeightLoader.swift
//
// The weight data every screen that shows it needs (the Progress tab's
// summary card, the full Weight screen's hero/chart/history list), kept in
// one place so both read the same in-memory snapshot rather than each
// re-reading `WeightStore`/`WeightOutbox` on its own -- mirrors
// `ProfileLoader`'s exact shape (App/ProfileLoader.swift), just over local
// stores instead of a network client, so `refresh()` never waits on
// anything and is safe to call as often as `AppEnvironment` calls its other
// loaders (foreground, after a log, after a delete).
//
// `outboxEntries` exists purely so a history row can show "waiting to
// sync"/"failed" next to a `WeightEntry` -- `WeightRow` (WeightComponents.swift)
// looks up the matching entry by `WeightEntry.outboxEntryId`.

import Foundation
import Observation
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class WeightLoader {
    @ObservationIgnored private let store: WeightStore
    @ObservationIgnored private let outbox: WeightOutbox

    /// Newest first, matching `WeightStore.all()`.
    private(set) var entries: [WeightEntry] = []
    private(set) var outboxEntries: [WeightOutboxEntry] = []

    init(store: WeightStore, outbox: WeightOutbox) {
        self.store = store
        self.outbox = outbox
    }

    var latest: WeightEntry? { entries.first }
    var previous: WeightEntry? { entries.dropFirst().first }

    /// The sync state for one history row, or `nil` if its outbox entry has
    /// already been fully delivered and reconciled away (or the entry
    /// predates this field). A missing outbox entry is treated as "synced"
    /// rather than shown as an error -- the far more common reason it's
    /// gone is that delivery succeeded, and this app doesn't reconcile
    /// weigh-in reads back from Garmin (see WeightLogCoordinator.swift's
    /// header), so there is no way to positively confirm that here; "no
    /// news" defaults to the optimistic, common case rather than a
    /// permanent false alarm.
    func outboxState(for entry: WeightEntry) -> OutboxEntryState? {
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

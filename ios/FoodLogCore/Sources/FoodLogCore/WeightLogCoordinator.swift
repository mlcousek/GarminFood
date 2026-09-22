// WeightLogCoordinator.swift
//
// The weight equivalent of LogEntryCoordinator.swift: the confirm-and-commit
// action for a weigh-in. Same zero-network-wait structure -- `WeightOutbox.
// logWeight` (GarminKit) only appends to a local JSON file and returns;
// `WeightStore.upsert` is the same kind of local file write. Neither call
// here makes or waits on a network request, matching this project's hard
// constraint that a confirm/save action never adds a network `await`.
// Delivery happens later, whenever something drains the weight outbox
// (AppEnvironment.drainAndReconcile, mirroring how the food outbox is
// drained on foreground) -- not this coordinator's job.

import Foundation
import GarminKit

public struct WeightLogCoordinator: Sendable {
    private let store: WeightStore
    private let outbox: WeightOutbox

    public init(store: WeightStore, outbox: WeightOutbox) {
        self.store = store
        self.outbox = outbox
    }

    /// Commits a weigh-in locally and enqueues it for delivery, in that
    /// order -- the outbox entry's id has to exist before `WeightEntry` can
    /// reference it via `outboxEntryId`. Both are local-only writes, so the
    /// ordering costs nothing in wait time either way. Returns as soon as
    /// both local writes succeed; callers may show success immediately.
    @discardableResult
    public func logWeight(
        weightKg: Double,
        note: String? = nil,
        loggedAt: Date = Date(),
        now: Date = Date()
    ) async throws -> WeightEntry {
        let outboxEntry = try await outbox.logWeight(weightKg: weightKg, loggedAt: loggedAt)
        let entry = WeightEntry(
            weightKg: weightKg,
            loggedAt: loggedAt,
            note: note,
            createdAt: now,
            outboxEntryId: outboxEntry.id
        )
        return try await store.upsert(entry)
    }

    /// Removes the local record, and -- only if Garmin has not yet accepted
    /// its matching outbox entry (still `.pending`/`.failed`) -- removes
    /// that too, so a deleted-before-delivery weigh-in is never sent after
    /// the fact.
    ///
    /// An already `.sent` entry cannot be recalled from here: this app does
    /// not implement a Garmin-side delete for weigh-ins in this first
    /// version. `GarminClient` has no `deleteWeighIn` method yet -- doing
    /// that reliably needs to first find the right Garmin `samplePk` for a
    /// local entry, which means reading `getWeighIns` back, and that
    /// route's response shape is only a documented GUESS (see
    /// `WeightRangeResponse`'s doc comment in GarminKit/GarminModels.swift),
    /// not a confirmed contract worth building delete-reconciliation logic
    /// on top of yet. Deleting locally is always safe and always available,
    /// which is why it's what this app offers today; a Garmin-side delete
    /// is explicit future work once that read shape is confirmed or fixed
    /// against a real device.
    public func deleteWeight(_ entry: WeightEntry) async throws {
        try await store.delete(id: entry.id)
        guard let outboxEntryId = entry.outboxEntryId else { return }
        let stillQueued = await outbox.allEntries().contains { $0.id == outboxEntryId && $0.state != .sent }
        if stillQueued {
            try await outbox.delete(id: outboxEntryId)
        }
    }
}

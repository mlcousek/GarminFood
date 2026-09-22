// HydrationLogCoordinator.swift
//
// The hydration equivalent of WeightLogCoordinator.swift: the confirm-and-
// commit action for a drink. Same zero-network-wait structure -- neither
// `HydrationOutbox.logHydration` (GarminKit) nor `HydrationStore.upsert`
// makes or waits on a network request. Delivery happens later, whenever
// something drains the hydration outbox (AppEnvironment.drainAndReconcile,
// mirroring how the weight and food outboxes are drained) -- not this
// coordinator's job.

import Foundation
import GarminKit

public struct HydrationLogCoordinator: Sendable {
    private let store: HydrationStore
    private let outbox: HydrationOutbox

    public init(store: HydrationStore, outbox: HydrationOutbox) {
        self.store = store
        self.outbox = outbox
    }

    /// Commits a drink locally and enqueues it for delivery, in that order
    /// -- same reasoning as `WeightLogCoordinator.logWeight`. Returns as
    /// soon as both local writes succeed; callers may show success
    /// immediately.
    @discardableResult
    public func logHydration(
        valueInML: Double,
        loggedAt: Date = Date(),
        now: Date = Date()
    ) async throws -> HydrationEntry {
        let outboxEntry = try await outbox.logHydration(valueInML: valueInML, loggedAt: loggedAt)
        let entry = HydrationEntry(
            valueInML: valueInML,
            loggedAt: loggedAt,
            createdAt: now,
            outboxEntryId: outboxEntry.id
        )
        return try await store.upsert(entry)
    }

    /// Removes the local record, and -- only if Garmin has not yet accepted
    /// its matching outbox entry -- removes that too. Same "an already
    /// `.sent` entry cannot be recalled" limitation as
    /// `WeightLogCoordinator.deleteWeight`, for the same reason: this app
    /// does not implement a Garmin-side delete for hydration entries
    /// either.
    public func deleteHydration(_ entry: HydrationEntry) async throws {
        try await store.delete(id: entry.id)
        guard let outboxEntryId = entry.outboxEntryId else { return }
        let stillQueued = await outbox.allEntries().contains { $0.id == outboxEntryId && $0.state != .sent }
        if stillQueued {
            try await outbox.delete(id: outboxEntryId)
        }
    }
}

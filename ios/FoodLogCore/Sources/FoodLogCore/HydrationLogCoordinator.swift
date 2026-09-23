// HydrationLogCoordinator.swift
//
// The hydration equivalent of WeightLogCoordinator.swift: the confirm-and-
// commit action for a drink. Same zero-network-wait structure -- neither
// `HydrationOutbox.logHydration` (GarminKit) nor `HydrationStore.upsert`
// makes or waits on a network request. Delivery happens later, whenever
// something drains the hydration outbox (AppEnvironment.drainAndReconcile,
// mirroring how the weight and food outboxes are drained) -- not this
// coordinator's job.
//
// sync-weight-hydration-with-garmin (2026-09-23): `removeHydration`
// replaces the old local-only `deleteHydration` -- removing a drink that
// already reached Garmin now queues a negative correction, so Garmin's day
// total (now the source of truth, `HydrationDayTotal`) drops too.

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

    /// Removes a drink (design.md D4, sync-weight-hydration-with-garmin).
    /// Local-only writes, no network `await`:
    ///
    /// - Not delivered yet (`.pending`/`.failed`): the drink and its outbox
    ///   entry are both removed -- it is simply never sent.
    /// - Already delivered (`.sent`, or its outbox entry is gone, which only
    ///   happens after delivery): Garmin keeps only a day total and its log
    ///   route is additive, so a `-valueInML` correction is queued for the
    ///   drink's own date/time and delivered by the drain like any drink.
    ///   `HydrationDayTotal` counts the queued correction at once, so the
    ///   shown total drops immediately.
    ///
    /// The correction is enqueued BEFORE the local record is removed: if
    /// the second write failed, the drink would still be listed with its
    /// correction queued -- visible and fixable -- rather than silently gone
    /// from the list while Garmin keeps counting it.
    @discardableResult
    public func removeHydration(_ entry: HydrationEntry) async throws -> HydrationRemoval {
        let outboxEntries = await outbox.allEntries()
        if let outboxEntryId = entry.outboxEntryId,
           outboxEntries.contains(where: { $0.id == outboxEntryId && $0.state != .sent }) {
            try await outbox.delete(id: outboxEntryId)
            try await store.delete(id: entry.id)
            return .cancelledBeforeDelivery
        }
        try await outbox.logHydration(valueInML: -entry.valueInML, loggedAt: entry.loggedAt)
        try await store.delete(id: entry.id)
        return .correctionQueued
    }
}

/// What `HydrationLogCoordinator.removeHydration(_:)` did.
public enum HydrationRemoval: Sendable, Equatable {
    /// Never reached Garmin; cancelled.
    case cancelledBeforeDelivery
    /// A negative correction is queued for Garmin's total.
    case correctionQueued
}

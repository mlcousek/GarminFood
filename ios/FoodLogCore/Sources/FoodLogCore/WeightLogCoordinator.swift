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
//
// sync-weight-hydration-with-garmin (2026-09-23) adds `delete(_:)` for a
// row of the merged Garmin + local history (`WeightHistoryMerge`): deleting
// a Garmin weigh-in now deletes it in Garmin too, through the same durable
// outbox (a `.delete` operation), never a blocking call.

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
    /// the fact. Returns whether such an undelivered entry was cancelled.
    ///
    /// The local half of `delete(_:)` below, which is what the UI calls: a
    /// weigh-in Garmin already accepted is NOT deleted from Garmin here. The
    /// one exception is an add being sent right now -- it is flagged, and
    /// the drain sending it deletes it from Garmin again if Garmin accepts it
    /// (see `withdrawAdd`).
    @discardableResult
    public func deleteWeight(_ entry: WeightEntry) async throws -> Bool {
        try await store.delete(id: entry.id)
        return try await withdrawAdd(of: entry) == .cancelled
    }

    private enum AddWithdrawal: Equatable {
        /// Never sent; removed from the queue.
        case cancelled
        /// In flight; the drain drops it or deletes it from Garmin again.
        case compensatingAfterDelivery
        /// Garmin already has it (or it predates the outbox).
        case delivered
    }

    /// Takes a weigh-in's add back out of the queue if Garmin hasn't
    /// accepted it. "Is it delivered / in flight?" and "cancel it" happen in
    /// ONE step inside the outbox's store (2026-09-23 race fix -- this used
    /// to read the state and then delete, so an add deleted mid-POST still
    /// landed in Garmin with nothing left to delete it).
    private func withdrawAdd(of entry: WeightEntry) async throws -> AddWithdrawal {
        guard let outboxEntryId = entry.outboxEntryId else { return .delivered }
        do {
            switch try await outbox.cancelQueued(id: outboxEntryId) {
            case .removed:
                return .cancelled
            case .compensateAfterDelivery:
                return .compensatingAfterDelivery
            }
        } catch let error as OutboxEditError where error == .alreadyDelivered || error == .entryNotFound {
            // `.sent`, or its outbox entry is gone -- only after delivery.
            return .delivered
        }
    }

    /// Deletes one row of the merged weigh-in history (design.md D3,
    /// sync-weight-hydration-with-garmin). Local-only writes, no network
    /// `await` -- the Garmin delete is enqueued and delivered later by
    /// `WeightOutbox.drain`, and `WeightHistoryMerge` hides the sample the
    /// moment its delete is queued.
    ///
    /// - A Garmin sample: enqueues `DELETE .../byversion/{samplePk}`
    ///   (live-confirmed 2026-09-23). If a delete for that sample already
    ///   FAILED, it is retried instead of queued twice; if one is already
    ///   queued, nothing new is added. The matching local record, if the
    ///   weigh-in was logged here, is removed too.
    /// - A local entry not delivered yet: cancelled -- no network call.
    /// - A local entry whose add is being sent right now: the drain sending
    ///   it drops it, or deletes it from Garmin again once Garmin accepts it.
    /// - A local entry that WAS delivered but isn't matched to a Garmin
    ///   sample yet (Garmin not re-read since, so its `samplePk` is
    ///   unknown): a delete-by-match is queued, which the drain resolves
    ///   from Garmin's day view with the D1 rule (2026-09-23 review fix --
    ///   this used to delete locally only, so the weigh-in stayed in Garmin
    ///   and reappeared on the next read). The merged history hides the
    ///   matching sample meanwhile.
    @discardableResult
    public func delete(_ entry: WeighInDisplayEntry, calendar: Calendar = .current) async throws -> WeighInDeletion {
        switch entry.source {
        case .local(let local):
            switch try await withdrawAdd(of: local) {
            case .cancelled:
                try await store.delete(id: local.id)
                return .cancelledBeforeDelivery
            case .compensatingAfterDelivery:
                try await store.delete(id: local.id)
                return .garminDeleteQueued
            case .delivered:
                // Queue first: if removing the local record then failed,
                // the row would still be listed with its delete queued --
                // visible -- rather than gone here but kept in Garmin.
                try await outbox.logDeleteMatching(
                    weightKg: local.weightKg,
                    loggedAt: local.loggedAt,
                    calendarDate: NutritionDate.string(from: local.loggedAt, calendar: calendar)
                )
                try await store.delete(id: local.id)
                return .garminDeleteQueued
            }

        case .garmin(let sample, let matchedLocal):
            // Deletes already aimed at this sample: by its samplePk, or the
            // row's own failed delete (possibly a delete-by-match).
            let existingDeletes = await outbox.allEntries().filter {
                $0.kind == .delete && ($0.samplePk == sample.samplePk || $0.id == entry.outboxEntryId)
            }
            let result: WeighInDeletion
            if let failed = existingDeletes.first(where: { $0.state == .failed }) {
                try await outbox.retry(id: failed.id)
                result = .garminDeleteQueued
            } else if !existingDeletes.isEmpty {
                result = .garminDeleteQueued
            } else {
                try await outbox.logDelete(
                    samplePk: sample.samplePk,
                    calendarDate: sample.calendarDate,
                    weightKg: sample.weightKg,
                    loggedAt: sample.timestamp
                )
                result = .garminDeleteQueued
            }
            if let matchedLocal {
                try await store.delete(id: matchedLocal.id)
            }
            return result
        }
    }
}

/// What `WeightLogCoordinator.delete(_:)` did -- lets the UI word its
/// confirmation honestly.
public enum WeighInDeletion: Sendable, Equatable {
    /// A Garmin delete is queued (or an earlier failed one retried, or --
    /// for an add in flight -- follows automatically once Garmin accepts
    /// it).
    case garminDeleteQueued
    /// The weigh-in never reached Garmin; it was simply cancelled.
    case cancelledBeforeDelivery
}

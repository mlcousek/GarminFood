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
    /// This alone never touches Garmin: it's the local half of `delete(_:)`
    /// below, which is what the UI calls. An already `.sent` add can't be
    /// recalled by its outbox entry (the add route returns no `samplePk`);
    /// the Garmin-side delete works on the merged history's Garmin sample
    /// instead (`WeighInDisplayEntry.Source.garmin`).
    @discardableResult
    public func deleteWeight(_ entry: WeightEntry) async throws -> Bool {
        try await store.delete(id: entry.id)
        guard let outboxEntryId = entry.outboxEntryId else { return false }
        let stillQueued = await outbox.allEntries().contains { $0.id == outboxEntryId && $0.state != .sent }
        if stillQueued {
            try await outbox.delete(id: outboxEntryId)
        }
        return stillQueued
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
    /// - A local entry that WAS delivered but isn't matched to a Garmin
    ///   sample yet (Garmin not re-read since): removed locally only, since
    ///   its `samplePk` isn't known. It reappears from Garmin on the next
    ///   read, where it can then be deleted for real.
    @discardableResult
    public func delete(_ entry: WeighInDisplayEntry) async throws -> WeighInDeletion {
        switch entry.source {
        case .local(let local):
            let cancelled = try await deleteWeight(local)
            return cancelled ? .cancelledBeforeDelivery : .removedLocally

        case .garmin(let sample, let matchedLocal):
            let existingDeletes = await outbox.allEntries().filter { $0.kind == .delete && $0.samplePk == sample.samplePk }
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
    /// A Garmin delete is queued (or an earlier failed one retried).
    case garminDeleteQueued
    /// The weigh-in never reached Garmin; it was simply cancelled.
    case cancelledBeforeDelivery
    /// Delivered but not yet matched to a Garmin sample: removed from this
    /// phone only (see `delete(_:)`).
    case removedLocally
}

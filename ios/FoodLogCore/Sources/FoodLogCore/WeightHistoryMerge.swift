// WeightHistoryMerge.swift
//
// The weigh-in history every weight screen shows (sync-weight-hydration-
// with-garmin, design.md D1). WHY: Garmin is now the source of truth for
// weigh-ins -- a scale or Garmin Connect entry must appear here, and a
// delete must reach Garmin -- but the app's own weigh-ins are committed
// locally first and only reach Garmin later, through `WeightOutbox`. So
// neither list alone is right: this merges Garmin's samples (from the
// `GarminHealthCacheStore` cache) with the local `WeightEntry`s that are
// not in Garmin yet, and drops each delivered local entry in favour of its
// Garmin copy. Garmin's copy wins because it is the trusted one AND it
// carries the `samplePk` a delete needs -- the add route returns 204 with
// no body, so the app can never learn a `samplePk` any other way.
//
// Pure (no I/O, no clock), so every rule below is covered by
// FoodLogCoreTests/WeightHistoryMergeTests.swift. Used by the app's
// `WeightLoader` (GarminFood/Weight) and by `WeightLogCoordinator.delete`.

import Foundation
import GarminKit

/// Where a row stands relative to Garmin.
public enum WeighInSyncState: Sendable, Equatable {
    /// In Garmin (or delivered and assumed so).
    case synced
    /// Logged here, not yet delivered.
    case pending
    /// Logged here, delivery gave up -- retry from the row or the sync queue.
    case failed
    /// A Garmin weigh-in whose queued delete gave up -- it is still in
    /// Garmin, so it is shown again, flagged, until a retry succeeds.
    case deleteFailed
}

/// One row of weigh-in history.
public struct WeighInDisplayEntry: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        /// A Garmin sample. `matchedLocalEntry` is the app's own record of
        /// the same weigh-in, if it was logged here (kept so its note still
        /// shows, and so a delete removes it too).
        case garmin(GarminWeighIn, matchedLocalEntry: WeightEntry?)
        /// An app entry Garmin doesn't have (yet).
        case local(WeightEntry)
    }

    public let source: Source
    public let syncState: WeighInSyncState
    /// The `WeightOutboxEntry` a retry acts on: a local entry's add, or a
    /// Garmin sample's failed delete. `nil` when there is nothing to retry.
    public let outboxEntryId: UUID?

    public init(source: Source, syncState: WeighInSyncState, outboxEntryId: UUID?) {
        self.source = source
        self.syncState = syncState
        self.outboxEntryId = outboxEntryId
    }

    public var id: String {
        switch source {
        case .garmin(let sample, _): return "garmin-\(sample.samplePk)"
        case .local(let entry): return "local-\(entry.id.uuidString)"
        }
    }

    public var weightKg: Double {
        switch source {
        case .garmin(let sample, _): return sample.weightKg
        case .local(let entry): return entry.weightKg
        }
    }

    public var loggedAt: Date {
        switch source {
        case .garmin(let sample, _): return sample.timestamp
        case .local(let entry): return entry.loggedAt
        }
    }

    public var note: String? {
        switch source {
        case .garmin(_, let matched): return matched?.note
        case .local(let entry): return entry.note
        }
    }

    public var isFromGarmin: Bool {
        if case .garmin = source { return true }
        return false
    }
}

public enum WeightHistoryMerge {
    /// A delivered local entry and a Garmin sample are the same weigh-in
    /// when both their times and weights agree this closely (D1). Defined
    /// in GarminKit's `WeighInMatching`, because `WeightOutbox.drain`
    /// resolves a delete-by-match with the very same rule.
    public static let matchTimeTolerance: TimeInterval = WeighInMatching.timeTolerance
    public static let matchWeightToleranceKg: Double = WeighInMatching.weightToleranceKg

    /// Merges Garmin's weigh-ins with the app's own, newest first.
    ///
    /// - `garminWeighIns`: every cached Garmin sample.
    /// - `garminDayFetchedAt`: `calendarDate` -> when Garmin was last read
    ///   for that day (`GarminHealthSnapshot.weighInDayFetchTimes`).
    /// - `localEntries` / `outboxEntries`: `WeightStore.all()` /
    ///   `WeightOutbox.allEntries()`.
    ///
    /// Rules:
    /// 1. A Garmin sample with a `.pending`/`.sent` delete in the outbox is
    ///    hidden (deleted here at once, D3). With a `.failed` delete it is
    ///    shown again as `.deleteFailed`. A delete-by-match (no `samplePk`
    ///    yet -- `WeightOutbox.logDeleteMatching`) applies to the closest
    ///    sample matching its weight/time, the one the drain will resolve.
    /// 2. A local entry whose add is `.pending`/`.failed` is shown as such
    ///    -- never de-duplicated, it isn't in Garmin yet.
    /// 3. A delivered local entry (outbox `.sent`, or its outbox entry gone,
    ///    which only happens after delivery) is dropped in favour of the
    ///    closest unclaimed Garmin sample within the tolerances above.
    /// 4. A delivered local entry with NO matching sample is dropped too if
    ///    Garmin was read for its day AFTER it was delivered -- Garmin is the
    ///    truth, so it was deleted there (e.g. in Connect). If Garmin hasn't
    ///    been read for that day since the delivery (offline, or the read
    ///    hasn't happened yet), it is kept as `.synced` so it doesn't blink
    ///    out of the list in the meantime.
    public static func merge(
        garminWeighIns: [GarminWeighIn],
        garminDayFetchedAt: [String: Date],
        localEntries: [WeightEntry],
        outboxEntries: [WeightOutboxEntry],
        calendar: Calendar = .current
    ) -> [WeighInDisplayEntry] {
        let outboxById = Dictionary(outboxEntries.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })

        // Rule 1: deletes by samplePk.
        var hiddenSamplePks = Set<Int>()
        var failedDeleteBySamplePk: [Int: UUID] = [:]
        var deletesByMatch: [WeightOutboxEntry] = []
        for entry in outboxEntries where entry.kind == .delete {
            guard let samplePk = entry.samplePk else {
                deletesByMatch.append(entry)
                continue
            }
            if entry.state == .failed {
                failedDeleteBySamplePk[samplePk] = entry.id
            } else {
                hiddenSamplePks.insert(samplePk)
            }
        }

        var seenSamplePks = Set<Int>()
        let samples = garminWeighIns.filter { seenSamplePks.insert($0.samplePk).inserted }

        // Rule 1, delete-by-match: each claims its own closest sample among
        // those no other delete already targets.
        var targetedSamplePks = hiddenSamplePks.union(failedDeleteBySamplePk.keys)
        for entry in deletesByMatch {
            guard let sample = WeighInMatching.closest(weightKg: entry.weightKg, at: entry.loggedAt, in: samples, excluding: targetedSamplePks) else { continue }
            targetedSamplePks.insert(sample.samplePk)
            if entry.state == .failed {
                failedDeleteBySamplePk[sample.samplePk] = entry.id
            } else {
                hiddenSamplePks.insert(sample.samplePk)
            }
        }

        var claimedSamplePks = Set<Int>()
        var matchedLocalBySamplePk: [Int: WeightEntry] = [:]
        var rows: [WeighInDisplayEntry] = []

        for local in localEntries.sorted(by: { $0.loggedAt > $1.loggedAt }) {
            let outboxEntry = local.outboxEntryId.flatMap { outboxById[$0] }
            switch outboxEntry?.state {
            case .pending?:
                rows.append(WeighInDisplayEntry(source: .local(local), syncState: .pending, outboxEntryId: outboxEntry?.id))
                continue
            case .failed?:
                rows.append(WeighInDisplayEntry(source: .local(local), syncState: .failed, outboxEntryId: outboxEntry?.id))
                continue
            // `.createdAwaitingDelete` is food-outbox-only (add-log-entry-
            // editing); a weigh-in never reaches it.
            case .sent?, .createdAwaitingDelete?, nil:
                break
            }

            // Rule 3. Hidden samples are candidates too: a local entry whose
            // Garmin copy is being deleted is being deleted as well.
            if let match = closestMatch(for: local, in: samples, excluding: claimedSamplePks) {
                claimedSamplePks.insert(match.samplePk)
                matchedLocalBySamplePk[match.samplePk] = local
                continue
            }

            // Rule 4.
            let day = NutritionDate.string(from: local.loggedAt, calendar: calendar)
            let deliveredAt = outboxEntry?.deliveredAt ?? .distantPast
            if let fetchedAt = garminDayFetchedAt[day], fetchedAt > deliveredAt {
                continue
            }
            rows.append(WeighInDisplayEntry(source: .local(local), syncState: .synced, outboxEntryId: nil))
        }

        for sample in samples where !hiddenSamplePks.contains(sample.samplePk) {
            let failedDeleteId = failedDeleteBySamplePk[sample.samplePk]
            rows.append(WeighInDisplayEntry(
                source: .garmin(sample, matchedLocalEntry: matchedLocalBySamplePk[sample.samplePk]),
                syncState: failedDeleteId == nil ? .synced : .deleteFailed,
                outboxEntryId: failedDeleteId
            ))
        }

        return rows.sorted {
            if $0.loggedAt != $1.loggedAt { return $0.loggedAt > $1.loggedAt }
            return $0.id < $1.id
        }
    }

    /// Whether `local` and `sample` are the same weigh-in (D1 tolerances).
    public static func isSameWeighIn(_ local: WeightEntry, _ sample: GarminWeighIn) -> Bool {
        WeighInMatching.isSame(weightKg: local.weightKg, at: local.loggedAt, as: sample)
    }

    private static func closestMatch(for local: WeightEntry, in samples: [GarminWeighIn], excluding claimed: Set<Int>) -> GarminWeighIn? {
        WeighInMatching.closest(weightKg: local.weightKg, at: local.loggedAt, in: samples, excluding: claimed)
    }
}

extension WeightHistory {
    /// The change from `previous` to `latest` in kg, or `nil` without an
    /// earlier row -- the merged-history twin of `delta(latest:previous:)`.
    public static func delta(latest: WeighInDisplayEntry, previous: WeighInDisplayEntry?) -> Double? {
        guard let previous else { return nil }
        return latest.weightKg - previous.weightKg
    }
}

// Reconciliation.swift
//
// After a drain, re-read the day's log from Garmin and match delivered
// entries against it (design.md D5, tasks 10.1-10.3; garmin-sync spec's
// "Delivered entries are reconciled against Garmin, not against local
// state" requirement). Garmin is authoritative; a process's own outbox
// record is a claim about what SHOULD be true, not a source of truth about
// what IS true.
//
// Match key: (date, mealType, foodId, servingId, numberOfUnits) -- date and
// mealType come from which day/meal bucket an entry is found in, foodId and
// servingId from `LoggedFood`, numberOfUnits via `LoggedFood.matchesQuantity`
// (see GarminModels.swift for why that comparison is deliberately tolerant
// of either candidate quantity field).

import Foundation

/// The subset of `GarminClient` reconciliation needs. Exists so
/// `Reconciliation.reconcile(delivered:using:)` can be unit-tested with a
/// fake day's log, no network access required -- see
/// GarminKitTests/ReconciliationTests.swift.
public protocol FoodLogReconciling: Sendable {
    func dailyFoodLog(date: String) async throws -> DailyFoodLog?
    @discardableResult
    func deleteFoodLogEntries(logIds: [String]) async throws -> HTTPURLResponse
}

public struct ReconciliationOutcome: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        /// This entry has exactly one corresponding Garmin entry -- the
        /// happy path.
        case confirmed(logId: String?)
        /// More Garmin entries matched this entry's key than were locally
        /// expected; the excess (not necessarily just one -- see B1's
        /// grouped resolution in `resolveGroup`) were deleted, and this
        /// entry was matched to one of the kept copies.
        case duplicateResolved(keptLogId: String?, deletedLogIds: [String])
        /// A 2xx was received on delivery, but no matching entry exists on
        /// re-read. Re-queued.
        case missingRequeued
        /// The day's log couldn't be re-read this cycle (network error,
        /// etc). Not a verdict either way -- try again on the next drain.
        case reconciliationSkipped
    }

    public let entryId: UUID
    public let date: String
    public let verdict: Verdict
}

public actor Reconciliation {
    private let outbox: Outbox

    public init(outbox: Outbox) {
        self.outbox = outbox
    }

    /// Reconciles a batch of just-delivered entries (typically
    /// `DrainResult.delivered` from `Outbox.drain`) against Garmin's own
    /// record of each entry's day.
    ///
    /// B1 fix: entries sharing the same match key (date, mealType, foodId,
    /// servingId, numberOfUnits) are resolved TOGETHER, not independently.
    /// Two genuinely-distinct local entries (e.g. the user really did log
    /// the same snack twice) share a match key and both legitimately match
    /// two Garmin entries on re-read; resolving them one call at a time used
    /// to have each call independently see "2 Garmin matches" and each
    /// conclude "delete 1 duplicate", so both calls raced to delete the same
    /// second copy -- net-deleting a real user entry. Resolving the whole
    /// group at once makes "N locally-expected vs M found on Garmin" the
    /// only quantity that decides what happens (see `resolveGroup`).
    @discardableResult
    public func reconcile(
        delivered: [OutboxEntry],
        using client: some FoodLogReconciling
    ) async -> [ReconciliationOutcome] {
        guard !delivered.isEmpty else { return [] }

        var outcomes: [ReconciliationOutcome] = []
        // Fetch each distinct date's log at most once, even if several
        // entries landed on the same day this cycle.
        let entriesByDate = Dictionary(grouping: delivered, by: \.date)

        for (date, entriesForDate) in entriesByDate {
            let log: DailyFoodLog?
            do {
                log = try await client.dailyFoodLog(date: date)
            } catch {
                for entry in entriesForDate {
                    outcomes.append(ReconciliationOutcome(entryId: entry.id, date: date, verdict: .reconciliationSkipped))
                }
                continue
            }

            // Within this date, group again by the rest of the match key so
            // every entry that shares a full (date, mealType, foodId,
            // servingId, numberOfUnits) key is resolved as one unit.
            let entriesByKey = Dictionary(grouping: entriesForDate, by: MatchKey.init)
            for (_, group) in entriesByKey {
                let groupOutcomes = await resolveGroup(group, in: log, date: date, using: client)
                outcomes.append(contentsOf: groupOutcomes)
            }
        }

        return outcomes
    }

    /// Resolves one match-key group's worth of just-delivered entries
    /// against however many Garmin entries actually match that key.
    ///
    /// For N locally-expected entries and M matching Garmin entries:
    ///   - M == N: every entry is confirmed 1:1 against a Garmin entry.
    ///   - M >  N: exactly (M - N) excess remote entries are deleted -- not
    ///     "delete down to 1" regardless of how many entries share the key.
    ///   - M <  N: exactly (N - M) entries are re-queued as missing; the
    ///     rest are confirmed.
    ///
    /// Confirmed/duplicate-resolved entries (i.e. entries proven to have
    /// exactly one corresponding Garmin entry) are removed from the outbox
    /// store entirely (R4) -- they are done, and keeping delivered entries
    /// around forever would make `OutboxStore.persist()` rewrite an
    /// ever-growing array on every future mutation for no benefit. Entries
    /// re-queued as missing are deliberately NOT removed; they go back to
    /// `.pending` instead (via `Outbox.requeue`).
    private func resolveGroup(
        _ group: [OutboxEntry],
        in log: DailyFoodLog?,
        date: String,
        using client: some FoodLogReconciling
    ) async -> [ReconciliationOutcome] {
        guard let representative = group.first else { return [] }
        // Every entry in `group` shares the same (mealType, foodId,
        // servingId, numberOfUnits) by construction (`MatchKey`), so any one
        // of them produces the identical match set.
        let matches = Self.matchingLoggedFoods(for: representative, in: log)
        let sortedMatches = Self.sortedByTimestamp(matches)
        let sortedGroup = Self.sortedByCreation(group)

        let n = sortedGroup.count
        let m = sortedMatches.count

        if m == n {
            // Exactly as many Garmin entries as locally expected (this also
            // covers the ordinary N == 1, M == 1 happy path) -- nothing to
            // delete, nothing missing.
            let outcomes = zip(sortedGroup, sortedMatches).map { entry, match in
                ReconciliationOutcome(entryId: entry.id, date: date, verdict: .confirmed(logId: match.logId))
            }
            await removeConfirmed(sortedGroup)
            return outcomes
        }

        if m > n {
            // More Garmin entries than locally expected: exactly (m - n)
            // are excess duplicates (e.g. a drain that retried after a
            // successful-but-unacknowledged POST). Keep the n
            // earliest-logged copies (deterministic tie-break: sort by
            // logTimestamp, falling back to logId), delete the rest --
            // never "down to 1" regardless of how many entries share this
            // key.
            let toKeep = Array(sortedMatches.prefix(n))
            let toDelete = sortedMatches.dropFirst(n).compactMap(\.logId)

            if !toDelete.isEmpty {
                do {
                    try await client.deleteFoodLogEntries(logIds: Array(toDelete))
                    Self.logLoudly("deleted \(toDelete.count) excess duplicate(s) for \(representative.mealType.rawValue)/\(representative.foodId) on \(date) (\(n) locally expected, \(m) found on Garmin).")
                } catch {
                    Self.logLoudly("found \(toDelete.count) excess duplicate(s) for \(representative.mealType.rawValue)/\(representative.foodId) on \(date) (\(n) locally expected, \(m) found on Garmin) but failed to delete: \(error)")
                }
            }
            let outcomes = zip(sortedGroup, toKeep).map { entry, match in
                ReconciliationOutcome(entryId: entry.id, date: date, verdict: .duplicateResolved(keptLogId: match.logId, deletedLogIds: Array(toDelete)))
            }
            await removeConfirmed(sortedGroup)
            return outcomes
        }

        // m < n: fewer Garmin entries than locally expected -- (n - m)
        // entries that received a 2xx are nonetheless missing on re-read.
        // Confirm the m that do have a Garmin match; re-queue the rest, and
        // make sure the discrepancy is loud, not a silent retry with no
        // trace (garmin-sync spec).
        let confirmedEntries = Array(sortedGroup.prefix(m))
        let missingEntries = Array(sortedGroup.dropFirst(m))

        var outcomes = zip(confirmedEntries, sortedMatches).map { entry, match in
            ReconciliationOutcome(entryId: entry.id, date: date, verdict: .confirmed(logId: match.logId))
        }
        await removeConfirmed(confirmedEntries)

        for entry in missingEntries {
            var requeued = entry
            requeued.state = .pending
            requeued.attemptCount = 0
            requeued.lastError = "reconciliation: 2xx received but entry not found on re-read of \(entry.date)"
            requeued.nextAttemptAt = Date()
            try? await outbox.requeue(requeued)
            Self.logLoudly("entry \(entry.id) got a 2xx but is missing from Garmin's \(entry.date) log; re-queued.")
            outcomes.append(ReconciliationOutcome(entryId: entry.id, date: date, verdict: .missingRequeued))
        }

        return outcomes
    }

    /// R4: entries proven delivered (confirmed, or the kept side of a
    /// duplicate resolution) are done -- remove them from the outbox store
    /// rather than keeping them forever. Best-effort (`try?`): if this
    /// happens to fail, the entry simply survives in the store as `.sent`
    /// and gets reconciled (and removed) again next cycle; it is never
    /// re-delivered, since `Outbox.drain` only ever attempts `.pending`
    /// entries.
    private func removeConfirmed(_ entries: [OutboxEntry]) async {
        for entry in entries {
            try? await outbox.delete(id: entry.id)
        }
    }

    /// Groups entries by the parts of the match key beyond `date` (which the
    /// caller already groups by separately to fetch each day's log once).
    private struct MatchKey: Hashable {
        let mealType: String
        let foodId: String
        let servingId: String
        let numberOfUnits: Double

        init(_ entry: OutboxEntry) {
            self.mealType = entry.mealType.rawValue
            self.foodId = entry.foodId
            self.servingId = entry.servingId
            self.numberOfUnits = entry.numberOfUnits
        }
    }

    /// Deterministic ordering for Garmin's matching entries: earliest
    /// `logTimestamp` first, falling back to `logId` so the choice is still
    /// stable rather than arbitrary when timestamps are missing or equal.
    private static func sortedByTimestamp(_ matches: [LoggedFood]) -> [LoggedFood] {
        matches.sorted {
            ($0.logTimestamp ?? "", $0.logId ?? "") < ($1.logTimestamp ?? "", $1.logId ?? "")
        }
    }

    /// Deterministic ordering for local entries sharing a match key: oldest
    /// `createdAt` first, falling back to `id` so the choice is still stable
    /// rather than arbitrary when timestamps are equal.
    private static func sortedByCreation(_ entries: [OutboxEntry]) -> [OutboxEntry] {
        entries.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
    }

    /// Pure matching logic, extracted so it is unit-testable with a
    /// hand-built `DailyFoodLog` and no network access whatsoever.
    static func matchingLoggedFoods(for entry: OutboxEntry, in log: DailyFoodLog?) -> [LoggedFood] {
        guard let log else { return [] }
        let candidatesInMeal = (log.mealDetails ?? [])
            .filter { $0.meal?.mealName == entry.mealType.rawValue }
            .flatMap { $0.loggedFoods ?? [] }

        return candidatesInMeal.filter { food in
            food.foodId == entry.foodId
                && food.servingId == entry.servingId
                && food.matchesQuantity(entry.numberOfUnits)
        }
    }

    /// `NSLog` rather than `print`: it shows up in the device console even
    /// in a release build with no attached debugger, which matters for a
    /// background drain nobody is watching interactively (design.md D9:
    /// "no interactive debugger"). This is an operational log, not the
    /// user-facing auth banner -- that's `GarminAuthState`'s job -- but per
    /// design.md D7's spirit, a reconciliation discrepancy must never
    /// disappear without a trace.
    private static func logLoudly(_ message: String) {
        NSLog("[GarminKit.Reconciliation] %@", message)
    }
}

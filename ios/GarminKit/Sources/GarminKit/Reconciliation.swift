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
//
// add-log-entry-editing (design.md D2) adds three kinds of Garmin entries
// that match a key without being "this group's delivery":
//   - the OLD entry of any replace still in the outbox (`replaces.logId`) --
//     expected to vanish, deleted by the replace itself, so never counted
//     here and never deleted here;
//   - the SOURCE of a duplicate (`duplicateOf`) -- an older entry with the
//     same key, which would otherwise make the duplicate's own delivery look
//     like an excess copy and get it deleted;
//   - the corrected entry a `.createdAwaitingDelete` replace already created
//     -- a legitimately expected copy, so the temporary duplicate it forms
//     with an identical `.sent` entry is not "deleted again".
// The first two are excluded only while that doesn't make a delivered entry
// look missing (see `resolveGroup`): a false "missing" would re-send it.
//
// What gets DELETED is decided far more narrowly than what gets COUNTED
// (fix/reconcile-duplicate-delete, 2026-09-23). Counting is generous on
// purpose -- `couldBeThisAppsDelivery` lets an entry logged up to 10 minutes
// before a delivery count toward it, so clock skew never makes a real
// delivery look missing and get re-sent. But that same generosity used to
// decide deletion too: a second coffee logged 5 minutes after the first
// (from search/Usual/Recent, a move into that meal, a same-day copyMeal)
// found "2 copies, 1 expected" and the LATER one -- the one just logged --
// was deleted from Garmin; for a move, whose old entry is already gone,
// that lost the food entirely. The only duplicate this file exists to clean
// up is one of THIS app's own deliveries sent twice (a create retried after
// a lost 2xx, a re-send after a "missing" verdict, a replace re-created
// after a crash) -- and every such re-send carries the SAME `createdAt` as
// its `logTimestamp`. So only a Garmin entry whose timestamp is exactly a
// locally-expected entry's `createdAt`, left over once each such entry has
// its own copy, is ever deleted (`provableRetryCopies`). Anything that
// can't be proven a re-send is kept: a leftover duplicate is visible and
// one tap to remove, a deleted real log is silent data loss.

import Foundation

/// The subset of `GarminClient` reconciliation needs. Exists so
/// `Reconciliation.reconcile(delivered:using:)` can be unit-tested with a
/// fake day's log, no network access required -- see
/// GarminKitTests/ReconciliationTests.swift.
public protocol FoodLogReconciling: Sendable {
    func dailyFoodLog(date: String) async throws -> DailyFoodLog?
    @discardableResult
    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse
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
        /// As `missingRequeued`, but this entry has now gone missing after
        /// delivery as many times as it's allowed to be retried, so it was
        /// marked `.failed` instead of being sent yet again.
        case missingGaveUp
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
        // add-log-entry-editing D2: what else in this outbox explains a
        // Garmin entry (see this file's header).
        let queued = await outbox.allEntries()
        let deliveredIds = Set(delivered.map(\.id))
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
            let expectedToVanish = Set(queued.compactMap { entry -> String? in
                guard let replaced = entry.replaces, replaced.date == date else { return nil }
                return replaced.logId
            })
            for (key, group) in entriesByKey {
                let alsoExpected = queued.filter {
                    $0.state == .createdAwaitingDelete
                        && $0.date == date
                        && !deliveredIds.contains($0.id)
                        && MatchKey($0) == key
                }
                let groupOutcomes = await resolveGroup(
                    group,
                    in: log,
                    date: date,
                    expectedToVanish: expectedToVanish,
                    alsoExpected: alsoExpected,
                    using: client
                )
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
    ///   - M >  N: AT MOST (M - N) remote entries are deleted -- not "delete
    ///     down to 1" regardless of how many entries share the key -- and
    ///     only those that are provably re-sent copies of this group's own
    ///     deliveries (`provableRetryCopies`). If none are, M > N just means
    ///     the user has other identical entries (logged earlier, moved in,
    ///     copied in): every entry is confirmed and nothing is deleted.
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
    ///
    /// add-log-entry-editing D2: `expectedToVanish` (old entries of pending
    /// replaces) and the group's `duplicateOf` sources are left out of M,
    /// unless leaving them out would make M < N (see
    /// `excludingExplained`); `alsoExpected` (`.createdAwaitingDelete`
    /// replaces whose corrected entry already exists under this key) raises
    /// the number of copies that may exist before any is "excess", and each
    /// one's own copy is protected from deletion like the group's own.
    /// With neither, this is exactly the N-vs-M rule above.
    private func resolveGroup(
        _ group: [OutboxEntry],
        in log: DailyFoodLog?,
        date: String,
        expectedToVanish: Set<String>,
        alsoExpected: [OutboxEntry],
        using client: some FoodLogReconciling
    ) async -> [ReconciliationOutcome] {
        guard let representative = group.first else { return [] }
        // Every entry in `group` shares the same (mealType, foodId,
        // servingId, numberOfUnits) by construction (`MatchKey`), so any one
        // of them produces the identical match set.
        let sortedGroup = Self.sortedByCreation(group)
        let earliestCreated = sortedGroup.first?.createdAt ?? Date()
        let matches = Self.matchingLoggedFoods(for: representative, in: log)
            .filter { Self.couldBeThisAppsDelivery($0, notBefore: earliestCreated) }
        let n = sortedGroup.count
        let excluded = expectedToVanish.union(sortedGroup.compactMap(\.duplicateOf))
        let sortedMatches = Self.excludingExplained(Self.sortedByTimestamp(matches), excluded: excluded, keepAtLeast: n)

        let m = sortedMatches.count
        let expectedTotal = n + alsoExpected.count

        if m >= n && m <= expectedTotal {
            // As many Garmin entries as locally expected (this also covers
            // the ordinary N == 1, M == 1 happy path), plus at most the
            // copies awaiting-delete replaces account for -- nothing to
            // delete, nothing missing.
            let outcomes = Self.pairedWithOwnDelivery(sortedGroup, among: sortedMatches).map { entry, match in
                ReconciliationOutcome(entryId: entry.id, date: date, verdict: .confirmed(logId: match.logId))
            }
            await removeConfirmed(sortedGroup)
            return outcomes
        }

        if m > expectedTotal {
            // More Garmin entries than locally expected. That alone proves
            // nothing: the extra ones may be the user's own separate,
            // identical logs (an earlier coffee inside the clock tolerance,
            // a move or copy into this meal). Only a re-sent copy of one of
            // THIS group's deliveries (e.g. a drain that retried after a
            // successful-but-unacknowledged create) is deleted, and never
            // more than (m - expectedTotal) of them.
            let toDelete = Self.provableRetryCopies(
                in: sortedMatches,
                expectedCreatedAt: (sortedGroup + alsoExpected).map(\.createdAt),
                protected: excluded,
                limit: m - expectedTotal
            ).compactMap(\.logId)

            if toDelete.isEmpty {
                // Nothing provably a re-send: keep every entry. A real
                // leftover duplicate stays visible for the user to remove;
                // guessing wrong here would silently delete a real log.
                Self.logLoudly("kept \(m - expectedTotal) more identical \(representative.mealType.rawValue) entr(ies) on \(date) than expected (\(n) locally expected, \(m) found on Garmin); none is provably a re-sent copy of this delivery.")
                let outcomes = Self.pairedWithOwnDelivery(sortedGroup, among: sortedMatches).map { entry, match in
                    ReconciliationOutcome(entryId: entry.id, date: date, verdict: .confirmed(logId: match.logId))
                }
                await removeConfirmed(sortedGroup)
                return outcomes
            }

            let deletedSet = Set(toDelete)
            let toKeep = sortedMatches.filter { match in
                guard let logId = match.logId else { return true }
                return !deletedSet.contains(logId)
            }

            do {
                try await client.deleteFoodLogEntries(logIds: toDelete, date: date)
                // 2026-09-21 security fix: no longer embeds `foodId` (which
                // food was actually logged) -- NSLog output is readable via
                // Console.app/sysdiagnose with only brief physical/USB
                // access to an unlocked device, no debugger needed. The
                // meal category + date + counts are still enough to
                // diagnose a reconciliation issue.
                Self.logLoudly("deleted \(toDelete.count) re-sent duplicate(s) for \(representative.mealType.rawValue) on \(date) (\(n) locally expected, \(m) found on Garmin).")
            } catch {
                Self.logLoudly("found \(toDelete.count) re-sent duplicate(s) for \(representative.mealType.rawValue) on \(date) (\(n) locally expected, \(m) found on Garmin) but failed to delete: \(error)")
            }
            let outcomes = Self.pairedWithOwnDelivery(sortedGroup, among: toKeep).map { entry, match in
                ReconciliationOutcome(entryId: entry.id, date: date, verdict: .duplicateResolved(keptLogId: match.logId, deletedLogIds: toDelete))
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
            let reason = "reconciliation: 2xx received but entry not found on re-read of \(entry.date)"
            let updated = try? await outbox.requeueMissingAfterDelivery(entry, reason: reason)
            if updated?.state == .failed {
                Self.logLoudly("entry \(entry.id) got a 2xx but is still missing from Garmin's \(entry.date) log after \(updated?.attemptCount ?? 0) deliveries; giving up.")
                outcomes.append(ReconciliationOutcome(entryId: entry.id, date: date, verdict: .missingGaveUp))
            } else {
                Self.logLoudly("entry \(entry.id) got a 2xx but is missing from Garmin's \(entry.date) log; re-queued.")
                outcomes.append(ReconciliationOutcome(entryId: entry.id, date: date, verdict: .missingRequeued))
            }
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

    /// add-log-entry-editing D2: drops the Garmin entries whose `logId` is in
    /// `excluded` (an old entry a replace will delete, or a duplicate's
    /// source) -- but only down to `keepAtLeast`. If this group's own
    /// deliveries can't all be accounted for without them, the earliest
    /// excluded ones are put back: an edit or duplicate of an entry whose
    /// OWN delivery hadn't been reconciled yet would otherwise make that
    /// delivery look missing, and a "missing" entry is sent again. Putting
    /// them back never pushes the count above `keepAtLeast`, so an excluded
    /// entry is never deleted as an excess copy either. `sorted` must
    /// already be in `sortedByTimestamp` order; so is the result.
    static func excludingExplained(_ sorted: [LoggedFood], excluded: Set<String>, keepAtLeast: Int) -> [LoggedFood] {
        guard !excluded.isEmpty else { return sorted }
        func isExcluded(_ food: LoggedFood) -> Bool {
            guard let logId = food.logId else { return false }
            return excluded.contains(logId)
        }
        let kept = sorted.filter { !isExcluded($0) }
        guard kept.count < keepAtLeast else { return kept }
        let restored = sorted.filter { isExcluded($0) }.prefix(keepAtLeast - kept.count)
        return sortedByTimestamp(kept + Array(restored))
    }

    /// How close a Garmin entry's `logTimestamp` must be to a local entry's
    /// `createdAt` to be that entry's own delivery (or a re-send of it).
    /// This app sends `createdAt` itself as `logTimestamp`, to the
    /// millisecond (`FoodLogWriteBody.logTimestampString`), and Garmin reads
    /// it back as sent (docs/garmin-food-log-contract.md, 2026-09-16) -- the
    /// slack only absorbs the sub-millisecond part the wire format drops.
    /// If Garmin ever stopped echoing it, nothing would match: duplicates
    /// would be left for the user rather than real logs deleted.
    static let ownDeliveryTimestampTolerance: TimeInterval = 0.002

    /// Whether `food` carries exactly the `logTimestamp` this app sends for
    /// a local entry created at `createdAt`. Unlike
    /// `couldBeThisAppsDelivery`, this fails CLOSED: a missing or
    /// unparseable timestamp proves nothing, and this is what licenses a
    /// delete.
    static func isOwnDelivery(_ food: LoggedFood, ofEntryCreatedAt createdAt: Date) -> Bool {
        guard let raw = food.logTimestamp, let logged = parseLogTimestamp(raw) else { return false }
        return abs(logged.timeIntervalSince(createdAt)) <= ownDeliveryTimestampTolerance
    }

    /// The Garmin entries that are provably surplus re-sends of locally
    /// expected deliveries, latest first to go, at most `limit` of them.
    ///
    /// Every re-send of one outbox entry (a create retried after a lost
    /// 2xx, a re-send after a "missing" verdict, a replace re-created after
    /// a crash) carries that entry's one `createdAt` as its timestamp. So:
    /// each expected local entry first claims one Garmin entry with its own
    /// timestamp -- the copy it really is (two entries created in the same
    /// instant, e.g. by `copyMeal`, claim two) -- and only entries with such
    /// a timestamp left over after that are candidates. An entry logged at
    /// any other moment -- earlier the same morning, moved or copied in --
    /// is never one, however close in time; nor is anything in `protected`
    /// (an old entry a replace deletes itself, a duplicate's source), nor
    /// anything without a `logId` to delete by. `sorted` must be in
    /// `sortedByTimestamp` order, so the earliest-`logId` copy is the one
    /// kept.
    static func provableRetryCopies(
        in sorted: [LoggedFood],
        expectedCreatedAt: [Date],
        protected: Set<String>,
        limit: Int
    ) -> [LoggedFood] {
        guard limit > 0 else { return [] }
        var claimed = Set<Int>()
        for createdAt in expectedCreatedAt.sorted() {
            let own = sorted.indices.first { index in
                !claimed.contains(index) && isOwnDelivery(sorted[index], ofEntryCreatedAt: createdAt)
            }
            if let own {
                claimed.insert(own)
            }
        }
        let candidates = sorted.indices.filter { index in
            let food = sorted[index]
            guard !claimed.contains(index), let logId = food.logId, !protected.contains(logId) else { return false }
            return expectedCreatedAt.contains { isOwnDelivery(food, ofEntryCreatedAt: $0) }
        }
        return candidates.suffix(limit).map { sorted[$0] }
    }

    /// Pairs each local entry (in `sortedByCreation` order) with the Garmin
    /// entry an outcome reports for it: its own delivery when one can be
    /// told apart by timestamp (`isOwnDelivery`), otherwise the earliest
    /// one still unpaired -- which is exactly the old positional pairing
    /// when no timestamp matches. Only chooses which `logId` a verdict
    /// names; never decides what is deleted. Returns one pair per entry as
    /// long as `matches` has at least as many elements as `entries`.
    static func pairedWithOwnDelivery(_ entries: [OutboxEntry], among matches: [LoggedFood]) -> [(OutboxEntry, LoggedFood)] {
        var used = Set<Int>()
        var ownIndex: [Int?] = []
        for entry in entries {
            let own = matches.indices.first { index in
                !used.contains(index) && isOwnDelivery(matches[index], ofEntryCreatedAt: entry.createdAt)
            }
            if let own {
                used.insert(own)
            }
            ownIndex.append(own)
        }
        var pairs: [(OutboxEntry, LoggedFood)] = []
        for (entry, own) in zip(entries, ownIndex) {
            if let own {
                pairs.append((entry, matches[own]))
            } else if let next = matches.indices.first(where: { !used.contains($0) }) {
                used.insert(next)
                pairs.append((entry, matches[next]))
            }
        }
        return pairs
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

    /// How far a Garmin entry's `logTimestamp` may precede a local entry's
    /// `createdAt` and still count as possibly this app's own delivery.
    /// Generous on purpose: if Garmin replaced the client's timestamp with
    /// its own receive time, a phone clock running ahead of Garmin's would
    /// otherwise make a real delivery look "too early", get it re-queued,
    /// and send it again.
    static let deliveryClockTolerance: TimeInterval = 10 * 60

    /// Whether `food` could be an entry this app delivered, for a group
    /// whose earliest local entry was created at `earliestCreated`.
    ///
    /// The match key alone can't answer that: (meal, food, serving,
    /// quantity) is just as true of an identical entry the user logged in
    /// the official app earlier the same day. Counting that entry made a
    /// normal delivery look like an excess duplicate -- and excess
    /// duplicates are DELETED, latest first, so the copy that went was the
    /// one just logged here. Both apps stamp an entry with the moment it was
    /// logged (this one sends `createdAt` as `logTimestamp`), and nothing
    /// this app delivers can have been logged before it was queued, so
    /// anything logged earlier is ruled out.
    ///
    /// Fails open: a missing or unparseable timestamp can't rule anything
    /// out, so it still counts, which is exactly the behaviour before this
    /// check existed.
    ///
    /// This decides only what COUNTS toward a delivery (so skew never makes
    /// a real delivery look missing and get re-sent) -- never what may be
    /// deleted. An entry inside the tolerance can still be the user's own
    /// separate log; deletion additionally requires `isOwnDelivery`, via
    /// `provableRetryCopies`.
    static func couldBeThisAppsDelivery(_ food: LoggedFood, notBefore earliestCreated: Date) -> Bool {
        guard let raw = food.logTimestamp, let logged = parseLogTimestamp(raw) else { return true }
        return logged >= earliestCreated.addingTimeInterval(-deliveryClockTolerance)
    }

    /// `2026-09-16T13:35:49.324Z` as observed, with or without the fraction.
    static func parseLogTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }
        return ISO8601DateFormatter().date(from: raw)
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

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
        /// Exactly one matching entry was found -- the happy path.
        case confirmed(logId: String?)
        /// More than one matching entry was found; all but one were deleted.
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

            for entry in entriesForDate {
                let verdict = await resolve(entry: entry, in: log, using: client)
                outcomes.append(ReconciliationOutcome(entryId: entry.id, date: date, verdict: verdict))
            }
        }

        return outcomes
    }

    private func resolve(
        entry: OutboxEntry,
        in log: DailyFoodLog?,
        using client: some FoodLogReconciling
    ) async -> ReconciliationOutcome.Verdict {
        let matches = Self.matchingLoggedFoods(for: entry, in: log)

        switch matches.count {
        case 0:
            // A 2xx was received but the entry isn't actually there.
            // Re-queue it, and make sure the discrepancy is loud, not a
            // silent retry with no trace (garmin-sync spec).
            var requeued = entry
            requeued.state = .pending
            requeued.attemptCount = 0
            requeued.lastError = "reconciliation: 2xx received but entry not found on re-read of \(entry.date)"
            requeued.nextAttemptAt = Date()
            try? await outbox.requeue(requeued)
            Self.logLoudly("entry \(entry.id) got a 2xx but is missing from Garmin's \(entry.date) log; re-queued.")
            return .missingRequeued

        case 1:
            return .confirmed(logId: matches[0].logId)

        default:
            // Duplicate. Keep the earliest-logged copy (deterministic: sort
            // by logTimestamp when present, falling back to logId so the
            // choice is still stable rather than arbitrary), delete the
            // rest.
            let sorted = matches.sorted {
                ($0.logTimestamp ?? "", $0.logId ?? "") < ($1.logTimestamp ?? "", $1.logId ?? "")
            }
            let keep = sorted[0]
            let toDelete = sorted.dropFirst().compactMap(\.logId)

            if !toDelete.isEmpty {
                do {
                    try await client.deleteFoodLogEntries(logIds: Array(toDelete))
                    Self.logLoudly("deleted \(toDelete.count) duplicate(s) of entry \(entry.id) on \(entry.date).")
                } catch {
                    Self.logLoudly("found \(toDelete.count) duplicate(s) of entry \(entry.id) on \(entry.date) but failed to delete: \(error)")
                }
            }
            return .duplicateResolved(keptLogId: keep.logId, deletedLogIds: Array(toDelete))
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

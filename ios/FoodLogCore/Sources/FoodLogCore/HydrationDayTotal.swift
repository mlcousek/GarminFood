// HydrationDayTotal.swift
//
// "How much water today" with Garmin as the source of truth
// (sync-weight-hydration-with-garmin, design.md D4). WHY: Garmin's
// hydration read (`GET /usersummary-service/usersummary/hydration/daily/
// {date}`, live-verified 2026-09-23) returns only a day TOTAL -- it includes
// water logged on the watch or in Connect, which the app's own
// `HydrationStore` never sees, so the local sum alone is wrong. But the
// total is also missing whatever this app logged that hasn't been delivered
// yet. So:
//
//     shown = Garmin's valueInML
//           + every outbox entry for that day that Garmin's number can't
//             include yet (not delivered, or delivered after the read)
//
// Outbox entries rather than `HydrationEntry`s, because a removed drink
// that already reached Garmin exists ONLY as a queued negative correction
// in the outbox (`HydrationLogCoordinator.removeHydration`) -- counting the
// outbox makes the total drop the moment the user removes it (spec
// "Removing a drink corrects Garmin's total").
//
// Pure; unit-tested in FoodLogCoreTests/HydrationDayTotalTests.swift. Used
// by the app's `HydrationLoader`.

import Foundation
import GarminKit

public enum HydrationDayTotal {
    /// The day's total in ml, never negative.
    ///
    /// - `garminDaily`/`garminFetchedAt`: the cached Garmin read for `day`
    ///   and when it was made (`GarminHealthSnapshot.hydrationDays`). When
    ///   either is `nil` (never read -- first launch offline), the total
    ///   falls back to the app's own entries for the day, the pre-2026-09-23
    ///   behaviour.
    /// - `outboxEntries`: `HydrationOutbox.allEntries()`, drinks AND
    ///   corrections, every state.
    public static func total(
        garminDaily: HydrationDaily?,
        garminFetchedAt: Date?,
        outboxEntries: [HydrationOutboxEntry],
        on day: Date,
        calendar: Calendar = .current
    ) -> Double {
        // A drink removed while its delivery was in flight counts for
        // nothing until it settles (dropped, or delivered + corrected).
        let sameDay = outboxEntries.filter { !$0.isWithdrawn && calendar.isDate($0.loggedAt, inSameDayAs: day) }

        guard let garminDaily, let garminFetchedAt else {
            return max(sameDay.reduce(0) { $0 + $1.valueInML }, 0)
        }

        let notYetInGarmin = sameDay.filter { entry in
            guard entry.state == .sent else { return true }
            // Delivered: Garmin's number includes it only if the read came
            // after the delivery. A delivery by an older build has no
            // `deliveredAt`; it happened before any read this build made.
            return (entry.deliveredAt ?? .distantPast) > garminFetchedAt
        }
        let garminValue = garminDaily.valueInML ?? 0
        return max(garminValue + notYetInGarmin.reduce(0) { $0 + $1.valueInML }, 0)
    }
}

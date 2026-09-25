// StreakFreezePlanner.swift
//
// add-weekly-boss-and-streak-freezes design D6: decides, without any user
// action, which recent missed days a streak freeze covers. Pure: logged
// days, already-frozen days, freeze grants, recorded consumptions and
// "today" in; the NEW consumptions out. The caller (`WeeklyBossFeature.
// applyStreakFreezes`) persists them in `StreakFreezeStore` and only then
// passes the union of frozen days into `StreakEngine`/`StreakHistory`.
//
// Loop (earliest miss first, so a freeze always saves the streak at the
// point it would first have broken):
//   1. walk = StreakEngine.simulate(logged, frozen, today)
//   2. the earliest day d with outcome `.missed` where
//        today - 7 <= d < today,
//        the running length immediately before d was >= 3 (owner decision:
//          only real streaks are protected), and
//        a freeze earned strictly BEFORE d is still available
//          (`FreezeBalance.available(forMissOn:)`)
//   3. found -> freeze d, record the consumption, repeat; else stop.
//
// A `.grace` day is never frozen (the grace rule already forgave it), and
// a frozen day that is later backfilled simply walks as `.logged` -- the
// consumption stays (no refund). With no grants, nothing is ever consumed,
// so the streak is exactly what it was before this change. Idempotent: a
// second run over its own output finds no new qualifying miss.
//
// Depends on: StreakEngine.simulate (internal walk), FreezeBalance,
// StreakFreezeStore.Consumption, FreezeDayKey.
// Depended on by: WeeklyBossFeature.applyStreakFreezes.

import Foundation

public enum StreakFreezePlanner {
    /// Owner decision: freezes protect streaks of at least this many days.
    public static let minimumProtectedLength = 3
    /// Only misses within this many days before today are considered.
    public static let lookbackDays = 7

    public struct Plan: Sendable, Equatable {
        /// Consumptions to record (empty = nothing to do).
        public let newConsumptions: [StreakFreezeStore.Consumption]
        /// Every frozen day after the plan (existing + new), midnights.
        public let frozenDays: Set<Date>
    }

    public static func plan(
        loggedDays: Set<Date>,
        frozenDays: Set<Date>,
        grants: [RewardLedger.FreezeGrant],
        consumptions: [StreakFreezeStore.Consumption],
        today: Date,
        calendar: Calendar
    ) -> Plan {
        var frozen = frozenDays
        var allConsumptions = consumptions
        var fresh: [StreakFreezeStore.Consumption] = []
        let todayKey = FreezeDayKey.key(for: today, calendar: calendar)
        let earliest = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today

        // Each pass freezes at most one day; a small bound keeps this total.
        for _ in 0..<(lookbackDays + 1) {
            let walk = StreakEngine.simulate(loggedDays: loggedDays, frozenDays: frozen, today: today, calendar: calendar)
            let candidates = walk.outcomes
                .filter { $0.value == .missed && $0.key >= earliest && $0.key < today }
                .map(\.key)
                .sorted()
            var chosen: (day: Date, length: Int)?
            for day in candidates {
                let length = walk.lengthBefore[day] ?? 0
                guard length >= minimumProtectedLength else { continue }
                let key = FreezeDayKey.key(for: day, calendar: calendar)
                guard FreezeBalance.available(forMissOn: key, grants: grants, consumptions: allConsumptions) >= 1 else { continue }
                chosen = (day, length)
                break
            }
            guard let chosen else { break }
            let consumption = StreakFreezeStore.Consumption(
                frozenDay: FreezeDayKey.key(for: chosen.day, calendar: calendar),
                consumedOn: todayKey,
                protectedLength: chosen.length
            )
            frozen.insert(chosen.day)
            allConsumptions.append(consumption)
            fresh.append(consumption)
        }
        return Plan(newConsumptions: fresh, frozenDays: frozen)
    }

    /// The consumptions' frozen days as midnights in `calendar`.
    public static func frozenDays(
        from consumptions: [StreakFreezeStore.Consumption],
        calendar: Calendar
    ) -> Set<Date> {
        Set(consumptions.compactMap { FreezeDayKey.date(for: $0.frozenDay, calendar: calendar) })
    }
}

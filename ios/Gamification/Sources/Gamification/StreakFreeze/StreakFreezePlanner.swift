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
// add-supplements D9: `planShared` runs the same loop over the food AND
// the supplement streak with ONE pool (see its doc comment); `plan` is
// `planShared` without supplements, so the food-only result is unchanged
// (pinned by StreakFreezeTests).
//
// Depends on: StreakEngine.simulate (internal walk), SupplementStreak.walk,
// FreezeBalance, StreakFreezeStore.Consumption, FreezeDayKey, FoodLogCore
// (SupplementDaySignal).
// Depended on by: WeeklyBossFeature.applyStreakFreezes.

import Foundation
import FoodLogCore

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
        let shared = planShared(
            loggedDays: loggedDays,
            frozenDays: frozenDays,
            supplements: nil,
            grants: grants,
            consumptions: consumptions,
            today: today,
            calendar: calendar
        )
        return Plan(newConsumptions: shared.newConsumptions, frozenDays: shared.frozenDays)
    }

    // MARK: - Shared pool (add-supplements D9)

    /// The supplement streak's input: the digest's days (oldest first) and
    /// the supplement days already frozen (`yyyy-MM-dd`).
    public struct SupplementStreakInput: Sendable, Equatable {
        public let days: [SupplementDaySignal]
        public let frozenDays: Set<String>

        public init(days: [SupplementDaySignal], frozenDays: Set<String>) {
            self.days = days
            self.frozenDays = frozenDays
        }
    }

    public struct SharedPlan: Sendable, Equatable {
        /// Consumptions to record (each tagged with its streak).
        public let newConsumptions: [StreakFreezeStore.Consumption]
        /// Every frozen FOOD day after the plan (existing + new), midnights.
        public let frozenDays: Set<Date>
        /// Every frozen SUPPLEMENT day after the plan, `yyyy-MM-dd`.
        public let supplementFrozenDays: Set<String>
    }

    /// Design D6 over BOTH streaks with one pool (add-supplements D9):
    /// each pass looks for the earliest protectable miss of the food streak
    /// (`StreakEngine.simulate`) and of the supplement streak
    /// (`SupplementStreak.walk`) -- a `.missed` day in the last 7 days whose
    /// streak was >= 3 days and for which a freeze earned before it is still
    /// available -- and freezes the EARLIER one (the food streak on a tie),
    /// so the pool goes to whichever streak breaks first. Consumptions of
    /// both streaks count against the same balance. A day is frozen at most
    /// once per streak (a frozen day never walks as `.missed` again).
    /// `supplements == nil` (feature off, no plan, or unreadable) = exactly
    /// the food-only planner.
    public static func planShared(
        loggedDays: Set<Date>,
        frozenDays: Set<Date>,
        supplements: SupplementStreakInput?,
        grants: [RewardLedger.FreezeGrant],
        consumptions: [StreakFreezeStore.Consumption],
        today: Date,
        calendar: Calendar
    ) -> SharedPlan {
        var foodFrozen = frozenDays
        var supplementFrozen = supplements?.frozenDays ?? []
        var allConsumptions = consumptions
        var fresh: [StreakFreezeStore.Consumption] = []
        let todayKey = FreezeDayKey.key(for: today, calendar: calendar)
        let earliest = calendar.date(byAdding: .day, value: -lookbackDays, to: today) ?? today
        let earliestKey = FreezeDayKey.key(for: earliest, calendar: calendar)

        // Each pass freezes at most one day of one streak; each streak can
        // lose at most `lookbackDays` days, so this bound keeps it total.
        for _ in 0..<(2 * (lookbackDays + 1)) {
            // The food streak's earliest protectable miss.
            var food: (day: Date, key: String, length: Int)?
            let walk = StreakEngine.simulate(loggedDays: loggedDays, frozenDays: foodFrozen, today: today, calendar: calendar)
            let foodCandidates = walk.outcomes
                .filter { $0.value == .missed && $0.key >= earliest && $0.key < today }
                .map(\.key)
                .sorted()
            for day in foodCandidates {
                let length = walk.lengthBefore[day] ?? 0
                guard length >= minimumProtectedLength else { continue }
                let key = FreezeDayKey.key(for: day, calendar: calendar)
                guard FreezeBalance.available(forMissOn: key, grants: grants, consumptions: allConsumptions) >= 1 else { continue }
                food = (day, key, length)
                break
            }

            // The supplement streak's earliest protectable miss.
            var supplement: (key: String, length: Int)?
            if let supplements {
                let supplementWalk = SupplementStreak.walk(days: supplements.days, frozenDays: supplementFrozen, today: todayKey)
                let candidates = supplementWalk.outcomes
                    .filter { $0.value == .missed && $0.key >= earliestKey && $0.key < todayKey }
                    .map(\.key)
                    .sorted()
                for key in candidates {
                    let length = supplementWalk.lengthBefore[key] ?? 0
                    guard length >= minimumProtectedLength else { continue }
                    guard FreezeBalance.available(forMissOn: key, grants: grants, consumptions: allConsumptions) >= 1 else { continue }
                    supplement = (key, length)
                    break
                }
            }

            let consumption: StreakFreezeStore.Consumption
            if let food, supplement.map({ food.key <= $0.key }) ?? true {
                consumption = StreakFreezeStore.Consumption(frozenDay: food.key, consumedOn: todayKey, protectedLength: food.length)
                foodFrozen.insert(food.day)
            } else if let supplement {
                consumption = StreakFreezeStore.Consumption(
                    frozenDay: supplement.key,
                    consumedOn: todayKey,
                    protectedLength: supplement.length,
                    streak: FreezeStreakKind.supplements.rawValue
                )
                supplementFrozen.insert(supplement.key)
            } else {
                break
            }
            allConsumptions.append(consumption)
            fresh.append(consumption)
        }
        return SharedPlan(newConsumptions: fresh, frozenDays: foodFrozen, supplementFrozenDays: supplementFrozen)
    }

    /// The FOOD streak's frozen days as midnights in `calendar`
    /// (supplement freezes share the pool but not the days).
    public static func frozenDays(
        from consumptions: [StreakFreezeStore.Consumption],
        calendar: Calendar
    ) -> Set<Date> {
        Set(consumptions.filter { $0.streakKind == .food }.compactMap { FreezeDayKey.date(for: $0.frozenDay, calendar: calendar) })
    }

    /// The supplement streak's frozen days (`yyyy-MM-dd`).
    public static func supplementFrozenDays(from consumptions: [StreakFreezeStore.Consumption]) -> Set<String> {
        Set(consumptions.filter { $0.streakKind == .supplements }.map(\.frozenDay))
    }
}

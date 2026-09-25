// BossPicker.swift
//
// add-weekly-boss-and-streak-freezes design D2: which boss the owner faces
// this ISO week, and how many hits it takes. Pure: the week, last week's
// boss and the signals snapshot in; a `BossPick` out. `WeeklyBossFeature`
// calls it once per week (first run of the week) and persists the result,
// so a boss is never re-rolled mid-week even when later data would change
// the analysis.
//
//   - Analysis window: the 28 days of the 4 ISO weeks before this one.
//   - Per archetype: considered = days passing its filter, adherence =
//     good / considered. Eligible when its data requirement is met by some
//     day in the window and considered >= 14 (the ghost: always, over 28).
//   - Fewer than 7 logged days in the window -> the forgetful ghost.
//   - Otherwise the eligible archetype with the LOWEST adherence, never
//     last week's boss; exact ties broken by `DeterministicRandom` seeded
//     "boss-<week>", over the tied kinds in catalog order.
//   - Target = clamp(ceil(adherence * 7) + 2, 3, 7).
//
// Fallback (not in the design, needed to keep "never twice in a row" and
// "new user -> ghost" both true): when the rule's choice is last week's
// boss and nothing else is eligible, the breakfast goblin (or, if IT was
// last week's boss, the ghost) is used, with its adherence over whatever
// days it has.
//
// Depends on: BossCatalog, WeekKey, DeterministicRandom, FoodLogCore
// (SignalsSnapshot).
// Depended on by: WeeklyBossFeature.

import Foundation
import FoodLogCore

public struct BossPick: Sendable, Equatable {
    public let kind: BossKind
    public let target: Int
    public let adherence: Double
    public let goodDays: Int
    public let consideredDays: Int
}

public enum BossPicker {
    public struct Adherence: Sendable, Equatable {
        public let good: Int
        public let considered: Int

        public var fraction: Double {
            considered > 0 ? Double(good) / Double(considered) : 0
        }
    }

    /// The 28 `yyyy-MM-dd` keys of the four ISO weeks before `week`,
    /// oldest first.
    public static func analysisDayKeys(before week: WeekKey, calendar: Calendar) -> [String] {
        (1...4).reversed().flatMap { offset -> [String] in
            week.adding(weeks: -offset, calendar: calendar)?.dayKeys(calendar: calendar) ?? []
        }
    }

    public static func adherence(
        _ kind: BossKind,
        dayKeys: [String],
        snapshot: SignalsSnapshot,
        calendar: Calendar
    ) -> Adherence {
        let archetype = BossCatalog.archetype(kind)
        var good = 0
        var considered = 0
        for key in dayKeys {
            guard let day = snapshot.days[key] else {
                // No data at all: only the ghost counts the day (as a miss).
                if kind == .forgetfulGhost { considered += 1 }
                continue
            }
            guard archetype.isConsidered(day) else { continue }
            considered += 1
            if archetype.isGood(day, history: snapshot, calendar: calendar) { good += 1 }
        }
        return Adherence(good: good, considered: considered)
    }

    public static func isEligible(
        _ kind: BossKind,
        adherence: Adherence,
        dayKeys: [String],
        snapshot: SignalsSnapshot
    ) -> Bool {
        if kind == .forgetfulGhost { return true }
        let days = snapshot.days(dayKeys)
        guard BossCatalog.archetype(kind).requirement.isSatisfied(byAnyOf: days) else { return false }
        return adherence.considered >= BossCatalog.minimumConsideredDays
    }

    /// Design D2's target: two days better than the recent average, never
    /// below 3 or above 7. Integer maths, so 4 of 7 is exactly 4, not 4.0000001.
    public static func target(good: Int, considered: Int) -> Int {
        guard considered > 0 else { return 3 }
        let ceiling = (max(0, good) * 7 + considered - 1) / considered
        return min(max(ceiling + 2, 3), 7)
    }

    /// The same formula over a fraction (tests and display).
    public static func target(adherence: Double) -> Int {
        let ceiling = Int((max(0, adherence) * 7 - 1e-9).rounded(.up))
        return min(max(ceiling + 2, 3), 7)
    }

    public static func pick(
        week: WeekKey,
        previous: BossKind?,
        snapshot: SignalsSnapshot,
        calendar: Calendar
    ) -> BossPick {
        let keys = analysisDayKeys(before: week, calendar: calendar)
        let logged = snapshot.days(keys).filter(\.hasEntries).count

        func make(_ kind: BossKind, _ value: Adherence) -> BossPick {
            BossPick(
                kind: kind,
                target: target(good: value.good, considered: value.considered),
                adherence: value.fraction,
                goodDays: value.good,
                consideredDays: value.considered
            )
        }
        func fallback() -> BossPick {
            let kind: BossKind = previous == .breakfastGoblin ? .forgetfulGhost : .breakfastGoblin
            return make(kind, adherence(kind, dayKeys: keys, snapshot: snapshot, calendar: calendar))
        }

        if logged < BossCatalog.newUserLoggedDays {
            guard previous != .forgetfulGhost else { return fallback() }
            return make(.forgetfulGhost, adherence(.forgetfulGhost, dayKeys: keys, snapshot: snapshot, calendar: calendar))
        }

        var candidates: [(kind: BossKind, value: Adherence)] = []
        for kind in BossKind.allCases where kind != previous {
            let value = adherence(kind, dayKeys: keys, snapshot: snapshot, calendar: calendar)
            if isEligible(kind, adherence: value, dayKeys: keys, snapshot: snapshot) {
                candidates.append((kind: kind, value: value))
            }
        }
        guard let lowest = candidates.map({ $0.value.fraction }).min() else { return fallback() }
        // Exact ties only (same good/considered ratio), compared without
        // floating-point noise: a/b == c/d  <=>  a*d == c*b.
        let reference = candidates.first { $0.value.fraction == lowest }!.value
        let tied = candidates.filter {
            $0.value.good * reference.considered == reference.good * $0.value.considered
        }
        var random = DeterministicRandom(seed: "boss-" + week.rawValue)
        let chosen = tied.count == 1 ? tied[0] : tied[random.nextInt(below: tied.count)]
        return make(chosen.kind, chosen.value)
    }
}

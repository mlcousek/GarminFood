// FreezeBalance.swift
//
// add-weekly-boss-and-streak-freezes design D4: how many streak freezes the
// owner holds right now. Nothing stores the balance itself -- it is REPLAYED
// from the two append-only facts that do exist: freeze grants recorded by
// `RewardLedger` (`bingo.freeze.<week>`, `boss.freeze.<week>`, each with the
// day it was earned) and consumptions recorded by `StreakFreezeStore` (each
// with the day it froze). Replaying in day order and clamping at the cap
// after every grant is what makes "a grant into a full bank is wasted" hold
// without ever persisting a counter that could drift from the two lists.
//
// Same-day ordering: a consumption sorts before a grant of the same day, so
// a freeze earned on the very day it would cover never looks available for
// it (design D6: a freeze cannot be earned after the miss and applied
// retroactively). The balance is never negative.
//
// Pure; `yyyy-MM-dd` keys compare correctly as strings, so no Date maths.
//
// Depends on: RewardLedger.FreezeGrant, StreakFreezeStore.Consumption.
// Depended on by: StreakFreezePlanner, WeeklyBossFeature, the app's streak
// card and screen (via GamificationEngine).

import Foundation

public enum FreezeBalance {
    /// Design D4: at most two unused freezes.
    public static let cap = 2

    public struct Result: Sendable, Equatable {
        /// Freezes available now, `0...cap`.
        public let available: Int
        /// Grants that arrived while the bank was full and were discarded.
        public let wasted: Int
        /// Every valid grant ever recorded (kept + wasted).
        public let earned: Int
        /// Every consumption ever recorded.
        public let used: Int
        /// `yyyy-MM-dd` of the most recent wasted grant, if any.
        public let lastWastedDay: String?

        public init(available: Int, wasted: Int, earned: Int, used: Int, lastWastedDay: String?) {
            self.available = available
            self.wasted = wasted
            self.earned = earned
            self.used = used
            self.lastWastedDay = lastWastedDay
        }

        public static let zero = Result(available: 0, wasted: 0, earned: 0, used: 0, lastWastedDay: nil)
    }

    /// Replays every grant and consumption.
    public static func compute(
        grants: [RewardLedger.FreezeGrant],
        consumptions: [StreakFreezeStore.Consumption],
        cap: Int = FreezeBalance.cap
    ) -> Result {
        replay(grantDays: grants.map(\.day), consumptionDays: consumptions.map(\.frozenDay), cap: cap)
    }

    /// The balance usable for a miss on `day`: only grants earned strictly
    /// before it, and every recorded consumption is charged (a freeze
    /// already spent on a LATER day is not available again, whatever order
    /// the planner ran in). Also never more than today's overall balance.
    public static func available(
        forMissOn day: String,
        grants: [RewardLedger.FreezeGrant],
        consumptions: [StreakFreezeStore.Consumption],
        cap: Int = FreezeBalance.cap
    ) -> Int {
        let before = replay(
            grantDays: grants.map(\.day).filter { $0 < day },
            consumptionDays: consumptions.map(\.frozenDay).filter { $0 < day },
            cap: cap
        )
        let spentLater = consumptions.filter { $0.frozenDay >= day }.count
        let overall = compute(grants: grants, consumptions: consumptions, cap: cap).available
        return max(0, min(before.available - spentLater, overall))
    }

    static func replay(grantDays: [String], consumptionDays: [String], cap: Int) -> Result {
        // (day, order): consumptions (0) before grants (1) on the same day.
        var events: [(day: String, order: Int)] = []
        events += consumptionDays.filter(isValidDay).map { (day: $0, order: 0) }
        let validGrants = grantDays.filter(isValidDay)
        events += validGrants.map { (day: $0, order: 1) }
        events.sort { ($0.day, $0.order) < ($1.day, $1.order) }

        var balance = 0
        var wasted = 0
        var lastWasted: String?
        for event in events {
            if event.order == 1 {
                if balance < cap {
                    balance += 1
                } else {
                    wasted += 1
                    lastWasted = event.day
                }
            } else {
                balance = max(0, balance - 1)
            }
        }
        return Result(
            available: balance,
            wasted: wasted,
            earned: validGrants.count,
            used: consumptionDays.filter(isValidDay).count,
            lastWastedDay: lastWasted
        )
    }

    /// `yyyy-MM-dd` shape check (a grant recorded without a day is ignored
    /// rather than sorting before every real day).
    static func isValidDay(_ key: String) -> Bool {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0].count == 4 && parts[1].count == 2 && parts[2].count == 2
            && parts.allSatisfy { Int($0) != nil }
    }
}

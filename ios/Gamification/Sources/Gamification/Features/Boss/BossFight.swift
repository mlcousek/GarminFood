// BossFight.swift
//
// add-weekly-boss-and-streak-freezes design D3: the fight itself. Each day
// of the boss's ISO week on which its habit is met is one hit; the boss has
// `target` HP. Pure -- `WeeklyBossFeature` persists hits (as a growing set,
// so a hit once counted is never taken back) and the outcome.
//
//   - Days after today never count; today counts as soon as it qualifies,
//     except for archetypes that judge completed days only (midnight
//     muncher, soda lich), where an evening entry could still spoil it.
//   - `isWeekOver` = the week has fully passed (its Sunday is before
//     today), so every one of its days is complete: the feature then
//     settles the week as defeated or escaped (no penalty).
//
// Depends on: BossCatalog, WeekKey, FoodLogCore (SignalsSnapshot).
// Depended on by: WeeklyBossFeature.

import Foundation
import FoodLogCore

public enum BossFight {
    /// The week's day keys on which `kind` scored a hit, as of
    /// `snapshot.today`, oldest first.
    public static func hitDays(
        _ kind: BossKind,
        week: WeekKey,
        snapshot: SignalsSnapshot,
        calendar: Calendar
    ) -> [String] {
        let archetype = BossCatalog.archetype(kind)
        let today = snapshot.today
        return week.dayKeys(calendar: calendar).filter { key in
            guard key <= today else { return false }
            if archetype.judgesCompletedDaysOnly && key == today { return false }
            guard let day = snapshot.days[key] else { return false }
            return archetype.isGood(day, history: snapshot, calendar: calendar)
        }
    }

    /// Whether every day of `week` lies before `todayKey`.
    public static func isWeekOver(_ week: WeekKey, todayKey: String, calendar: Calendar) -> Bool {
        guard let sunday = week.dayKeys(calendar: calendar).last else { return false }
        return sunday < todayKey
    }

    /// Days of `week` from today on (today included); 0 once it is over.
    public static func daysLeft(in week: WeekKey, todayKey: String, calendar: Calendar) -> Int {
        week.dayKeys(calendar: calendar).filter { $0 >= todayKey }.count
    }

    /// Design D3: 150 XP + 25 per target day above 3 (150-250).
    public static func defeatXP(target: Int) -> Int {
        XPAward.bossDefeatedBase + XPAward.bossDefeatedPerTargetDay * max(0, target - 3)
    }
}

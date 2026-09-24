// XPAward+Features.swift
//
// Design D10: the XP budget for the new gamification sources, in one place
// so wave-2 features never invent their own numbers. The total (~ +31 XP a
// day on average) is why `LevelCurve.growthFactor` moved 1.045 -> 1.0505
// in the same change: level 84 stays roughly three years away.
//
// Depends on: XPAward (XPStore.swift). Depended on by: every wave-2
// feature, ChallengeTemplates+Signals (creative challenge XP).

import Foundation

extension XPAward {
    public static let bingoLine = 25
    public static let bingoFullCard = 150
    /// Per event per year.
    public static let seasonalEventCompleted = 50
    /// The first time a collection entry is found.
    public static let collectionDiscovery = 5
    public static let journeyMilestone = 40
    /// At most once per record per day.
    public static let personalRecord = 20
    /// On top of `achievementBonus`.
    public static let secretUnlocked = 50
    /// On top of `achievementBonus` -- the generic bonus is enough.
    public static let sportBadge = 0
    public static let bossDefeatedBase = 150
    public static let bossDefeatedPerTargetDay = 25
    /// The range creative long-running challenges award (design D11).
    public static let creativeChallengeRange: ClosedRange<Int> = 60...160
}

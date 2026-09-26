// XPAward+Features.swift
//
// Design D10: the XP budget for the new gamification sources, in one place
// so wave-2 features never invent their own numbers.
//
// rebalance-xp-economy: each constant here feeds a line of `XPBudget`
// (constant x assumed frequency), and `LevelCurve.growthFactor` is solved
// from the sum. Changing a value here fails `XPBudgetTests` until the
// factor is re-solved (the failure prints the new literal). The 2026-09-25
// audit changed none of them: no feature exceeds 25% of the core budget.
//
// Depends on: XPAward (XPStore.swift). Depended on by: every wave-2
// feature, ChallengeTemplates+Signals (creative challenge XP), XPBudget.

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
    /// add-supplements D9: one grant per stack-complete day, BEFORE the
    /// optional-source multiplier (`XPBudget.optionalGrantXP`) -- the
    /// supplements feature is optional, so what it actually pays is scaled
    /// down to fit the 0.5% allowance (in practice 1 XP).
    public static let supplementStackComplete = 6
}

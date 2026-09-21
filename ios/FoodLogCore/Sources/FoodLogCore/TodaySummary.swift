// TodaySummary.swift
//
// The home screen's hero is built around this: today's consumed calories
// against today's goal, derived from Garmin's daily food log
// (`GET /nutrition-service/food/logs/{date}`, confirmed live 2026-09-14 --
// `dailyNutritionContent.calories` is the REAL consumed total; the legacy
// `usersummary-service` field is disconnected from nutrition and must never
// be used for this, per docs/garmin-food-log-contract.md).
//
// Lives here rather than in the app target so its logic (goalFraction,
// goalState's under/on-target/over bands) is a plain, testable value type --
// see TodaySummaryTests.swift. The app target's TodaySummaryLoader is the
// thin GarminClient-calling, @Observable wrapper around this; that part
// can't be unit-tested without a device/toolchain, so keeping this half
// pure and covered is what a test *can* reach.

import Foundation

public struct TodaySummary: Equatable, Sendable {
    public let consumedCalories: Double
    public let goalCalories: Double?
    public let protein: Double?
    public let carbs: Double?
    public let fat: Double?
    public let fetchedAt: Date

    public init(consumedCalories: Double, goalCalories: Double?, protein: Double?, carbs: Double?, fat: Double?, fetchedAt: Date) {
        self.consumedCalories = consumedCalories
        self.goalCalories = goalCalories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fetchedAt = fetchedAt
    }

    /// 2026-09-21 bug fix: matches `MacroProgress.remaining`'s identical
    /// fix -- guard `goalCalories > 0`, not just non-nil, so this agrees
    /// with `goalFraction`/`goalState` below about what counts as "no goal."
    public var remainingCalories: Double? {
        guard let goalCalories, goalCalories > 0 else { return nil }
        return goalCalories - consumedCalories
    }

    /// 0...1 (clamped) share of the goal consumed; `nil` when there is no goal
    /// to measure against, so the UI can show a plain count instead of a bar
    /// that would otherwise be lying.
    public var goalFraction: Double? {
        guard let goalCalories, goalCalories > 0 else { return nil }
        return min(max(consumedCalories / goalCalories, 0), 1)
    }

    public enum GoalState: Equatable, Sendable { case under, onTarget, over, noGoal }

    /// "On target" is +/-10% -- a narrower band than GamificationEngine's
    /// 15% goal-met tolerance on purpose: this is a visual cue on a live
    /// number, not an XP award, so it can afford to be stricter.
    public var goalState: GoalState {
        guard let goalCalories, goalCalories > 0 else { return .noGoal }
        let ratio = consumedCalories / goalCalories
        if ratio > 1.10 { return .over }
        if ratio >= 0.90 { return .onTarget }
        return .under
    }
}

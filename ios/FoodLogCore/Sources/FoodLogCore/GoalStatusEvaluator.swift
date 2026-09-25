// GoalStatusEvaluator.swift
//
// The "did this day meet its goals?" judgement (add-standalone-mode D11,
// task 2.4), moved unchanged out of the app's
// `GamificationEngine.refreshGoalStatus` so it is pure, unit-tested, and
// the same code for a Garmin day and a local one (`LocalNutritionReader`
// builds the same `DailyFoodLog` shape). The engine still owns fetching
// the log and recording the result; only the judgement lives here.
//
// The rules, exactly as they were:
//   - no goals or no content on the day: no judgement (nothing recorded);
//   - the FIXED goal is used, `adjusted*` only as a fallback for a payload
//     with no base value (today-dashboard spec, owner decision 2026-09-23:
//     burned calories must not move "goal met");
//   - calories: met when the day lands in `CalorieBand.onTarget`;
//   - protein/carbs/fat: met when at least the goal, and a goal of 0 or
//     less is no goal.
//
// Returns its own small value, not Gamification's `DailyGoalStatus`:
// FoodLogCore doesn't depend on Gamification (the dependency runs the
// other way), and Gamification doesn't import GarminKit, so the app maps
// one to the other. Tests: GoalStatusEvaluatorTests.

import Foundation
import GarminKit

public struct DayGoalJudgement: Sendable, Equatable {
    public let metCalorieGoal: Bool
    public let metProteinGoal: Bool
    public let metCarbGoal: Bool
    public let metFatGoal: Bool

    public init(metCalorieGoal: Bool, metProteinGoal: Bool, metCarbGoal: Bool, metFatGoal: Bool) {
        self.metCalorieGoal = metCalorieGoal
        self.metProteinGoal = metProteinGoal
        self.metCarbGoal = metCarbGoal
        self.metFatGoal = metFatGoal
    }
}

public enum GoalStatusEvaluator {
    /// The day's judgement, or `nil` when the log carries no goals or no
    /// content -- then nothing is recorded, as before.
    public static func evaluate(_ log: DailyFoodLog) -> DayGoalJudgement? {
        guard let goals = log.dailyNutritionGoals,
              let content = log.dailyNutritionContent
        else { return nil }
        return DayGoalJudgement(
            metCalorieGoal: CalorieBand.isGoalMet(consumed: content.calories, goal: goals.calories ?? goals.adjustedCalories),
            metProteinGoal: metAtLeast(actual: content.protein, goal: goals.protein ?? goals.adjustedProtein),
            metCarbGoal: metAtLeast(actual: content.carbs, goal: goals.carbs ?? goals.adjustedCarbs),
            metFatGoal: metAtLeast(actual: content.fat, goal: goals.fat ?? goals.adjustedFat)
        )
    }

    public static func metAtLeast(actual: Double?, goal: Double?) -> Bool {
        guard let actual, let goal, goal > 0 else { return false }
        return actual >= goal
    }
}

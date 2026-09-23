// AppPreferences+Goals.swift
//
// Turns the raw goal overrides (AppPreferences.swift, sync-weight-
// hydration-with-garmin D5) into FoodLogCore's `GoalSource`, which
// `WeightLoader`/`HydrationLoader` hand to `WeightAndWaterOverview`. Same
// split as AppPreferences+Fasting.swift: AppPreferences.swift stays free of
// a FoodLogCore import. Edited from Settings -> Goals (GoalsSettingsSection).

import Foundation
import FoodLogCore

extension AppPreferences {
    var waterGoalSource: GoalSource {
        waterGoalOverrideML.map { GoalSource.override($0) } ?? .garmin
    }

    var weightGoalSource: GoalSource {
        weightGoalOverrideKg.map { GoalSource.override($0) } ?? .garmin
    }
}

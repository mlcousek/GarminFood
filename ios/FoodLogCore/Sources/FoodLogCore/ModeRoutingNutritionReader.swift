// ModeRoutingNutritionReader.swift
//
// The read-side twin of `ModeRoutingFoodLogging` (add-standalone-mode D3,
// task 2.5): the one `NutritionLogReading` every consumer holds
// (`DayLogLoader`, `MacroTrendLoader`, `GamificationEngine`,
// `AppEnvironment.copyMealPlan`). It forwards each read to Garmin's
// `GarminClient` or to the `LocalNutritionReader`, choosing by the
// effective `DataMode` on EVERY call -- so in Garmin mode each read reaches
// the very same `GarminClient` value as before this change, and flipping
// the testing toggle needs no relaunch.
//
// Lives in FoodLogCore (not GarminKit) because `DataMode` does.
// Depended on by: Shared/AppServices.swift (the one instance per process).
// Tests: ModeRoutingTests.

import Foundation
import GarminKit

public struct ModeRoutingNutritionReader: NutritionLogReading {
    private let garmin: any NutritionLogReading
    private let local: any NutritionLogReading
    private let mode: @Sendable () -> DataMode

    public init(
        garmin: any NutritionLogReading,
        local: any NutritionLogReading,
        mode: @escaping @Sendable () -> DataMode
    ) {
        self.garmin = garmin
        self.local = local
        self.mode = mode
    }

    private var current: any NutritionLogReading {
        mode() == .standalone ? local : garmin
    }

    public func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
        try await current.dailyFoodLog(date: date)
    }

    public func mealsForDate(date: String) async throws -> MealsForDate {
        try await current.mealsForDate(date: date)
    }

    public func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse {
        try await current.calorieSummaryDaily(startDate: startDate, endDate: endDate)
    }

    public func dailyUserSummary(date: String) async throws -> DailyUserSummary {
        try await current.dailyUserSummary(date: date)
    }
}

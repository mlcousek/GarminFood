// NutritionLogReading.swift
//
// The read seam of add-standalone-mode (design D3): every nutrition READ the
// app's day log, Trends, gamification and copy-meal code makes, as one
// protocol. `GarminClient` satisfies it as-is (no body changes -- the four
// methods below are its existing, confirmed-live read routes); wave 2 adds
// FoodLogCore's `LocalNutritionReader`, which builds the same DTOs from the
// local food log via the public inits in GarminModels+Inits.swift.
//
// Consumers hold `any NutritionLogReading` (DayLogLoader, MacroTrendLoader,
// GamificationEngine, AppEnvironment.copyMealPlan). In Garmin mode they get
// the very same `GarminClient` value, so behaviour is identical.
//
// Same shape as `FoodLogReconciling` (Reconciliation.swift): a subset of
// `GarminClient`'s surface, `Sendable`, conformed to by an empty extension.

import Foundation

public protocol NutritionLogReading: Sendable {
    /// `GET /nutrition-service/food/logs/{date}`, or its local equivalent.
    func dailyFoodLog(date: String) async throws -> DailyFoodLog?
    /// `GET /nutrition-service/meals/{date}`: the meal definitions/windows.
    func mealsForDate(date: String) async throws -> MealsForDate
    /// Per-day totals and goals over a range (Trends).
    func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse
    /// Burned calories for "Active today"; a local reader throws.
    func dailyUserSummary(date: String) async throws -> DailyUserSummary
}

extension GarminClient: NutritionLogReading {}

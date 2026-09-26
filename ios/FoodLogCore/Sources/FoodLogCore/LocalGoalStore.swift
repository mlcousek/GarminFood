// LocalGoalStore.swift
//
// Standalone mode's nutrition targets (add-standalone-mode D6, task 4.1).
// Garmin mode reads its targets from Garmin's day log and never touches
// this file; a standalone install has no Garmin, so its calorie and macro
// targets live here, on the phone.
//
// Why a HISTORY and not one current goal: the goal for a day is the latest
// entry whose `effectiveFrom` is on or before that day. Editing a goal adds
// an entry starting today, so yesterday's ring, Trends and goal-met status
// keep the target they had (spec "Editing a goal keeps history"). Saving
// twice on the same day replaces that day's entry instead of stacking.
//
// Storage follows every other FoodLogCore store: one JSON file
// (`local-goals.json`), loaded through `FoodLogCoreStorage.loadPersistedJSON`
// (an undecodable file is quarantined, never silently wiped; an unreadable
// one -- before first unlock -- is retried and never overwritten), written
// atomically. Unknown keys are ignored and every field but the day and the
// calories is optional, so an older or newer build still reads the file.
//
// `mealSplit` (optional per-meal fractions) is kept in the shape for a later
// per-meal UI; owner decision 0.4 defaulted to day targets only, so nothing
// sets it yet and `LocalNutritionReader` ignores it.
//
// Depended on by: LocalNutritionReader (the goal in effect per day),
// AppServices (one instance per process), the app's Nutrition plan editor
// and onboarding goal setup. Tests: LocalGoalStoreTests.

import Foundation
import GarminKit

/// One goal, applying from `effectiveFrom` until the next entry starts.
public struct LocalNutritionGoals: Codable, Sendable, Equatable {
    /// The nutrition day (`yyyy-MM-dd`) this goal starts applying.
    public let effectiveFrom: String
    public var calories: Double
    public var proteinG: Double?
    public var carbsG: Double?
    public var fatG: Double?
    /// Optional fractions per `MealType.rawValue`; `nil` = day targets only.
    public var mealSplit: [String: Double]?

    public init(
        effectiveFrom: String,
        calories: Double,
        proteinG: Double? = nil,
        carbsG: Double? = nil,
        fatG: Double? = nil,
        mealSplit: [String: Double]? = nil
    ) {
        self.effectiveFrom = effectiveFrom
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.mealSplit = mealSplit
    }

    /// The Garmin-shaped goals `LocalNutritionReader` puts on a day log, so
    /// the dashboard, Trends and `GoalStatusEvaluator` read them exactly
    /// like Garmin's. Fixed values only: there are no "adjusted" (burned
    /// calories) targets without Garmin.
    public var nutritionGoals: NutritionGoals {
        NutritionGoals(calories: calories, carbs: carbsG, fat: fatG, protein: proteinG)
    }

    /// Calories finite and above zero; each macro, when set, finite and not
    /// negative.
    public var isValid: Bool {
        guard calories.isFinite, calories > 0 else { return false }
        for macro in [proteinG, carbsG, fatG] {
            if let macro, !(macro.isFinite && macro >= 0) { return false }
        }
        return (try? LocalFoodLogStore.month(ofDay: effectiveFrom)) != nil
    }
}

/// The pure rules over a goal history (tested without a file).
public enum LocalGoalHistory {
    /// The latest goal starting on or before `day`, or `nil` before the
    /// first one. `yyyy-MM-dd` strings sort chronologically.
    public static func goal(on day: String, in history: [LocalNutritionGoals]) -> LocalNutritionGoals? {
        history
            .filter { $0.effectiveFrom <= day }
            .max { $0.effectiveFrom < $1.effectiveFrom }
    }

    /// `history` with `goal` added, replacing an entry that starts on the
    /// same day, oldest first.
    public static func setting(_ goal: LocalNutritionGoals, in history: [LocalNutritionGoals]) -> [LocalNutritionGoals] {
        (history.filter { $0.effectiveFrom != goal.effectiveFrom } + [goal])
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
    }
}

public enum LocalGoalError: Error, Sendable, Equatable, LocalizedError {
    /// Calories missing or not above zero, a negative macro, or a bad day.
    case invalidGoal

    public var errorDescription: String? {
        String(localized: "Enter a calorie target above zero.", bundle: .module, comment: "Error when saving a nutrition goal on the phone (standalone mode) with an invalid number.")
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `DayNoteStore`.
public actor LocalGoalStore {
    private let fileURL: URL
    private var history: [LocalNutritionGoals] = []
    private var loaded = false

    public init(fileURL: URL = LocalGoalStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("local-goals.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON([LocalNutritionGoals].self, from: fileURL, decoder: JSONDecoder(), category: "LocalGoalStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        history = (result.value ?? []).sorted { $0.effectiveFrom < $1.effectiveFrom }
    }

    private func persist(_ newHistory: [LocalNutritionGoals]) throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "LocalGoalStore")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(newHistory)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        // In memory only after the write succeeded.
        history = newHistory
    }

    /// Every goal, oldest first.
    public func all() -> [LocalNutritionGoals] {
        loadIfNeeded()
        return history
    }

    /// The goal in effect on `day` (`yyyy-MM-dd`), or `nil` for none.
    public func goal(on day: String) -> LocalNutritionGoals? {
        loadIfNeeded()
        return LocalGoalHistory.goal(on: day, in: history)
    }

    /// Adds `goal` to the history (replacing one that starts the same day).
    /// Refuses an invalid goal with `LocalGoalError.invalidGoal`.
    public func save(_ goal: LocalNutritionGoals) throws {
        loadIfNeeded()
        guard goal.isValid else { throw LocalGoalError.invalidGoal }
        try persist(LocalGoalHistory.setting(goal, in: history))
    }
}

extension LocalNutritionReader {
    /// The reader with its goals from `goalStore` (task 4.1 wires the
    /// placeholder `goalsForDay` to the real history).
    public init(store: LocalFoodLogStore, goalStore: LocalGoalStore) {
        self.init(store: store, goalsForDay: { day in await goalStore.goal(on: day)?.nutritionGoals })
    }
}

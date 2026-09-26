// LocalNutritionReader.swift
//
// Standalone mode's side of the read seam (add-standalone-mode D3, task
// 2.3): `NutritionLogReading`, answered from `LocalFoodLogStore` instead of
// Garmin. It builds the very DTOs Garmin's routes decode into
// (`DailyFoodLog`, `MealsForDate`, `CalorieSummaryDailyResponse`) through
// their public inits, so the Today dashboard (`MealDashboard.build`),
// "Copy from…" (`CopyMealPlanner`), goal status, Trends and the
// gamification digests run the SAME code in both modes -- nothing
// downstream knows which system of record a day came from.
//
// How a local entry becomes a Garmin-shaped row:
//   - one `MealDetail` per meal, in `MealDashboard.defaultOrder`, even an
//     empty one (Garmin lists every meal too);
//   - `logId` = the entry's UUID, which is how `LocalLogEntryCoordinator`
//     finds it again for edit/duplicate/delete (`MealEntry.Status.synced`
//     means "in the system of record", design D4);
//   - `nutritionContent` is PER SERVING (snapshot / quantity) and
//     `servingQty` the quantity, because that is how Garmin's read-back is
//     shaped and how `MealDashboard.syncedEntries` multiplies it back;
//   - meal and day content are plain sums of the snapshots. A nutrient no
//     entry stated stays `nil` (the dashboard then doesn't show it); one
//     only some entries stated sums what is known (wave 3 adds the "some
//     values missing" marker);
//   - `logSource` is this app's own, and `logTimestamp` the moment of
//     logging, so fasting and the signal digests treat local entries
//     exactly like this app's delivered ones.
//
// A day is always answered with a log (never `nil`), because the local log
// IS the system of record: an empty day really is empty, not "not loaded".
//
// Goals: the reader asks `goalsForDay`. The app passes the goal history of
// `LocalGoalStore` (task 4.1, `init(store:goalStore:)` in
// LocalGoalStore.swift); a day before any goal -- or when the user skipped
// goal setup -- gets none, so it shows consumed-only rings and records no
// goal status, what Garmin mode does for an account without goals (design
// D11). `noGoalsYet` stays as the default for tests.
//
// `mealsForDate` answers the four default meals without windows, so meal
// defaulting falls back to the clock (`MealTypeDefaulting`).
// `dailyUserSummary` throws `.unavailable`: there is no activity data
// without Garmin, and the "Active today" line already hides on any failure.
//
// Depends on: LocalFoodLogStore, GarminKit's read DTOs. Depended on by:
// ModeRoutingNutritionReader (the app's reader, AppEnvironment). Tests:
// LocalNutritionReaderTests (golden tests through MealDashboard.build and
// CopyMealPlanner).

import Foundation
import GarminKit

public enum LocalNutritionReaderError: Error, Sendable, Equatable {
    /// Standalone mode has no source for this (activity/burned calories).
    case unavailable
}

public struct LocalNutritionReader: NutritionLogReading {
    /// The goal in effect on a `yyyy-MM-dd` day, or `nil` for none.
    public typealias GoalsForDay = @Sendable (String) async -> NutritionGoals?

    /// PLACEHOLDER until `LocalGoalStore` (add-standalone-mode 4.1): no
    /// local goals exist yet, so every day has no target.
    public static let noGoalsYet: GoalsForDay = { _ in nil }

    private let store: LocalFoodLogStore
    private let goalsForDay: GoalsForDay

    public init(store: LocalFoodLogStore, goalsForDay: @escaping GoalsForDay = LocalNutritionReader.noGoalsYet) {
        self.store = store
        self.goalsForDay = goalsForDay
    }

    // MARK: NutritionLogReading

    public func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
        let entries = try await store.entries(forDay: date)
        let goals = await goalsForDay(date)
        return Self.dayLog(date: date, entries: entries, goals: goals)
    }

    public func mealsForDate(date: String) async throws -> MealsForDate {
        MealsForDate(meals: Self.defaultMeals)
    }

    /// Only days with at least one entry, oldest first, each with the goal
    /// in effect that day -- the Trends chart shows logged days.
    public func calorieSummaryDaily(startDate: String, endDate: String) async throws -> CalorieSummaryDailyResponse {
        let entries = try await store.entries(fromDay: startDate, toDay: endDate)
        var days: [String] = []
        var byDay: [String: [LocalLogEntry]] = [:]
        for entry in entries {
            if byDay[entry.day] == nil { days.append(entry.day) }
            byDay[entry.day, default: []].append(entry)
        }
        var summaries: [CalorieSummaryDay] = []
        summaries.reserveCapacity(days.count)
        for day in days {
            let goals = await goalsForDay(day)
            summaries.append(CalorieSummaryDay(
                mealDate: day,
                nutritionContent: Self.content(summing: byDay[day] ?? []),
                nutritionGoals: goals
            ))
        }
        return CalorieSummaryDailyResponse(startDate: startDate, endDate: endDate, dailyNutritionContents: summaries)
    }

    public func dailyUserSummary(date: String) async throws -> DailyUserSummary {
        throw LocalNutritionReaderError.unavailable
    }

    // MARK: Building Garmin-shaped values (pure)

    /// The four meals, Garmin Connect's order, no windows.
    public static let defaultMeals: [Meal] = MealDashboard.defaultOrder.enumerated().map { index, type in
        Meal(mealName: type.rawValue, displayOrder: index)
    }

    static func dayLog(date: String, entries: [LocalLogEntry], goals: NutritionGoals?) -> DailyFoodLog {
        let details = zip(MealDashboard.defaultOrder, defaultMeals).map { type, meal -> MealDetail in
            let mealEntries = entries.filter { $0.mealType == type }
            return MealDetail(
                meal: meal,
                mealNutritionContent: content(summing: mealEntries),
                // Per-meal targets are an open owner decision (0.4); none yet.
                mealNutritionGoals: nil,
                loggedFoods: mealEntries.map(loggedFood)
            )
        }
        return DailyFoodLog(
            mealDate: date,
            dailyNutritionGoals: goals,
            dailyNutritionContent: content(summing: entries),
            mealDetails: details
        )
    }

    static func loggedFood(_ entry: LocalLogEntry) -> LoggedFood {
        // Validated > 0 before every commit; guarded anyway so a hand-edited
        // file can't divide by zero -- the snapshot then reads as 1 serving.
        let quantity = entry.quantity.isFinite && entry.quantity > 0 ? entry.quantity : 1
        func perServing(_ kind: NutrientKind) -> Double? {
            entry.amount(kind).map { $0 / quantity }
        }
        let id = entry.id.uuidString
        return LoggedFood(
            id: id,
            logId: id,
            logTimestamp: timestampString(entry.loggedAt),
            logSource: LoggedFood.thisAppLogSource,
            servingQty: quantity,
            foodMetaData: FoodMetaData(
                foodId: entry.food.id,
                foodName: entry.food.name,
                brandName: entry.food.brandName,
                source: entry.food.source?.rawValue,
                regionCode: entry.food.regionCode,
                languageCode: entry.food.languageCode
            ),
            nutritionContent: LoggedNutritionContent(
                servingId: entry.servingId,
                servingUnit: entry.servingUnit ?? entry.servingLabel,
                numberOfUnits: entry.servingNumberOfUnits,
                calories: perServing(.calories),
                carbs: perServing(.carbs),
                protein: perServing(.protein),
                fat: perServing(.fat),
                fiber: perServing(.fiber),
                sugar: perServing(.sugar),
                saturatedFat: perServing(.saturatedFat),
                sodium: perServing(.sodium)
            )
        )
    }

    /// Sums of the logged amounts. The four headline values are always
    /// numbers (0 for an empty meal, as Garmin sends); every other field is
    /// `nil` unless at least one entry stated it.
    static func content(summing entries: [LocalLogEntry]) -> DailyNutritionContent {
        func total(_ kind: NutrientKind) -> Double? {
            let known = entries.compactMap { $0.amount(kind) }
            return known.isEmpty ? nil : known.reduce(0, +)
        }
        return DailyNutritionContent(
            calories: total(.calories) ?? 0,
            carbs: total(.carbs) ?? 0,
            fat: total(.fat) ?? 0,
            protein: total(.protein) ?? 0,
            fiber: total(.fiber),
            sugar: total(.sugar),
            saturatedFat: total(.saturatedFat),
            monounsaturatedFat: total(.monounsaturatedFat),
            polyunsaturatedFat: total(.polyunsaturatedFat),
            cholesterol: total(.cholesterol),
            sodium: total(.sodium),
            potassium: total(.potassium),
            vitaminA: total(.vitaminA),
            vitaminC: total(.vitaminC),
            calcium: total(.calcium),
            iron: total(.iron)
        )
    }

    /// Garmin's own `logTimestamp` shape (`2026-09-16T13:35:49.324Z`), which
    /// `FastingLogMoments.parseTimestamp` reads.
    static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

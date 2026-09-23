// UsageMealBackfill.swift
//
// Fills in `UsageEvent.mealType` for usage events recorded before that
// field existed (2026-09-23), so the "Usual for <meal>" shelf
// (`MealUsualRanker`) isn't empty for weeks after the upgrade -- the owner's
// testing-feedback follow-up.
//
// Why from Garmin's day logs and not from the clock: `MealUsualRanker`
// deliberately refuses to guess a meal from the time of day (a 10pm snack
// would land on the dinner shelf). Garmin's own day log records which meal
// every food was actually logged under, so it is ground truth: an event is
// filled in only when its food appears in exactly ONE meal of that day's
// log. Anything ambiguous or not found stays `nil`, exactly as before.
//
// Pure functions over `[UsageEvent]` + `[day: DailyFoodLog]`, so they are
// unit-testable without I/O. The reads themselves (the confirmed
// `GET /nutrition-service/food/logs/{date}` route the Today tab uses) and
// the one-time trigger live in the app's `AppEnvironment`;
// `UsageHistoryStore.applyMealBackfill` persists the result.
//
// Depended on by: UsageHistory.swift (store method), AppEnvironment.

import Foundation
import GarminKit

public enum UsageMealBackfill {
    /// How far back legacy events are worth backfilling: `MealUsualRanker`'s
    /// 14-day half-life makes anything older than about four weeks weigh
    /// under a quarter of a fresh log.
    public static let lookbackDays = 28

    /// The nutrition day an event counts for: its recorded `nutritionDay`,
    /// or (for the oldest events, which predate that field too) the day it
    /// was logged on. A wrong fallback day is harmless: the food then just
    /// isn't found in that day's log and the event stays unfilled.
    static func day(of event: UsageEvent, calendar: Calendar) -> String {
        event.nutritionDay ?? NutritionDate.string(from: event.timestamp, calendar: calendar)
    }

    /// The days whose Garmin log would let `apply` fill something in:
    /// days with at least one event missing its meal, within `lookbackDays`
    /// of `now`, newest first.
    public static func daysNeedingBackfill(
        _ events: [UsageEvent],
        now: Date = Date(),
        lookbackDays: Int = UsageMealBackfill.lookbackDays,
        calendar: Calendar = .current
    ) -> [String] {
        guard let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: now) else { return [] }
        let days = Set(
            events
                .filter { $0.mealType == nil && $0.timestamp >= cutoff }
                .map { Self.day(of: $0, calendar: calendar) }
        )
        return days.sorted(by: >)
    }

    /// For each day's log: foodId -> the single meal it was logged under,
    /// or `nil` when the same food sits in more than one meal that day.
    static func mealsByFood(in log: DailyFoodLog) -> [String: MealType?] {
        var result: [String: MealType?] = [:]
        for detail in log.mealDetails ?? [] {
            guard let name = detail.meal?.mealName, let mealType = MealType(rawValue: name) else { continue }
            for food in detail.loggedFoods ?? [] {
                guard let foodId = food.foodMetaData?.foodId, !foodId.isEmpty else { continue }
                if let existing = result[foodId] {
                    if existing != mealType { result[foodId] = .some(nil) }
                } else {
                    result[foodId] = .some(mealType)
                }
            }
        }
        return result
    }

    /// Returns `events` with `mealType` filled in wherever that day's log
    /// shows the food under exactly one meal, plus how many were filled.
    /// Events that already have a meal, or whose day has no log in `logs`,
    /// are returned unchanged and in the same order.
    public static func apply(
        to events: [UsageEvent],
        logs: [String: DailyFoodLog],
        calendar: Calendar = .current
    ) -> (events: [UsageEvent], filled: Int) {
        guard !logs.isEmpty else { return (events, 0) }
        var mealsByDay: [String: [String: MealType?]] = [:]
        var filled = 0
        let updated = events.map { event -> UsageEvent in
            guard event.mealType == nil else { return event }
            let dayString = Self.day(of: event, calendar: calendar)
            guard let log = logs[dayString] else { return event }
            let meals: [String: MealType?]
            if let cached = mealsByDay[dayString] {
                meals = cached
            } else {
                meals = Self.mealsByFood(in: log)
                mealsByDay[dayString] = meals
            }
            guard let found = meals[event.foodId], let mealType = found else { return event }
            filled += 1
            return UsageEvent(
                foodId: event.foodId,
                servingId: event.servingId,
                numberOfUnits: event.numberOfUnits,
                timestamp: event.timestamp,
                nutritionDay: event.nutritionDay,
                mealType: mealType
            )
        }
        return (updated, filled)
    }
}

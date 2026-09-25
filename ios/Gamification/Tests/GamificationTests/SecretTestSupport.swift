// SecretTestSupport.swift
//
// add-secret-achievements D5: literal `DaySignals`/`SignalsSnapshot`
// builders for SecretRulesTests and SecretAchievementsFeatureTests. Kept
// apart from the foundation's SignalFixtures (wave-2 file ownership) because
// the secret rules need a calorie goal on a day, an explicit "today" and a
// full 42-day window, which SignalFixtures does not model.
//
// Everything is in TestClock's UTC Gregorian calendar.

import Foundation
import FoodLogCore
@testable import Gamification

enum SecretFixtures {
    static let calendar = TestClock.calendar

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        TestClock.date(year, month, day, hour: hour, minute: minute)
    }

    /// `base` moved by `days` calendar days (keeps the time of day).
    static func date(_ base: Date, plusDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: base)!
    }

    static func key(_ date: Date) -> String {
        NutritionDate.string(from: date, calendar: calendar)
    }

    static func entry(
        _ foodId: String,
        tags: Set<FoodTag> = [],
        at date: Date,
        meal: SignalMeal = .lunch,
        calories: Double? = 100
    ) -> SignalEntry {
        SignalEntry(foodId: foodId, name: foodId, tags: tags, timestamp: date, meal: meal, calories: calories)
    }

    /// A day keyed by `date`'s calendar day, calories summed from `entries`
    /// (`nil` when any entry's calories are unknown).
    static func day(
        _ date: Date,
        entries: [SignalEntry] = [],
        calorieGoal: Double? = nil,
        waterML: Double? = nil,
        waterGoalML: Double? = nil,
        activities: [ActivitySummary] = []
    ) -> DaySignals {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var calories: Double? = 0
        for entry in sorted {
            if let running = calories, let value = entry.calories {
                calories = running + value
            } else {
                calories = nil
            }
        }
        return DaySignals(
            day: key(date),
            date: calendar.startOfDay(for: date),
            entries: sorted,
            totals: MacroTotals(calories: calories),
            goals: calorieGoal.map { MacroGoals(calories: $0) },
            waterML: waterML,
            waterGoalML: waterGoalML,
            activities: activities,
            availability: SignalAvailability(
                hasGarminLog: false,
                hasMacros: false,
                hasWater: waterML != nil,
                hasActivities: !activities.isEmpty,
                hasWeight: false
            )
        )
    }

    /// `count` entries of `foodId`/`tags` on `date`'s day, an hour apart
    /// from 08:00.
    static func entries(_ count: Int, _ foodId: String, tags: Set<FoodTag> = [], on date: Date, calories: Double? = 100) -> [SignalEntry] {
        let morning = calendar.startOfDay(for: date).addingTimeInterval(8 * 3600)
        return (0..<count).map { index in
            entry(foodId, tags: tags, at: morning.addingTimeInterval(Double(index) * 3600), calories: calories)
        }
    }

    /// A snapshot whose window is the `windowLength` days ending at `today`.
    static func snapshot(_ days: [DaySignals], today: Date, windowLength: Int = 42) -> SignalsSnapshot {
        let windowDays = (0..<windowLength).reversed().map { key(date(today, plusDays: -$0)) }
        return SignalsSnapshot(
            days: Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }),
            today: key(today),
            windowDays: windowDays
        )
    }

    static func context(
        _ snapshot: SignalsSnapshot,
        now: Date,
        unlocked: Set<String> = []
    ) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            streak: StreakEngine.status(loggedDays: [], today: now, calendar: calendar),
            level: 1,
            unlockedBadgeIds: unlocked,
            isConfirmPath: false
        )
    }
}

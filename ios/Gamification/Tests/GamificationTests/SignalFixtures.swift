// SignalFixtures.swift
//
// Literal `DaySignals`/`SignalsSnapshot` builders for the foundation's own
// tests (DayPredicateTests, signal-challenge tests). Wave-2 changes add
// their own `*TestSupport.swift` rather than editing this file (design
// "Wave plan & file ownership").

import Foundation
import FoodLogCore

enum SignalFixtures {
    static let calendar = TestClock.calendar

    static func dayKey(_ year: Int, _ month: Int, _ day: Int) -> String {
        NutritionDate.string(from: TestClock.date(year, month, day), calendar: calendar)
    }

    static func entry(
        _ foodId: String,
        tags: Set<FoodTag> = [],
        at date: Date,
        meal: SignalMeal = .lunch,
        brand: String? = nil,
        calories: Double? = 100,
        protein: Double? = 5,
        carbs: Double? = 10,
        fat: Double? = 3,
        fiber: Double? = 2,
        sugar: Double? = 4
    ) -> SignalEntry {
        SignalEntry(
            foodId: foodId,
            name: foodId,
            brand: brand,
            tags: tags,
            timestamp: date,
            meal: meal,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            sugar: sugar
        )
    }

    /// A day whose totals are summed from `entries` (nil when any is nil).
    static func day(
        _ year: Int, _ month: Int, _ dayOfMonth: Int,
        entries: [SignalEntry] = [],
        goalStatus: SignalGoalStatus? = nil,
        waterML: Double? = nil,
        waterGoalML: Double? = nil,
        activities: [ActivitySummary]? = nil,
        weighInKg: Double? = nil
    ) -> DaySignals {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        func sum(_ value: (SignalEntry) -> Double?) -> Double? {
            var total = 0.0
            for entry in sorted {
                guard let v = value(entry) else { return nil }
                total += v
            }
            return total
        }
        let totals = MacroTotals(
            calories: sum(\.calories),
            protein: sum(\.protein),
            carbs: sum(\.carbs),
            fat: sum(\.fat),
            fiber: sum(\.fiber),
            sugar: sum(\.sugar)
        )
        return DaySignals(
            day: dayKey(year, month, dayOfMonth),
            date: TestClock.date(year, month, dayOfMonth, hour: 0),
            entries: sorted,
            totals: totals,
            goalStatus: goalStatus,
            waterML: waterML,
            waterGoalML: waterGoalML,
            activities: activities ?? [],
            weighInKg: weighInKg,
            availability: SignalAvailability(
                hasGarminLog: false,
                hasMacros: !sorted.isEmpty && totals.calories != nil && totals.protein != nil
                    && totals.carbs != nil && totals.fat != nil,
                hasWater: waterML != nil,
                hasActivities: activities != nil,
                hasWeight: weighInKg != nil
            )
        )
    }

    static func snapshot(
        _ days: [DaySignals],
        today: String? = nil,
        firstSeenDayByFood: [String: String] = [:],
        firstSeenDayByCzechBrand: [String: String] = [:]
    ) -> SignalsSnapshot {
        let keys = days.map(\.day).sorted()
        return SignalsSnapshot(
            days: Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }),
            today: today ?? keys.last ?? "",
            windowDays: keys,
            firstSeenDayByFood: firstSeenDayByFood,
            firstSeenDayByCzechBrand: firstSeenDayByCzechBrand
        )
    }
}

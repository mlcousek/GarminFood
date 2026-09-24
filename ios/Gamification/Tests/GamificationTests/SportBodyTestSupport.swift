// SportBodyTestSupport.swift
//
// Literal builders for the sport & body tests (add-sport-and-body-
// achievements). Its own file rather than an edit to SignalFixtures.swift
// (design "Wave plan & file ownership"). Everything is UTC (`TestClock`)
// so window edges are exact minutes on every CI runner; entries are tagged
// with the real `FoodTagger`, the same pipeline the app runs.

import Foundation
import FoodLogCore
@testable import Gamification

enum SportFixtures {
    static var calendar: Calendar { TestClock.calendar }

    static func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        TestClock.date(year, month, day, hour: hour, minute: minute)
    }

    static func key(_ year: Int, _ month: Int, _ day: Int) -> String {
        NutritionDate.string(from: TestClock.date(year, month, day), calendar: calendar)
    }

    static func key(of date: Date) -> String {
        NutritionDate.string(from: date, calendar: calendar)
    }

    static func entry(
        _ name: String,
        at date: Date,
        calories: Double? = 200,
        protein: Double? = nil,
        carbs: Double? = nil,
        tags: Set<FoodTag>? = nil
    ) -> SignalEntry {
        SignalEntry(
            foodId: name,
            name: name,
            tags: tags ?? FoodTagger.tags(name: name, brand: nil, barcode: nil),
            timestamp: date,
            meal: .snack,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: 5
        )
    }

    static func activity(_ id: String, _ typeKey: String, start: Date, minutes: Double) -> ActivitySummary {
        ActivitySummary(id: id, typeKey: typeKey, day: key(of: start), start: start, durationS: minutes * 60)
    }

    /// A day whose calorie/protein/carb totals are summed from `entries`
    /// (`nil` when any entry's value is unknown).
    static func day(
        _ key: String,
        entries: [SignalEntry] = [],
        activities: [ActivitySummary]? = nil,
        activeKcal: Double? = nil,
        goals: MacroGoals? = nil,
        goalStatus: SignalGoalStatus? = nil,
        weighInKg: Double? = nil,
        fasting: FastingOutcome? = nil,
        noteTags: Set<DayNoteTag> = [],
        caloriesTotal: Double? = nil
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
        let parts = key.split(separator: "-").compactMap { Int($0) }
        let date = parts.count == 3 ? TestClock.date(parts[0], parts[1], parts[2], hour: 0) : Date(timeIntervalSince1970: 0)
        return DaySignals(
            day: key,
            date: date,
            entries: sorted,
            totals: MacroTotals(
                calories: caloriesTotal ?? sum(\.calories),
                protein: sum(\.protein),
                carbs: sum(\.carbs),
                fat: sum(\.fat)
            ),
            goals: goals,
            goalStatus: goalStatus,
            activeKcal: activeKcal,
            activities: activities ?? [],
            weighInKg: weighInKg,
            fasting: fasting,
            noteTags: noteTags,
            availability: SignalAvailability(
                hasActivities: activities != nil,
                hasWeight: weighInKg != nil,
                hasFasting: fasting != nil
            )
        )
    }

    /// A snapshot whose `windowDays` are every calendar day from
    /// `windowStart` (default: the earliest data day) through `today`.
    static func snapshot(
        _ days: [DaySignals],
        today: String,
        windowStart: String? = nil,
        weightGoal: WeightGoalSignal? = nil
    ) -> SignalsSnapshot {
        let first = windowStart ?? days.map(\.day).min() ?? today
        var keys: [String] = []
        var cursor = first
        while cursor <= today {
            keys.append(cursor)
            guard let next = SportRules.dayKey(cursor, offsetBy: 1, calendar: calendar) else { break }
            cursor = next
        }
        return SignalsSnapshot(
            days: Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }),
            today: today,
            windowDays: keys,
            profile: ProfileSignals(weightGoal: weightGoal)
        )
    }

    static func context(_ snapshot: SignalsSnapshot, now: Date, unlocked: Set<String> = []) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: unlocked,
            isConfirmPath: false
        )
    }

    static func goalsMet(protein: Bool = false, carbs: Bool = false) -> SignalGoalStatus {
        SignalGoalStatus(metCalorieGoal: false, metProteinGoal: protein, metCarbGoal: carbs, metFatGoal: false)
    }
}

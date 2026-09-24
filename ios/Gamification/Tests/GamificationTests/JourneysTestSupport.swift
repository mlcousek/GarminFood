// JourneysTestSupport.swift
//
// add-journeys-and-records: literal `DaySignals` / consecutive-window
// `SignalsSnapshot` builders for the journeys and records tests (the
// foundation's `SignalFixtures.snapshot` only lists the given days as its
// window; the ledgers here need the real consecutive window).

import Foundation
import FoodLogCore
@testable import Gamification

enum JR {
    static let calendar = TestClock.calendar

    /// `2026-09-DD`.
    static func key(_ day: Int) -> String {
        SignalFixtures.dayKey(2026, 9, day)
    }

    static func entry(
        _ foodId: String,
        day: Int,
        hour: Int = 12,
        minute: Int = 0,
        tags: Set<FoodTag> = [],
        calories: Double? = 100,
        protein: Double? = 5,
        sugar: Double? = 4
    ) -> SignalEntry {
        SignalFixtures.entry(
            foodId,
            tags: tags,
            at: TestClock.date(2026, 9, day, hour: hour, minute: minute),
            calories: calories,
            protein: protein,
            sugar: sugar
        )
    }

    /// A day; macro totals are summed from `entries` (nil when any is nil).
    static func day(
        _ day: Int,
        entries: [SignalEntry] = [],
        calorieGoal: Double? = nil,
        waterML: Double? = nil,
        waterGoalML: Double? = nil,
        activeKcal: Double? = nil,
        weighInKg: Double? = nil
    ) -> DaySignals {
        let base = SignalFixtures.day(
            2026, 9, day,
            entries: entries,
            waterML: waterML,
            waterGoalML: waterGoalML,
            activities: activeKcal == nil ? nil : [],
            weighInKg: weighInKg
        )
        return DaySignals(
            day: base.day,
            date: base.date,
            entries: base.entries,
            totals: base.totals,
            goals: calorieGoal.map { MacroGoals(calories: $0) },
            goalStatus: base.goalStatus,
            waterML: base.waterML,
            waterGoalML: base.waterGoalML,
            activeKcal: activeKcal,
            activities: base.activities,
            weighInKg: base.weighInKg,
            availability: base.availability
        )
    }

    /// A protein-only day (one entry carrying `grams`).
    static func protein(_ day: Int, _ grams: Double) -> DaySignals {
        JR.day(day, entries: [entry("food-\(day)", day: day, protein: grams)])
    }

    /// Consecutive window `2026-09-<from>...<today>` holding `days`.
    static func snapshot(
        _ days: [DaySignals],
        from: Int = 1,
        today: Int,
        firstSeenDayByFood: [String: String] = [:]
    ) -> SignalsSnapshot {
        SignalsSnapshot(
            days: Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last }),
            today: key(today),
            windowDays: (from...today).map(key),
            firstSeenDayByFood: firstSeenDayByFood
        )
    }

    static func context(_ snapshot: SignalsSnapshot, today: Int, hour: Int = 20) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: TestClock.date(2026, 9, today, hour: hour),
            calendar: calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: [],
            isConfirmPath: false
        )
    }

    static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("journeys-records-\(UUID().uuidString)", isDirectory: true)
    }
}

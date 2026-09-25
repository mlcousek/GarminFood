// WeeklyBingoTestSupport.swift
//
// add-weekly-bingo: literal `DaySignals` builders for the bingo tests, on
// top of the foundation's `SignalFixtures` (which wave-2 changes must not
// edit). Everything is in ISO week 2026-W39 (Monday 21 -- Sunday 27
// September 2026) in UTC, like `TestClock`.

import Foundation
import FoodLogCore
@testable import Gamification

enum BingoFixtures {
    static let calendar = TestClock.calendar
    static let week = WeekKey(yearForWeek: 2026, week: 39)

    /// 2026-09-(21 + offset), offset 0 = Monday.
    static func key(_ offset: Int) -> String {
        SignalFixtures.dayKey(2026, 9, 21 + offset)
    }

    static func at(_ offset: Int, hour: Int = 12, minute: Int = 0) -> Date {
        TestClock.date(2026, 9, 21 + offset, hour: hour, minute: minute)
    }

    static func entry(
        _ foodId: String,
        _ tags: Set<FoodTag> = [],
        on offset: Int = 1,
        hour: Int = 12,
        minute: Int = 0,
        meal: SignalMeal = .lunch,
        brand: String? = nil,
        protein: Double? = 5,
        fiber: Double? = 2,
        sugar: Double? = 4
    ) -> SignalEntry {
        SignalFixtures.entry(
            foodId,
            tags: tags,
            at: at(offset, hour: hour, minute: minute),
            meal: meal,
            brand: brand,
            protein: protein,
            fiber: fiber,
            sugar: sugar
        )
    }

    static func day(
        _ offset: Int,
        _ entries: [SignalEntry] = [],
        goalStatus: SignalGoalStatus? = nil,
        waterML: Double? = nil,
        waterGoalML: Double? = nil,
        activities: [ActivitySummary]? = nil
    ) -> DaySignals {
        SignalFixtures.day(
            2026, 9, 21 + offset,
            entries: entries,
            goalStatus: goalStatus,
            waterML: waterML,
            waterGoalML: waterGoalML,
            activities: activities
        )
    }

    /// A day with one untagged lunch entry -- satisfies no bingo task.
    static func plainDay(_ offset: Int) -> DaySignals {
        day(offset, [entry("bread-\(offset)", on: offset)])
    }

    static func goals(calories: Bool = false, protein: Bool = false, carbs: Bool = false, fat: Bool = false) -> SignalGoalStatus {
        SignalGoalStatus(metCalorieGoal: calories, metProteinGoal: protein, metCarbGoal: carbs, metFatGoal: fat)
    }

    static func activity(on offset: Int, endHour: Int, minutes: Double) -> ActivitySummary {
        let end = at(offset, hour: endHour)
        return ActivitySummary(
            id: "act-\(offset)-\(endHour)",
            typeKey: "running",
            day: key(offset),
            start: end.addingTimeInterval(-minutes * 60),
            durationS: minutes * 60
        )
    }

    static func snapshot(
        _ days: [DaySignals],
        today: String = BingoFixtures.key(3),
        firstSeenDayByFood: [String: String] = [:],
        firstSeenDayByCzechBrand: [String: String] = [:]
    ) -> SignalsSnapshot {
        SignalFixtures.snapshot(
            days,
            today: today,
            firstSeenDayByFood: firstSeenDayByFood,
            firstSeenDayByCzechBrand: firstSeenDayByCzechBrand
        )
    }

    static func context(_ snapshot: SignalsSnapshot, now: Date = BingoFixtures.at(3), unlocked: Set<String> = []) -> FeatureContext {
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

    static func tempDirectory(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    /// A hand-made card whose squares are all simple tag tasks:
    ///   e-fruit     e-tea    e-egg
    ///   e-nuts      FREE     e-soup
    ///   m-fish      m-legume e-fermented
    static let fixedCard = ["e-fruit", "e-tea", "e-egg", "e-nuts", "free", "e-soup", "m-fish", "m-legume", "e-fermented"]

    /// The tag that ticks each square of `fixedCard`.
    static let fixedCardTags: [String: FoodTag] = [
        "e-fruit": .fruit, "e-tea": .tea, "e-egg": .egg, "e-nuts": .nuts,
        "e-soup": .soup, "m-fish": .fish, "m-legume": .legume, "e-fermented": .fermented,
    ]

    /// One entry per listed task id of `fixedCard`, on `offset`.
    static func entries(ticking taskIds: [String], on offset: Int = 1) -> [SignalEntry] {
        taskIds.compactMap { id in
            fixedCardTags[id].map { entry("food-\(id)", [$0], on: offset) }
        }
    }
}

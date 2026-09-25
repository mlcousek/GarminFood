// BossTestSupport.swift
//
// add-weekly-boss-and-streak-freezes: literal day/snapshot builders for the
// weekly-boss and streak-freeze tests (the foundation's `SignalFixtures`
// stays untouched, per the wave plan). Everything is in UTC via
// `TestClock`, in September 2026: ISO week 2026-W39 is Mon 21 - Sun 27 Sep,
// so a W39 boss analyses W35-W38 = 24 Aug - 20 Sep.

import Foundation
import FoodLogCore
@testable import Gamification

enum BT {
    static let calendar = TestClock.calendar

    /// Noon of 2026-`month`-`day`.
    static func date(_ month: Int, _ day: Int) -> Date {
        TestClock.date(2026, month, day)
    }

    /// Midnight of 2026-`month`-`day` (the streak engine's day marker).
    static func midnight(_ month: Int, _ day: Int) -> Date {
        calendar.startOfDay(for: date(month, day))
    }

    static func key(_ month: Int, _ day: Int) -> String {
        SignalFixtures.dayKey(2026, month, day)
    }

    /// Every noon from `start` through `end`, one per day.
    static func dates(from start: Date, through end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        return result
    }

    /// Every midnight from `start` through `end`.
    static func midnights(from start: Date, through end: Date) -> Set<Date> {
        Set(dates(from: start, through: end).map { calendar.startOfDay(for: $0) })
    }

    /// A logged day: lunch with vegetables (and fruit unless `fruit` is
    /// false), a vegetable dinner at 13:00, optionally a breakfast at 08:00,
    /// a late snack at 22:00, an evening entry at 19:00, water data. Fibre
    /// is unknown on every entry (so the fibre phantom is never eligible)
    /// and there is no goal status (protein/calorie bosses never eligible).
    static func day(
        _ date: Date,
        breakfast: Bool,
        fruit: Bool = true,
        lateSnack: Bool = false,
        eveningEntry: Bool = false,
        waterML: Double? = nil,
        waterGoalML: Double? = nil
    ) -> DaySignals {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let (y, m, d) = (parts.year!, parts.month!, parts.day!)
        func at(_ hour: Int) -> Date { TestClock.date(y, m, d, hour: hour) }
        var entries: [SignalEntry] = [
            SignalFixtures.entry("salad", tags: fruit ? [.vegetable, .fruit] : [.vegetable], at: at(12), meal: .lunch, fiber: nil),
            SignalFixtures.entry("soup", tags: [.vegetable], at: at(13), meal: .lunch, fiber: nil),
        ]
        if breakfast {
            entries.append(SignalFixtures.entry("oats", at: at(8), meal: .breakfast, fiber: nil))
        }
        if eveningEntry {
            entries.append(SignalFixtures.entry("yoghurt", at: at(19), meal: .snack, fiber: nil))
        }
        if lateSnack {
            entries.append(SignalFixtures.entry("chips", at: at(22), meal: .snack, fiber: nil))
        }
        return SignalFixtures.day(y, m, d, entries: entries, waterML: waterML, waterGoalML: waterGoalML)
    }

    /// Logged days from `start` through `end`; breakfast where
    /// `breakfastOn(index)` is true (index 0 = `start`).
    static func history(
        from start: Date,
        through end: Date,
        breakfastOn: (Int) -> Bool,
        fruitOn: (Int) -> Bool = { _ in true }
    ) -> [DaySignals] {
        dates(from: start, through: end).enumerated().map { index, date in
            day(date, breakfast: breakfastOn(index), fruit: fruitOn(index))
        }
    }

    /// The W35-W38 window (24 Aug - 20 Sep) with breakfast on 12 of 28
    /// days (Mon-Wed each week): breakfast is the weakest habit (3/7 -> 43 %),
    /// so a W39 boss is the breakfast goblin with target 5.
    static func weakBreakfastWindow() -> [DaySignals] {
        history(from: date(8, 24), through: date(9, 20), breakfastOn: { $0 % 7 < 3 })
    }

    static func snapshot(_ days: [DaySignals], today: Date) -> SignalsSnapshot {
        SignalFixtures.snapshot(days, today: NutritionDate.string(from: today, calendar: calendar))
    }

    static func context(_ snapshot: SignalsSnapshot, now: Date) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            streak: StreakEngine.status(loggedDays: [], today: calendar.startOfDay(for: now), calendar: calendar),
            level: 1,
            unlockedBadgeIds: [],
            isConfirmPath: false
        )
    }

    static func tempDirectory(_ name: String = "boss") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    }

    static func grant(_ month: Int, _ day: Int, _ name: String = "bingo.freeze.test") -> RewardLedger.FreezeGrant {
        RewardLedger.FreezeGrant(key: "\(name).\(month)-\(day)", day: key(month, day))
    }

    static func week(_ raw: String) -> WeekKey {
        WeekKey(rawValue: raw)!
    }
}

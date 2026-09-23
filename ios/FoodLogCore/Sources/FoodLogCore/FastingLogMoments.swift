// FastingLogMoments.swift
//
// Turns what the app already has on hand -- the local usage history (one
// event per in-app log, with the moment it was logged) and whatever Garmin
// day logs are cached in memory (each entry's `logTimestamp`) -- into the
// plain list of "moments food was eaten" that `FastingDayEvaluator` judges
// fasting windows against (redesign-fasting-schedule 1.2 / 2.3). Kept
// separate from FastingSchedule.swift because it's the one place that has
// to know about GarminKit's wire models and the usage-history file format;
// the schedule math itself knows about neither.
//
// Deliberately NO network: the history screen evaluates the last 30 days
// from what's already local (config.yaml: local-first, never wait on
// connectapi.garmin.com), and says so when the data doesn't reach back far
// enough (`coverageStart`) rather than guessing "kept" for a day it simply
// has no records of.
//
// The "does this log count as eating at its timestamp" rule
// (`countsAsEating`) exists because a log's timestamp is when the button
// was pressed, not necessarily when the food was eaten: back-filling
// yesterday's dinner at 09:00 this morning must not break this morning's
// fast. A log counts only when it was logged FOR the day it was logged ON
// -- with a 4 h grace after midnight (Garmin's own nutrition day starts at
// 04:00, per docs/garmin-food-log-contract.md), so a 00:30 snack filed
// under the previous day still counts. The confirm screens' fasting note
// uses the very same rule (`FastingSchedule.fastEndIfLogging`), so the
// note shows exactly when the log will later mark the day broken.

import Foundation
import GarminKit

public enum FastingLogMoments {
    /// See the file header. `nutritionDay` is `yyyy-MM-dd`; `nil` (usage
    /// events recorded before that field existed) can't be checked, so it
    /// counts.
    public static func countsAsEating(timestamp: Date, nutritionDay: String?, calendar: Calendar) -> Bool {
        guard let nutritionDay else { return true }
        if NutritionDate.string(from: timestamp, calendar: calendar) == nutritionDay { return true }
        let graceShifted = timestamp.addingTimeInterval(-afterMidnightGrace)
        return NutritionDate.string(from: graceShifted, calendar: calendar) == nutritionDay
    }

    /// Garmin's observed `dayStartTime` of 04:00.
    public static let afterMidnightGrace: TimeInterval = 4 * 3600

    /// Eating moments from the local usage history -- every food logged in
    /// this app (search, quick pick, meal preset, Siri/Control), queued or
    /// delivered.
    public static func moments(from events: [UsageEvent], calendar: Calendar) -> [Date] {
        events
            .filter { countsAsEating(timestamp: $0.timestamp, nutritionDay: $0.nutritionDay, calendar: calendar) }
            .map(\.timestamp)
    }

    /// Eating moments from one cached Garmin day log (`date` is its
    /// `yyyy-MM-dd` key). Covers foods logged OUTSIDE this app (the
    /// official Garmin Connect app), which the usage history never sees --
    /// but only for days that happen to be cached. Entries with a missing
    /// or unparseable `logTimestamp` are skipped: without a time they can't
    /// be placed inside or outside a window.
    public static func moments(fromGarminLog log: DailyFoodLog, date: String, calendar: Calendar) -> [Date] {
        let fromMeals = (log.mealDetails ?? []).flatMap { $0.loggedFoods ?? [] }
        let loose = log.loggedFoodsWithServingSizes ?? []
        return (fromMeals + loose).compactMap { food -> Date? in
            guard let raw = food.logTimestamp, let timestamp = parseTimestamp(raw) else { return nil }
            return countsAsEating(timestamp: timestamp, nutritionDay: date, calendar: calendar) ? timestamp : nil
        }
    }

    /// The earliest moment the usage history is known to be complete from.
    /// `UsageHistoryStore` trims its oldest events once it reaches
    /// `capacity`, so a full store may be missing logs from before its
    /// oldest surviving event; a store below capacity has never trimmed
    /// anything, so it's complete (`nil`).
    public static func coverageStart(events: [UsageEvent], capacity: Int = UsageHistoryStore.maxStoredEvents) -> Date? {
        guard events.count >= capacity else { return nil }
        return events.map(\.timestamp).min()
    }

    /// `2026-09-16T13:35:49.324Z` as Garmin returns it, with or without the
    /// fractional seconds.
    static func parseTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

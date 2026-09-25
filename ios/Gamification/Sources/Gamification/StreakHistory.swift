// StreakHistory.swift
//
// The streak screen's data (add-app-shell-and-meal-dashboard, progress-screens
// spec): the longest streak ever reached and a calendar of recent weeks.
// Built on `StreakEngine.simulate`, the same walk the current streak uses,
// so a day the calendar marks as "grace" is exactly a day the current streak
// was allowed to skip, and the two can never disagree.

import FoodLogCore
import Foundation

public enum StreakHistory {
    public enum Mark: String, Sendable, Equatable {
        /// At least one entry was logged for this day.
        case logged
        /// Missed, but forgiven by the one-miss-per-week grace rule while a
        /// streak was running.
        case grace
        /// Missed, and not forgiven (or no streak was running).
        case missed
        /// Missed, but covered by a consumed streak freeze (design D5 of
        /// add-weekly-boss-and-streak-freezes): the streak survived without
        /// growing.
        case frozen
        /// Today, with nothing logged yet.
        case pending
        /// Later than today.
        case future
        /// Earlier than anything ever logged.
        case beforeHistory
    }

    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public let mark: Mark
        public let isToday: Bool
        public var id: Date { date }
    }

    public struct Summary: Sendable, Equatable {
        public let currentLength: Int
        public let longestLength: Int
        public let loggedDayCount: Int
        /// Whole weeks (aligned to the calendar's first weekday), oldest
        /// first, ending with the week that contains today.
        public let days: [Day]
    }

    public static func summary(
        events: [UsageEvent],
        frozenDays: Set<Date> = [],
        now: Date = Date(),
        weeks: Int = 6,
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> Summary {
        let loggedDays = StreakEngine.loggedDays(events: events, boundaryHour: boundaryHour, calendar: calendar)
        let today = NutritionDayBoundary.nutritionDay(for: now, boundaryHour: boundaryHour, calendar: calendar)
        return summary(loggedDays: loggedDays, frozenDays: frozenDays, today: today, weeks: weeks, calendar: calendar)
    }

    public static func summary(
        loggedDays: Set<Date>,
        frozenDays: Set<Date> = [],
        today: Date,
        weeks: Int = 6,
        calendar: Calendar = .current
    ) -> Summary {
        let walk = StreakEngine.simulate(loggedDays: loggedDays, frozenDays: frozenDays, today: today, calendar: calendar)
        let current = StreakEngine.status(loggedDays: loggedDays, frozenDays: frozenDays, today: today, calendar: calendar).length
        let earliest = loggedDays.min()

        let weekCount = max(weeks, 1)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let gridStart = calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: weekStart) ?? weekStart

        var days: [Day] = []
        days.reserveCapacity(weekCount * 7)
        for offset in 0..<(weekCount * 7) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let day = calendar.startOfDay(for: date)
            let mark = self.mark(for: day, today: today, loggedDays: loggedDays, walk: walk, earliest: earliest)
            days.append(Day(date: day, mark: mark, isToday: day == today))
        }

        return Summary(
            currentLength: current,
            longestLength: walk.longestLength,
            loggedDayCount: loggedDays.count,
            days: days
        )
    }

    static func mark(
        for day: Date,
        today: Date,
        loggedDays: Set<Date>,
        walk: StreakEngine.Walk,
        earliest: Date?
    ) -> Mark {
        if day > today {
            return .future
        }
        if let outcome = walk.outcomes[day] {
            switch outcome {
            case .logged: return .logged
            case .grace: return .grace
            case .missed: return .missed
            case .frozen: return .frozen
            }
        }
        if day == today {
            return loggedDays.contains(day) ? .logged : .pending
        }
        guard let earliest, day >= earliest else {
            return .beforeHistory
        }
        return loggedDays.contains(day) ? .logged : .missed
    }
}

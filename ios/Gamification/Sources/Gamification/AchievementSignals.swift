import FoodLogCore
import Foundation

// AchievementSignals.swift
//
// Pure, directly testable computation of the small calendar/novelty
// booleans a handful of achievements need (achievements spec's "evaluated
// against locally available cumulative statistics") -- kept separate from
// `GamificationEngine` so this logic isn't buried in the app layer.
public enum AchievementSignals {
    /// Any retained event's nutrition-day falls on February 29th.
    public static func loggedOnLeapDay(events: [UsageEvent], boundaryHour: Int, calendar: Calendar) -> Bool {
        events.contains { event in
            let day = NutritionDayBoundary.nutritionDay(for: event, boundaryHour: boundaryHour, calendar: calendar)
            let components = calendar.dateComponents([.month, .day], from: day)
            return components.month == 2 && components.day == 29
        }
    }

    /// Any retained event's nutrition-day falls on January 1st.
    public static func loggedOnNewYearsDay(events: [UsageEvent], boundaryHour: Int, calendar: Calendar) -> Bool {
        events.contains { event in
            let day = NutritionDayBoundary.nutritionDay(for: event, boundaryHour: boundaryHour, calendar: calendar)
            let components = calendar.dateComponents([.month, .day], from: day)
            return components.month == 1 && components.day == 1
        }
    }

    /// Any event's raw capture timestamp lands exactly at hour 0 -- the
    /// real clock time, not the nutrition-day boundary.
    public static func loggedAtMidnight(events: [UsageEvent], calendar: Calendar) -> Bool {
        events.contains { calendar.component(.hour, from: $0.timestamp) == 0 }
    }

    /// At least one FULLY COMPLETED calendar month (every one of that
    /// month's real day-count, not just "the days so far") has a logged
    /// entry on every single day. An in-progress month naturally fails
    /// this (its later days simply aren't in `loggedDays` yet), so no
    /// special-casing "is this month still ongoing" is needed.
    public static func hasPerfectCalendarMonth(loggedDays: Set<Date>, calendar: Calendar) -> Bool {
        var daysByMonth: [DateComponents: Set<Int>] = [:]
        for day in loggedDays {
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            let key = DateComponents(year: components.year, month: components.month)
            daysByMonth[key, default: []].insert(components.day ?? 0)
        }
        for (key, days) in daysByMonth {
            guard let year = key.year, let month = key.month,
                  let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
            else { continue }
            if days.count >= range.count, Set(range).isSubset(of: days) {
                return true
            }
        }
        return false
    }

    /// Whole years elapsed since `firstLogDate`, `0` if unknown or less
    /// than a year -- the basis for the anniversary achievements.
    public static func yearsSince(_ firstLogDate: Date?, now: Date, calendar: Calendar) -> Int {
        guard let firstLogDate else { return 0 }
        let years = calendar.dateComponents([.year], from: firstLogDate, to: now).year ?? 0
        return max(0, years)
    }
}

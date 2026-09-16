// StreakEngine.swift
//
// Streaks spec's "A streak counts consecutive nutrition-days with at least
// one logged entry" and "One missed day per rolling week is forgiven"
// requirements (design.md D1/D2, tasks 23.1/23.2). A pure function over a
// set of nutrition-days that had at least one log -- no store, no
// persisted state at all, per design.md's Goals: "The whole system is a
// pure function of local log data."
//
// THE GRACE ALGORITHM, worked through in prose because the code below is
// a forward simulation and is easy to misread backwards:
//
// Walk the calendar forward, one nutrition-day at a time, starting on the
// earliest day that has ever been logged (there is no streak before that)
// and ending on "today" if today has already been logged, or "yesterday"
// otherwise (today, still in progress, is never itself counted as a miss --
// that is exactly the "at risk" state, not a broken one). For each day:
//
//   - Logged: the running streak length increases by one.
//   - Missed, and no OTHER missed day fell within the trailing 7 days
//     (inclusive, i.e. at most 6 days apart): this is the week's one
//     forgiven miss. The streak length does not increase, but it does not
//     reset either -- the day is skipped over "as if it had not occurred"
//     (streaks spec's own wording). This miss is remembered for future
//     window checks.
//   - Missed, and another missed day already fell within the trailing 7
//     days: this is the SECOND miss in that rolling window. Per D2, the
//     streak resets to zero, "starting from the next logged day" -- which
//     falls out of the simulation naturally, since the running length is
//     reset to zero right here and then rebuilds from whatever is logged
//     afterward.
//
// This is a forward simulation, not a backward scan from today, precisely
// because a reset must happen at the point of the SECOND miss
// chronologically, collapsing whatever was built up to that point
// (including anything the first, forgiven miss had let survive) -- a
// backward scan from today would find the two miss days in the wrong order
// and attribute the reset to the wrong one.
//
// The rolling window is a plain 7-day sliding window measured in absolute
// days between miss dates, never aligned to a calendar week (Sunday- or
// Monday-starting) -- this is what makes "a miss straddling a week
// boundary" (design.md's named risk) a non-issue: there is no boundary to
// straddle, only a distance between two dates.

import FoodLogCore
import Foundation

public enum StreakEngine {
    /// A rolling window is 7 days wide: two misses at most 6 days apart
    /// fall in the same window.
    public static let graceWindowDays = 7

    public struct Status: Equatable, Sendable {
        /// The current streak length in nutrition-days.
        public let length: Int
        /// `true` when today's nutrition-day already has a logged entry.
        public let hasLoggedToday: Bool
        /// Streaks spec's "visibly at risk" requirement: the streak is
        /// still alive (`length > 0`), yesterday was logged, and nothing
        /// has been logged yet today. `false` whenever `hasLoggedToday` is
        /// `true` (that is the "safe" state) or the streak is already 0.
        public let isAtRiskToday: Bool
        /// The most recent nutrition-day with at least one logged entry,
        /// if any has ever been logged.
        public let lastLoggedDay: Date?

        public init(length: Int, hasLoggedToday: Bool, isAtRiskToday: Bool, lastLoggedDay: Date?) {
            self.length = length
            self.hasLoggedToday = hasLoggedToday
            self.isAtRiskToday = isAtRiskToday
            self.lastLoggedDay = lastLoggedDay
        }
    }

    /// The primary pure entry point: raw wall-clock capture timestamps in,
    /// a `Status` out. No FoodLogCore/GarminKit type is required to call
    /// this -- see `status(events:...)` below for the convenience overload
    /// that reads real `UsageEvent`s.
    public static func status(
        eventTimestamps: [Date],
        now: Date = Date(),
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> Status {
        let loggedDays = Set(eventTimestamps.map {
            NutritionDayBoundary.nutritionDay(for: $0, boundaryHour: boundaryHour, calendar: calendar)
        })
        let today = NutritionDayBoundary.nutritionDay(for: now, boundaryHour: boundaryHour, calendar: calendar)

        guard let earliest = loggedDays.min() else {
            return Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil)
        }
        let lastLoggedDay = loggedDays.max()
        let hasLoggedToday = loggedDays.contains(today)

        let endDay = hasLoggedToday ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)

        // Nothing to walk: the only ever-logged day(s) are still in the
        // future relative to `endDay` (shouldn't normally happen, but keeps
        // this total rather than trapping on a malformed input).
        guard earliest <= endDay else {
            return Status(length: 0, hasLoggedToday: hasLoggedToday, isAtRiskToday: false, lastLoggedDay: lastLoggedDay)
        }

        var streakLength = 0
        var recentMisses: [Date] = [] // miss-days still within the trailing window of "the current day" as we walk forward
        var cursor = earliest
        var iterations = 0
        // A generous safety cap -- purely defensive against a malformed
        // `now`/event far enough in the future to otherwise loop for years;
        // real usage history (capped at 500 events) never approaches this.
        let maxIterations = 20 * 365

        while cursor <= endDay, iterations < maxIterations {
            iterations += 1
            if loggedDays.contains(cursor) {
                streakLength += 1
            } else {
                recentMisses.removeAll { daysBetween($0, cursor, calendar: calendar) > Self.graceWindowDays - 1 }
                if recentMisses.isEmpty {
                    // First miss in its rolling window: forgiven.
                    recentMisses.append(cursor)
                } else {
                    // Second miss within the same rolling window: reset.
                    streakLength = 0
                    recentMisses = [cursor]
                }
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? endDay.addingTimeInterval(1)
        }

        let isAtRisk = !hasLoggedToday && streakLength > 0 && loggedDays.contains(
            calendar.date(byAdding: .day, value: -1, to: today) ?? today
        )

        return Status(length: streakLength, hasLoggedToday: hasLoggedToday, isAtRiskToday: isAtRisk, lastLoggedDay: lastLoggedDay)
    }

    /// Convenience overload for real call sites: reads `UsageEvent`
    /// (FoodLogCore) directly rather than making every caller extract
    /// `.timestamp` itself.
    public static func status(
        events: [UsageEvent],
        now: Date = Date(),
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> Status {
        status(eventTimestamps: events.map(\.timestamp), now: now, boundaryHour: boundaryHour, calendar: calendar)
    }

    private static func daysBetween(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        abs(calendar.dateComponents([.day], from: a, to: b).day ?? Int.max)
    }
}

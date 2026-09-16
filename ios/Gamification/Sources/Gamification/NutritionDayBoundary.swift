// NutritionDayBoundary.swift
//
// design.md D1: "The streak day boundary is the Garmin nutrition day, not
// local midnight" -- `establish-garmin-nutrition-contract` observed the
// account's real `dayStartTime`/`dayEndTime` as 04:00-17:00
// (GarminKit.DailyFoodLog's doc comment), i.e. NOT a plain midnight-to-
// midnight window.
//
// IMPORTANT LIMITATION, read before changing anything here: D1 also says
// the streak should be "computed from the entry's own logged date rather
// than re-deriving it from a wall-clock timestamp." That logged date (the
// `date: String` `LogEntryCoordinator.confirm`/`confirmCustomFood` sends to
// `Outbox.logFood`, itself a user-editable field defaulting to
// `NutritionDate.todayString()`) is NOT persisted anywhere this package can
// read -- `UsageEvent` (FoodLogCore/UsageHistory.swift) deliberately stores
// only `foodId`/`servingId`/`numberOfUnits`/`timestamp`, and this phase's
// brief was explicit: "Do not guess the shape; use exactly what's there."
// So the ideal implementation of D1 is not achievable from the data that
// actually exists on disk today. This is the best available approximation
// given that constraint: it re-derives a nutrition-day boundary from the
// raw capture `timestamp` using the one boundary hour Garmin's contract
// doc actually observed (04:00), rather than falling back to local
// midnight the way `NutritionDate.swift` deliberately does for the
// (unrelated, user-editable) outbound log-date field. A log made at
// 01:00 counts toward the PREVIOUS nutrition-day; a log made at 05:00
// counts toward the day it was made on. This is still strictly closer to
// D1's intent than local midnight, and is the documented, deliberate
// trade-off -- see this change's final report for the full reasoning.

// UPDATE 2026-09-16: the limitation above is resolved. `UsageEvent` now
// carries `nutritionDay`, the logged date sent to Garmin. That date is
// local-midnight based (`NutritionDate`), so the app now passes
// `loggedDateBoundaryHour` (0) and `nutritionDay(for event:)` prefers the
// recorded date. With both halves on the same calendar day, streaks, XP and
// goal status agree with what Garmin shows even for a log made at 01:00.
// The 04:00 default stays only for existing callers and tests; only events
// written before the field existed still fall back to their timestamp.

import FoodLogCore
import Foundation

public enum NutritionDayBoundary {
    /// The boundary that matches the date an entry is actually logged for:
    /// `NutritionDate` in FoodLogCore is local-midnight based, and that is
    /// the date Garmin receives.
    public static let loggedDateBoundaryHour = 0

    /// The nutrition day an event counts toward: its recorded
    /// `nutritionDay` when present, otherwise its timestamp bucketed with
    /// `boundaryHour`.
    public static func nutritionDay(
        for event: UsageEvent,
        boundaryHour: Int = defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> Date {
        if let recorded = event.nutritionDay, let day = date(fromDayString: recorded, calendar: calendar) {
            return day
        }
        return nutritionDay(for: event.timestamp, boundaryHour: boundaryHour, calendar: calendar)
    }

    /// Parses `yyyy-MM-dd` into midnight of that day in `calendar`'s zone.
    public static func date(fromDayString string: String, calendar: Calendar = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let parsed = formatter.date(from: string) else { return nil }
        return calendar.startOfDay(for: parsed)
    }

    /// The one `dayStartTime` value actually observed on the probed
    /// account (docs/garmin-food-log-contract.md via
    /// GarminKit.DailyFoodLog's doc comment). Not confirmed to be constant
    /// across accounts or across time on the SAME account, but it is the
    /// only real data point available, and a fixed local heuristic is
    /// required anyway (see this type's header) -- so it is used as-is
    /// rather than invented from nothing.
    public static let defaultBoundaryHour = 4

    /// Buckets a wall-clock `Date` into the start-of-day `Date` (midnight,
    /// in `calendar`'s time zone) of the "nutrition day" it falls in, per
    /// the boundary above: the nutrition day runs from `boundaryHour:00`
    /// to the next occurrence of `boundaryHour:00`, not from local
    /// midnight to midnight.
    public static func nutritionDay(
        for date: Date,
        boundaryHour: Int = defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: -boundaryHour, to: date) ?? date
        return calendar.startOfDay(for: shifted)
    }

    /// `yyyy-MM-dd` string for a nutrition day, for use as a dictionary key
    /// or a persisted record's identity (e.g. `DailyGoalStatus.date`,
    /// `XPStore`'s "already awarded this bonus today" bookkeeping) --
    /// matches `NutritionDate.string(from:calendar:)`'s format exactly
    /// (FoodLogCore/NutritionDate.swift) so the two remain visually and
    /// lexically comparable, even though they answer different questions
    /// (that one is local-midnight-based by design; this one is not).
    public static func dayString(
        for date: Date,
        boundaryHour: Int = defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> String {
        let day = nutritionDay(for: date, boundaryHour: boundaryHour, calendar: calendar)
        return string(forNutritionDay: day, calendar: calendar)
    }

    /// Formats a `Date` that is ALREADY a nutrition-day marker (i.e. already
    /// the output of `nutritionDay(for:)` -- midnight of the correct day) as
    /// `yyyy-MM-dd`, with NO further boundary-hour shift applied.
    ///
    /// `ChallengeEngine`'s day-iteration loops (`eachDay(from:to:)`) walk
    /// `Date`s that came from `nutritionDay(for:)` already. Passing one of
    /// those into `dayString(for:)` re-shifts it a SECOND time -- a real bug
    /// found via CI test failures (every goal-hitting challenge undercounted
    /// by exactly one day). Use this function instead whenever the `Date` in
    /// hand is already day-normalized; use `dayString(for:)` only for a raw,
    /// unshifted wall-clock timestamp.
    public static func string(forNutritionDay day: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }
}

// TrainingDay.swift
//
// Which plan day the app shows (spec "The training day follows the plan's
// time zone and day boundary", design D6):
//
//   - on today's date, "now" is read in the projection's `athlete.tz`
//     (owner decision 0.5, defaulted: the contract's dates and `asOf` are
//     local to it), and a time before `athlete.dayBoundaryHour` still
//     belongs to the previous training day -- at 00:40 after a late evening
//     session, Today still shows that evening;
//   - any other date the day switcher selects is used as is.
//
// The device's zone is the fallback when `tz` is absent or unknown.
//
// Depended on by: the app's TrainingModel (Today follows the day switcher),
// TodayTrainingBuilder, the freshness check. Tests: TrainingDayTests
// (boundary hour, 00:40, other dates, DST change days, zone choice).

import Foundation

public enum TrainingDay {
    /// The training day "now" falls on.
    public static func current(now: Date, boundaryHour: Int, timeZone: TimeZone) -> LocalDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: now)
        let today = LocalDate(date: now, timeZone: timeZone)
        return hour < boundaryHour ? today.adding(days: -1) : today
    }

    /// The day to show for the day switcher's selection.
    public static func resolve(
        selectedDate: LocalDate,
        isToday: Bool,
        now: Date,
        boundaryHour: Int,
        timeZone: TimeZone
    ) -> LocalDate {
        guard isToday else { return selectedDate }
        return current(now: now, boundaryHour: boundaryHour, timeZone: timeZone)
    }

    /// `resolve` with the athlete's settings (device zone as fallback).
    public static func resolve(
        selectedDate: LocalDate,
        isToday: Bool,
        now: Date,
        athlete: Athlete,
        deviceTimeZone: TimeZone
    ) -> LocalDate {
        resolve(
            selectedDate: selectedDate,
            isToday: isToday,
            now: now,
            boundaryHour: athlete.dayBoundaryHour,
            timeZone: athlete.timeZone(fallback: deviceTimeZone)
        )
    }
}

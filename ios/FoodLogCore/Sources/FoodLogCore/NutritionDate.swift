// NutritionDate.swift
//
// `YYYY-MM-DD` formatting for the date field GarminKit's
// `CreateFoodLogEntryRequest`/`Outbox.logFood` expect.
//
// Deliberately uses the DEVICE'S calendar day, not Garmin's own nutrition-
// day window (`dayStartTime`/`dayEndTime` from `dailyFoodLog`, observed as
// 04:00-17:00 on one account -- docs/garmin-food-log-contract.md). Reading
// that window would require a network call before the confirm screen even
// opens, which conflicts with the flow's zero-network-wait requirement, and
// the date field is explicitly editable per the spec regardless -- a user
// logging just after midnight but before their Garmin "day" rolls over can
// simply pick the earlier date by hand. This is a known, accepted
// simplification, not an oversight.
//
// The string is always a GREGORIAN `yyyy-MM-dd` (fix-review-findings-
// 2026-09-b, finding 1): it goes on the wire (request paths, `mealDate`)
// and is the day key every store and Gamification uses. The `calendar`
// argument contributes only its time zone -- which is what makes the day
// the device's local day -- never its calendar system, so a phone set to
// the Buddhist or Japanese calendar still writes `2026-09-30`. The key
// parsers below (and Gamification's, which call them) read it back the
// same way. Formatting goes through GarminKit's `GarminWireDate`.

import Foundation
import GarminKit

public enum NutritionDate {
    public static func todayString(now: Date = Date(), calendar: Calendar = .current) -> String {
        string(from: now, calendar: calendar)
    }

    /// The Gregorian local day of `date` in `calendar`'s time zone.
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        GarminWireDate.dayString(from: date, timeZone: calendar.timeZone)
    }

    /// Midnight, in `calendar`'s time zone, of a key `string(from:)` made
    /// (`nil` when it doesn't parse).
    public static func startOfDay(fromDayString day: String, calendar: Calendar = .current) -> Date? {
        GarminWireDate.startOfDay(fromDayString: day, timeZone: calendar.timeZone)
    }

    /// Noon, in `calendar`'s time zone, of a `yyyy-MM-dd` key built from
    /// its numbers (`nil` for a malformed key). Noon, so no DST change
    /// moves it into a neighbouring day.
    public static func noon(ofDayString day: String, calendar: Calendar = .current) -> Date? {
        GarminWireDate.noon(ofDayString: day, timeZone: calendar.timeZone)
    }

    /// A Gregorian calendar in `calendar`'s time zone, for day arithmetic on
    /// keys (moving a key by N days) whatever the device calendar is.
    public static func keyCalendar(matching calendar: Calendar = .current) -> Calendar {
        GarminWireDate.calendar(timeZone: calendar.timeZone)
    }

    /// Whether a day screen showing `selectedDay` should move to today:
    /// only when it was showing "today" as of `previousToday` and that day
    /// has since ended (midnight passed while the app was open or in the
    /// background). A past day the user picked on purpose is never moved.
    /// The app's `DayLogLoader.rollOverIfNeeded` asks this on foreground and
    /// on a day-change notification.
    public static func shouldRollOver(
        selectedDay: Date,
        previousToday: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(selectedDay, inSameDayAs: previousToday)
            && !calendar.isDate(selectedDay, inSameDayAs: now)
    }
}

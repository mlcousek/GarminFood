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

import Foundation

public enum NutritionDate {
    public static func todayString(now: Date = Date(), calendar: Calendar = .current) -> String {
        string(from: now, calendar: calendar)
    }

    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

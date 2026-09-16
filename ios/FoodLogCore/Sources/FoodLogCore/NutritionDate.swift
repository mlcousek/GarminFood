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
}

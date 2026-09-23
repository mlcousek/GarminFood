// FastingFormatting.swift
//
// The handful of strings every fasting surface shares -- "16 h fast · 8 h
// eating", "11 h 20 m", "12:00" -- in one place so the Settings section,
// the home card, the history screen and the confirm-screen note can never
// word the same number two different ways (config.yaml: one small design
// system, not per-screen improvisation). App-layer only: FoodLogCore keeps
// its own 24-hour `HH:mm` for notification copy, which has no view-layer
// locale to format with.

import Foundation
import FoodLogCore

enum FastingFormat {
    /// "16 h", "15 h 30 m", "45 m".
    static func duration(minutes: Int) -> String {
        let total = max(0, minutes)
        let hours = total / 60
        let remainder = total % 60
        switch (hours, remainder) {
        case (0, _): return "\(remainder) m"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(remainder) m"
        }
    }

    /// Same, for an elapsed/remaining interval (rounded down to the
    /// minute, so a live countdown never shows a minute that hasn't passed).
    static func duration(_ interval: TimeInterval) -> String {
        duration(minutes: Int(max(0, interval) / 60))
    }

    /// "16 h fast · 8 h eating" -- the spec's Settings label.
    static func split(_ schedule: FastingSchedule) -> String {
        "\(duration(minutes: schedule.fastingMinutes)) fast · \(duration(minutes: schedule.eatingMinutes)) eating"
    }

    /// Clock time in the user's own locale/24-hour setting ("12:00").
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// A minute-of-day as a date today, for `DatePicker` bindings and
    /// clock formatting of the schedule's own boundaries.
    static func date(minuteOfDay: Int, calendar: Calendar = .current) -> Date {
        let minute = FastingSchedule.normalized(minuteOfDay)
        return calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
    }

    static func minuteOfDay(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

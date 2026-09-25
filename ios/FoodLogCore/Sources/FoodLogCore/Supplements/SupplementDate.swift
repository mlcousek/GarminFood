// SupplementDate.swift
//
// Pure `yyyy-MM-dd` day arithmetic for the supplements feature
// (add-supplements D3/D14). Schedules are evaluated on day STRINGS -- the
// same `NutritionDate.string` keys the rest of the app uses -- and need
// "days between", "day + n" and "weekday of" for every-N-days patterns,
// cycles, weekday sets, the 365-day backfill window and the 7-day XP grace.
//
// Deliberately calendar- and time-zone-free (a proleptic Gregorian day
// number, Howard Hinnant's days_from_civil / civil_from_days): a day string
// already IS the local calendar date, so converting it back to a `Date`
// would only reintroduce DST and time-zone edge cases (a 23-hour day, a
// device that travelled) into what is plain integer arithmetic. Cycles are
// "computed arithmetically, with no stored per-day state" (design D3).
//
// Depended on by: ScheduleEvaluator, StockProjection, PastDayLogging and the
// supplement stores. Tests: SupplementDateTests.

import Foundation

public enum SupplementDate {
    /// Days since 1970-01-01 for a valid `yyyy-MM-dd` day, else `nil`
    /// (including impossible dates such as 2026-02-30).
    public static func ordinal(_ day: String) -> Int? {
        let parts = day.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(dayOfMonth)
        else { return nil }
        let value = daysFromCivil(year: year, month: month, day: dayOfMonth)
        // Rejects 2026-02-30 and friends: they would round-trip to March.
        guard string(fromOrdinal: value) == day else { return nil }
        return value
    }

    /// The `yyyy-MM-dd` day for a day number (see `ordinal`).
    public static func string(fromOrdinal value: Int) -> String {
        let (year, month, day) = civilFromDays(value)
        return pad(year, 4) + "-" + pad(month, 2) + "-" + pad(day, 2)
    }

    /// `day` moved by `count` days (negative = earlier), or `nil` for an
    /// invalid day.
    public static func adding(_ count: Int, to day: String) -> String? {
        guard let value = ordinal(day) else { return nil }
        return string(fromOrdinal: value + count)
    }

    /// `to - from` in days, or `nil` if either day is invalid.
    public static func daysBetween(_ from: String, _ to: String) -> Int? {
        guard let start = ordinal(from), let end = ordinal(to) else { return nil }
        return end - start
    }

    /// Weekday in `Calendar`'s numbering: 1 = Sunday ... 7 = Saturday.
    public static func weekday(_ day: String) -> Int? {
        guard let value = ordinal(day) else { return nil }
        // 1970-01-01 was a Thursday (5).
        return positiveModulo(value + 4, 7) + 1
    }

    /// Every day from `start` through `end` inclusive, oldest first. Empty
    /// when either is invalid or `start > end`. Capped at 3 660 days.
    public static func days(from start: String, through end: String) -> [String] {
        guard let first = ordinal(start), let last = ordinal(end), first <= last else { return [] }
        let upper = min(last, first + 3_659)
        return (first...upper).map(string(fromOrdinal:))
    }

    static func positiveModulo(_ value: Int, _ divisor: Int) -> Int {
        let remainder = value % divisor
        return remainder < 0 ? remainder + divisor : remainder
    }

    // MARK: - Hinnant's algorithms (public domain)

    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ value: Int) -> (Int, Int, Int) {
        let z = value + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }

    private static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

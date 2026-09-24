// SeasonalCalendar.swift
//
// add-seasonal-events design D1: the date arithmetic behind every seasonal
// event window -- Western Easter via the Anonymous Gregorian computus
// (Meeus/Jones/Butcher) and the Easter-relative days Czech food traditions
// hang off (Tučný čtvrtek, Masopustní úterý, Popeleční středa, Zelený
// čtvrtek, Velikonoční pondělí).
//
// Why a tiny civil-date type instead of `Date` + `Calendar`: event windows
// are LOGGED dates ("yyyy-MM-dd", the same key `DaySignals.day` uses), not
// instants, so pure integer arithmetic (Hinnant's days-from-civil) keeps
// window membership independent of the device time zone and DST, and makes
// every boundary unit-testable without a calendar.
//
// Depends on: Foundation only. Depended on by: SeasonalEventCatalog,
// CzechNameDays, SeasonalEvaluator, SeasonalEventsFeature (and the app's
// seasonal slot views via `SeasonalEventStatus`).

import Foundation

/// A proleptic-Gregorian calendar day (no time, no zone).
public struct SeasonalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a `yyyy-MM-dd` day key; `nil` for anything else.
    public init?(dayKey: String) {
        let parts = dayKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The calendar day `date` falls on in `calendar` (the device calendar
    /// for "today").
    public init(date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// `yyyy-MM-dd`, zero-padded -- the `DaySignals.day` format.
    public var dayKey: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { dayKey }

    /// Days since 1970-01-01 (negative before it).
    public var ordinal: Int {
        SeasonalCalendar.daysFromCivil(year: year, month: month, day: day)
    }

    public func adding(days: Int) -> SeasonalDate {
        SeasonalCalendar.civil(fromDays: ordinal + days)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(until other: SeasonalDate) -> Int {
        other.ordinal - ordinal
    }

    /// Start of this day in `calendar`, for display formatting only.
    public func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    public static func < (lhs: SeasonalDate, rhs: SeasonalDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }
}

public enum SeasonalCalendar {
    /// A day of the year without the year (a name day, "11 November").
    public struct MonthDay: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
        public let month: Int
        public let day: Int

        public init(month: Int, day: Int) {
            self.month = month
            self.day = day
        }

        public func date(in year: Int) -> SeasonalDate {
            SeasonalDate(year: year, month: month, day: day)
        }

        /// Whether this day exists in `year` (29 February only in leap years).
        public func exists(in year: Int) -> Bool {
            guard (1...12).contains(month), day >= 1 else { return false }
            return day <= SeasonalCalendar.daysInMonth(month, year: year)
        }

        public var description: String { String(format: "%02d-%02d", month, day) }

        public static func < (lhs: MonthDay, rhs: MonthDay) -> Bool {
            lhs.month != rhs.month ? lhs.month < rhs.month : lhs.day < rhs.day
        }
    }

    // MARK: - Easter (design D1)

    /// Western (Gregorian) Easter Sunday by the Anonymous Gregorian
    /// algorithm -- integer arithmetic only.
    public static func easterSunday(year: Int) -> SeasonalDate {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let n = h + l - 7 * m + 114
        return SeasonalDate(year: year, month: n / 31, day: (n % 31) + 1)
    }

    /// The same, as `DateComponents` (year/month/day only).
    public static func easterSundayComponents(year: Int) -> DateComponents {
        let easter = easterSunday(year: year)
        return DateComponents(year: easter.year, month: easter.month, day: easter.day)
    }

    /// Easter Sunday shifted by `days` (negative = before).
    public static func easter(offset days: Int, year: Int) -> SeasonalDate {
        easterSunday(year: year).adding(days: days)
    }

    /// Tučný čtvrtek (Fat Thursday): Easter − 52.
    public static func fatThursday(year: Int) -> SeasonalDate { easter(offset: -52, year: year) }
    /// Masopustní úterý (Shrove Tuesday): Easter − 47.
    public static func shroveTuesday(year: Int) -> SeasonalDate { easter(offset: -47, year: year) }
    /// Popeleční středa (Ash Wednesday): Easter − 46.
    public static func ashWednesday(year: Int) -> SeasonalDate { easter(offset: -46, year: year) }
    /// Zelený čtvrtek (Maundy Thursday): Easter − 3.
    public static func maundyThursday(year: Int) -> SeasonalDate { easter(offset: -3, year: year) }
    /// Velikonoční pondělí (Easter Monday): Easter + 1.
    public static func easterMonday(year: Int) -> SeasonalDate { easter(offset: 1, year: year) }

    // MARK: - Civil-date arithmetic (Howard Hinnant's algorithms)

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days since 1970-01-01 for a proleptic-Gregorian date.
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of `daysFromCivil`.
    static func civil(fromDays days: Int) -> SeasonalDate {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let y = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        return SeasonalDate(year: month <= 2 ? y + 1 : y, month: month, day: day)
    }
}

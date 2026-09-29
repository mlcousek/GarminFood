// LocalDate.swift
//
// The contract's calendar formats (design D2): `LocalDate` (`YYYY-MM-DD`,
// a day local to `athlete.tz`), `ISOWeek` (`YYYY-Www`) and `ClockTime`
// (`HH:MM`). A malformed value throws, which drops only the element that
// holds it (`LossyArray`), never the file.
//
// Why dates are not `Date`: a plan day is a calendar day in the athlete's
// time zone, not an instant. Keeping year/month/day and doing the
// arithmetic on a proleptic Gregorian day number (Howard Hinnant's
// days-from-civil) makes adding days, weekdays and ISO weeks exact and
// time-zone free -- no DST day that is 23 hours long, no calendar whose
// first weekday depends on the phone's region. A `Date` is made only at the
// edges (`init(date:timeZone:)`, `startDate(in:)`).
//
// ISO weeks are Monday first; week 1 holds the year's first Thursday, so
// 28 Dec 2026 is 2026-W53 and 1 Jan 2027 belongs to it too.
//
// Depended on by: every model, TrainingDay, the builders. Tests:
// ContractPrimitivesTests (W53, year boundaries, leap days).

import Foundation

public struct LocalDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// `nil` unless a real Gregorian day.
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              day >= 1, day <= LocalDate.daysInMonth(year: year, month: month)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Exactly `YYYY-MM-DD`.
    public init?(_ string: String) {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else { return nil }
        let digits = [0, 1, 2, 3, 5, 6, 8, 9]
        guard digits.allSatisfy({ ("0"..."9").contains(scalars[$0]) }) else { return nil }
        let parts = string.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The calendar day of `date` in `timeZone`.
    public init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(dayNumber: LocalDate.dayNumber(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1))
    }

    /// From days since 1970-01-01.
    public init(dayNumber: Int) {
        let civil = LocalDate.civil(fromDayNumber: dayNumber)
        year = civil.year
        month = civil.month
        day = civil.day
    }

    /// Days since 1970-01-01 (negative before).
    public var dayNumber: Int {
        LocalDate.dayNumber(year: year, month: month, day: day)
    }

    /// 1 = Monday ... 7 = Sunday.
    public var isoWeekday: Int {
        let remainder = (dayNumber % 7 + 7) % 7 // 0 = Thursday
        return (remainder + 3) % 7 + 1
    }

    public func adding(days: Int) -> LocalDate {
        LocalDate(dayNumber: dayNumber + days)
    }

    public func days(until other: LocalDate) -> Int {
        other.dayNumber - dayNumber
    }

    /// The first day of this date's month.
    public var firstOfMonth: LocalDate {
        LocalDate(dayNumber: LocalDate.dayNumber(year: year, month: month, day: 1))
    }

    /// Midnight of this day in `timeZone`.
    public func startDate(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeap(year) ? 29 : 28
        default: return 0
        }
    }

    public static func isLeap(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    static func dayNumber(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func civil(fromDayNumber number: Int) -> (year: Int, month: Int, day: Int) {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}

extension LocalDate: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = LocalDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a YYYY-MM-DD date")
        }
        self = date
    }
}

// MARK: - ISO week

public struct ISOWeek: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let week: Int

    /// The ISO week containing `date`.
    public init(containing date: LocalDate) {
        let thursday = date.adding(days: 4 - date.isoWeekday)
        let januaryFirst = LocalDate(dayNumber: LocalDate.dayNumber(year: thursday.year, month: 1, day: 1))
        year = thursday.year
        week = (thursday.dayNumber - januaryFirst.dayNumber) / 7 + 1
    }

    /// `nil` unless the year really has that week (W53 only in long years).
    public init?(year: Int, week: Int) {
        guard (1...9999).contains(year), (1...53).contains(week) else { return nil }
        let candidate = ISOWeek.monday(year: year, week: week)
        let check = ISOWeek(containing: candidate)
        guard check.year == year, check.week == week else { return nil }
        self.year = year
        self.week = week
    }

    /// Exactly `YYYY-Www`.
    public init?(_ string: String) {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 8, scalars[4] == "-", scalars[5] == "W",
              [0, 1, 2, 3, 6, 7].allSatisfy({ ("0"..."9").contains(scalars[$0]) }),
              let year = Int(String(string.prefix(4))), let week = Int(String(string.suffix(2)))
        else { return nil }
        self.init(year: year, week: week)
    }

    public var monday: LocalDate {
        ISOWeek.monday(year: year, week: week)
    }

    public var sunday: LocalDate {
        monday.adding(days: 6)
    }

    /// Monday ... Sunday.
    public var days: [LocalDate] {
        (0..<7).map { monday.adding(days: $0) }
    }

    public func contains(_ date: LocalDate) -> Bool {
        monday <= date && date <= sunday
    }

    public func adding(weeks: Int) -> ISOWeek {
        ISOWeek(containing: monday.adding(days: 7 * weeks))
    }

    public var description: String {
        String(format: "%04d-W%02d", year, week)
    }

    public static func < (lhs: ISOWeek, rhs: ISOWeek) -> Bool {
        lhs.monday < rhs.monday
    }

    static func monday(year: Int, week: Int) -> LocalDate {
        let fourthOfJanuary = LocalDate(dayNumber: LocalDate.dayNumber(year: year, month: 1, day: 4))
        let firstMonday = fourthOfJanuary.adding(days: -(fourthOfJanuary.isoWeekday - 1))
        return firstMonday.adding(days: (week - 1) * 7)
    }
}

extension ISOWeek: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let week = ISOWeek(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a YYYY-Www week")
        }
        self = week
    }
}

// MARK: - Clock time

public struct ClockTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let hour: Int
    public let minute: Int

    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    /// Exactly `HH:MM`.
    public init?(_ string: String) {
        let scalars = Array(string.unicodeScalars)
        guard scalars.count == 5, scalars[2] == ":",
              [0, 1, 3, 4].allSatisfy({ ("0"..."9").contains(scalars[$0]) }),
              let hour = Int(String(string.prefix(2))), let minute = Int(String(string.suffix(2)))
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }
}

extension ClockTime: Decodable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let time = ClockTime(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an HH:MM time")
        }
        self = time
    }
}

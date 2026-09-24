// WeekKey.swift
//
// The ONE week identity every weekly gamification feature shares (bingo
// cards, weekly bosses, creative week challenges, reward-ledger keys such as
// `bingo.line.2026-W39.row0`): an ISO-8601 week, Monday start,
// `minimumDaysInFirstWeek = 4`, spelled "2026-W39". Defined once here so two
// wave-2 features can never disagree about which week a day belongs to --
// in particular around New Year, where the ISO week-year differs from the
// calendar year (2026-12-31 and 2027-01-01 are both "2026-W53").
//
// The week is computed in the caller's calendar TIME ZONE (so a day key
// produced by `NutritionDate` maps to the same week) but always with ISO
// week rules, whatever the device's locale says the first weekday is.
//
// Depended on by: WeekPredicate/SignalEvaluator, every wave-2 weekly
// feature, RewardLedger keys (by convention).

import Foundation

public struct WeekKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// The ISO week-numbering year (not always the calendar year).
    public let yearForWeek: Int
    /// 1...53.
    public let week: Int

    public init(yearForWeek: Int, week: Int) {
        self.yearForWeek = yearForWeek
        self.week = week
    }

    /// The ISO week containing `date`, evaluated in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar) {
        let iso = WeekKey.isoCalendar(timeZone: calendar.timeZone)
        let components = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        self.init(yearForWeek: components.yearForWeekOfYear ?? 0, week: components.weekOfYear ?? 0)
    }

    /// The ISO week of a `yyyy-MM-dd` day key (as `NutritionDate` spells
    /// it). Uses the day's noon, so no time-zone edge can move it.
    public init?(dayKey: String, calendar: Calendar) {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let noon = calendar.date(from: components) else { return nil }
        self.init(date: noon, calendar: calendar)
    }

    /// Parses "2026-W39". `nil` for anything else.
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              parts[1].hasPrefix("W"),
              let week = Int(parts[1].dropFirst()),
              (1...53).contains(week)
        else { return nil }
        self.init(yearForWeek: year, week: week)
    }

    /// "2026-W39".
    public var rawValue: String {
        let paddedWeek = week < 10 ? "0\(week)" : "\(week)"
        return "\(yearForWeek)-W\(paddedWeek)"
    }

    public var description: String { rawValue }

    public static func < (lhs: WeekKey, rhs: WeekKey) -> Bool {
        (lhs.yearForWeek, lhs.week) < (rhs.yearForWeek, rhs.week)
    }

    /// Midnight of the week's Monday in `calendar`'s time zone.
    public func start(calendar: Calendar) -> Date? {
        let iso = WeekKey.isoCalendar(timeZone: calendar.timeZone)
        var components = DateComponents()
        components.yearForWeekOfYear = yearForWeek
        components.weekOfYear = week
        components.weekday = 2 // Monday
        components.hour = 0
        return iso.date(from: components)
    }

    /// The seven `yyyy-MM-dd` day keys, Monday first, in `calendar`'s zone.
    public func dayKeys(calendar: Calendar) -> [String] {
        guard let monday = start(calendar: calendar) else { return [] }
        let iso = WeekKey.isoCalendar(timeZone: calendar.timeZone)
        // Same formatter setup as `NutritionDate.string`, so the keys match
        // the ones the rest of the app produces.
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<7).compactMap { offset in
            iso.date(byAdding: .day, value: offset, to: monday).map { formatter.string(from: $0) }
        }
    }

    /// The week `count` weeks later (negative = earlier).
    public func adding(weeks count: Int, calendar: Calendar) -> WeekKey? {
        guard let monday = start(calendar: calendar) else { return nil }
        let iso = WeekKey.isoCalendar(timeZone: calendar.timeZone)
        guard let moved = iso.date(byAdding: .day, value: 7 * count, to: monday) else { return nil }
        return WeekKey(date: moved, calendar: calendar)
    }

    // MARK: - Codable as the "2026-W39" string

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = WeekKey(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO week key: \(raw)")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static func isoCalendar(timeZone: TimeZone) -> Calendar {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        return iso
    }
}

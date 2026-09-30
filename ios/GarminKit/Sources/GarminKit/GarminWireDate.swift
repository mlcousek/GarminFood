// GarminWireDate.swift
//
// The ONE place a date becomes text for Garmin (a request path such as
// `/nutrition-service/food/logs/{yyyy-MM-dd}`, a write body's
// `mealDate`/`calendarDate`/`timestampLocal`/`logTimestamp`) or text from
// Garmin becomes a date again (fix-review-findings-2026-09-b, finding 1).
//
// Why it exists: a `DateFormatter` given the device's `Calendar.current`
// spells the year in THAT calendar. On a phone set to the Buddhist calendar
// "2026-09-30" came out as "2569-09-30", on the Japanese calendar as
// "0008-09-30" -- a request for a day that doesn't exist, a food logged in
// the wrong year, and Garmin's own timestamps read back 543 years off.
// Garmin's wire format is Gregorian, always: so every formatter here is
// Gregorian, `en_US_POSIX` (fixed digits, no locale-specific symbols) and
// has an explicit time zone.
//
// The time zone is the ONLY thing the caller chooses, and it keeps the
// existing local-day semantics unchanged: a nutrition day is the device's
// own local calendar day (FoodLogCore's `NutritionDate`, which passes its
// calendar's time zone here), a weigh-in's `dateTimestamp` is local wall
// clock and its `gmtTimestamp` UTC (GarminModels.swift). A caller's
// non-Gregorian calendar contributes its time zone and nothing else.
//
// Depends on: Foundation only. Depended on by: GarminModels (write
// bodies), WeightSync, Reconciliation, and FoodLogCore's NutritionDate /
// GarminHistoryImport / ActivityCache / LocalNutritionReader /
// FastingLogMoments (and through NutritionDate, Gamification's day keys).

import Foundation

public enum GarminWireDate {
    /// The POSIX locale every wire formatter uses.
    public static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// A Gregorian calendar in `timeZone` -- for day arithmetic and for
    /// building a day key's date from its numeric parts, whatever calendar
    /// the device is set to.
    public static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = posixLocale
        calendar.timeZone = timeZone
        return calendar
    }

    /// A fresh Gregorian/POSIX formatter for `format` in `timeZone`. Callers
    /// that format many dates in a loop may keep the one they get.
    public static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.calendar = calendar(timeZone: timeZone)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }

    // MARK: - Days (`yyyy-MM-dd`)

    public static let dayFormat = "yyyy-MM-dd"

    /// `2026-09-30`: the Gregorian day `date` falls on in `timeZone`.
    public static func dayString(from date: Date, timeZone: TimeZone) -> String {
        formatter(dayFormat, timeZone: timeZone).string(from: date)
    }

    /// Midnight (start of day in `timeZone`) of a `yyyy-MM-dd` day, or `nil`
    /// when it doesn't parse.
    public static func startOfDay(fromDayString string: String, timeZone: TimeZone) -> Date? {
        guard let parsed = formatter(dayFormat, timeZone: timeZone).date(from: string) else { return nil }
        return calendar(timeZone: timeZone).startOfDay(for: parsed)
    }

    /// Noon of a `yyyy-MM-dd` day in `timeZone` (noon, so no DST change can
    /// move it into a neighbouring day), or `nil` for a malformed key.
    /// Built from the key's numbers, so it is as lenient as the component
    /// parsers it replaces.
    public static func noon(ofDayString string: String, timeZone: TimeZone) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)
        return calendar(timeZone: timeZone).date(from: components)
    }

    // MARK: - Timestamps

    /// `2026-09-22T10:30:00.000`: wall clock in `timeZone`, no offset,
    /// milliseconds (python-garminconnect's `_fmt_ts`; GarminModels.swift).
    public static func localTimestampString(_ date: Date, timeZone: TimeZone) -> String {
        formatter("yyyy-MM-dd'T'HH:mm:ss.SSS", timeZone: timeZone).string(from: date)
    }

    /// Reads a zone-less Garmin timestamp (`2026-09-22T10:30:00.000`, or
    /// without the milliseconds) as wall clock in `timeZone`.
    public static func parseLocalTimestamp(_ raw: String, timeZone: TimeZone) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            if let date = formatter(format, timeZone: timeZone).date(from: raw) { return date }
        }
        return nil
    }

    /// `2026-09-16T13:35:49.324Z`, the shape `logTimestamp` reads back with.
    /// (`ISO8601DateFormatter` is Gregorian and GMT by definition; kept here
    /// so every wire date has one home.)
    public static func isoTimestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// `2026-09-16T13:35:49.324Z` with or without the fraction.
    public static func parseISOTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        return ISO8601DateFormatter().date(from: raw)
    }
}

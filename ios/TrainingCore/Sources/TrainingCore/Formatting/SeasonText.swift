// SeasonText.swift
//
// The extra pieces of text the Season, Phase and Race screens need
// (add-season-phase-race-screens, design D2), in English and Czech:
//
//   | What                 | English            | Czech              |
//   | a date with its year | 3 Nov 2030         | 3. 11. 2030        |
//   | a long range         | 14 Oct – 31 Jan 2031 | 14. 10. – 31. 1. 2031 |
//   | a timeline tick      | Oct / Jan 2031     | říj / led 2031     |
//   | a clock + minutes    | 10:05, 01:10 +1 d  | (the same)         |
//   | a pace               | 5:39 /km           | (the same)         |
//
// plus display names for the enumerations these screens add (phase kind
// and status, race priority, checkpoint aid). Like DateText, the order and
// punctuation are fixed here and only the month and weekday names come
// from Foundation's CLDR symbols, so a string reads the same whatever
// region the phone is set to.
//
// Depended on by: the season, phase and race builders. Tests:
// SeasonPhaseRaceTests.

import Foundation

public extension DateText {
    /// "3 Nov 2030" / "3. 11. 2030".
    func dayMonthYear(_ date: LocalDate) -> String {
        "\(dayMonth(date)) \(date.year)"
    }

    /// A range that may cross a year: "14 Oct – 31 Jan 2031",
    /// "2 Sep 2030 – 31 Aug 2031" when the years differ, the short range
    /// ("21–27 Oct") inside one month.
    func longRange(_ from: LocalDate, _ to: LocalDate) -> String {
        if from.year == to.year && from.month == to.month {
            return "\(range(from, to)) \(to.year)"
        }
        if from.year == to.year {
            return "\(dayMonth(from)) – \(dayMonthYear(to))"
        }
        return "\(dayMonthYear(from)) – \(dayMonthYear(to))"
    }

    /// A timeline tick: the short month, with the year in January.
    func monthTick(year: Int, month: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        let symbols = calendar.shortStandaloneMonthSymbols
        let name = (month >= 1 && month <= symbols.count) ? symbols[month - 1] : String(month)
        // January carries the year (not a plural: `month` is a month number).
        guard month != 1 else { return "\(name) \(year)" }
        return name
    }
}

public extension NumberText {
    /// A start time plus minutes, "10:05"; "01:10 +1 d" past midnight
    /// (the plugin's `clockAt`). `nil` when either is unknown.
    static func clock(_ start: ClockTime?, plus minutes: Int?) -> String? {
        guard let start, let minutes else { return nil }
        let total = start.hour * 60 + start.minute + minutes
        let days = total >= 0 ? total / 1440 : -((1439 - total) / 1440)
        let inDay = ((total % 1440) + 1440) % 1440
        let clock = String(format: "%02d:%02d", inDay / 60, inDay % 60)
        return days > 0 ? "\(clock) +\(days) d" : clock
    }

    /// Minutes per kilometre as "5:39 /km"; `nil` for a non-positive pace.
    static func pace(minutesPerKm: Double) -> String? {
        guard minutesPerKm.isFinite, minutesPerKm > 0 else { return nil }
        let seconds = Int((minutesPerKm * 60).rounded())
        return String(format: "%d:%02d /km", seconds / 60, seconds % 60)
    }

    /// "900 m+" (elevation gain; the unit is the same in both languages).
    static func climb(_ metres: Double, _ language: TrainingLanguage) -> String {
        "\(decimal(metres, language, maxFractionDigits: 0)) m+"
    }

    /// A whole percentage, "19 %" (a plain space in both languages).
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }
}

public extension TrainingText {
    func phaseKindName(_ kind: OpenEnum<PhaseKind>?) -> String? {
        switch kind?.known {
        case .base?: return self(.phaseKindBase)
        case .build?: return self(.kindBuild)
        case .specific?: return self(.phaseKindSpecific)
        case .taper?: return self(.kindTaper)
        case .transition?: return self(.kindTransition)
        case nil: return nil
        }
    }

    func phaseStatusName(_ status: OpenEnum<PhaseStatus>?) -> String? {
        switch status?.known {
        case .draft?: return self(.phaseDraft)
        case .active?: return self(.habitActive)
        case .closed?: return self(.weekClosed)
        case nil: return nil
        }
    }

    /// "A race", "B race", "C race"; `nil` for an unknown priority.
    func priorityName(_ priority: OpenEnum<RacePriority>?) -> String? {
        switch priority?.known {
        case .a?: return self(.racePriorityA)
        case .b?: return self(.racePriorityB)
        case .c?: return self(.racePriorityC)
        case nil: return nil
        }
    }

    func aidName(_ aid: OpenEnum<CheckpointAid>?) -> String? {
        switch aid?.known {
        case .full?: return self(.aidFull)
        case .water?: return self(.aidWater)
        case CheckpointAid.none?: return self(.aidNone)
        case nil: return nil
        }
    }
}

// DateText.swift
//
// Plan dates as the screens show them, in English and Czech:
//
//   | What            | English             | Czech               |
//   | a day           | Tue 20 Oct          | út 20. 10.          |
//   | day and month   | 20 Oct              | 20. 10.             |
//   | a day row       | Wed 23              | st 23.              |
//   | a week's range  | 21-27 Oct           | 21.-27. 10.         |
//   | across months   | 28 Oct - 3 Nov      | 28. 10. - 3. 11.    |
//   | a month title   | October 2030        | Říjen 2030          |
//
// Weekday and month names come from Foundation's CLDR symbols for the
// language's locale; the order and punctuation are fixed here, so a date
// reads the same whatever region the phone is set to. Weeks are Monday
// first in both languages (design D6). Nothing here makes a `Date`.
//
// Depended on by: the builders. Tests: FormattingTests.

import Foundation

public struct DateText: Sendable {
    public let language: TrainingLanguage

    public init(_ language: TrainingLanguage) {
        self.language = language
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        return calendar
    }

    /// Short weekday name, 1 = Monday ... 7 = Sunday.
    public func weekdayShort(_ isoWeekday: Int) -> String {
        let symbols = calendar.shortStandaloneWeekdaySymbols // Sunday first
        guard symbols.count == 7 else { return "" }
        return symbols[isoWeekday % 7]
    }

    /// Monday-first short weekday names for a calendar header.
    public var weekdayHeaders: [String] {
        (1...7).map(weekdayShort)
    }

    private func monthShort(_ month: Int) -> String {
        let symbols = calendar.shortMonthSymbols
        guard month >= 1, month <= symbols.count else { return String(month) }
        return symbols[month - 1]
    }

    /// "20 Oct" / "20. 10."
    public func dayMonth(_ date: LocalDate) -> String {
        switch language {
        case .english: return "\(date.day) \(monthShort(date.month))"
        case .czech: return "\(date.day). \(date.month)."
        }
    }

    /// "Tue 20 Oct" / "út 20. 10."
    public func short(_ date: LocalDate) -> String {
        "\(weekdayShort(date.isoWeekday)) \(dayMonth(date))"
    }

    /// "Wed 23" / "st 23."
    public func weekdayAndDay(_ date: LocalDate) -> String {
        switch language {
        case .english: return "\(weekdayShort(date.isoWeekday)) \(date.day)"
        case .czech: return "\(weekdayShort(date.isoWeekday)) \(date.day)."
        }
    }

    /// "21–27 Oct" / "28 Oct – 3 Nov" (Czech: "21.–27. 10.").
    public func range(_ from: LocalDate, _ to: LocalDate) -> String {
        let sameMonth = from.year == to.year && from.month == to.month
        switch language {
        case .english:
            return sameMonth ? "\(from.day)–\(dayMonth(to))" : "\(dayMonth(from)) – \(dayMonth(to))"
        case .czech:
            return sameMonth ? "\(from.day).–\(dayMonth(to))" : "\(dayMonth(from)) – \(dayMonth(to))"
        }
    }

    /// "October 2030" / "Říjen 2030".
    public func monthTitle(year: Int, month: Int) -> String {
        let symbols = calendar.standaloneMonthSymbols
        guard month >= 1, month <= symbols.count else { return "\(month)/\(year)" }
        let name = symbols[month - 1]
        let capitalized = name.prefix(1).uppercased(with: language.locale) + name.dropFirst()
        return "\(capitalized) \(year)"
    }

    /// A clock time as written ("05:10").
    public func clock(_ time: ClockTime) -> String {
        time.description
    }
}

// SecretRules.swift
//
// add-secret-achievements D2/D3: one PURE function per secret achievement,
// each a yes/no over the 42-day `SignalsSnapshot` (no store, no clock
// beyond `snapshot.today`, no network). `SecretAchievementsFeature` asks
// `holds(_:in:calendar:)` for every still-locked secret on every run, which
// is also what makes the first run retroactive over recent history.
//
// Conventions shared by the rules:
// - "logged date" is `DaySignals.day` (the date the entry was logged FOR);
// - a "completed day" is a logged date strictly before `snapshot.today`
//   (its totals can no longer grow), and a "completed week" is an ISO week
//   (`WeekKey`) strictly before today's -- rules that talk about completed
//   days/weeks never look at today / the current week (spec);
// - consecutive days and weekdays are computed from the `yyyy-MM-dd` keys
//   with plain Gregorian arithmetic (`SecretDayMath`), so no time zone or
//   DST edge can shift them; only the two rules that look at a clock time
//   (fridge raid, dawn patrol) use `calendar` for the hour.
//
// Depends on: FoodLogCore (SignalsSnapshot, DaySignals, FoodTag,
// NutritionDate), WeekKey, SecretAchievementId (SecretCatalog.swift).
// Depended on by: SecretAchievementsFeature, SecretRulesTests.

import Foundation
import FoodLogCore

public enum SecretRules {
    /// Every secret whose rule holds on `snapshot`.
    public static func satisfied(in snapshot: SignalsSnapshot, calendar: Calendar) -> Set<SecretAchievementId> {
        Set(SecretAchievementId.allCases.filter { holds($0, in: snapshot, calendar: calendar) })
    }

    public static func holds(_ id: SecretAchievementId, in snapshot: SignalsSnapshot, calendar: Calendar) -> Bool {
        switch id {
        case .fridgeRaid: return fridgeRaid(snapshot, calendar: calendar)
        case .barista: return barista(snapshot)
        case .pizzaFriday: return pizzaFriday(snapshot)
        case .bullseye: return bullseye(snapshot)
        case .palindrome: return palindrome(snapshot)
        case .groundhogBreakfast: return groundhogBreakfast(snapshot)
        case .friday13: return friday13(snapshot)
        case .worldTour: return worldTour(snapshot, calendar: calendar)
        case .piDay: return piDay(snapshot)
        case .dejaVu: return dejaVu(snapshot)
        case .knedlikMarathon: return threeDaysInARow(of: .knedlik, in: snapshot)
        case .goneFishing: return threeDaysInARow(of: .fish, in: snapshot)
        case .vodnik: return vodnik(snapshot)
        case .dawnPatrol: return dawnPatrol(snapshot, calendar: calendar)
        case .answer42: return answer42(snapshot, calendar: calendar)
        }
    }

    // MARK: - Rules

    /// An entry timestamped 00:00-03:59 whose logged date is that same
    /// calendar date (backfilling yesterday at 1 a.m. does not count).
    static func fridgeRaid(_ snapshot: SignalsSnapshot, calendar: Calendar) -> Bool {
        snapshot.days.values.contains { day in
            day.entries.contains { entry in
                calendar.component(.hour, from: entry.timestamp) < 4
                    && NutritionDate.string(from: entry.timestamp, calendar: calendar) == day.day
            }
        }
    }

    /// At least 5 coffee entries on one logged date.
    static func barista(_ snapshot: SignalsSnapshot) -> Bool {
        snapshot.days.values.contains { $0.entries(tagged: .coffee).count >= 5 }
    }

    /// A pizza entry on 4 consecutive Fridays.
    static func pizzaFriday(_ snapshot: SignalsSnapshot) -> Bool {
        let fridays = Set(snapshot.days.values.compactMap { day -> Int? in
            guard !day.entries(tagged: .pizza).isEmpty,
                  let number = SecretDayMath.dayNumber(day.day),
                  SecretDayMath.weekday(dayNumber: number) == SecretDayMath.friday
            else { return nil }
            return number
        })
        return fridays.contains { first in
            (1...3).allSatisfy { fridays.contains(first + 7 * $0) }
        }
    }

    /// A completed day with a calorie goal and at least 3 entries whose
    /// rounded total equals the rounded goal.
    static func bullseye(_ snapshot: SignalsSnapshot) -> Bool {
        snapshot.days.values.contains { day in
            guard isCompleted(day, in: snapshot),
                  day.entries.count >= 3,
                  let total = day.totals.calories, total.isFinite,
                  let goal = day.goals?.calories, goal.isFinite, goal > 0
            else { return false }
            return total.rounded() == goal.rounded()
        }
    }

    /// A completed day with at least 3 entries whose rounded calorie total
    /// is at least 1000 and reads the same backwards.
    static func palindrome(_ snapshot: SignalsSnapshot) -> Bool {
        snapshot.days.values.contains { day in
            guard isCompleted(day, in: snapshot),
                  day.entries.count >= 3,
                  let total = day.totals.calories, total.isFinite, total < 1_000_000_000
            else { return false }
            return isPalindrome(Int(total.rounded()))
        }
    }

    /// One food id among breakfast entries on at least 30 of 35
    /// consecutive days.
    static func groundhogBreakfast(_ snapshot: SignalsSnapshot) -> Bool {
        var daysByFood: [String: Set<Int>] = [:]
        for day in snapshot.days.values {
            guard let number = SecretDayMath.dayNumber(day.day) else { continue }
            for entry in day.entries(in: .breakfast) {
                daysByFood[entry.foodId, default: []].insert(number)
            }
        }
        return daysByFood.values.contains { days in
            guard days.count >= 30 else { return false }
            // The best 35-day span can always start on a day that has it.
            return days.contains { start in
                days.filter { $0 >= start && $0 < start + 35 }.count >= 30
            }
        }
    }

    /// Any entry on a logged date that is a Friday the 13th.
    static func friday13(_ snapshot: SignalsSnapshot) -> Bool {
        snapshot.days.values.contains { day in
            guard day.hasEntries,
                  let parts = SecretDayMath.components(day.day), parts.day == 13,
                  let number = SecretDayMath.dayNumber(day.day)
            else { return false }
            return SecretDayMath.weekday(dayNumber: number) == SecretDayMath.friday
        }
    }

    /// At least 7 distinct `cuisine.*` tags within one ISO week.
    static func worldTour(_ snapshot: SignalsSnapshot, calendar: Calendar) -> Bool {
        var cuisinesByWeek: [WeekKey: Set<FoodTag>] = [:]
        for day in snapshot.days.values {
            guard let week = WeekKey(dayKey: day.day, calendar: calendar) else { continue }
            let cuisines = day.allTags.filter { $0.hasPrefix(FoodTag.cuisinePrefix) }
            guard !cuisines.isEmpty else { continue }
            cuisinesByWeek[week, default: []].formUnion(cuisines)
        }
        return cuisinesByWeek.values.contains { $0.count >= 7 }
    }

    /// A `pie` entry (koláč, štrúdl, pie, tart) on 14 March.
    static func piDay(_ snapshot: SignalsSnapshot) -> Bool {
        snapshot.days.values.contains { day in
            guard let parts = SecretDayMath.components(day.day), parts.month == 3, parts.day == 14 else { return false }
            return !day.entries(tagged: .pie).isEmpty
        }
    }

    /// Two consecutive completed days with identical sets of food ids, each
    /// with at least 3 distinct foods.
    static func dejaVu(_ snapshot: SignalsSnapshot) -> Bool {
        let byNumber = daysByNumber(snapshot)
        return byNumber.contains { number, day in
            guard isCompleted(day, in: snapshot),
                  let next = byNumber[number + 1], isCompleted(next, in: snapshot)
            else { return false }
            let foods = Set(day.entries.map(\.foodId))
            return foods.count >= 3 && foods == Set(next.entries.map(\.foodId))
        }
    }

    /// An entry tagged `tag` on 3 consecutive logged dates.
    static func threeDaysInARow(of tag: FoodTag, in snapshot: SignalsSnapshot) -> Bool {
        let days = Set(snapshot.days.values.compactMap { day -> Int? in
            day.entries(tagged: tag).isEmpty ? nil : SecretDayMath.dayNumber(day.day)
        })
        return days.contains { days.contains($0 + 1) && days.contains($0 + 2) }
    }

    /// Water at least 150 % of the water goal on one day. No water data
    /// (or no goal) never counts.
    static func vodnik(_ snapshot: SignalsSnapshot) -> Bool {
        snapshot.days.values.contains { day in
            guard let water = day.waterML, let goal = day.waterGoalML, goal > 0 else { return false }
            return water >= goal * 1.5
        }
    }

    /// A Garmin activity starting before 06:00 local and an entry within
    /// 60 minutes after it ends, on the same logged date.
    static func dawnPatrol(_ snapshot: SignalsSnapshot, calendar: Calendar) -> Bool {
        snapshot.days.values.contains { day in
            day.activities.contains { activity in
                guard activity.day == day.day,
                      calendar.component(.hour, from: activity.start) < 6
                else { return false }
                let end = activity.end
                let limit = end.addingTimeInterval(60 * 60)
                return day.entries.contains { $0.timestamp >= end && $0.timestamp <= limit }
            }
        }
    }

    /// Exactly 42 entries in one completed ISO week that lies entirely
    /// inside the snapshot window (a week cut off by the window's start
    /// could under-count).
    static func answer42(_ snapshot: SignalsSnapshot, calendar: Calendar) -> Bool {
        guard let current = WeekKey(dayKey: snapshot.today, calendar: calendar),
              let windowStart = snapshot.windowDays.first
        else { return false }
        var entriesByWeek: [WeekKey: Int] = [:]
        for day in snapshot.days.values {
            guard let week = WeekKey(dayKey: day.day, calendar: calendar), week < current else { continue }
            entriesByWeek[week, default: 0] += day.entries.count
        }
        return entriesByWeek.contains { week, count in
            guard count == 42, let monday = week.dayKeys(calendar: calendar).first else { return false }
            return monday >= windowStart
        }
    }

    // MARK: - Helpers

    static func isCompleted(_ day: DaySignals, in snapshot: SignalsSnapshot) -> Bool {
        !snapshot.today.isEmpty && day.day < snapshot.today
    }

    static func isPalindrome(_ value: Int) -> Bool {
        guard value >= 1000 else { return false }
        let digits = String(value)
        return digits == String(digits.reversed())
    }

    static func daysByNumber(_ snapshot: SignalsSnapshot) -> [Int: DaySignals] {
        var result: [Int: DaySignals] = [:]
        for day in snapshot.days.values {
            if let number = SecretDayMath.dayNumber(day.day) {
                result[number] = day
            }
        }
        return result
    }
}

/// Calendar arithmetic on `yyyy-MM-dd` keys (proleptic Gregorian), free of
/// time zones: day numbers for "consecutive", weekday for "Friday".
enum SecretDayMath {
    /// `weekday(dayNumber:)` value of a Friday (0 = Sunday ... 6 = Saturday).
    static let friday = 5

    static func components(_ key: String) -> (year: Int, month: Int, day: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month),
              (1...31).contains(day)
        else { return nil }
        return (year: year, month: month, day: day)
    }

    /// Days since 1970-01-01 (H. Hinnant's `days_from_civil`).
    static func dayNumber(_ key: String) -> Int? {
        guard let parts = components(key) else { return nil }
        let year = parts.month <= 2 ? parts.year - 1 : parts.year
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let shiftedMonth = (parts.month + 9) % 12 // March = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + parts.day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 0 = Sunday ... 6 = Saturday (1970-01-01 was a Thursday).
    static func weekday(dayNumber: Int) -> Int {
        let remainder = (dayNumber + 4) % 7
        return remainder < 0 ? remainder + 7 : remainder
    }
}

// SportRules.swift
//
// add-sport-and-body-achievements design D2 (activity and race rows): the
// pure rules linking food entries to cached Garmin activities and race days.
// Everything here is a function of one `SignalsSnapshot` (no store, no
// clock beyond what the caller passes), so every edge in design D7 is a
// plain unit test (SportRulesTests).
//
// Entry <-> activity linking is by INSTANT, across nutrition-day borders: a
// 06:00 porridge fuels a 07:30 run even when they fall on different
// `DaySignals` (a run just after midnight, a 04:00 day boundary), so
// `allEntries(in:)` flattens the whole window first. Windows:
//   - fuel: logged 30...180 min before the start (both ends inclusive);
//   - recovery: logged 0...60 min after the end, protein summed over the
//     entries whose protein is known (unknown protein is ignored);
//   - during: strictly after the start and strictly before the end.
//
// Entries carry the time they were LOGGED, not eaten (the app has no "ate
// at" field) -- the windows are generous for that reason (design Risks).
//
// Depends on: FoodLogCore (SignalsSnapshot, DaySignals, SignalEntry,
// ActivitySummary, FoodTag+Sport, NutritionDate), SportActivityClass.
// Depended on by: SportAndBodyFeature.

import Foundation
import FoodLogCore

/// One counted activity and the entries that made it count.
public struct SportActivityEvaluation: Sendable, Equatable, Identifiable {
    public let activity: ActivitySummary
    public let activityClass: SportActivityClass
    /// Qualifying pre-start entries (>= 30 g carbs, or carbs unknown and
    /// carb-rich), oldest first. Empty for a non-endurance activity.
    public let fuelEntries: [SignalEntry]
    /// Entries with a KNOWN protein value logged within 60 min after the end.
    public let recoveryEntries: [SignalEntry]
    public let recoveryProteinGrams: Double
    /// Entries logged strictly inside the activity.
    public let duringEntries: [SignalEntry]

    public var id: String { activity.id }

    public var isFuelled: Bool { activityClass == .endurance && !fuelEntries.isEmpty }

    public var isRecovered: Bool {
        activityClass.countsForRecovery && recoveryProteinGrams >= SportRules.recoveryProteinGrams - SportRules.epsilon
    }

    public var isGelGuru: Bool {
        activityClass == .endurance
            && activity.durationMinutes >= SportRules.gelGuruMinimumMinutes
            && duringEntries.count >= SportRules.gelGuruMinimumEntries
    }

    public var isLongHaul: Bool {
        activityClass == .endurance
            && activity.durationMinutes >= SportRules.longHaulMinimumMinutes
            && !duringEntries.isEmpty
    }

    /// The fuel entry to show in a moment: the one with the most known
    /// carbs, else the latest carb-rich one.
    public var headlineFuelEntry: SignalEntry? {
        fuelEntries.max { lhs, rhs in
            (lhs.carbs ?? -1, lhs.timestamp) < (rhs.carbs ?? -1, rhs.timestamp)
        }
    }
}

public enum SportRules {
    static let epsilon = 1e-9

    // MARK: Thresholds (design D2)

    public static let fuelMinimumCarbGrams: Double = 30
    public static let fuelWindowEarliestMinutes: Double = 180
    public static let fuelWindowLatestMinutes: Double = 30
    public static let recoveryWindowMinutes: Double = 60
    public static let recoveryProteinGrams: Double = 20
    public static let earnedMinimumActiveKcal: Double = 400
    public static let earnedMinimumEntries = 3
    public static let earnedFloorFraction: Double = 0.8
    public static let earnedActiveAllowance: Double = 0.5
    public static let gelGuruMinimumMinutes: Double = 90
    public static let gelGuruMinimumEntries = 3
    public static let longHaulMinimumMinutes: Double = 180

    // MARK: Snapshot helpers

    /// Every entry in the window, oldest first.
    public static func allEntries(in snapshot: SignalsSnapshot) -> [SignalEntry] {
        snapshot.orderedDays.flatMap(\.entries).sorted { $0.timestamp < $1.timestamp }
    }

    /// Every cached activity in the window, de-duplicated by id, oldest
    /// first.
    public static func activities(in snapshot: SignalsSnapshot) -> [ActivitySummary] {
        var seen = Set<String>()
        var result: [ActivitySummary] = []
        for day in snapshot.orderedDays {
            for activity in day.activities where seen.insert(activity.id).inserted {
                result.append(activity)
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Whether ANY day of the window had its Garmin activities read
    /// (possibly zero of them). `false` = the activities route never
    /// answered (standalone mode, route broken): activity badges simply do
    /// not progress, and nothing is shown as failed.
    public static func activitiesAvailable(in snapshot: SignalsSnapshot) -> Bool {
        snapshot.orderedDays.contains { $0.availability.hasActivities || !$0.activities.isEmpty }
    }

    // MARK: Activities

    /// `nil` for an activity that does not count (design D1).
    public static func evaluate(_ activity: ActivitySummary, entries: [SignalEntry]) -> SportActivityEvaluation? {
        let activityClass = SportActivityClass.classify(activity)
        guard activityClass != .other else { return nil }

        let fuel = activityClass == .endurance
            ? entries.filter { isFuelEntry($0, before: activity.start) }
            : []
        let recovery = entries.filter { entry in
            guard entry.protein != nil else { return false }
            let after = entry.timestamp.timeIntervalSince(activity.end)
            return after >= 0 && after <= recoveryWindowMinutes * 60
        }
        let protein = recovery.reduce(0) { $0 + ($1.protein ?? 0) }
        let during = entries.filter { $0.timestamp > activity.start && $0.timestamp < activity.end }

        return SportActivityEvaluation(
            activity: activity,
            activityClass: activityClass,
            fuelEntries: fuel,
            recoveryEntries: recovery,
            recoveryProteinGrams: protein,
            duringEntries: during
        )
    }

    /// Every counted activity of the window, oldest first.
    public static func evaluations(in snapshot: SignalsSnapshot) -> [SportActivityEvaluation] {
        let entries = allEntries(in: snapshot)
        return activities(in: snapshot).compactMap { evaluate($0, entries: entries) }
    }

    /// >= 30 g carbs (or carbs unknown and tagged carb-rich), logged 30...180
    /// minutes before `start`.
    public static func isFuelEntry(_ entry: SignalEntry, before start: Date) -> Bool {
        let lead = start.timeIntervalSince(entry.timestamp)
        guard lead >= fuelWindowLatestMinutes * 60, lead <= fuelWindowEarliestMinutes * 60 else { return false }
        if let carbs = entry.carbs {
            return carbs >= fuelMinimumCarbGrams - epsilon
        }
        return entry.has(.sportCarbRich)
    }

    // MARK: Days

    /// Earned It: a COMPLETED day (before `today`) with >= 400 active kcal,
    /// >= 3 entries and a calorie goal, eaten within
    /// [0.8 x goal, goal + 0.5 x active kcal].
    public static func isEarnedDay(_ day: DaySignals, today: String) -> Bool {
        guard day.day < today,
              let active = day.activeKcal, active >= earnedMinimumActiveKcal - epsilon,
              day.entries.count >= earnedMinimumEntries,
              let goal = day.goals?.calories, goal > 0,
              let intake = day.totals.calories
        else { return false }
        return intake >= earnedFloorFraction * goal - epsilon
            && intake <= goal + earnedActiveAllowance * active + epsilon
    }

    /// Double Day: two counted (endurance) activities on one day and the
    /// protein goal met that day.
    public static func isDoubleDay(_ day: DaySignals) -> Bool {
        let counted = day.activities.filter { SportActivityClass.classify($0) == .endurance }
        return counted.count >= 2 && day.goalStatus?.metProteinGoal == true
    }

    /// Race Day Fuel: a day (up to today) tagged `race` in the day note --
    /// the ONLY source of race days -- with at least one entry.
    public static func isRaceDay(_ day: DaySignals, today: String) -> Bool {
        day.day <= today && day.noteTags.contains(.race) && !day.entries.isEmpty
    }

    /// The carb goal is known and met. A day whose cached goals lack a carb
    /// goal never counts (design D7 "missing carb goal").
    public static func metCarbGoal(_ day: DaySignals) -> Bool {
        if let goals = day.goals, goals.carbs == nil { return false }
        return day.goalStatus?.metCarbGoal == true
    }

    /// Race days (up to today) whose two preceding days both met the carb
    /// goal -- Carb Loader.
    public static func carbLoadedRaceDays(in snapshot: SignalsSnapshot, calendar: Calendar) -> [String] {
        snapshot.orderedDays.compactMap { day -> String? in
            guard day.day <= snapshot.today, day.noteTags.contains(.race),
                  let dayBefore = dayKey(day.day, offsetBy: -1, calendar: calendar),
                  let twoBefore = dayKey(day.day, offsetBy: -2, calendar: calendar),
                  let first = snapshot.days[twoBefore], let second = snapshot.days[dayBefore],
                  metCarbGoal(first), metCarbGoal(second)
            else { return nil }
            return day.day
        }
    }

    /// `key` moved by `days` calendar days (`nil` for a malformed key).
    static func dayKey(_ key: String, offsetBy days: Int, calendar: Calendar) -> String? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let noon = calendar.date(from: components),
              let moved = calendar.date(byAdding: .day, value: days, to: noon)
        else { return nil }
        return NutritionDate.string(from: moved, calendar: calendar)
    }
}

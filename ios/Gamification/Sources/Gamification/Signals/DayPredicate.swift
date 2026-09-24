// DayPredicate.swift
//
// ONE shared rule vocabulary (design D6) for "a day satisfies X": bingo
// squares, weekly bosses and the creative long-running challenges all
// describe their rules with these cases instead of three separate rule
// languages. A predicate is plain data (Codable, Equatable) so a feature can
// persist the rule it offered; `SignalEvaluator` is the only code that
// interprets it, over FoodLogCore's `DaySignals`.
//
// `requirement` names the data sources a rule needs. Features check it
// BEFORE offering a rule (a water square is never offered to someone with
// no water data), and evaluation of a day whose data is missing is
// "unknown", never "failed".
//
// Wave-2 changes must NOT add cases here (design "Wave plan"): a missing
// rule is written as a feature-local function over `DaySignals`.
//
// Depends on: FoodLogCore (FoodTag, SignalMeal, DaySignals), GoalMacro.
// Depended on by: WeekPredicate, SignalEvaluator, ChallengeKind.signalDays,
// ChallengeRotationPolicy, every wave-2 feature.

import Foundation
import FoodLogCore

/// A macro value on `MacroTotals` a rule can threshold.
public enum SignalMacro: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case calories, protein, carbs, fat, fiber, sugar

    public func value(in totals: MacroTotals) -> Double? {
        switch self {
        case .calories: return totals.calories
        case .protein: return totals.protein
        case .carbs: return totals.carbs
        case .fat: return totals.fat
        case .fiber: return totals.fiber
        case .sugar: return totals.sugar
        }
    }

    public func value(in entry: SignalEntry) -> Double? {
        switch self {
        case .calories: return entry.calories
        case .protein: return entry.protein
        case .carbs: return entry.carbs
        case .fat: return entry.fat
        case .fiber: return entry.fiber
        case .sugar: return entry.sugar
        }
    }
}

/// The data sources a rule needs. `[]` = only logged entries.
public struct DataRequirement: OptionSet, Sendable, Hashable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Macro values (calories/protein/carbs/fat, or the goal status).
    public static let macros = DataRequirement(rawValue: 1 << 0)
    public static let water = DataRequirement(rawValue: 1 << 1)
    public static let activities = DataRequirement(rawValue: 1 << 2)
    public static let weight = DataRequirement(rawValue: 1 << 3)

    /// Whether `day` has every source this requirement names.
    public func isSatisfied(by day: DaySignals) -> Bool {
        if contains(.macros) && !(day.availability.hasMacros || day.availability.hasGarminLog || day.goalStatus != nil) {
            return false
        }
        if contains(.water) && !day.availability.hasWater { return false }
        if contains(.activities) && !day.availability.hasActivities { return false }
        if contains(.weight) && !day.availability.hasWeight { return false }
        return true
    }

    /// Whether ANY of `days` has every source this requirement names (the
    /// eligibility check: "met by at least one of the last 14 days").
    /// An empty requirement is always satisfied, even with no days.
    public func isSatisfied(byAnyOf days: [DaySignals]) -> Bool {
        if isEmpty { return true }
        return days.contains { isSatisfied(by: $0) }
    }
}

public indirect enum DayPredicate: Sendable, Equatable, Codable {
    /// Any entry carries the tag.
    case hasTag(FoodTag)
    /// At least `n` entries carry the tag.
    case tagCountAtLeast(FoodTag, Int)
    /// At least `n` entries carry ANY of the tags (an entry counts once).
    case anyTagCountAtLeast([FoodTag], Int)
    /// At least `n` distinct tags starting with `prefix` ("colour.", 5).
    case distinctTagsAtLeast(prefix: String, Int)
    /// At least `minEntries` entries were logged and none carries the tag.
    /// Fewer entries = the day is not considered (unknown).
    case noTag(FoodTag, minEntries: Int)
    /// An entry in `meal` carries the tag.
    case tagInMeal(FoodTag, SignalMeal)
    case mealLogged(SignalMeal)
    /// The day's first entry was logged before hour:minute of that day.
    case firstLogBefore(hour: Int, minute: Int)
    /// The day's last entry was logged before hour:minute of that day.
    case lastLogBefore(hour: Int, minute: Int)
    case distinctFoodsAtLeast(Int)
    /// The day's Garmin goal for the macro was met (cached goal status).
    case goalMet(GoalMacro)
    case macroAtLeast(SignalMacro, grams: Double)
    /// Total ≤ grams on a day with at least `minEntries` entries.
    case macroAtMost(SignalMacro, grams: Double, minEntries: Int)
    case waterGoalMet
    /// An activity of at least `minMinutes`.
    case hasActivity(minMinutes: Int)
    /// ≥ grams of protein logged within `withinMinutes` after an activity ended.
    case proteinAfterActivity(grams: Double, withinMinutes: Int)
    /// A food first seen (in the retained history) on this day.
    case newFood
    /// A Czech-brand entry whose brand was first seen on this day.
    case newCzechBrand
    case all([DayPredicate])
    case any([DayPredicate])

    public var requirement: DataRequirement {
        switch self {
        case .hasTag, .tagCountAtLeast, .anyTagCountAtLeast, .distinctTagsAtLeast, .noTag,
             .tagInMeal, .mealLogged, .firstLogBefore, .lastLogBefore, .distinctFoodsAtLeast,
             .newFood, .newCzechBrand:
            return []
        case .goalMet, .macroAtLeast, .macroAtMost:
            return .macros
        case .waterGoalMet:
            return .water
        case .hasActivity:
            return .activities
        case .proteinAfterActivity:
            return [.activities, .macros]
        case .all(let predicates), .any(let predicates):
            return predicates.reduce(into: DataRequirement()) { $0.formUnion($1.requirement) }
        }
    }
}

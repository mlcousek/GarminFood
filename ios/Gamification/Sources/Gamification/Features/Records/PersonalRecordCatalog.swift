// PersonalRecordCatalog.swift
//
// add-journeys-and-records design D6: the eight personal records, Garmin
// style -- what each one measures per day, which direction is "better", when
// it is judged (live during the day, or only once the day is closed) and
// the smallest step that counts as a strict improvement. The per-day metric
// functions live here as pure functions of one `DaySignals`; the two
// sequence metrics (water-goal streak, longest fast) need neighbouring days
// and live in `RecordsEvaluator`.
//
// Improvement steps (design D6 "strictly"): protein by >= 1 g, water by
// >= 50 ml, kcal by >= 1; counts and streak days by >= 1; the fast by one
// minute; sugar by 0.1 g. A value of 0 never becomes a "higher" record (a
// day with no fruit is not a record), but still counts as a qualifying day.
//
// Names are localized (Gamification .lproj) and computed on access; the
// store keeps only ids.
//
// Depends on: DataRequirement, AchievementDefinition, FoodLogCore
// (DaySignals, FoodTag).
// Depended on by: RecordsEvaluator, PersonalRecordsFeature, the app's
// Records UI.

import Foundation
import FoodLogCore

public enum PersonalRecordId: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case proteinDay = "protein-day"
    case fruitVegDay = "fruit-veg-day"
    case distinctFoodsDay = "distinct-foods-day"
    case waterDay = "water-day"
    case activeKcalDay = "active-kcal-day"
    case waterStreak = "water-streak"
    case longestFast = "longest-fast"
    case lowSugarOnTarget = "low-sugar-on-target"
}

public enum PersonalRecordDirection: String, Sendable, Equatable {
    case higher, lower
}

public enum PersonalRecordTiming: String, Sendable, Equatable {
    /// Compared during the day (today's running value).
    case live
    /// Judged only once the day is over (design D6: a fast or a low-sugar
    /// day is only known then).
    case closedDay
}

public enum PersonalRecordUnit: String, Sendable, Equatable {
    case grams, count, millilitres, kilocalories, days, hours
}

public struct PersonalRecordDefinition: Sendable, Equatable, Identifiable {
    public let id: PersonalRecordId
    public let name: String
    /// An SF Symbol name.
    public let symbol: String
    public let unit: PersonalRecordUnit
    public let direction: PersonalRecordDirection
    public let timing: PersonalRecordTiming
    /// The smallest change that counts as a strict improvement.
    public let minImprovement: Double
    /// The data source the record needs (documentation + eligibility).
    public let requirement: DataRequirement

    /// Whether `value` strictly beats `current` (`nil` = no record yet).
    public func isImprovement(_ value: Double, over current: Double?) -> Bool {
        guard let current else {
            switch direction {
            case .higher: return value > 0
            case .lower: return value >= 0
            }
        }
        switch direction {
        case .higher: return value >= current + minImprovement
        case .lower: return value <= current - minImprovement
        }
    }
}

public enum PersonalRecordCatalog {
    /// Design D6: a record announces PRs only once it has this many days of
    /// qualifying data.
    public static let warmUpDays = 7
    /// Design D6: gaps longer than this are unlogged days, not a fast.
    public static let maxFastGapHours = 48.0
    /// Design D6: calories within this fraction of the goal = "on target".
    public static let onTargetTolerance = 0.10
    /// Design D6: an on-target day needs at least this many entries.
    public static let onTargetMinEntries = 3
    /// `record.full-house` needs at least this many records with a value
    /// (so one lonely record can't make a "full house").
    public static let fullHouseMinRecords = 6
    /// History list length (design D6).
    public static let historyLimit = 10

    public static var all: [PersonalRecordDefinition] {
        PersonalRecordId.allCases.map(definition)
    }

    public static func definition(_ id: PersonalRecordId) -> PersonalRecordDefinition {
        switch id {
        case .proteinDay:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Most protein in a day", bundle: .module, comment: "Personal record name."),
                symbol: "fork.knife",
                unit: .grams, direction: .higher, timing: .live, minImprovement: 1, requirement: .macros
            )
        case .fruitVegDay:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Most fruit & veg in a day", bundle: .module, comment: "Personal record name: entries tagged fruit or vegetable."),
                symbol: "carrot.fill",
                unit: .count, direction: .higher, timing: .live, minImprovement: 1, requirement: []
            )
        case .distinctFoodsDay:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Most different foods in a day", bundle: .module, comment: "Personal record name."),
                symbol: "square.grid.3x3.fill",
                unit: .count, direction: .higher, timing: .live, minImprovement: 1, requirement: []
            )
        case .waterDay:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Most water in a day", bundle: .module, comment: "Personal record name."),
                symbol: "drop.fill",
                unit: .millilitres, direction: .higher, timing: .live, minImprovement: 50, requirement: .water
            )
        case .activeKcalDay:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Biggest active day", bundle: .module, comment: "Personal record name: most active kilocalories in a day."),
                symbol: "flame.fill",
                unit: .kilocalories, direction: .higher, timing: .live, minImprovement: 1, requirement: .activities
            )
        case .waterStreak:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Longest water-goal streak", bundle: .module, comment: "Personal record name: consecutive days the water goal was met."),
                symbol: "drop.circle.fill",
                unit: .days, direction: .higher, timing: .live, minImprovement: 1, requirement: .water
            )
        case .longestFast:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Longest fast", bundle: .module, comment: "Personal record name: most hours between two logged entries."),
                symbol: "moon.stars.fill",
                unit: .hours, direction: .higher, timing: .closedDay, minImprovement: 1.0 / 60.0, requirement: []
            )
        case .lowSugarOnTarget:
            return PersonalRecordDefinition(
                id: id,
                name: String(localized: "Lowest sugar on an on-target day", bundle: .module, comment: "Personal record name: least sugar on a day whose calories hit the goal."),
                symbol: "cube.fill",
                unit: .grams, direction: .lower, timing: .closedDay, minImprovement: 0.1, requirement: .macros
            )
        }
    }

    // MARK: - Per-day metrics (nil = the day doesn't qualify)

    public static func proteinGrams(_ day: DaySignals) -> Double? {
        guard day.hasEntries || day.availability.hasGarminLog else { return nil }
        return day.totals.protein
    }

    /// Entries tagged fruit or vegetable (an entry counts once).
    public static func fruitVegEntries(_ day: DaySignals) -> Double? {
        guard day.hasEntries else { return nil }
        return Double(day.entries.filter { $0.has(.fruit) || $0.has(.vegetable) }.count)
    }

    public static func distinctFoods(_ day: DaySignals) -> Double? {
        guard day.hasEntries else { return nil }
        return Double(Set(day.entries.map(\.foodId).filter { !$0.isEmpty }).count)
    }

    public static func waterML(_ day: DaySignals) -> Double? {
        day.waterML
    }

    public static func activeKcal(_ day: DaySignals) -> Double? {
        day.activeKcal
    }

    /// Sugar grams of an on-target day: calories within ±10 % of the goal
    /// and at least 3 entries; `nil` for any other day.
    public static func onTargetSugarGrams(_ day: DaySignals) -> Double? {
        guard day.entries.count >= onTargetMinEntries,
              let goal = day.goals?.calories, goal > 0,
              let calories = day.totals.calories,
              abs(calories - goal) <= goal * onTargetTolerance,
              let sugar = day.totals.sugar
        else { return nil }
        return sugar
    }

    /// Whether the day's water met its goal; `nil` when either is unknown.
    public static func metWaterGoal(_ day: DaySignals) -> Bool? {
        guard let water = day.waterML, let goal = day.waterGoalML, goal > 0 else { return nil }
        return water >= goal
    }

    // MARK: - Badges (design D6)

    public static var badges: [AchievementDefinition] {
        func badge(_ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ rarity: AchievementRarity) -> AchievementDefinition {
            AchievementDefinition(
                id: id,
                title: title,
                subtitle: subtitle,
                category: .extreme,
                badgeSymbol: symbol,
                condition: .featureEvaluated,
                rarityOverride: rarity,
                featureId: PersonalRecordsFeature.id
            )
        }
        return [
            badge("record.first-pr", String(localized: "First PR", bundle: .module, comment: "Badge title: first personal record set."),
                  String(localized: "Set your first personal record.", bundle: .module, comment: "Badge subtitle."), "trophy", .common),
            badge("record.pr-10", String(localized: "Record Breaker", bundle: .module, comment: "Badge title: 10 personal records set."),
                  String(localized: "Set 10 personal records.", bundle: .module, comment: "Badge subtitle."), "trophy.fill", .uncommon),
            badge("record.pr-50", String(localized: "Record Machine", bundle: .module, comment: "Badge title: 50 personal records set."),
                  String(localized: "Set 50 personal records.", bundle: .module, comment: "Badge subtitle."), "trophy.circle.fill", .epic),
            badge("record.full-house", String(localized: "Full House", bundle: .module, comment: "Badge title: a PR in every tracked record."),
                  String(localized: "Set a PR in every record you track.", bundle: .module, comment: "Badge subtitle."), "rosette", .rare),
        ]
    }
}

/// Value formatting shared by the records' moments and the app's screens.
public enum PersonalRecordFormat {
    /// "186 g", "7", "3.2 L", "812 kcal", "12 d", "16.5 h".
    public static func value(_ value: Double, unit: PersonalRecordUnit) -> String {
        func number(_ v: Double, digits: Int) -> String {
            v.formatted(.number.precision(.fractionLength(0...digits)))
        }
        switch unit {
        case .grams: return "\(number(value, digits: value < 10 ? 1 : 0)) g"
        case .count: return number(value, digits: 0)
        case .millilitres: return "\(number(value / 1000, digits: 1)) L"
        case .kilocalories: return "\(number(value, digits: 0)) kcal"
        case .days: return "\(number(value, digits: 0)) d"
        case .hours: return "\(number(value, digits: 1)) h"
        }
    }
}

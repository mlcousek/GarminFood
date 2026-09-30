// FuelDay.swift
//
// add-winter-arc-nutrition-and-rewards (A1): in the training experience the
// food target follows the training day. The plan (TrainingCore's
// `DayFuelTargets`, copied into `FuelDayTarget` by the app -- FoodLogCore
// never imports TrainingCore) says how many grams of carbohydrate the day
// wants (the vault's PM-FUEL-1 g/kg band x weight) and about how much
// protein. This file is the pure judgement over that:
//
//   - `FuelDaySummary`: what the Today summary leads with -- carbs against
//     the band (below / in / above), protein against its target -- and
//     whether to show the gentle under-fuelling note: only on TODAY, from
//     `underFuellingHour` (18:00) on, when carbs are under
//     `underFuellingFraction` (75 %) of the band's lower edge. Never a
//     warning colour; never on a past day (nothing can be done about it).
//   - `displayBand(_:target:)`: the calorie ring's colour step with "over"
//     softened -- on a day with training sessions or a carb band, eating
//     past the calorie target is never shown orange or red (it becomes the
//     neutral ring). Without a target the ring is exactly as before.
//   - `judge(content:goals:target:)`: goal status for gamification that
//     never punishes eating inside the band (GoalStatusEvaluator's
//     training-experience path): with a band, calories AND carbs are met
//     once carbs reach the band's lower edge (above the band is not a
//     miss); on a training day without a band, calories are met from 95 %
//     of the target up with no upper limit; protein is met from 90 % of the
//     plan's protein target ("about 1.6 g/kg").
//
// Pure, no SwiftUI. Depended on by: GoalStatusEvaluator, the app's Today
// summary (FuelSummaryCard) and GamificationEngine. Tests: FuelDayTests.

import Foundation

/// The plan day's food targets in grams (the app fills it from
/// TrainingCore's `DayFuelTargets`).
public struct FuelDayTarget: Sendable, Equatable {
    public let carbsMinG: Double?
    public let carbsMaxG: Double?
    public let proteinG: Double?
    public let isCarbLoad: Bool
    public let hasTrainingSessions: Bool
    public let isFastingPaused: Bool

    public init(
        carbsMinG: Double?,
        carbsMaxG: Double?,
        proteinG: Double?,
        isCarbLoad: Bool = false,
        hasTrainingSessions: Bool,
        isFastingPaused: Bool = false
    ) {
        self.carbsMinG = carbsMinG.flatMap { $0 > 0 ? $0 : nil }
        self.carbsMaxG = carbsMaxG.flatMap { $0 > 0 ? $0 : nil }
        self.proteinG = proteinG.flatMap { $0 > 0 ? $0 : nil }
        self.isCarbLoad = isCarbLoad
        self.hasTrainingSessions = hasTrainingSessions
        self.isFastingPaused = isFastingPaused
    }

    /// The band in grams, when both edges are known (min <= max).
    public var carbBand: ClosedRange<Double>? {
        guard let low = carbsMinG, let high = carbsMaxG else { return nil }
        return min(low, high)...max(low, high)
    }

    /// "Over" is never a warning on this day.
    public var softensOver: Bool {
        hasTrainingSessions || carbBand != nil
    }
}

public enum FuelCarbStatus: String, Sendable, Equatable {
    case below
    case inBand
    case above
}

public struct FuelDaySummary: Sendable, Equatable {
    public let carbsG: Double
    public let carbBand: ClosedRange<Double>
    public let carbStatus: FuelCarbStatus
    /// 0...1 of the band's upper edge, for a bar.
    public let carbFraction: Double
    public let proteinG: Double
    public let proteinTargetG: Double?
    /// 0...1 of the protein target; `nil` without one.
    public let proteinFraction: Double?
    public let isCarbLoad: Bool
    public let showsUnderFuellingNote: Bool
}

public enum FuelDayEvaluator {
    /// Carbs under this share of the band's lower edge are "clearly below".
    public static let underFuellingFraction = 0.75
    /// The note shows from this local hour on (the evening meal is the
    /// last good chance to fix a low-carb day).
    public static let underFuellingHour = 18
    /// "About" the protein target: met from this share of it.
    public static let proteinTolerance = 0.9
    /// A training day without a band: calories met from this share up.
    public static let trainingDayCalorieFloor = 0.95

    /// The summary for the day, or `nil` without a carb band (the Today
    /// card then keeps its calorie-first look).
    public static func summary(
        carbsG: Double,
        proteinG: Double,
        target: FuelDayTarget?,
        isToday: Bool,
        now: Date,
        calendar: Calendar = .current
    ) -> FuelDaySummary? {
        guard let target, let band = target.carbBand else { return nil }
        let carbs = max(0, carbsG)
        let status: FuelCarbStatus = carbs < band.lowerBound ? .below : (carbs > band.upperBound ? .above : .inBand)
        let proteinFraction = target.proteinG.map { min(max(proteinG / $0, 0), 1) }
        let late = calendar.component(.hour, from: now) >= underFuellingHour
        let clearlyBelow = carbs < band.lowerBound * underFuellingFraction
        return FuelDaySummary(
            carbsG: carbs,
            carbBand: band,
            carbStatus: status,
            carbFraction: band.upperBound > 0 ? min(max(carbs / band.upperBound, 0), 1) : 0,
            proteinG: max(0, proteinG),
            proteinTargetG: target.proteinG,
            proteinFraction: proteinFraction,
            isCarbLoad: target.isCarbLoad,
            showsUnderFuellingNote: isToday && late && clearlyBelow
        )
    }

    /// The calorie ring's step, with "over" softened on a training/fuel
    /// day to `nil` (the neutral ring colour).
    public static func displayBand(_ band: CalorieBand?, target: FuelDayTarget?) -> CalorieBand? {
        guard let band, let target, target.softensOver else { return band }
        switch band {
        case .slightlyOver, .over: return nil
        case .low, .building, .approaching, .onTarget: return band
        }
    }

    /// Goal status on a plan day (see the header). The caller decides
    /// whether there is anything to judge (`GoalStatusEvaluator`).
    public static func judge(
        calories: Double?,
        protein: Double?,
        carbs: Double?,
        fat: Double?,
        calorieGoal: Double?,
        proteinGoal: Double?,
        carbGoal: Double?,
        fatGoal: Double?,
        target: FuelDayTarget
    ) -> DayGoalJudgement {
        let carbsMet: Bool
        let caloriesMet: Bool
        if let band = target.carbBand {
            carbsMet = (carbs ?? 0) >= band.lowerBound
            caloriesMet = carbsMet
        } else {
            carbsMet = GoalStatusEvaluator.metAtLeast(actual: carbs, goal: carbGoal)
            if target.hasTrainingSessions {
                if let calories, let calorieGoal, calorieGoal > 0 {
                    caloriesMet = calories / calorieGoal >= trainingDayCalorieFloor
                } else {
                    caloriesMet = false
                }
            } else {
                caloriesMet = CalorieBand.isGoalMet(consumed: calories, goal: calorieGoal)
            }
        }
        let proteinMet: Bool
        if let proteinTarget = target.proteinG {
            proteinMet = (protein ?? 0) >= proteinTarget * proteinTolerance
        } else {
            proteinMet = GoalStatusEvaluator.metAtLeast(actual: protein, goal: proteinGoal)
        }
        return DayGoalJudgement(
            metCalorieGoal: caloriesMet,
            metProteinGoal: proteinMet,
            metCarbGoal: carbsMet,
            metFatGoal: GoalStatusEvaluator.metAtLeast(actual: fat, goal: fatGoal)
        )
    }
}

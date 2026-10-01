// DayFuelTargets.swift
//
// add-winter-arc-nutrition-and-rewards (A1): what one plan day asks the
// food side to aim for, in grams -- the vault's per-day `fuel` band
// (PM-FUEL-1, g/kg) times the athlete's weight. The phone never invents a
// band: it only multiplies what the projection says. The food side
// (FoodLogCore's `FuelDayTarget`, filled by the app's one-line adapter)
// then judges the day's log against these grams.
//
// Rules:
//   - weight: `athlete.weightKg`, else the caller's fallback (the latest
//     weigh-in), else no gram targets at all (a band is g/kg; without a
//     weight the day falls back to today's calorie view);
//   - carb-load day: `carbsG` when given, else its single g/kg x weight,
//     as a one-point band (min == max);
//   - band day: `carbsBand.min/max` x weight; protein `proteinGPerKg` x
//     weight when the vault gives it, else `defaultProteinGPerKg` (1.6,
//     PM-FUEL-1) -- but only when there is a carb band at all, so a day
//     without any fuel says nothing about protein either;
//   - `hasTrainingSessions`: the day has any session, whatever its status
//     (a skipped or missed one still counts: the day was planned as a
//     training day, and the food judgement shouldn't swing on a skip);
//   - `isFastingPaused`: `fuel.fasting == "off"`.
//
// Pure. Depended on by: the app's TrainingModel (fuel targets for the
// Today summary and goal status). Tests: DayFuelTargetsTests.

import Foundation

public struct DayFuelTargets: Equatable, Sendable {
    /// PM-FUEL-1: "protein about 1.6 g/kg a day".
    public static let defaultProteinGPerKg = 1.6

    public let date: LocalDate
    /// The weight the grams were computed with; `nil` = none known.
    public let weightKg: Double?
    /// The day's carbohydrate band in grams (min == max on a carb-load day).
    public let carbsMinG: Double?
    public let carbsMaxG: Double?
    /// About this much protein in grams.
    public let proteinG: Double?
    public let isCarbLoad: Bool
    public let hasTrainingSessions: Bool
    public let isFastingPaused: Bool

    public init(
        date: LocalDate,
        weightKg: Double?,
        carbsMinG: Double?,
        carbsMaxG: Double?,
        proteinG: Double?,
        isCarbLoad: Bool,
        hasTrainingSessions: Bool,
        isFastingPaused: Bool
    ) {
        self.date = date
        self.weightKg = weightKg
        self.carbsMinG = carbsMinG
        self.carbsMaxG = carbsMaxG
        self.proteinG = proteinG
        self.isCarbLoad = isCarbLoad
        self.hasTrainingSessions = hasTrainingSessions
        self.isFastingPaused = isFastingPaused
    }

    /// Whether there is a carbohydrate band in grams to judge by.
    public var hasCarbBand: Bool {
        carbsMinG != nil && carbsMaxG != nil
    }

    /// The targets for `day`, or `nil` when the day says nothing the food
    /// side could use (no fuel, no sessions).
    public static func resolve(day: Day, athleteWeightKg: Double?, fallbackWeightKg: Double? = nil) -> DayFuelTargets? {
        let weight = [athleteWeightKg, fallbackWeightKg].compactMap { $0 }.first { $0.isFinite && $0 > 0 }
        let fuel = day.fuel
        let hasSessions = !day.sessions.isEmpty
        var carbsMin: Double?
        var carbsMax: Double?
        var protein: Double?
        // add-daily-checkin-and-pain-mode: every day has a `fuel` now, so
        // a carb-load day is its `kind`, never "the fuel is there".
        let isCarbLoad = fuel?.isCarbLoad ?? false

        if let fuel {
            if isCarbLoad {
                let grams = fuel.carbsG.map { Double($0) }.flatMap { $0 > 0 ? $0 : nil }
                    ?? weight.flatMap { kg in fuel.carbsGPerKg.map { $0 * kg } }
                if let grams, grams > 0 {
                    carbsMin = grams
                    carbsMax = grams
                }
            } else if let band = fuel.carbsBand, let weight {
                carbsMin = band.min * weight
                carbsMax = band.max * weight
            }
            if carbsMin != nil, let weight {
                protein = (fuel.proteinGPerKg ?? defaultProteinGPerKg) * weight
            }
        }

        let fastingPaused = fuel?.isFastingOff ?? false
        guard carbsMin != nil || hasSessions || fastingPaused else { return nil }
        return DayFuelTargets(
            date: day.date,
            weightKg: weight,
            carbsMinG: carbsMin,
            carbsMaxG: carbsMax,
            proteinG: protein,
            isCarbLoad: isCarbLoad && carbsMin != nil,
            hasTrainingSessions: hasSessions,
            isFastingPaused: fastingPaused
        )
    }
}

extension TrainingSnapshot {
    /// add-winter-arc-nutrition-and-rewards: the fuel targets of the plan
    /// day `date` (with the phone's pending plan edits applied), `nil`
    /// when the file has no such day or it says nothing about food.
    /// add-daily-checkin-and-pain-mode: a day skeleton counts (a day
    /// outside every written week, or with no plan at all).
    public func fuelTargets(on date: LocalDate, fallbackWeightKg: Double? = nil) -> DayFuelTargets? {
        // `self.`: the local `day` would otherwise shadow the lookup.
        guard let day = self.day(date) else { return nil }
        return DayFuelTargets.resolve(day: day, athleteWeightKg: athlete.weightKg, fallbackWeightKg: fallbackWeightKg)
    }
}

// GoalCalculator.swift
//
// A suggested STARTING calorie and macro target for a standalone user
// (add-standalone-mode D6, task 4.2). Garmin mode never uses it: there the
// targets are Garmin's. Pure and unit-tested with reference people, because
// a wrong number here is the one piece of this change that could actually
// hurt someone -- hence the floors, and the pace limits enforced here rather
// than only in the UI.
//
// The method (design D6, owner decision 0.4 defaulted):
//   - BMR (Mifflin-St Jeor) = 10*kg + 6.25*cm - 5*age + (male +5 | female -161);
//     `sex` only picks that constant, and the UI says why it asks.
//   - TDEE = BMR * activity factor (1.2 / 1.375 / 1.55 / 1.725 / 1.9).
//   - Target = TDEE -/+ pace * 7700 / 7 kcal a day (lose / gain); maintain
//     ignores the pace.
//   - Floors: never below 1200 kcal, never below BMR -- the same for
//     everyone (0.4 default). When one applies the result says which, so
//     the screen can say why.
//   - Pace: one of 0.25 / 0.5 / 0.75 kg a week, and never more than 1 % of
//     body weight a week; a faster pace is refused, not silently lowered.
//   - Macros: protein 1.6 g/kg when losing, 1.4 g/kg otherwise; fat 30 % of
//     the target; carbs whatever calories remain, never below 0. If protein
//     and fat already exceed the target, fat drops to 25 %.
//
// Everything it returns is a suggestion; the editor lets every number be
// changed before it is saved (as a new `LocalNutritionGoals`, starting
// today). Not medical advice -- the screen says so.
//
// Depended on by: the app's goal calculator screen (Settings -> Nutrition
// plan in standalone mode, and onboarding). Tests: GoalCalculatorTests.

import Foundation

public enum GoalCalculator {
    public enum Sex: String, Codable, Sendable, CaseIterable {
        case female, male
    }

    public enum ActivityLevel: String, Codable, Sendable, CaseIterable {
        case sedentary, light, moderate, very, extra

        public var factor: Double {
            switch self {
            case .sedentary: return 1.2
            case .light: return 1.375
            case .moderate: return 1.55
            case .very: return 1.725
            case .extra: return 1.9
            }
        }
    }

    public enum Direction: String, Codable, Sendable, CaseIterable {
        case lose, maintain, gain
    }

    /// The pace choices, kg per week (design D6).
    public static let paceChoices: [Double] = [0.25, 0.5, 0.75]
    public static let maximumPaceKgPerWeek = 0.75
    /// A pace above this fraction of body weight a week is refused.
    public static let maximumPaceFractionOfBodyWeight = 0.01
    public static let minimumCalories = 1200.0
    /// ~7700 kcal per kg of body weight.
    public static let kcalPerKg = 7700.0

    public struct Input: Sendable, Equatable {
        public var sex: Sex
        public var birthYear: Int
        public var heightCm: Double
        public var weightKg: Double
        public var activity: ActivityLevel
        public var direction: Direction
        /// kg a week; ignored for `.maintain`.
        public var paceKgPerWeek: Double

        public init(sex: Sex, birthYear: Int, heightCm: Double, weightKg: Double, activity: ActivityLevel, direction: Direction, paceKgPerWeek: Double = 0.5) {
            self.sex = sex
            self.birthYear = birthYear
            self.heightCm = heightCm
            self.weightKg = weightKg
            self.activity = activity
            self.direction = direction
            self.paceKgPerWeek = paceKgPerWeek
        }
    }

    /// Which floor raised the target, so the screen can say why.
    public enum Floor: String, Sendable, Equatable {
        /// Raised to 1200 kcal.
        case minimumCalories
        /// Raised to the person's BMR.
        case bmr
    }

    public struct Suggestion: Sendable, Equatable {
        public let bmr: Double
        public let tdee: Double
        /// Whole kcal.
        public let calories: Double
        /// Whole grams.
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double
        /// `nil` when the pace-based target was already above both floors.
        public let appliedFloor: Floor?
    }

    public enum InputError: Error, Sendable, Equatable {
        case ageOutOfRange
        case heightOutOfRange
        case weightOutOfRange
        /// Not one of the pace choices, or above 1 % of body weight a week.
        /// `maximumKgPerWeek` is the fastest pace this person may pick.
        case paceTooFast(maximumKgPerWeek: Double)
    }

    public static let ageRange = 14...100
    public static let heightRange = 100.0...250.0
    public static let weightRange = 30.0...300.0

    /// The paces this body weight may choose (design D6: at most 0.75 kg
    /// and at most 1 % of body weight a week).
    public static func allowedPaces(weightKg: Double) -> [Double] {
        let limit = min(maximumPaceKgPerWeek, weightKg * maximumPaceFractionOfBodyWeight)
        // A hair of tolerance so 0.5 kg for exactly 50 kg stays allowed.
        return paceChoices.filter { $0 <= limit + 1e-9 }
    }

    public static func age(birthYear: Int, currentYear: Int) -> Int {
        currentYear - birthYear
    }

    public static func bmr(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        switch sex {
        case .female: return base - 161
        case .male: return base + 5
        }
    }

    /// The suggestion for `input` in `currentYear` (the age comes from the
    /// birth year). Throws `InputError` for an implausible body or a pace
    /// that isn't allowed; never returns a target under either floor.
    public static func suggest(_ input: Input, currentYear: Int) throws -> Suggestion {
        let years = Self.age(birthYear: input.birthYear, currentYear: currentYear)
        guard ageRange.contains(years) else { throw InputError.ageOutOfRange }
        guard input.heightCm.isFinite, heightRange.contains(input.heightCm) else { throw InputError.heightOutOfRange }
        guard input.weightKg.isFinite, weightRange.contains(input.weightKg) else { throw InputError.weightOutOfRange }
        if input.direction != .maintain {
            let allowed = allowedPaces(weightKg: input.weightKg)
            guard allowed.contains(where: { abs($0 - input.paceKgPerWeek) < 1e-9 }) else {
                throw InputError.paceTooFast(maximumKgPerWeek: allowed.last ?? 0)
            }
        }

        let basal = Self.bmr(sex: input.sex, weightKg: input.weightKg, heightCm: input.heightCm, age: years)
        let tdee = basal * input.activity.factor
        let dailyDelta = input.paceKgPerWeek * kcalPerKg / 7
        let raw: Double
        switch input.direction {
        case .lose: raw = tdee - dailyDelta
        case .maintain: raw = tdee
        case .gain: raw = tdee + dailyDelta
        }

        let floorValue = max(minimumCalories, basal)
        let target: Double
        let appliedFloor: Floor?
        if raw < floorValue {
            target = floorValue
            appliedFloor = basal > minimumCalories ? .bmr : .minimumCalories
        } else {
            target = raw
            appliedFloor = nil
        }

        // Rounded UP when a floor applies, so rounding can never land a
        // whole kcal under it.
        let calories = appliedFloor == nil ? target.rounded() : target.rounded(.up)
        let split = Self.macros(calories: calories, weightKg: input.weightKg, losing: input.direction == .lose)
        return Suggestion(
            bmr: basal,
            tdee: tdee,
            calories: calories,
            proteinG: split.proteinG,
            carbsG: split.carbsG,
            fatG: split.fatG,
            appliedFloor: appliedFloor
        )
    }

    /// Whole-gram macros for a calorie target (design D6).
    public static func macros(calories: Double, weightKg: Double, losing: Bool) -> (proteinG: Double, carbsG: Double, fatG: Double) {
        let protein = (losing ? 1.6 : 1.4) * weightKg
        let proteinKcal = protein * 4
        var fatKcal = calories * 0.30
        if proteinKcal + fatKcal > calories {
            fatKcal = calories * 0.25
        }
        let carbsKcal = max(0, calories - proteinKcal - fatKcal)
        return (protein.rounded(), (carbsKcal / 4).rounded(), (fatKcal / 9).rounded())
    }
}

// GoalCalculatorTests.swift
//
// add-standalone-mode 4.2 (local-nutrition-goals spec, "A goal calculator
// suggests a safe starting target"): reference people worked out by hand
// from Mifflin-St Jeor, the two floors (1200 kcal and BMR), the pace limits
// (0.75 kg and 1 % of body weight a week) and the macro split, including
// the fat fallback when protein and fat alone exceed the target. Pure.

import XCTest
@testable import FoodLogCore

final class GoalCalculatorTests: XCTestCase {
    private let year = 2026

    private func woman(_ direction: GoalCalculator.Direction, activity: GoalCalculator.ActivityLevel = .moderate, pace: Double = 0.5) -> GoalCalculator.Input {
        // 30 years, 165 cm, 60 kg.
        GoalCalculator.Input(sex: .female, birthYear: 1996, heightCm: 165, weightKg: 60, activity: activity, direction: direction, paceKgPerWeek: pace)
    }

    // MARK: Reference people

    func testTheSpecsReferenceWomanMaintaining() throws {
        // BMR = 600 + 1031.25 - 150 - 161 = 1320.25; x 1.55 = 2046.39.
        let result = try GoalCalculator.suggest(woman(.maintain), currentYear: year)
        XCTAssertEqual(result.bmr, 1320.25, accuracy: 0.001)
        XCTAssertEqual(result.tdee, 2046.3875, accuracy: 0.001)
        XCTAssertEqual(result.calories, 2046)
        XCTAssertEqual(result.proteinG, 84, "1.4 g per kg when not losing")
        XCTAssertEqual(result.fatG, 68, "30 % of 2046 kcal = 613.8 kcal = 68.2 g")
        XCTAssertEqual(result.carbsG, 274, "(2046 - 336 - 613.8) / 4 = 274.05")
        XCTAssertNil(result.appliedFloor)
    }

    func testAReferenceManMaintainingSedentary() throws {
        // 40 years, 180 cm, 80 kg: BMR = 800 + 1125 - 200 + 5 = 1730; x 1.2 = 2076.
        let input = GoalCalculator.Input(sex: .male, birthYear: 1986, heightCm: 180, weightKg: 80, activity: .sedentary, direction: .maintain)
        let result = try GoalCalculator.suggest(input, currentYear: year)
        XCTAssertEqual(result.bmr, 1730, accuracy: 0.001)
        XCTAssertEqual(result.calories, 2076)
        XCTAssertEqual(result.proteinG, 112)
        XCTAssertNil(result.appliedFloor)
    }

    func testLosingHalfAKiloAWeekTakes550KcalOffAndRaisesProtein() throws {
        let result = try GoalCalculator.suggest(woman(.lose, pace: 0.5), currentYear: year)
        XCTAssertEqual(result.calories, 1496, "2046.39 - 0.5 x 7700 / 7")
        XCTAssertEqual(result.proteinG, 96, "1.6 g per kg when losing")
        XCTAssertNil(result.appliedFloor, "1496 is above both floors")
    }

    func testGainingAddsThePace() throws {
        let result = try GoalCalculator.suggest(woman(.gain, pace: 0.25), currentYear: year)
        XCTAssertEqual(result.calories, 2321, "2046.39 + 275")
        XCTAssertEqual(result.proteinG, 84)
    }

    func testEveryActivityFactor() {
        XCTAssertEqual(GoalCalculator.ActivityLevel.allCases.map(\.factor), [1.2, 1.375, 1.55, 1.725, 1.9])
    }

    // MARK: Floors (spec: "Floor applies")

    func testATargetBelowBMRIsRaisedToBMR() throws {
        // Sedentary: 1320.25 x 1.2 = 1584.3; - 550 = 1034.3, under BMR 1320.25.
        let result = try GoalCalculator.suggest(woman(.lose, activity: .sedentary, pace: 0.5), currentYear: year)
        XCTAssertEqual(result.appliedFloor, .bmr)
        XCTAssertEqual(result.calories, 1321, "rounded up, never a kcal under BMR")
        XCTAssertGreaterThanOrEqual(result.calories, result.bmr)
    }

    func testATargetBelow1200IsRaisedTo1200() throws {
        // 60 years, 150 cm, 45 kg: BMR = 450 + 937.5 - 300 - 161 = 926.5;
        // x 1.2 = 1111.8; - 275 = 836.8.
        let input = GoalCalculator.Input(sex: .female, birthYear: 1966, heightCm: 150, weightKg: 45, activity: .sedentary, direction: .lose, paceKgPerWeek: 0.25)
        let result = try GoalCalculator.suggest(input, currentYear: year)
        XCTAssertEqual(result.bmr, 926.5, accuracy: 0.001)
        XCTAssertEqual(result.appliedFloor, .minimumCalories)
        XCTAssertEqual(result.calories, 1200)
    }

    func testMaintainingBelow1200IsRaisedToo() throws {
        let input = GoalCalculator.Input(sex: .female, birthYear: 1946, heightCm: 145, weightKg: 40, activity: .sedentary, direction: .maintain)
        let result = try GoalCalculator.suggest(input, currentYear: year)
        XCTAssertEqual(result.calories, 1200)
        XCTAssertEqual(result.appliedFloor, .minimumCalories)
    }

    func testNoSuggestionIsEverBelowEitherFloor() throws {
        for sex in GoalCalculator.Sex.allCases {
            for weight in stride(from: 40.0, through: 160.0, by: 20) {
                for height in stride(from: 150.0, through: 200.0, by: 25) {
                    for birthYear in [1950, 1980, 2005] {
                        for activity in GoalCalculator.ActivityLevel.allCases {
                            for pace in GoalCalculator.allowedPaces(weightKg: weight) {
                                let input = GoalCalculator.Input(sex: sex, birthYear: birthYear, heightCm: height, weightKg: weight, activity: activity, direction: .lose, paceKgPerWeek: pace)
                                let result = try GoalCalculator.suggest(input, currentYear: year)
                                XCTAssertGreaterThanOrEqual(result.calories, 1200, "\(input)")
                                XCTAssertGreaterThanOrEqual(result.calories, result.bmr, "\(input)")
                                XCTAssertGreaterThanOrEqual(result.carbsG, 0, "\(input)")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Pace limits

    func testAllowedPacesAreCappedAt075AndOnePercentOfBodyWeight() {
        XCTAssertEqual(GoalCalculator.allowedPaces(weightKg: 100), [0.25, 0.5, 0.75])
        XCTAssertEqual(GoalCalculator.allowedPaces(weightKg: 75), [0.25, 0.5, 0.75])
        XCTAssertEqual(GoalCalculator.allowedPaces(weightKg: 60), [0.25, 0.5], "0.75 kg is more than 1 % of 60 kg")
        XCTAssertEqual(GoalCalculator.allowedPaces(weightKg: 50), [0.25, 0.5], "exactly 1 % is allowed")
        XCTAssertEqual(GoalCalculator.allowedPaces(weightKg: 40), [0.25])
    }

    func testAPaceAboveOnePercentOfBodyWeightIsRefused() {
        XCTAssertThrowsError(try GoalCalculator.suggest(woman(.lose, pace: 0.75), currentYear: year)) { error in
            XCTAssertEqual(error as? GoalCalculator.InputError, .paceTooFast(maximumKgPerWeek: 0.5))
        }
    }

    func testAPaceThatIsNotAChoiceIsRefused() {
        let input = GoalCalculator.Input(sex: .male, birthYear: 1986, heightCm: 180, weightKg: 100, activity: .light, direction: .lose, paceKgPerWeek: 1.0)
        XCTAssertThrowsError(try GoalCalculator.suggest(input, currentYear: year)) { error in
            XCTAssertEqual(error as? GoalCalculator.InputError, .paceTooFast(maximumKgPerWeek: 0.75))
        }
    }

    func testMaintainingIgnoresThePace() throws {
        XCTAssertNoThrow(try GoalCalculator.suggest(woman(.maintain, pace: 0.75), currentYear: year))
    }

    // MARK: Input validation

    func testImplausibleInputIsRefused() {
        var young = woman(.maintain)
        young.birthYear = 2020
        XCTAssertThrowsError(try GoalCalculator.suggest(young, currentYear: year)) { XCTAssertEqual($0 as? GoalCalculator.InputError, .ageOutOfRange) }
        var short = woman(.maintain)
        short.heightCm = 90
        XCTAssertThrowsError(try GoalCalculator.suggest(short, currentYear: year)) { XCTAssertEqual($0 as? GoalCalculator.InputError, .heightOutOfRange) }
        var light = woman(.maintain)
        light.weightKg = 20
        XCTAssertThrowsError(try GoalCalculator.suggest(light, currentYear: year)) { XCTAssertEqual($0 as? GoalCalculator.InputError, .weightOutOfRange) }
        var nan = woman(.maintain)
        nan.weightKg = .nan
        XCTAssertThrowsError(try GoalCalculator.suggest(nan, currentYear: year))
    }

    // MARK: Macros

    func testFatDropsTo25PercentWhenProteinAndFatExceedTheTarget() {
        // 150 kg losing: protein 240 g = 960 kcal; 960 + 30 % of 1200 (360)
        // = 1320 > 1200, so fat is 25 % (300 kcal = 33.3 g), carbs 0.
        let split = GoalCalculator.macros(calories: 1200, weightKg: 150, losing: true)
        XCTAssertEqual(split.proteinG, 240)
        XCTAssertEqual(split.fatG, 33)
        XCTAssertEqual(split.carbsG, 0, "never negative")
    }
}

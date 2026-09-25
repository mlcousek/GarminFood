// SupplementLimitsTests.swift
//
// add-supplements 1.6: default limits, user overrides and reset, over-limit
// evaluation, the extra-dose notice, and the "no EU upper limit" cases that
// must never warn on their own.

import XCTest
@testable import FoodLogCore

final class SupplementLimitsTests: XCTestCase {
    private func product(_ rows: IngredientAmount...) -> SupplementProduct {
        SupplementProduct(name: "Test", ingredients: rows)
    }

    // Spec: Zinc from two products.
    func testZincAboveTheDefaultLimitWarns() {
        var totals = IngredientTotals()
        totals.add(product(IngredientAmount(ingredient: .zinc, amount: 10, unit: .mg)), servings: 1)
        totals.add(product(IngredientAmount(ingredient: .zinc, amount: 25, unit: .mg)), servings: 1)

        let warnings = SupplementLimits.warnings(for: totals, overrides: [:])

        XCTAssertEqual(warnings, [LimitWarning(ingredient: .zinc, kind: .daily, amount: 35, limit: 25, unit: .mg)])
    }

    func testExactlyAtTheLimitDoesNotWarn() {
        let totals = IngredientTotals(amounts: [.zinc: 25, .vitaminD: 100])
        XCTAssertTrue(SupplementLimits.warnings(for: totals, overrides: [:]).isEmpty)
    }

    // Spec: Athlete override.
    func testARaisedMagnesiumLimitSilencesTheWarning() {
        let totals = IngredientTotals(amounts: [.magnesium: 450])
        XCTAssertEqual(SupplementLimits.warnings(for: totals, overrides: [:]).map(\.limit), [250])

        let overrides: SupplementLimits.Overrides = [.magnesium: LimitOverride(ingredient: .magnesium, upperLimit: 500)]

        XCTAssertTrue(SupplementLimits.warnings(for: totals, overrides: overrides).isEmpty)
        let effective = SupplementLimits.effective(for: .magnesium, overrides: overrides)
        XCTAssertEqual(effective.upperLimit, 500)
        XCTAssertEqual(effective.defaultUpperLimit, 250)
        XCTAssertTrue(effective.isOverridden)
    }

    // Spec: Reset.
    func testResetMeansNoOverrideAndTheDefaultAgain() {
        let reset = SupplementLimits.effective(for: .magnesium, overrides: [:])
        XCTAssertEqual(reset.upperLimit, 250)
        XCTAssertFalse(reset.isOverridden)
        XCTAssertEqual(reset.defaultKind, .upperLimit)

        let targetOnly = SupplementLimits.effective(for: .magnesium, overrides: [.magnesium: LimitOverride(ingredient: .magnesium, target: 200)])
        XCTAssertEqual(targetOnly.target, 200)
        XCTAssertEqual(targetOnly.upperLimit, 250, "a nil field keeps the default")
        XCTAssertTrue(LimitOverride(ingredient: .zinc).isEmpty)
    }

    func testNoEUUpperLimitNeverWarnsByDefault() {
        let totals = IngredientTotals(amounts: [.vitaminC: 3000, .omega3EPA_DHA: 6000, .creatine: 20, .sodium: 5000, .vitaminB12: 2000])

        XCTAssertTrue(SupplementLimits.warnings(for: totals, overrides: [:]).isEmpty)

        let vitaminC = SupplementLimits.effective(for: .vitaminC, overrides: [:])
        XCTAssertNil(vitaminC.upperLimit)
        XCTAssertEqual(vitaminC.defaultKind, .noEUUpperLimit)
        // ...unless the user sets a limit of their own.
        let own: SupplementLimits.Overrides = [.vitaminC: LimitOverride(ingredient: .vitaminC, upperLimit: 1000)]
        XCTAssertEqual(SupplementLimits.warnings(for: totals, overrides: own).map(\.ingredient), [.vitaminC])
    }

    func testAnIngredientWithoutACardHasNoDefaults() {
        let totals = IngredientTotals(amounts: ["ashwagandha": 900])
        XCTAssertTrue(SupplementLimits.warnings(for: totals, overrides: [:]).isEmpty)
        let effective = SupplementLimits.effective(for: "ashwagandha", overrides: [:])
        XCTAssertNil(effective.defaultKind)
        XCTAssertEqual(effective.unit, .mg)
    }

    // Spec: Extra dose over the limit.
    func testExtraCaffeineDosePushingPastTheDailyLimit() {
        let current = IngredientTotals(amounts: [.caffeine: 350, .zinc: 30])
        let shot = product(IngredientAmount(ingredient: .caffeine, amount: 100, unit: .mg))

        let notice = SupplementLimits.extraDoseNotice(adding: shot, servings: 1, to: current, overrides: [:])

        XCTAssertEqual(notice, [LimitWarning(ingredient: .caffeine, kind: .daily, amount: 450, limit: 400, unit: .mg)],
                       "zinc was already over but isn't part of this dose, so it isn't repeated")
    }

    func testALargeSingleCaffeineDoseIsNoted() {
        let preWorkout = product(IngredientAmount(ingredient: .caffeine, amount: 300, unit: .mg))

        let notice = SupplementLimits.extraDoseNotice(adding: preWorkout, servings: 1, to: IngredientTotals(), overrides: [:])

        XCTAssertEqual(notice, [LimitWarning(ingredient: .caffeine, kind: .singleDose, amount: 300, limit: 200, unit: .mg)])
    }

    func testOverrideDecodesWithOnlyTheIngredient() throws {
        let decoded = try JSONDecoder().decode(LimitOverride.self, from: Data(#"{"ingredient":"sodium","futureKey":1}"#.utf8))
        XCTAssertEqual(decoded, LimitOverride(ingredient: .sodium))
    }
}

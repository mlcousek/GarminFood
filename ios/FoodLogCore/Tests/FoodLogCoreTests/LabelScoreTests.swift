// LabelScoreTests.swift
//
// add-supplements 1.7: the label score's three parts and the findings that
// explain them -- spec scenarios "Proprietary blend" and "Effective dose".

import XCTest
@testable import FoodLogCore

final class LabelScoreTests: XCTestCase {
    // Spec: Effective dose.
    func testCreatineAtFiveGramsScoresFull() {
        let creatine = SupplementProduct(name: "Creatine", ingredients: [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)])

        let score = LabelScore.evaluate(creatine)

        XCTAssertEqual(score.dose, LabelScore.Part(points: 40, maximum: 40, findings: [.withinRange(.creatine)]))
        XCTAssertEqual(score.transparency, LabelScore.Part(points: 40, maximum: 40, findings: [.allAmountsStated]))
        XCTAssertEqual(score.headroom, LabelScore.Part(points: 20, maximum: 20, findings: [.underLimits]))
        XCTAssertEqual(score.total, 100)
    }

    // Spec: Proprietary blend.
    func testAProprietaryBlendReducesTransparencyAndIsNamed() {
        let preWorkout = SupplementProduct(
            name: "Pump",
            ingredients: [IngredientAmount(ingredient: .caffeine, amount: 150, unit: .mg)],
            proprietaryBlends: ["Pump matrix"]
        )

        let transparency = LabelScore.evaluate(preWorkout).transparency

        XCTAssertEqual(transparency.points, 25)
        XCTAssertTrue(transparency.findings.contains(.proprietaryBlend("Pump matrix")))
        XCTAssertFalse(transparency.findings.contains(.allAmountsStated))
    }

    func testOnlyABlendScoresNoTransparency() {
        let mystery = SupplementProduct(name: "Mystery", ingredients: [], proprietaryBlends: ["Secret blend"])

        let score = LabelScore.evaluate(mystery)

        XCTAssertEqual(score.transparency, LabelScore.Part(points: 0, maximum: 40, findings: [.proprietaryBlend("Secret blend")]))
        XCTAssertEqual(score.dose.points, 20, "nothing scorable: half, said so")
        XCTAssertEqual(score.dose.findings, [.noIngredients])
    }

    func testMissingAmountsAndMagnesiumFormLowerTransparency() {
        let multi = SupplementProduct(name: "Multi", ingredients: [
            IngredientAmount(ingredient: .zinc, amount: 10, unit: .mg),
            IngredientAmount(ingredient: .vitaminC, amount: nil, unit: .mg),
            IngredientAmount(ingredient: .magnesium, amount: 100, unit: .mg)
        ])

        let transparency = LabelScore.evaluate(multi).transparency

        // 40 x 2/3 = 26.67, minus 5 for the unstated magnesium form.
        XCTAssertEqual(transparency.points, 22)
        XCTAssertEqual(transparency.findings, [.amountMissing(.vitaminC), .formMissing(.magnesium)])
    }

    func testDoseOutsideTheRangeScoresHalf() {
        let lowD3 = SupplementProduct(name: "D3 200 IU", ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 200, unit: .iu)])
        XCTAssertEqual(LabelScore.evaluate(lowD3).dose, LabelScore.Part(points: 20, maximum: 40, findings: [.belowRange(.vitaminD)]))

        // Loading-phase creatine: 4 servings of 5 g a day is above 3–5 g.
        let creatine = SupplementProduct(name: "Creatine", ingredients: [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)])
        XCTAssertEqual(LabelScore.evaluate(creatine, servingsPerDay: 4).dose.findings, [.aboveRange(.creatine)])

        let electrolytes = SupplementProduct(name: "Salt", ingredients: [
            IngredientAmount(ingredient: .sodium, amount: 500, unit: .mg),
            IngredientAmount(ingredient: .magnesium, amount: 100, unit: .mg, form: MagnesiumForm.citrate.rawValue)
        ])
        let dose = LabelScore.evaluate(electrolytes).dose
        XCTAssertEqual(dose.points, 40, "only magnesium has a range, and it's inside it")
        XCTAssertEqual(dose.findings, [.withinRange(.magnesium), .noReferenceRange(.sodium)])
    }

    func testHeadroomUsesTheUsersLimitsAndTheRestOfTheDay() {
        let zinc = SupplementProduct(name: "Zinc 30", ingredients: [IngredientAmount(ingredient: .zinc, amount: 30, unit: .mg)])
        XCTAssertEqual(LabelScore.evaluate(zinc).headroom, LabelScore.Part(points: 0, maximum: 20, findings: [.overLimit(.zinc)]))

        let raised: SupplementLimits.Overrides = [.zinc: LimitOverride(ingredient: .zinc, upperLimit: 40)]
        XCTAssertEqual(LabelScore.evaluate(zinc, overrides: raised).headroom.points, 20)

        let zinc10 = SupplementProduct(name: "Zinc 10", ingredients: [IngredientAmount(ingredient: .zinc, amount: 10, unit: .mg)])
        XCTAssertEqual(LabelScore.evaluate(zinc10).headroom.points, 20)
        XCTAssertEqual(LabelScore.evaluate(zinc10, otherIntake: IngredientTotals(amounts: [.zinc: 20, .caffeine: 900])).headroom.findings,
                       [.overLimit(.zinc)], "caffeine is over too, but this product has none")
    }
}

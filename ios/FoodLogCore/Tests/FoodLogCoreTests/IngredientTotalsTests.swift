// IngredientTotalsTests.swift
//
// add-supplements 1.4: daily ingredient totals across products, planned and
// extra, with unit conversion (IU -> µg for vitamin D) and multi-ingredient
// products -- spec scenarios "Zinc from two products" and
// "Multi-ingredient product".

import XCTest
@testable import FoodLogCore

final class IngredientTotalsTests: XCTestCase {
    private let takenAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(_ product: SupplementProduct, day: String = "2026-10-02", servings: Double = 1, kind: IntakeKind = .planned) -> IntakeRecord {
        IntakeRecord(day: day, productId: product.id, slot: kind == .planned ? .morning : nil, servings: servings, takenAt: takenAt, kind: kind)
    }

    // Spec: Zinc from two products (the over-limit half is in SupplementLimitsTests).
    func testZincFromTwoProductsAddsUp() {
        let multivitamin = SupplementProduct(name: "Multi", ingredients: [
            IngredientAmount(ingredient: .zinc, amount: 10, unit: .mg),
            IngredientAmount(ingredient: .vitaminC, amount: 80, unit: .mg)
        ])
        let zincTablet = SupplementProduct(name: "Zinc", ingredients: [IngredientAmount(ingredient: .zinc, amount: 25, unit: .mg)])

        let totals = IngredientTotals.of(day: "2026-10-02", records: [record(multivitamin), record(zincTablet, kind: .extra)], products: [multivitamin, zincTablet])

        XCTAssertEqual(totals.amount(of: .zinc), 35)
        XCTAssertEqual(totals.amount(of: .vitaminC), 80)
        XCTAssertTrue(totals.unconverted.isEmpty)
    }

    // Spec: Multi-ingredient product.
    func testOneTickOfZMAAddsEachIngredient() {
        let zma = SupplementProduct(name: "ZMA", ingredients: [
            IngredientAmount(ingredient: .zinc, amount: 15, unit: .mg),
            IngredientAmount(ingredient: .magnesium, amount: 450, unit: .mg, form: MagnesiumForm.aspartate.rawValue),
            IngredientAmount(ingredient: .vitaminB6, amount: 10, unit: .mg)
        ])

        let totals = IngredientTotals.of(day: "2026-10-02", records: [record(zma)], products: [zma])

        XCTAssertEqual(totals.amounts, [.zinc: 15, .magnesium: 450, .vitaminB6: 10])
        XCTAssertEqual(totals.ingredients, [.magnesium, .vitaminB6, .zinc])
    }

    func testUnitsConvertToTheCanonicalUnitAndServingsMultiply() {
        let d3IU = SupplementProduct(name: "D3 2000 IU", ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 2000, unit: .iu)])
        let d3Micrograms = SupplementProduct(name: "D3 25 µg", ingredients: [IngredientAmount(ingredient: .vitaminD, amount: 25, unit: .ug)])
        let creatineMilligrams = SupplementProduct(name: "Creatine caps", ingredients: [IngredientAmount(ingredient: .creatine, amount: 750, unit: .mg)])

        let totals = IngredientTotals.of(
            day: "2026-10-02",
            records: [record(d3IU), record(d3Micrograms, servings: 2), record(creatineMilligrams, servings: 4)],
            products: [d3IU, d3Micrograms, creatineMilligrams]
        )

        XCTAssertEqual(totals.amount(of: .vitaminD), 100, "50 µg + 2 x 25 µg")
        XCTAssertEqual(totals.amount(of: .creatine), 3, accuracy: 1e-9, "4 x 750 mg in grams")
    }

    func testUnstatedOrUnconvertibleRowsAreFlaggedNotGuessed() {
        let odd = SupplementProduct(name: "Odd", ingredients: [
            IngredientAmount(ingredient: .vitaminC, amount: 100, unit: .iu),
            IngredientAmount(ingredient: .zinc, amount: nil, unit: .mg),
            IngredientAmount(ingredient: .selenium, amount: 55, unit: .ug)
        ])

        let totals = IngredientTotals.of(day: "2026-10-02", records: [record(odd)], products: [odd])

        XCTAssertEqual(totals.amounts, [.selenium: 55])
        XCTAssertEqual(totals.unconverted, [.vitaminC, .zinc])
    }

    func testOtherDaysAndDeletedProductsDontCount() {
        let zinc = SupplementProduct(name: "Zinc", ingredients: [IngredientAmount(ingredient: .zinc, amount: 25, unit: .mg)])
        let deleted = SupplementProduct(name: "Gone", ingredients: [IngredientAmount(ingredient: .zinc, amount: 25, unit: .mg)])

        let totals = IngredientTotals.of(
            day: "2026-10-02",
            records: [record(zinc, day: "2026-10-01"), record(zinc), record(deleted)],
            products: [zinc]
        )

        XCTAssertEqual(totals.amount(of: .zinc), 25)
    }
}

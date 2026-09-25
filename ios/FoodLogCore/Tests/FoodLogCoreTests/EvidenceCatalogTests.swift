// EvidenceCatalogTests.swift
//
// add-supplements 1.5: the evidence cards and the built-in catalog. Pins the
// default limits to design D8's table (checked against the source PDFs --
// a changed number here must be re-checked there, never against a
// summary), and checks the task's two invariants: every catalog
// product's ingredients have a card, and every limit has a source.

import XCTest
@testable import FoodLogCore

final class EvidenceCatalogTests: XCTestCase {
    private func czechBundle() throws -> Bundle {
        let path = try XCTUnwrap(Bundle.module.path(forResource: "cs", ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testEveryBuiltInIngredientHasExactlyOneCard() {
        XCTAssertEqual(EvidenceCatalog.all.map(\.ingredient), IngredientID.builtIn)
        for ingredient in IngredientID.builtIn {
            let card = EvidenceCatalog.card(for: ingredient)
            XCTAssertNotNil(card, ingredient.rawValue)
            XCTAssertFalse(card?.purpose.isEmpty ?? true, ingredient.rawValue)
            XCTAssertFalse(card?.typicalDose.isEmpty ?? true, ingredient.rawValue)
            XCTAssertFalse(card?.timing.isEmpty ?? true, ingredient.rawValue)
            XCTAssertNotEqual(card?.name, ingredient.rawValue, "a built-in ingredient has a display name")
        }
        XCTAssertNil(EvidenceCatalog.card(for: "ashwagandha"))
    }

    func testEveryCatalogProductIngredientHasACard() {
        XCTAssertFalse(SupplementCatalog.all.isEmpty)
        XCTAssertEqual(Set(SupplementCatalog.all.map(\.id)).count, SupplementCatalog.all.count, "catalog ids are unique")
        for product in SupplementCatalog.all {
            XCTAssertFalse(product.ingredients.isEmpty, product.id)
            XCTAssertNotEqual(product.name, product.id, "\(product.id) has a display name")
            for row in product.ingredients {
                XCTAssertNotNil(EvidenceCatalog.card(for: row.ingredient), "\(product.id): \(row.ingredient.rawValue)")
                XCTAssertNotNil(row.canonicalAmount, "\(product.id): \(row.ingredient.rawValue) converts")
            }
        }
    }

    func testEveryLimitHasASource() {
        for card in EvidenceCatalog.all {
            XCTAssertFalse(card.sources.isEmpty, card.ingredient.rawValue)
            XCTAssertEqual(card.sources.first, card.limit.source, "\(card.ingredient.rawValue): the limit's source is cited first")
            XCTAssertFalse(card.limit.source.title.isEmpty)
            XCTAssertEqual(card.limit.source.url.scheme, "https")
            if card.limit.kind == .noEUUpperLimit {
                XCTAssertNil(card.limit.value, "\(card.ingredient.rawValue): no EU UL means no default warning figure")
            } else {
                XCTAssertNotNil(card.limit.value, card.ingredient.rawValue)
            }
        }
    }

    /// Design D8's table, value for value.
    func testDefaultLimitsMatchTheDesignTable() throws {
        func limit(_ ingredient: IngredientID) throws -> DefaultLimit {
            try XCTUnwrap(EvidenceCatalog.card(for: ingredient)).limit
        }
        XCTAssertEqual(try limit(.vitaminD).value, 100)
        XCTAssertEqual(try limit(.vitaminD).kind, .upperLimit)
        XCTAssertEqual(DoseUnit.convert(100, of: .vitaminD, from: .ug, to: .iu), 4000)
        XCTAssertEqual(try limit(.vitaminC).kind, .noEUUpperLimit)
        XCTAssertEqual(try limit(.vitaminC).usFigure, 2000)
        XCTAssertEqual(try limit(.zinc).value, 25)
        XCTAssertEqual(try limit(.magnesium).value, 250)
        XCTAssertTrue(try limit(.magnesium).supplementalOnly)
        XCTAssertEqual(try limit(.vitaminB6).value, 12)
        XCTAssertEqual(try limit(.iron).value, 40)
        XCTAssertEqual(try limit(.iron).kind, .safeLevel, "iron's 40 mg is a safe level, not a UL")
        XCTAssertEqual(try limit(.selenium).value, 255)
        XCTAssertEqual(try limit(.omega3EPA_DHA).kind, .noEUUpperLimit)
        XCTAssertEqual(try limit(.omega3EPA_DHA).noConcernLevel, 5000, "5 g in mg")
        XCTAssertEqual(try limit(.creatine).kind, .noEUUpperLimit)
        XCTAssertEqual(try limit(.creatine).noConcernLevel, 3)
        XCTAssertEqual(try limit(.caffeine).value, 400)
        XCTAssertEqual(try limit(.caffeine).singleDose, 200)
        for ingredient in [IngredientID.vitaminB12, .vitaminK2, .sodium, .potassium, .betaAlanine] {
            XCTAssertNil(try limit(ingredient).value, "\(ingredient.rawValue): no limit is invented")
        }
    }

    func testCatalogDosesSitUnderTheirDefaultLimits() {
        for product in SupplementCatalog.all {
            let totals = IngredientTotals.of(product.makeProduct(), servings: 1)
            for (ingredient, amount) in totals.amounts {
                if let limit = EvidenceCatalog.card(for: ingredient)?.limit.value {
                    XCTAssertLessThanOrEqual(amount, limit, "\(product.id): \(ingredient.rawValue)")
                }
            }
        }
    }

    // Spec: Catalog product.
    func testCreatineFromTheCatalogProposesFiveGrams() throws {
        let catalog = try XCTUnwrap(SupplementCatalog.product(id: "creatineMonohydrate"))
        let id = UUID()
        let product = catalog.makeProduct(id: id)

        XCTAssertEqual(product.id, id)
        XCTAssertEqual(product.ingredients, [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)])
        XCTAssertEqual(product.source, .catalog("creatineMonohydrate"))
        XCTAssertEqual(product.form, .powder)
        XCTAssertEqual(product.name, "Creatine monohydrate")
        XCTAssertEqual(product.servingDescription, "5 g scoop")
        XCTAssertEqual(catalog.suggestedSchedule, SupplementSchedule(slots: [.morning], servingsPerSlot: 1, pattern: .daily))
    }

    // Spec: Offline card / No EU upper limit (the data half; the view is wave 3).
    func testVitaminDAndVitaminCCards() throws {
        let vitaminD = try XCTUnwrap(EvidenceCatalog.card(for: .vitaminD))
        XCTAssertEqual(vitaminD.unit, .ug)
        XCTAssertTrue(vitaminD.limit.source.title.contains("EFSA"))
        XCTAssertFalse(EvidenceCatalog.disclaimer.isEmpty)

        let vitaminC = try XCTUnwrap(EvidenceCatalog.card(for: .vitaminC))
        XCTAssertEqual(vitaminC.limitNote, "No EU upper limit set. The US figure is 2000 mg a day.")
        XCTAssertEqual(EvidenceCatalog.noEUUpperLimitText, "No EU upper limit set")
    }

    func testEnglishServingPlurals() {
        XCTAssertEqual(ProductForm.capsule.servingText(count: 1), "1 capsule")
        XCTAssertEqual(ProductForm.capsule.servingText(count: 2), "2 capsules")
        XCTAssertEqual(ProductForm.tablet.servingText(count: 1), "1 tablet")
        XCTAssertEqual(ProductForm.powder.servingText(count: 3), "3 servings")
    }

    func testCzechTextsResolve() throws {
        let bundle = try czechBundle()
        func czech(_ key: String) -> String {
            bundle.localizedString(forKey: key, value: "<missing>", table: nil)
        }
        XCTAssertEqual(czech("Creatine"), "Kreatin")
        XCTAssertEqual(czech("No EU upper limit set"), "V EU není stanoven horní přípustný limit")
        XCTAssertEqual(czech("%lld g scoop"), "odměrka %lld g")
        // 1 and 5 have the same plural category under English and Czech
        // rules (see LocalizationTests), so the assertion holds whichever
        // rules the formatter applies.
        let capsules = czech("%lld capsules")
        XCTAssertNotEqual(capsules, "<missing>")
        XCTAssertEqual(String(format: capsules, locale: Locale(identifier: "cs_CZ"), 1), "1 kapsle")
        XCTAssertEqual(String(format: capsules, locale: Locale(identifier: "cs_CZ"), 5), "5 kapslí")
        XCTAssertEqual(String(format: czech("%lld servings"), locale: Locale(identifier: "cs_CZ"), 5), "5 dávek")
    }
}

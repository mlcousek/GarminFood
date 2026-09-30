// BrandedSupplementCatalogTests.swift
//
// add-custom-ingredients-and-owner-supplements: the bundled branded
// catalog (Resources/branded-supplements.json). Every entry must decode,
// carry at least one active with an amount and a unit that totals
// convert, name only known ingredients, cite an https source and the
// verification date, and list only quality facts the app knows how to
// word. Also pins a few label values that were read off the product pages
// on 2026-09-30 -- a changed number here must be re-checked on the page,
// never "fixed" from memory.

import XCTest
@testable import FoodLogCore

final class BrandedSupplementCatalogTests: XCTestCase {
    private func product(_ id: String) throws -> CatalogProduct {
        try XCTUnwrap(SupplementCatalog.branded.first { $0.id == id }, id)
    }

    private func amount(_ product: CatalogProduct, _ ingredient: IngredientID) -> Double? {
        product.ingredients.filter { $0.ingredient == ingredient }.compactMap(\.amount).reduce(0, +)
    }

    func testTheBundledFileDecodesStrictly() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: SupplementCatalog.brandedResourceName, withExtension: "json"))
        let decoded = try SupplementCatalog.decodeBranded(Data(contentsOf: url))
        XCTAssertEqual(decoded.count, 10)
        XCTAssertEqual(decoded.map(\.id), SupplementCatalog.branded.map(\.id))
    }

    func testEveryEntryHasActivesWithUnitsAndACitedSource() throws {
        let ids = SupplementCatalog.branded.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "branded ids are unique")
        XCTAssertTrue(Set(ids).isDisjoint(with: SupplementCatalog.all.map(\.id)), "no clash with the generic catalog")
        for entry in SupplementCatalog.branded {
            let label = try XCTUnwrap(entry.label, entry.id)
            XCTAssertFalse(entry.ingredients.isEmpty, entry.id)
            for row in entry.ingredients {
                XCTAssertNotNil(row.amount, "\(entry.id): \(row.ingredient.rawValue) has an amount")
                XCTAssertFalse(row.unit.rawValue.isEmpty, "\(entry.id): \(row.ingredient.rawValue) has a unit")
                XCTAssertNotNil(row.canonicalAmount, "\(entry.id): \(row.ingredient.rawValue) converts")
                XCTAssertTrue(IngredientCatalog.isKnown(row.ingredient), "\(entry.id): \(row.ingredient.rawValue) is a known ingredient")
            }
            XCTAssertFalse(label.brand.isEmpty, entry.id)
            XCTAssertFalse(label.productName.isEmpty, entry.id)
            XCTAssertEqual(label.sourceURL.scheme, "https", entry.id)
            XCTAssertEqual(label.verifiedOn, "2026-09-30", entry.id)
            for fact in label.quality {
                XCTAssertTrue(QualityFact.Kind.known.contains(fact.kind), "\(entry.id): \(fact.kind.rawValue)")
                XCTAssertFalse(fact.text.isEmpty)
            }
            if let packServings = label.packServings { XCTAssertGreaterThan(packServings, 0, entry.id) }
            XCTAssertNotNil(label.labelDetails, entry.id)
            XCTAssertEqual(entry.name, label.productName, "a branded name is shown as printed")
        }
    }

    func testMakeProductCarriesBrandBarcodeAndPack() throws {
        let zinc = try product("brainmaxZincComplex")
        let made = zinc.makeProduct()
        XCTAssertEqual(made.name, "BrainMax Zinc Complex®")
        XCTAssertEqual(made.brand, "BrainMax")
        XCTAssertEqual(made.barcode, "8594190020471")
        XCTAssertEqual(made.packServings, 100)
        XCTAssertEqual(made.source, .catalog("brainmaxZincComplex"))
        XCTAssertEqual(made.servingDescription, "1 capsule")
        XCTAssertEqual(SupplementCatalog.product(id: "brainmaxZincComplex")?.label?.brand, "BrainMax")
    }

    func testServingsWithDecimalsAndSachets() throws {
        let joint = try product("alavisMaximaTripleBlend")
        XCTAssertEqual(joint.serving, .measure(grams: 4.5))
        XCTAssertNil(joint.label?.packServings, "the page states 700 g, not a number of servings")
        let sachet = try product("magnosolv365")
        XCTAssertEqual(sachet.serving, .sachet(grams: 6.1))
        XCTAssertTrue(sachet.label?.quality.contains { $0.kind == .registeredMedicine } ?? false)
    }

    /// Values read off the product pages on 2026-09-30.
    func testLabelValuesAsPublished() throws {
        let zinc = try product("brainmaxZincComplex")
        XCTAssertEqual(amount(zinc, .zinc), 15)
        XCTAssertEqual(amount(zinc, .copper), 1)
        XCTAssertEqual(amount(zinc, .selenium), 100)

        let d3k2 = try product("brainmaxVitaminD3K2")
        XCTAssertEqual(IngredientTotals.of(d3k2.makeProduct(), servings: 1).amount(of: .vitaminD), 100, "4000 IU = 100 µg")
        XCTAssertEqual(amount(d3k2, .vitaminK2), 150)

        XCTAssertEqual(amount(try product("brainmaxLiposomalVitaminC"), .vitaminC), 500)
        XCTAssertEqual(amount(try product("brainmaxOmega3HighEPA"), .omega3EPA_DHA), 1600)
        XCTAssertEqual(amount(try product("brainmaxEnergyMagnesium"), .magnesium), 175.5)
        XCTAssertEqual(amount(try product("brainmaxSleepMagnesium"), .magnesium), 250)
        XCTAssertEqual(amount(try product("brainmaxPerformanceMagnesium"), .magnesium), 200)
        XCTAssertEqual(amount(try product("accelerateCreatineMonohydrate"), .creatine), 3)
        XCTAssertEqual(amount(try product("alavisMaximaTripleBlend"), .glucosamine), 1565)
        XCTAssertEqual(amount(try product("magnosolv365"), .magnesium), 365, "169 mg + 196 mg")
    }

    func testAMalformedEntryFailsTheDecode() {
        let badServing = #"{"schemaVersion":1,"products":[{"id":"x","brand":"B","productName":"P","form":"capsule","serving":{"kind":"units"},"suggestedSlot":{"kind":"morning"},"ingredients":[],"sourceURL":"https://example.com","verifiedOn":"2026-09-30"}]}"#
        XCTAssertThrowsError(try SupplementCatalog.decodeBranded(Data(badServing.utf8)))
        let insecure = #"{"schemaVersion":1,"products":[{"id":"x","brand":"B","productName":"P","form":"capsule","serving":{"kind":"units","count":1},"suggestedSlot":{"kind":"morning"},"ingredients":[],"sourceURL":"http://example.com","verifiedOn":"2026-09-30"}]}"#
        XCTAssertThrowsError(try SupplementCatalog.decodeBranded(Data(insecure.utf8)))
    }
}

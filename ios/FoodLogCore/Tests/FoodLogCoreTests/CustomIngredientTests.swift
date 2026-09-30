// CustomIngredientTests.swift
//
// add-custom-ingredients-and-owner-supplements: the owner could not enter
// an ingredient that the picker didn't list. What matters here: a custom
// ingredient survives a relaunch in the plan file, is found by the
// picker's search afterwards (diacritics and case ignored, both
// languages' names for known ones), keeps its own unit through totals
// (ml is never turned into mg), is not created twice under the same name,
// and a plan file written before the field existed still decodes -- while
// one damaged entry doesn't cost the plan. Real stores on unique temp
// paths (LogEntryCoordinatorTests' pattern), no mocks.

import XCTest
@testable import FoodLogCore

final class CustomIngredientTests: XCTestCase {
    private func planURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("custom-ingredients-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("supplement-plan.json")
    }

    // MARK: - Model

    func testMakeTrimsTheNameCarriesTheUnitAndRejectsBlankNames() throws {
        let ingredient = try XCTUnwrap(CustomIngredient.make(name: "  Ashwagandha   KSM-66 ", unit: .mg, form: " root extract "))
        XCTAssertEqual(ingredient.name, "Ashwagandha KSM-66")
        XCTAssertTrue(ingredient.id.isCustom)
        XCTAssertEqual(ingredient.id.canonicalUnit, .mg)
        XCTAssertEqual(ingredient.forms, ["root extract"])
        XCTAssertNil(CustomIngredient.make(name: "   ", unit: .mg))
    }

    func testEveryPickableUnitIsCarriedByTheId() throws {
        for unit in DoseUnit.pickable {
            let ingredient = try XCTUnwrap(CustomIngredient.make(name: "X", unit: unit))
            XCTAssertEqual(ingredient.id.canonicalUnit, unit, unit.rawValue)
        }
        XCTAssertEqual(DoseUnit.pickable, [.mg, .ug, .g, .iu, .ml])
        XCTAssertEqual(IngredientID("ashwagandha").canonicalUnit, .mg, "an old free id still counts in mg")
    }

    func testMillilitresAreTotalledAsMillilitresNeverAsMass() throws {
        let tincture = try XCTUnwrap(CustomIngredient.make(name: "Echinacea tincture", unit: .ml))
        let product = SupplementProduct(
            name: "Tincture",
            ingredients: [IngredientAmount(ingredient: tincture.id, amount: 2.5, unit: .ml, customName: tincture.name)]
        )
        let totals = IngredientTotals.of(product, servings: 2)
        XCTAssertEqual(totals.amount(of: tincture.id), 5)
        XCTAssertTrue(totals.unconverted.isEmpty)

        let inGrams = SupplementProduct(
            name: "Wrong unit",
            ingredients: [IngredientAmount(ingredient: tincture.id, amount: 1, unit: .g)]
        )
        XCTAssertEqual(IngredientTotals.of(inGrams, servings: 1).unconverted, [tincture.id], "g can't become ml")
    }

    func testAddFormPutsTheNewestFirstWithoutDuplicates() throws {
        var ingredient = try XCTUnwrap(CustomIngredient.make(name: "Iodine", unit: .ug, form: "potassium iodide"))
        ingredient.addForm("kelp")
        ingredient.addForm("Potassium Iodide")
        XCTAssertEqual(ingredient.forms, ["Potassium Iodide", "kelp"])
        ingredient.addForm("  ")
        XCTAssertEqual(ingredient.forms.count, 2)
    }

    // MARK: - Store

    func testACustomIngredientSurvivesARelaunchAndIsSearchable() async throws {
        let url = planURL()
        let ingredient = try XCTUnwrap(CustomIngredient.make(name: "Ashwagandha", unit: .mg, form: "KSM-66"))
        try await SupplementPlanStore(fileURL: url).saveCustomIngredient(ingredient)

        let plan = try await SupplementPlanStore(fileURL: url).plan()
        XCTAssertEqual(plan.customIngredientList, [ingredient])
        XCTAssertEqual(plan.ingredientName(ingredient.id), "Ashwagandha")

        let found = IngredientSearch.choices(for: "ashwa", custom: plan.customIngredientList)
        XCTAssertEqual(found.first?.id, ingredient.id)
        XCTAssertEqual(found.first?.isCustom, true)
        XCTAssertEqual(found.first?.unit, .mg)
        XCTAssertFalse(IngredientSearch.canCreate("ASHWAGANDHA", custom: plan.customIngredientList), "no second one with the same name")
        XCTAssertTrue(IngredientSearch.canCreate("Rhodiola", custom: plan.customIngredientList))
    }

    func testTheSameNameIsNotCreatedTwice() async throws {
        let url = planURL()
        let store = SupplementPlanStore(fileURL: url)
        let first = try XCTUnwrap(CustomIngredient.make(name: "Ashwagandha", unit: .mg, form: "KSM-66"))
        try await store.saveCustomIngredient(first)
        let again = try XCTUnwrap(CustomIngredient.make(name: "ashwagandha", unit: .mg, form: "Sensoril"))
        let saved = try await store.saveCustomIngredient(again)

        XCTAssertEqual(saved.id, first.id, "the existing one is reused")
        XCTAssertEqual(saved.forms, ["Sensoril", "KSM-66"])
        let plan = try await SupplementPlanStore(fileURL: url).plan()
        XCTAssertEqual(plan.customIngredientList.count, 1)
    }

    func testAPlanWithoutCustomIngredientsEncodesAsBefore() throws {
        let plan = SupplementPlan()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(plan), as: UTF8.self)
        XCTAssertFalse(json.contains("customIngredients"), json)
    }

    func testOldPlanFilesDecodeAndOneBadEntryIsDropped() throws {
        let old = #"{"items":[],"products":[]}"#
        XCTAssertNil(try JSONDecoder().decode(SupplementPlan.self, from: Data(old.utf8)).customIngredients)

        let mixed = #"""
        {"items":[],"products":[],"customIngredients":[
          {"id":"custom:ml:1","name":"Tincture","unit":"ml","forms":[]},
          {"id":"custom:mg:2"},
          {"id":"custom:mg:3","name":"   "},
          {"id":"zinc","name":"Not custom"},
          {"id":"custom:ug:4","name":"Iodine"}
        ]}
        """#
        let plan = try JSONDecoder().decode(SupplementPlan.self, from: Data(mixed.utf8))
        XCTAssertEqual(plan.customIngredientList.map(\.name), ["Tincture", "Iodine"])
        XCTAssertEqual(plan.customIngredientList.last?.unit, .ug, "a missing unit comes from the id")
    }

    // MARK: - Search over known ingredients

    func testSearchFindsKnownIngredientsInBothLanguagesIgnoringDiacritics() {
        XCTAssertEqual(IngredientSearch.choices(for: "horcik", custom: []).first?.id, .magnesium)
        XCTAssertEqual(IngredientSearch.choices(for: "Hořčík", custom: []).first?.id, .magnesium)
        XCTAssertEqual(IngredientSearch.choices(for: "zinc", custom: []).first?.id, .zinc)
        XCTAssertEqual(IngredientSearch.choices(for: "kurkuma", custom: []).first?.id, .turmeric)
        XCTAssertEqual(IngredientSearch.choices(for: "glukosamin", custom: []).first?.id, .glucosamine)
        XCTAssertTrue(IngredientSearch.choices(for: "qqqq", custom: []).isEmpty)
        XCTAssertTrue(IngredientSearch.canCreate("qqqq", custom: []))
        XCTAssertFalse(IngredientSearch.canCreate("  ", custom: []))
    }

    func testAnEmptyQueryListsCustomFirstThenEveryKnownIngredient() throws {
        let own = try XCTUnwrap(CustomIngredient.make(name: "Ashwagandha", unit: .mg))
        let all = IngredientSearch.choices(for: "", custom: [own])
        XCTAssertEqual(all.first?.id, own.id)
        XCTAssertEqual(Array(all.dropFirst()).map(\.id), IngredientCatalog.known)
        XCTAssertEqual(all.filter(\.hasEvidence).map(\.id), IngredientID.builtIn)
    }

    func testEveryKnownIngredientHasADisplayNameInBothLanguages() throws {
        let path = try XCTUnwrap(Bundle.module.path(forResource: "cs", ofType: "lproj"))
        let czech = try XCTUnwrap(Bundle(path: path))
        for ingredient in IngredientCatalog.known {
            let name = try XCTUnwrap(IngredientCatalog.knownName(of: ingredient), ingredient.rawValue)
            XCTAssertNotEqual(name, ingredient.rawValue, ingredient.rawValue)
            XCTAssertNotEqual(EvidenceCatalog.name(of: ingredient), ingredient.rawValue, ingredient.rawValue)
        }
        XCTAssertEqual(czech.localizedString(forKey: "Turmeric", value: nil, table: nil), "Kurkuma")
        XCTAssertEqual(czech.localizedString(forKey: "Collagen type II", value: nil, table: nil), "Kolagen typu II")
        XCTAssertEqual(Set(IngredientCatalog.known).count, IngredientCatalog.known.count, "no id twice")
    }

    func testSuggestedFormsCoverTheLabelsTheOwnerNamed() {
        XCTAssertTrue(IngredientCatalog.suggestedForms(of: .magnesium).contains("citrate"))
        XCTAssertTrue(IngredientCatalog.suggestedForms(of: .magnesium).contains("malate"))
        XCTAssertTrue(IngredientCatalog.suggestedForms(of: .magnesium).contains("bisglycinate"))
        XCTAssertTrue(IngredientCatalog.suggestedForms(of: .vitaminD).contains("cholecalciferol"))
        XCTAssertTrue(IngredientCatalog.suggestedForms(of: .vitaminK2).contains("MK-7"))
        let own = CustomIngredient(id: .custom(unit: .mg), name: "X", unit: .mg, forms: ["a", "b"])
        XCTAssertEqual(IngredientCatalog.suggestedForms(of: own.id, custom: own), ["a", "b"])
    }
}

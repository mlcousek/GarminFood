// CustomFoodWithoutBackingTests.swift
//
// add-standalone-mode 3.3 (design D5, standalone-food-catalog spec "Custom
// foods don't need a Garmin backing food in standalone mode"): the backing
// food became optional. Old files -- which always carry one -- must decode
// and log exactly as before; a food without one logs with its own macros in
// standalone mode and is refused (never logged silently or dropped) by the
// Garmin coordinator. Real stores and a real Outbox on unique temp files.

import XCTest
@testable import FoodLogCore
import GarminKit

final class CustomFoodWithoutBackingTests: XCTestCase {
    private let day = "2026-09-25"

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("custom-no-backing-\(name)-\(UUID().uuidString)")
    }

    /// Spec "Creating a custom food standalone".
    private func buchty() -> CustomFoodDraft {
        CustomFoodDraft(name: "Babiččiny buchty", servingUnit: "kus", numberOfUnits: 1, calories: 280, carbs: 40, protein: 6, fat: 10, createdAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    /// A custom-foods file exactly as the app wrote it before this change
    /// (synthesized Codable, iso8601 dates, every backing field present).
    private let oldFileJSON = """
    [
      {
        "id": "0E4F7F4C-2C1A-4B1E-9C55-2A3B4C5D6E7F",
        "name": "Domácí tvaroh",
        "servingUnit": "bowl",
        "numberOfUnits": 1,
        "calories": 220,
        "protein": 18,
        "createdAt": "2026-09-20T08:30:00Z",
        "backingFoodId": "garmin-food-42",
        "backingFoodName": "Cottage cheese, plain",
        "backingServingId": "garmin-serving-7",
        "backingQuantityMultiplier": 0.5,
        "backingRegionCode": "CZ",
        "backingLanguageCode": "cs"
      }
    ]
    """

    // MARK: Decoding

    func testAnOldFileDecodesUnchangedAndLogsAsBefore() async throws {
        let url = tempURL("old").appendingPathExtension("json")
        try Data(oldFileJSON.utf8).write(to: url)

        let drafts = await CustomFoodStore(fileURL: url).all()

        let draft = try XCTUnwrap(drafts.first)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(draft.name, "Domácí tvaroh")
        XCTAssertEqual(draft.backingFoodId, "garmin-food-42")
        XCTAssertEqual(draft.backingFoodName, "Cottage cheese, plain")
        XCTAssertEqual(draft.backingServingId, "garmin-serving-7")
        XCTAssertEqual(draft.backingRegionCode, "CZ")
        XCTAssertNil(draft.barcode)
        XCTAssertTrue(draft.hasGarminBacking)
        let target = try XCTUnwrap(draft.resolvedLoggingTarget(quantity: 2))
        XCTAssertEqual(target.foodId, "garmin-food-42")
        XCTAssertEqual(target.servingId, "garmin-serving-7")
        XCTAssertEqual(target.numberOfUnits, 1)
        XCTAssertTrue(draft.discrepancyNote.contains("Cottage cheese, plain"))

        // And it still reaches the outbox as its backing food.
        let outbox = Outbox(processName: "custom-no-backing-\(UUID().uuidString)")
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")))
        _ = try await coordinator.confirmCustomFood(draft, quantity: 2, mealType: .lunch, date: day)
        let queued = await outbox.allEntries()
        XCTAssertEqual(queued.map(\.foodId), ["garmin-food-42"])
        XCTAssertEqual(queued.first?.numberOfUnits, 1)
    }

    func testANewFoodWithoutBackingRoundTripsThroughTheStore() async throws {
        let url = tempURL("new").appendingPathExtension("json")
        var draft = buchty()
        draft.barcode = "8590000000017"

        try await CustomFoodStore(fileURL: url).upsert(draft)
        let reloaded = await CustomFoodStore(fileURL: url).all()

        XCTAssertEqual(reloaded, [draft])
        XCTAssertNil(reloaded.first?.backingFoodId)
        XCTAssertEqual(reloaded.first?.barcode, "8590000000017")
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(raw.contains("backingFoodId"), "absent, not an empty string")
    }

    func testWithoutBackingThereIsNoTargetAndNoNote() {
        let draft = buchty()
        XCTAssertFalse(draft.hasGarminBacking)
        XCTAssertNil(draft.resolvedLoggingTarget(quantity: 1))
        XCTAssertEqual(draft.discrepancyNote, "")
    }

    // MARK: Logging

    /// Standalone: logged as itself, 280 kcal per piece.
    func testStandaloneLogsItWithItsOwnMacros() async throws {
        let log = LocalFoodLogStore(directoryURL: tempURL("log"))
        let coordinator = LocalLogEntryCoordinator(store: log, usageHistory: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")))
        let draft = buchty()

        let (_, note) = try await coordinator.confirmCustomFood(draft, quantity: 2, mealType: .snacks, date: day)

        let entries = try await log.entries(forDay: day)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.customFoodId, draft.id)
        XCTAssertEqual(entries.first?.amount(.calories), 560)
        XCTAssertEqual(note, "")
    }

    /// Garmin mode: asks for a match; nothing is queued.
    func testGarminModeRefusesItBeforeWritingAnything() async throws {
        let outbox = Outbox(processName: "custom-no-backing-\(UUID().uuidString)")
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")))

        do {
            _ = try await coordinator.confirmCustomFood(buchty(), quantity: 1, mealType: .snacks, date: day)
            XCTFail("expected needsGarminMatch")
        } catch {
            XCTAssertEqual(error as? CustomFoodLoggingError, .needsGarminMatch)
        }
        let queued = await outbox.allEntries()
        XCTAssertTrue(queued.isEmpty)
    }

    func testGarminModeRefusesAPresetContainingOneBeforeTheFirstIngredient() async throws {
        let outbox = Outbox(processName: "custom-no-backing-\(UUID().uuidString)")
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")))
        let rohlik = Food(id: "g-1", name: "Rohlík", source: .fatSecret, servings: [Serving(id: "s", unit: "piece", numberOfUnits: 1, calories: 145)])
        let draft = buchty()
        let custom = draft.asFood()
        let preset = MealPreset(name: "Svačina", ingredients: [
            MealPresetIngredient(food: rohlik, serving: rohlik.servings[0], quantity: 1),
            MealPresetIngredient(food: custom, serving: custom.servings[0], quantity: 1, customFoodDraft: draft),
        ])

        do {
            _ = try await coordinator.confirmMealPreset(preset, mealType: .snacks, date: day)
            XCTFail("expected needsGarminMatch")
        } catch {
            XCTAssertEqual(error as? CustomFoodLoggingError, .needsGarminMatch)
        }
        let queued = await outbox.allEntries()
        XCTAssertTrue(queued.isEmpty, "the Garmin ingredient before it must not be queued either")
    }
}

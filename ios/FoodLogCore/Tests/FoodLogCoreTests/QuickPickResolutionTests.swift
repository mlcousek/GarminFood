// QuickPickResolutionTests.swift
//
// `QuickPickResolution.loggable` -- what the quick-pick Controls and the
// "Log usual food" Siri shortcut actually log. The real-device bug it
// fixes: a custom food at the top of the ranking was queued under its
// local UUID with serving "custom", which Garmin rejects. The last test
// runs the whole path against real stores (same pattern as
// LogEntryCoordinatorTests) and checks what lands in the outbox.

import XCTest
@testable import FoodLogCore
import GarminKit

final class QuickPickResolutionTests: XCTestCase {
    private let garminFood = Food(id: "garmin-1", name: "Rohlík", source: .fatSecret, servings: [
        Serving(id: "s-piece", unit: "piece", numberOfUnits: 1, calories: 130),
        Serving(id: "s-100g", unit: "g", numberOfUnits: 100, calories: 290),
    ])

    private let customFood = CustomFoodDraft(
        name: "Domácí tvaroh",
        servingUnit: "bowl",
        numberOfUnits: 1,
        calories: 180,
        backingFoodId: "garmin-42",
        backingFoodName: "Cottage cheese",
        backingServingId: "garmin-serving-7",
        backingQuantityMultiplier: 2
    )

    private func entry(_ foodId: String, _ servingId: String, units: Double = 1) -> QuickPick.Entry {
        QuickPick.Entry(foodId: foodId, servingId: servingId, numberOfUnits: units, score: 1, lastUsedAt: Date(), useCount: 1)
    }

    func testACustomFoodResolvesToItsDraftNotItsCachedSnapshot() {
        // The cache holds the custom food's `asFood()` snapshot under its
        // UUID -- exactly what the old code logged as if it were a Garmin id.
        let cache = [customFood.id.uuidString: customFood.asFood()]

        let resolved = QuickPickResolution.loggable(
            [entry(customFood.id.uuidString, CustomFoodDraft.servingId, units: 2)],
            cache: cache,
            customFoods: [customFood]
        )

        XCTAssertEqual(resolved, [.custom(customFood, quantity: 2)])
    }

    func testACustomFoodWhoseDraftWasDeletedIsSkippedNotSentToGarmin() {
        let cache = [customFood.id.uuidString: customFood.asFood(), garminFood.id: garminFood]

        let resolved = QuickPickResolution.loggable(
            [entry(customFood.id.uuidString, CustomFoodDraft.servingId), entry("garmin-1", "s-piece")],
            cache: cache,
            customFoods: []
        )

        XCTAssertEqual(resolved, [.catalog(food: garminFood, serving: garminFood.servings[0], numberOfUnits: 1)],
                       "the next-best loggable food moves up, like the app's own shelf")
    }

    func testACatalogFoodResolvesWithItsExactServingAndRememberedAmount() {
        let resolved = QuickPickResolution.loggable(
            [entry("garmin-1", "s-100g", units: 1.5)],
            cache: [garminFood.id: garminFood],
            customFoods: []
        )

        XCTAssertEqual(resolved, [.catalog(food: garminFood, serving: garminFood.servings[1], numberOfUnits: 1.5)])
    }

    func testUncachedFoodsAndVanishedServingsAreSkipped() {
        let resolved = QuickPickResolution.loggable(
            [entry("not-cached", "s1"), entry("garmin-1", "gone-serving"), entry("garmin-1", "s-piece")],
            cache: [garminFood.id: garminFood],
            customFoods: []
        )

        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved.first?.displayFood.id, "garmin-1")
    }

    func testRankOrderIsKept() {
        let resolved = QuickPickResolution.loggable(
            [entry(customFood.id.uuidString, CustomFoodDraft.servingId), entry("garmin-1", "s-piece")],
            cache: [garminFood.id: garminFood],
            customFoods: [customFood]
        )

        XCTAssertEqual(resolved.map(\.displayFood.id), [customFood.id.uuidString, "garmin-1"])
        XCTAssertEqual(resolved.first?.displayFood.name, "Domácí tvaroh", "shown as the custom food, not its backing food")
    }

    /// End to end with real stores: a custom food logged once becomes the
    /// #1 quick pick, and logging that pick queues its BACKING Garmin food.
    func testLoggingATopCustomQuickPickQueuesTheBackingFood() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let outbox = Outbox(processName: "foodlogcore-test-\(UUID().uuidString)")
        let usageHistory = UsageHistoryStore(fileURL: tmp.appendingPathComponent("qp-usage-\(UUID().uuidString).json"))
        let servingDefaults = ServingDefaultStore(fileURL: tmp.appendingPathComponent("qp-defaults-\(UUID().uuidString).json"))
        let foodCache = FoodCacheStore(fileURL: tmp.appendingPathComponent("qp-cache-\(UUID().uuidString).json"))
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults, foodCache: foodCache)
        // What CustomFoodEditorView does on save.
        await foodCache.upsert([customFood.asFood()])
        _ = try await coordinator.confirmCustomFood(customFood, quantity: 1.5, mealType: .breakfast, date: "2026-09-22")

        let ranked = QuickPick.rank(events: await usageHistory.all())
        let resolved = QuickPickResolution.loggable(ranked, cache: await foodCache.all(), customFoods: [customFood])
        guard case .custom(let draft, let quantity)? = resolved.first else {
            return XCTFail("expected the custom food to resolve through its draft, got \(resolved)")
        }
        _ = try await coordinator.confirmCustomFood(draft, quantity: quantity, mealType: .lunch, date: "2026-09-23")

        let queued = await outbox.allEntries().filter { $0.date == "2026-09-23" }
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.foodId, "garmin-42", "never the custom food's local UUID")
        XCTAssertEqual(queued.first?.servingId, "garmin-serving-7", "never the placeholder \"custom\" serving")
        XCTAssertEqual(queued.first?.numberOfUnits, 3, "1.5 remembered x the draft's 2x multiplier")
    }
}

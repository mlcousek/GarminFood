// ShortcutLoggingRulesTests.swift
//
// add-standalone-mode 3.6 (design D5, spec "Meal presets, quick picks, Siri
// and Controls log through the current mode"): what Siri searches and may
// log per mode, that only Garmin mode waits for Garmin delivery, and which
// quick picks Garmin can't take. Garmin mode must answer exactly as before.
// Plus the spec scenario "Siri in standalone mode" end to end at the
// FoodLogCore level: a food from her own foods, logged through the real
// mode-routing proxy, lands in the local log (real stores on temp files).

import XCTest
@testable import FoodLogCore
import GarminKit

final class ShortcutLoggingRulesTests: XCTestCase {
    private let rohlik = Food(id: "g-1", name: "Rohlík", source: .garmin, servings: [Serving(id: "s", unit: "piece", numberOfUnits: 1, calories: 145)])
    private let tvaroh = Food(id: "8594003963391", name: "Tvaroh odtučněný", source: .openFoodFacts, servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100, calories: 67, carbs: 4, protein: 12, fat: 0.5)])
    private let noCalories = Food(id: "859-x", name: "Neznámý sýr", source: .openFoodFacts, servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100)])
    private let buchty = CustomFoodDraft(name: "Babiččiny buchty", servingUnit: "kus", numberOfUnits: 1, calories: 280, carbs: 40, protein: 6, fat: 10)

    private func result(_ food: Food, _ origin: SearchOrigin, draft: CustomFoodDraft? = nil) -> SearchResult {
        SearchResult(food: food, origin: origin, score: 1, textScore: 1, coversQuery: true, customDraft: draft)
    }

    func testSiriSearchesNoGarminAndNoLiveOpenFoodFactsStandalone() {
        XCTAssertEqual(ShortcutLoggingRules.siriSearchOrigins(in: .garminConnected), [.local, .garmin], "unchanged for the owner")
        XCTAssertEqual(ShortcutLoggingRules.siriSearchOrigins(in: .standalone), [.local, .offlineIndex])
    }

    func testGarminModeKeepsTodaysLoggableRule() {
        XCTAssertTrue(ShortcutLoggingRules.siriCanLog(result(rohlik, .garmin), in: .garminConnected))
        XCTAssertTrue(ShortcutLoggingRules.siriCanLog(result(rohlik, .local), in: .garminConnected))
        XCTAssertFalse(ShortcutLoggingRules.siriCanLog(result(tvaroh, .offlineIndex), in: .garminConnected))
        XCTAssertFalse(ShortcutLoggingRules.siriCanLog(result(buchty.asFood(), .local, draft: buchty), in: .garminConnected))
    }

    func testStandaloneLogsHerOwnFoodsAndTheIndexButNotWithoutCalories() {
        XCTAssertTrue(ShortcutLoggingRules.siriCanLog(result(buchty.asFood(), .local, draft: buchty), in: .standalone))
        XCTAssertTrue(ShortcutLoggingRules.siriCanLog(result(tvaroh, .offlineIndex), in: .standalone))
        XCTAssertTrue(ShortcutLoggingRules.siriCanLog(result(tvaroh, .local), in: .standalone))
        XCTAssertFalse(ShortcutLoggingRules.siriCanLog(result(noCalories, .offlineIndex), in: .standalone))
    }

    func testOnlyGarminModeWaitsForDelivery() {
        XCTAssertTrue(ShortcutLoggingRules.waitsForGarminDelivery(in: .garminConnected))
        XCTAssertFalse(ShortcutLoggingRules.waitsForGarminDelivery(in: .standalone))
    }

    func testDefaultQuantity() {
        XCTAssertEqual(ShortcutLoggingRules.siriDefaultQuantity(for: tvaroh.servings[0], in: .garminConnected), 100, "unchanged for the owner")
        XCTAssertEqual(ShortcutLoggingRules.siriDefaultQuantity(for: tvaroh.servings[0], in: .standalone), 1, "one 100 g serving, never 10 kg")
    }

    func testQuickPicksGarminCannotTake() {
        XCTAssertFalse(QuickPickLogTarget.catalog(food: rohlik, serving: rohlik.servings[0], numberOfUnits: 1).needsGarminMatch)
        XCTAssertTrue(QuickPickLogTarget.catalog(food: tvaroh, serving: tvaroh.servings[0], numberOfUnits: 1).needsGarminMatch)
        XCTAssertTrue(QuickPickLogTarget.custom(buchty, quantity: 1).needsGarminMatch)
        var backed = buchty
        backed.backingFoodId = "g-1"
        backed.backingFoodName = "Rohlík"
        backed.backingServingId = "s"
        XCTAssertFalse(QuickPickLogTarget.custom(backed, quantity: 1).needsGarminMatch)
    }

    /// Spec "Siri in standalone mode": her own food, through the proxy the
    /// intents use, is committed to the local log; the Garmin outbox stays
    /// empty.
    func testAStandaloneLogThroughTheProxyIsLocal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shortcut-rules-\(UUID().uuidString)")
        let usage = UsageHistoryStore(fileURL: dir.appendingPathComponent("usage.json"))
        let outbox = Outbox(processName: "shortcut-rules-\(UUID().uuidString)")
        let log = LocalFoodLogStore(directoryURL: dir.appendingPathComponent("log"))
        let proxy = ModeRoutingFoodLogging(
            garmin: LogEntryCoordinator(outbox: outbox, usageHistory: usage),
            local: LocalLogEntryCoordinator(store: log, usageHistory: usage),
            mode: { .standalone }
        )

        _ = try await proxy.confirmCustomFood(buchty, quantity: 1, mealType: .snacks, date: "2026-09-25")

        let entries = try await log.entries(forDay: "2026-09-25")
        XCTAssertEqual(entries.map(\.food.name), ["Babiččiny buchty"])
        XCTAssertEqual(entries.first?.amount(.calories), 280)
        let queued = await outbox.allEntries()
        XCTAssertTrue(queued.isEmpty)
    }
}

// StandaloneCatalogTests.swift
//
// add-standalone-mode 3.2 (design D5, standalone-food-catalog spec "Search
// and log foods without a Garmin food identity"): which search origins log
// directly in each mode, when a serving's nutrition is complete enough to
// log standalone, and that the local coordinator enforces the calorie rule
// and remembers a logged Open Food Facts product for Quick pick / search.
// Real stores on unique temp files (LogEntryCoordinatorTests convention).

import XCTest
@testable import FoodLogCore
import GarminKit

final class StandaloneCatalogTests: XCTestCase {
    private let day = "2026-09-25"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("standalone-catalog-\(name)-\(UUID().uuidString)")
    }

    private func offProduct(calories: Double?, protein: Double? = 12) -> Food {
        Food(
            id: "8594003963391",
            name: "Tvaroh odtučněný",
            brandName: "Billa",
            source: .openFoodFacts,
            servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100, calories: calories, carbs: 4, protein: protein, fat: 0.5)]
        )
    }

    // MARK: SearchOrigin.isDirectlyLoggable(in:)

    func testEveryOriginLogsDirectlyInStandaloneMode() {
        for origin in SearchOrigin.allCases {
            XCTAssertTrue(origin.isDirectlyLoggable(in: .standalone), "\(origin)")
        }
    }

    func testGarminModeKeepsTodaysRule() {
        XCTAssertTrue(SearchOrigin.local.isDirectlyLoggable(in: .garminConnected))
        XCTAssertTrue(SearchOrigin.garmin.isDirectlyLoggable(in: .garminConnected))
        XCTAssertFalse(SearchOrigin.offlineIndex.isDirectlyLoggable(in: .garminConnected))
        XCTAssertFalse(SearchOrigin.openFoodFacts.isDirectlyLoggable(in: .garminConnected))
        for origin in SearchOrigin.allCases {
            XCTAssertEqual(origin.isDirectlyLoggable, origin.isDirectlyLoggable(in: .garminConnected))
        }
    }

    // MARK: NutritionCompleteness

    func testCompleteness() {
        XCTAssertEqual(Serving(id: "a", unit: "g", numberOfUnits: 100, calories: 67, carbs: 4, protein: 12, fat: 0.5).completeness, .complete)
        XCTAssertEqual(Serving(id: "b", unit: "g", numberOfUnits: 100, calories: 67, carbs: 4, fat: 0.5).completeness, .someValuesMissing)
        XCTAssertEqual(Serving(id: "c", unit: "g", numberOfUnits: 100, carbs: 4, protein: 12, fat: 0.5).completeness, .caloriesUnknown)
        XCTAssertEqual(Serving(id: "d", unit: "g", numberOfUnits: 100, calories: .nan).completeness, .caloriesUnknown)
        XCTAssertEqual(Serving(id: "e", unit: "ml", numberOfUnits: 250, calories: 0, carbs: 0, protein: 0, fat: 0).completeness, .complete, "zero calories is a known value")
        XCTAssertTrue(NutritionCompleteness.someValuesMissing.isLoggable)
        XCTAssertFalse(NutritionCompleteness.caloriesUnknown.isLoggable)
    }

    // MARK: LocalLogEntryCoordinator

    private struct Stores {
        let log: LocalFoodLogStore
        let usage: UsageHistoryStore
        let cache: FoodCacheStore
        let coordinator: LocalLogEntryCoordinator
    }

    private func makeStores() -> Stores {
        let log = LocalFoodLogStore(directoryURL: tempURL("log"))
        let usage = UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json"))
        let servings = ServingDefaultStore(fileURL: tempURL("servings").appendingPathExtension("json"))
        let cache = FoodCacheStore(fileURL: tempURL("cache").appendingPathExtension("json"))
        return Stores(
            log: log,
            usage: usage,
            cache: cache,
            coordinator: LocalLogEntryCoordinator(store: log, usageHistory: usage, servingDefaults: servings, foodCache: cache)
        )
    }

    /// Spec "Logging an Open Food Facts result": logged locally as itself,
    /// and remembered so Quick pick / her own foods can show it.
    func testAnOpenFoodFactsProductLogsAsItselfAndIsCached() async throws {
        let stores = makeStores()
        let product = offProduct(calories: 67)

        try await stores.coordinator.confirm(food: product, serving: product.servings[0], numberOfUnits: 2.5, mealType: .breakfast, date: day, now: now)

        let entries = try await stores.log.entries(forDay: day)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.food.id, "8594003963391")
        XCTAssertEqual(entries.first?.food.source, .openFoodFacts)
        XCTAssertEqual(entries.first?.amount(.calories) ?? 0, 167.5, accuracy: 0.001)
        let cached = await stores.cache.food(forId: "8594003963391")
        XCTAssertEqual(cached, product)
    }

    /// A missing macro is logged as unknown, never as a stored zero.
    func testAMissingMacroStaysUnknown() async throws {
        let stores = makeStores()
        let product = offProduct(calories: 67, protein: nil)

        try await stores.coordinator.confirm(food: product, serving: product.servings[0], numberOfUnits: 1, mealType: .lunch, date: day, now: now)

        let entries = try await stores.log.entries(forDay: day)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertNil(entry.amount(.protein))
        XCTAssertEqual(entry.amount(.calories), 67)
    }

    /// Spec "Result without calories": it can't be confirmed; nothing is
    /// written, nothing is recorded.
    func testAProductWithoutCaloriesIsRefused() async throws {
        let stores = makeStores()
        let product = offProduct(calories: nil)

        do {
            try await stores.coordinator.confirm(food: product, serving: product.servings[0], numberOfUnits: 1, mealType: .lunch, date: day, now: now)
            XCTFail("expected caloriesUnknown")
        } catch {
            XCTAssertEqual(error as? StandaloneLoggingError, .caloriesUnknown)
        }
        let entries = try await stores.log.entries(forDay: day)
        XCTAssertTrue(entries.isEmpty)
        let usage = await stores.usage.all()
        XCTAssertTrue(usage.isEmpty)
    }

    func testAPresetWithACalorieLessIngredientLogsNothing() async throws {
        let stores = makeStores()
        let good = offProduct(calories: 67)
        let bad = Food(id: "859-x", name: "Neznámý sýr", source: .openFoodFacts, servings: [Serving(id: "100g", unit: "g", numberOfUnits: 100)])
        let preset = MealPreset(name: "Snídaně", ingredients: [
            MealPresetIngredient(food: good, serving: good.servings[0], quantity: 1),
            MealPresetIngredient(food: bad, serving: bad.servings[0], quantity: 1),
        ])

        do {
            try await stores.coordinator.confirmMealPreset(preset, mealType: .breakfast, date: day, now: now)
            XCTFail("expected caloriesUnknown")
        } catch {
            XCTAssertEqual(error as? StandaloneLoggingError, .caloriesUnknown)
        }
        let entries = try await stores.log.entries(forDay: day)
        XCTAssertTrue(entries.isEmpty)
    }

    /// Garmin/FatSecret foods are not cached by the local coordinator (the
    /// parity with Garmin mode in LocalLogEntryCoordinatorTests holds).
    func testAGarminFoodIsNotCachedByTheCoordinator() async throws {
        let stores = makeStores()
        let garminFood = Food(id: "g-1", name: "Rohlík", source: .fatSecret, servings: [Serving(id: "s", unit: "piece", numberOfUnits: 1, calories: 145)])

        try await stores.coordinator.confirm(food: garminFood, serving: garminFood.servings[0], numberOfUnits: 1, mealType: .breakfast, date: day, now: now)

        let cached = await stores.cache.food(forId: "g-1")
        XCTAssertNil(cached)
    }
}

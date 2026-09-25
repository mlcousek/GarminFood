// LocalLogEntryCoordinatorTests.swift
//
// add-standalone-mode 2.2 (design D4, local-food-log spec): standalone
// mode's writes. Nutrients are snapshotted as serving x quantity, a custom
// food logs its OWN macros, presets and copies land as whole meals, edits
// rescale in place, deletes remove the entry -- and the bookkeeping other
// features read in both modes (usage history, remembered servings, food
// cache) ends up exactly as the Garmin `LogEntryCoordinator` leaves it.
// Real stores on unique temp files, as in LogEntryCoordinatorTests; no
// mocks.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LocalLogEntryCoordinatorTests: XCTestCase {
    private let day = "2026-09-25"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Stores {
        let log: LocalFoodLogStore
        let usage: UsageHistoryStore
        let servings: ServingDefaultStore
        let cache: FoodCacheStore
        let directory: URL
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("local-coordinator-\(name)-\(UUID().uuidString)")
    }

    private func makeStores() -> Stores {
        let directory = tempURL("log")
        return Stores(
            log: LocalFoodLogStore(directoryURL: directory),
            usage: UsageHistoryStore(fileURL: tempURL("usage").appendingPathExtension("json")),
            servings: ServingDefaultStore(fileURL: tempURL("servings").appendingPathExtension("json")),
            cache: FoodCacheStore(fileURL: tempURL("cache").appendingPathExtension("json")),
            directory: directory
        )
    }

    private func makeCoordinator(_ stores: Stores) -> LocalLogEntryCoordinator {
        LocalLogEntryCoordinator(store: stores.log, usageHistory: stores.usage, servingDefaults: stores.servings, foodCache: stores.cache)
    }

    /// 100 g serving, 120 kcal (the spec's "Logging offline" scenario).
    private let yoghurt = Food(
        id: "food-1",
        name: "Yoghurt",
        source: .garmin,
        servings: [Serving(id: "serving-100g", unit: "g", numberOfUnits: 100, calories: 120, carbs: 10, protein: 8, fat: 4, sodium: 50)]
    )

    private func customFood(calories: Double = 200) -> CustomFoodDraft {
        CustomFoodDraft(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            name: "Babiččiny buchty",
            servingUnit: "piece",
            numberOfUnits: 1,
            calories: calories,
            carbs: 30,
            protein: 5,
            fat: 7,
            backingFoodId: "garmin-bun",
            backingFoodName: "Sweet bun",
            backingServingId: "garmin-bun-serving",
            backingQuantityMultiplier: 2
        )
    }

    /// The dashboard row for a local entry: `.synced(logId: id)`, as
    /// `LocalNutritionReader` presents it.
    private func row(for receipt: OutboxEntry, serving: Serving?, quantity: Double, meal: MealType, foodId: String) -> MealEntry {
        MealEntry(
            id: receipt.id.uuidString,
            foodId: foodId,
            name: "row",
            brandName: nil,
            servingQty: quantity,
            servingDescription: nil,
            calories: nil,
            carbs: nil,
            protein: nil,
            fat: nil,
            status: .synced(logId: receipt.id.uuidString),
            mealType: meal,
            servingId: serving?.id,
            serving: serving
        )
    }

    // MARK: Confirm

    func testConfirmSnapshotsServingTimesQuantityAndSurvivesARelaunch() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)

        let receipt = try await coordinator.confirm(food: yoghurt, serving: yoghurt.servings[0], numberOfUnits: 1.5, mealType: .breakfast, date: day, now: now)

        // A fresh store on the same directory = the app relaunched.
        let reopened = LocalFoodLogStore(directoryURL: stores.directory)
        let entries = try await reopened.entries(forDay: day)
        XCTAssertEqual(entries.map(\.id), [receipt.id])
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.amount(.calories) ?? 0, 180, accuracy: 0.0001)
        XCTAssertEqual(entry.amount(.protein) ?? 0, 12, accuracy: 0.0001)
        XCTAssertEqual(entry.amount(.sodium) ?? 0, 75, accuracy: 0.0001)
        XCTAssertNil(entry.amount(.fiber), "a nutrient the food didn't state stays absent, never a fabricated 0")
        XCTAssertEqual(entry.mealType, .breakfast)
        XCTAssertEqual(entry.servingId, "serving-100g")
        XCTAssertEqual(entry.quantity, 1.5)
        XCTAssertEqual(entry.food.source, .garmin)
        XCTAssertEqual(receipt.state, .sent, "a receipt only: nothing is queued for delivery")
    }

    func testAnInvalidQuantityWritesNothing() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)

        do {
            _ = try await coordinator.confirm(food: yoghurt, serving: yoghurt.servings[0], numberOfUnits: 0, mealType: .lunch, date: day, now: now)
            XCTFail("expected a throw")
        } catch let error as LogQuantityError {
            XCTAssertEqual(error, .outOfRange)
        }
        let entries = try await stores.log.entries(forDay: day)
        XCTAssertTrue(entries.isEmpty)
        let usage = await stores.usage.all()
        XCTAssertTrue(usage.isEmpty)
    }

    func testACustomFoodLogsItsOwnMacrosNeverTheBackingFoods() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let draft = customFood()

        let (receipt, note) = try await coordinator.confirmCustomFood(draft, quantity: 2, mealType: .snacks, date: day, now: now)

        XCTAssertEqual(note, "", "no Garmin food stands in for it, so there is no discrepancy to explain")
        let logged = try await stores.log.entries(forDay: day)
        let entry = try XCTUnwrap(logged.first)
        XCTAssertEqual(entry.id, receipt.id)
        XCTAssertEqual(entry.food.id, draft.id.uuidString)
        XCTAssertEqual(entry.food.source, .custom)
        XCTAssertEqual(entry.customFoodId, draft.id)
        XCTAssertEqual(entry.servingId, CustomFoodDraft.servingId)
        XCTAssertEqual(entry.quantity, 2, "the custom food's own servings, not the backing multiplier")
        XCTAssertEqual(entry.amount(.calories) ?? 0, 400, accuracy: 0.0001)
        XCTAssertEqual(entry.amount(.carbs) ?? 0, 60, accuracy: 0.0001)
    }

    func testASnapshotSurvivesAnEditOfTheCustomFood() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        _ = try await coordinator.confirmCustomFood(customFood(calories: 200), quantity: 1, mealType: .lunch, date: "2026-09-24", now: now)

        // The food is edited today and logged again.
        _ = try await coordinator.confirmCustomFood(customFood(calories: 250), quantity: 1, mealType: .lunch, date: day, now: now)

        let yesterday = try await stores.log.entries(forDay: "2026-09-24")
        XCTAssertEqual(yesterday.first?.amount(.calories), 200)
        let today = try await stores.log.entries(forDay: day)
        XCTAssertEqual(today.first?.amount(.calories), 250)
    }

    func testAPresetLandsAsOneMealWithEveryIngredientScaled() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let draft = customFood()
        let custom = draft.asFood()
        let preset = MealPreset(name: "Breakfast", ingredients: [
            MealPresetIngredient(food: yoghurt, serving: yoghurt.servings[0], quantity: 2),
            MealPresetIngredient(food: custom, serving: custom.servings[0], quantity: 1, customFoodDraft: draft),
        ])

        let receipts = try await coordinator.confirmMealPreset(preset, servingsMultiplier: 0.5, mealType: .breakfast, date: day, now: now)

        let entries = try await stores.log.entries(forDay: day)
        XCTAssertEqual(entries.map(\.id), receipts.map(\.id))
        XCTAssertEqual(entries.map(\.presetId), [preset.id, preset.id])
        XCTAssertEqual(entries.map(\.mealType), [.breakfast, .breakfast])
        XCTAssertEqual(entries[0].amount(.calories) ?? 0, 120, accuracy: 0.0001, "2 x 0.5 servings of 120 kcal")
        XCTAssertEqual(entries[1].amount(.calories) ?? 0, 100, accuracy: 0.0001, "the custom food's own 200 kcal, halved")
        XCTAssertEqual(entries[1].customFoodId, draft.id)
    }

    func testAPresetWithOneBadQuantityLogsNothing() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let preset = MealPreset(name: "Bad", ingredients: [
            MealPresetIngredient(food: yoghurt, serving: yoghurt.servings[0], quantity: 1),
            MealPresetIngredient(food: yoghurt, serving: yoghurt.servings[0], quantity: -1),
        ])

        do {
            _ = try await coordinator.confirmMealPreset(preset, mealType: .lunch, date: day, now: now)
            XCTFail("expected a throw")
        } catch let error as LogQuantityError {
            XCTAssertEqual(error, .outOfRange)
        }
        let entries = try await stores.log.entries(forDay: day)
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: Edit, duplicate, copy

    func testAnEditRescalesTheNutrientsAndMovesTheMealInPlace() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let serving = yoghurt.servings[0]
        let receipt = try await coordinator.confirm(food: yoghurt, serving: serving, numberOfUnits: 1, mealType: .breakfast, date: day, now: now)
        let later = now.addingTimeInterval(60)

        _ = try await coordinator.edit(
            row(for: receipt, serving: serving, quantity: 1, meal: .breakfast, foodId: yoghurt.id),
            date: day, newQuantity: 1.5, newMeal: .lunch, now: later
        )

        let entries = try await stores.log.entries(forDay: day)
        XCTAssertEqual(entries.count, 1, "changed in place, not a new entry plus a delete")
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, receipt.id)
        XCTAssertEqual(entry.quantity, 1.5)
        XCTAssertEqual(entry.mealType, .lunch)
        XCTAssertEqual(entry.amount(.calories) ?? 0, 180, accuracy: 0.0001)
        XCTAssertEqual(entry.amount(.sodium) ?? 0, 75, accuracy: 0.0001)
        XCTAssertEqual(entry.editedAt, later)
        let remembered = await stores.servings.defaultServing(forFoodId: yoghurt.id)
        XCTAssertEqual(remembered?.numberOfUnits, 1.5)
        let usage = await stores.usage.all()
        XCTAssertEqual(usage.count, 1, "an edit isn't another thing eaten")
    }

    func testAnEditWithNothingChangedIsRefused() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let serving = yoghurt.servings[0]
        let receipt = try await coordinator.confirm(food: yoghurt, serving: serving, numberOfUnits: 1, mealType: .breakfast, date: day, now: now)

        do {
            _ = try await coordinator.edit(row(for: receipt, serving: serving, quantity: 1, meal: .breakfast, foodId: yoghurt.id), date: day, newQuantity: 1, newMeal: .breakfast, now: now)
            XCTFail("expected a throw")
        } catch let error as LogEntryEditError {
            XCTAssertEqual(error, .noChange)
        }
    }

    func testEditingAnEntryThatIsGoneSaysSo() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let serving = yoghurt.servings[0]
        let receipt = try await coordinator.confirm(food: yoghurt, serving: serving, numberOfUnits: 1, mealType: .breakfast, date: day, now: now)
        try await coordinator.deleteCommitted(logId: receipt.id.uuidString, date: day)

        do {
            _ = try await coordinator.edit(row(for: receipt, serving: serving, quantity: 1, meal: .breakfast, foodId: yoghurt.id), date: day, newQuantity: 2, newMeal: .breakfast, now: now)
            XCTFail("expected a throw")
        } catch let error as LogEntryEditError {
            XCTAssertEqual(error, .entryGone)
        }
    }

    func testDuplicateAppendsTheSameSnapshotAgain() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let serving = yoghurt.servings[0]
        let receipt = try await coordinator.confirm(food: yoghurt, serving: serving, numberOfUnits: 2, mealType: .snacks, date: day, now: now)

        let copy = try await coordinator.duplicate(row(for: receipt, serving: serving, quantity: 2, meal: .snacks, foodId: yoghurt.id), date: day, now: now)

        let entries = try await stores.log.entries(forDay: day)
        XCTAssertEqual(entries.map(\.id), [receipt.id, copy.id])
        XCTAssertNotEqual(copy.id, receipt.id)
        XCTAssertEqual(entries[1].nutrients, entries[0].nutrients)
        XCTAssertEqual(entries[1].mealType, .snacks)
        let usage = await stores.usage.all()
        XCTAssertEqual(usage.count, 2, "a duplicate is another thing eaten")
    }

    func testCopyingALocalMealKeepsEveryNutrientOfTheOriginal() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let source = try await coordinator.confirm(food: yoghurt, serving: yoghurt.servings[0], numberOfUnits: 1, mealType: .breakfast, date: "2026-09-20", now: now)
        // As CopyMealPlanner builds it from a read-back: id = the source's
        // logId, only the four headline nutrients in its serving.
        let item = CopyableMealItem(
            id: source.id.uuidString, foodId: yoghurt.id, servingId: "serving-100g", servingQty: 1, name: "Yoghurt",
            serving: Serving(id: "serving-100g", unit: "g", numberOfUnits: 100, calories: 120)
        )

        let receipts = try await coordinator.copyMeal([item], to: .lunch, date: day, now: now)

        let copiedDay = try await stores.log.entries(forDay: day)
        let copied = try XCTUnwrap(copiedDay.first)
        XCTAssertEqual(copied.id, receipts.first?.id)
        XCTAssertEqual(copied.mealType, .lunch)
        XCTAssertEqual(copied.amount(.sodium), 50, "taken from the original snapshot, not the thinner read-back")
        let original = try await stores.log.entries(forDay: "2026-09-20")
        XCTAssertEqual(original.map(\.id), [source.id], "the source day is untouched")
    }

    func testCopyingAnItemTheLocalLogDoesNotHaveUsesItsServing() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let item = CopyableMealItem(
            id: "not-a-uuid", foodId: "food-9", servingId: "s9", servingQty: 2, name: "Rohlík",
            serving: Serving(id: "s9", unit: "piece", numberOfUnits: 1, calories: 150, protein: 5)
        )
        let quickAddLike = CopyableMealItem(id: "item-1", foodId: "food-8", servingId: "s8", servingQty: 1, name: "Tea", calories: 20)
        let invalid = CopyableMealItem(id: "item-2", foodId: "food-7", servingId: "s7", servingQty: 0, name: "Nothing")

        let receipts = try await coordinator.copyMeal([item, quickAddLike, invalid], to: .dinner, date: day, now: now)

        let entries = try await stores.log.entries(forDay: day)
        XCTAssertEqual(entries.map(\.id), receipts.map(\.id))
        XCTAssertEqual(entries.count, 2, "an invalid quantity is skipped, as in Garmin mode")
        XCTAssertEqual(entries[0].amount(.calories), 300)
        XCTAssertEqual(entries[0].amount(.protein), 10)
        XCTAssertEqual(entries[1].amount(.calories), 20, "no serving: the row's own calories")
    }

    // MARK: Delete

    func testDeleteCommittedRemovesTheEntry() async throws {
        let stores = makeStores()
        let coordinator = makeCoordinator(stores)
        let keep = try await coordinator.confirm(food: yoghurt, serving: yoghurt.servings[0], numberOfUnits: 1, mealType: .lunch, date: day, now: now)
        let remove = try await coordinator.confirm(food: yoghurt, serving: yoghurt.servings[0], numberOfUnits: 2, mealType: .lunch, date: day, now: now)

        try await coordinator.deleteCommitted(logId: remove.id.uuidString, date: day)

        let entries = try await stores.log.entries(forDay: day)
        XCTAssertEqual(entries.map(\.id), [keep.id])
    }

    func testDeletingSomethingUnknownSaysItIsGone() async throws {
        let coordinator = makeCoordinator(makeStores())

        for logId in ["garmin-12345", UUID().uuidString] {
            do {
                try await coordinator.deleteCommitted(logId: logId, date: day)
                XCTFail("expected a throw for \(logId)")
            } catch let error as LogEntryEditError {
                XCTAssertEqual(error, .entryGone)
            }
        }
    }

    // MARK: Same bookkeeping as Garmin mode

    func testUsageServingMemoryAndFoodCacheEndUpAsGarminModeLeavesThem() async throws {
        let local = makeStores()
        let localCoordinator = makeCoordinator(local)
        let garmin = makeStores()
        let outbox = Outbox(processName: "local-coordinator-parity-\(UUID().uuidString)")
        let garminCoordinator = LogEntryCoordinator(outbox: outbox, usageHistory: garmin.usage, servingDefaults: garmin.servings, foodCache: garmin.cache)

        let draft = customFood()
        let custom = draft.asFood()
        let preset = MealPreset(name: "Snack", ingredients: [
            MealPresetIngredient(food: yoghurt, serving: yoghurt.servings[0], quantity: 1),
            MealPresetIngredient(food: custom, serving: custom.servings[0], quantity: 2, customFoodDraft: draft),
        ])
        let serving = yoghurt.servings[0]
        let copyItem = CopyableMealItem(id: "item-0", foodId: "food-c", servingId: "s-c", servingQty: 3, name: "Copied", serving: Serving(id: "s-c", unit: "g", numberOfUnits: 10, calories: 5))

        // The same actions, the same moments, in both modes.
        let localFirst = try await localCoordinator.confirm(food: yoghurt, serving: serving, numberOfUnits: 1.5, mealType: .breakfast, date: day, now: now)
        let garminFirst = try await garminCoordinator.confirm(food: yoghurt, serving: serving, numberOfUnits: 1.5, mealType: .breakfast, date: day, now: now)
        _ = try await localCoordinator.confirmCustomFood(draft, quantity: 1, mealType: .lunch, date: day, now: now)
        _ = try await garminCoordinator.confirmCustomFood(draft, quantity: 1, mealType: .lunch, date: day, now: now)
        _ = try await localCoordinator.confirmMealPreset(preset, mealType: .snacks, date: day, now: now)
        _ = try await garminCoordinator.confirmMealPreset(preset, mealType: .snacks, date: day, now: now)

        let editTime = now.addingTimeInterval(10)
        let localRow = row(for: localFirst, serving: serving, quantity: 1.5, meal: .breakfast, foodId: yoghurt.id)
        let garminRow = MealEntry(
            id: garminFirst.id.uuidString, foodId: yoghurt.id, name: "row", brandName: nil, servingQty: 1.5, servingDescription: nil,
            calories: nil, carbs: nil, protein: nil, fat: nil, status: .syncing(outboxId: garminFirst.id),
            mealType: .breakfast, servingId: serving.id, serving: serving
        )
        _ = try await localCoordinator.edit(localRow, date: day, newQuantity: 2, newMeal: .breakfast, now: editTime)
        _ = try await garminCoordinator.edit(garminRow, date: day, newQuantity: 2, newMeal: .breakfast, now: editTime)

        let duplicateTime = now.addingTimeInterval(20)
        let localEdited = row(for: localFirst, serving: serving, quantity: 2, meal: .breakfast, foodId: yoghurt.id)
        let garminEdited = MealEntry(
            id: garminFirst.id.uuidString, foodId: yoghurt.id, name: "row", brandName: nil, servingQty: 2, servingDescription: nil,
            calories: nil, carbs: nil, protein: nil, fat: nil, status: .syncing(outboxId: garminFirst.id),
            mealType: .breakfast, servingId: serving.id, serving: serving
        )
        _ = try await localCoordinator.duplicate(localEdited, date: day, now: duplicateTime)
        _ = try await garminCoordinator.duplicate(garminEdited, date: day, now: duplicateTime)
        _ = try await localCoordinator.copyMeal([copyItem], to: .dinner, date: day, now: duplicateTime)
        _ = try await garminCoordinator.copyMeal([copyItem], to: .dinner, date: day, now: duplicateTime)

        let localUsage = await local.usage.all()
        let garminUsage = await garmin.usage.all()
        XCTAssertEqual(localUsage, garminUsage)
        XCTAssertEqual(localUsage.count, 6, "confirm, custom, 2 preset ingredients, duplicate, copy -- not the edit")

        let localDefaults = await local.servings.all().sorted { $0.foodId < $1.foodId }
        let garminDefaults = await garmin.servings.all().sorted { $0.foodId < $1.foodId }
        XCTAssertEqual(localDefaults, garminDefaults)

        let localCache = await local.cache.all()
        let garminCache = await garmin.cache.all()
        XCTAssertEqual(localCache, garminCache)
        XCTAssertNotNil(localCache["food-c"], "a copied food is cached for display in both modes")
    }
}

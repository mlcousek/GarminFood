// LogEntryEditingTests.swift
//
// add-log-entry-editing: the domain half of editing, duplicating and
// copying a past meal -- `LogEntryCoordinator.edit`/`duplicate`/`copyMeal`,
// `CopyMealPlanner`, and the day view's overlay of a pending edit
// (`MealDashboard`, design.md D3). Same conventions as
// LogEntryCoordinatorTests.swift: a REAL `Outbox` (unique process name per
// test) and real stores on unique temp files, never mocks. Nothing here
// touches the network -- delivery (create-then-delete) is GarminKit's
// OutboxTests' job.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LogEntryEditingTests: XCTestCase {
    private let day = "2026-09-16"

    private struct Harness {
        let coordinator: LogEntryCoordinator
        let outbox: Outbox
        let usageHistory: UsageHistoryStore
        let foodCache: FoodCacheStore
    }

    private func makeHarness() -> Harness {
        let outbox = Outbox(processName: "foodlogcore-editing-test-\(UUID().uuidString)")
        let usageHistory = UsageHistoryStore(fileURL: tempURL("usage"))
        let servingDefaults = ServingDefaultStore(fileURL: tempURL("servingdefaults"))
        let foodCache = FoodCacheStore(fileURL: tempURL("foodcache"))
        let coordinator = LogEntryCoordinator(outbox: outbox, usageHistory: usageHistory, servingDefaults: servingDefaults, foodCache: foodCache)
        return Harness(coordinator: coordinator, outbox: outbox, usageHistory: usageHistory, foodCache: foodCache)
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-editing-\(name)-\(UUID().uuidString).json")
    }

    private let rohlikServing = Serving(id: "serving-r", unit: "piece", numberOfUnits: 1, calories: 150, carbs: 28, protein: 5, fat: 2)

    /// A synced "Rohlík, 1 piece" in lunch, as MealDashboard builds it from
    /// a read-back.
    private func syncedRohlik(logId: String = "log-rohlik", quantity: Double = 1, source: GarminFoodSource? = .fatSecret) -> MealEntry {
        MealEntry(
            id: logId,
            foodId: "4242",
            name: "Rohlík",
            brandName: nil,
            servingQty: quantity,
            servingDescription: "piece",
            calories: 150 * quantity,
            carbs: nil,
            protein: nil,
            fat: nil,
            status: .synced(logId: logId),
            mealType: .lunch,
            servingId: "serving-r",
            serving: rohlikServing,
            source: source,
            regionCode: "CZ",
            languageCode: "en"
        )
    }

    // MARK: - Edit a synced entry (D1 replace)

    func testEditingASyncedEntryQueuesAReplaceOfItsGarminEntry() async throws {
        let h = makeHarness()
        let now = Date(timeIntervalSince1970: 1_789_000_000)

        let queued = try await h.coordinator.edit(syncedRohlik(), date: day, newQuantity: 2, newMeal: .lunch, now: now)

        let stored = await h.outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [queued.id])
        XCTAssertEqual(queued.replaces, ReplacedLog(date: day, logId: "log-rohlik"), "the old entry is deleted only after this one is created")
        XCTAssertEqual(queued.numberOfUnits, 2)
        XCTAssertEqual(queued.mealType, .lunch)
        XCTAssertEqual(queued.foodId, "4242")
        XCTAssertEqual(queued.servingId, "serving-r")
        XCTAssertEqual(queued.source, .fatSecret)
        XCTAssertEqual(queued.regionCode, "CZ", "the read-back region is kept, so a custom food still logs under its own region")
        XCTAssertEqual(queued.state, .pending, "editing never waits on the network")
        XCTAssertEqual(queued.createdAt, now)
    }

    func testMovingASyncedEntryToAnotherMealIsAReplaceToo() async throws {
        let h = makeHarness()

        let queued = try await h.coordinator.edit(syncedRohlik(), date: day, newQuantity: 1, newMeal: .snacks)

        XCTAssertEqual(queued.mealType, .snacks)
        XCTAssertEqual(queued.numberOfUnits, 1)
        XCTAssertEqual(queued.replaces?.logId, "log-rohlik")
    }

    func testAnEditIsNotCountedAsAnotherThingEaten() async throws {
        let h = makeHarness()

        _ = try await h.coordinator.edit(syncedRohlik(), date: day, newQuantity: 2, newMeal: .lunch)

        let events = await h.usageHistory.all()
        XCTAssertTrue(events.isEmpty, "an edit must not add a usage event (streak/XP)")
    }

    func testAnEditWithNothingChangedIsRefused() async throws {
        let h = makeHarness()
        await assertEditError(.noChange) {
            try await h.coordinator.edit(self.syncedRohlik(), date: self.day, newQuantity: 1, newMeal: .lunch)
        }
        let stored = await h.outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testAZeroAmountIsRefused() async throws {
        let h = makeHarness()
        await assertEditError(.invalidQuantity) {
            try await h.coordinator.edit(self.syncedRohlik(), date: self.day, newQuantity: 0, newMeal: .lunch)
        }
    }

    func testAnAbsurdlyLargeAmountIsRefused() async throws {
        let h = makeHarness()
        await assertEditError(.invalidQuantity) {
            try await h.coordinator.edit(self.syncedRohlik(), date: self.day, newQuantity: 1e19, newMeal: .lunch)
        }
        await assertEditError(.invalidQuantity) {
            try await h.coordinator.edit(self.syncedRohlik(), date: self.day, newQuantity: .infinity, newMeal: .lunch)
        }
        let stored = await h.outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testAQuickAddEntryIsNotEditable() async throws {
        let h = makeHarness()
        let quickAdd = MealEntry(
            id: "log-qa", foodId: "", name: "Quick add", brandName: nil, servingQty: 1, servingDescription: nil,
            calories: 300, carbs: nil, protein: nil, fat: nil, status: .synced(logId: "log-qa"), mealType: .lunch
        )
        XCTAssertFalse(quickAdd.canRelog)
        await assertEditError(.notEditable) {
            try await h.coordinator.edit(quickAdd, date: self.day, newQuantity: 2, newMeal: .lunch)
        }
        await assertEditError(.notEditable) {
            try await h.coordinator.duplicate(quickAdd, date: self.day)
        }
    }

    // MARK: - Edit a still-queued entry (local swap)

    func testEditingAQueuedEntrySwapsItWithoutAGarminReplace() async throws {
        let h = makeHarness()
        let original = try await h.outbox.logFood(date: day, mealType: .lunch, foodId: "4242", servingId: "serving-r", numberOfUnits: 1, source: .fatSecret)
        let row = MealDashboard.pendingEntry(original, food: nil, mealType: .lunch)

        let queued = try await h.coordinator.edit(row, date: day, newQuantity: 3, newMeal: .dinner)

        let stored = await h.outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [queued.id], "the old queued entry is gone, the new one is there -- never both")
        XCTAssertNil(queued.replaces, "nothing in Garmin to delete")
        XCTAssertEqual(queued.numberOfUnits, 3)
        XCTAssertEqual(queued.mealType, .dinner)
    }

    func testEditingAnEditKeepsTheOriginalGarminEntryToDelete() async throws {
        let h = makeHarness()
        let firstEdit = try await h.coordinator.edit(syncedRohlik(), date: day, newQuantity: 2, newMeal: .lunch)
        let row = MealDashboard.pendingEntry(firstEdit, food: nil, mealType: .lunch)
        XCTAssertEqual(row.replacesLogId, "log-rohlik")

        let secondEdit = try await h.coordinator.edit(row, date: day, newQuantity: 3, newMeal: .lunch)

        let stored = await h.outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [secondEdit.id])
        XCTAssertEqual(secondEdit.replaces?.logId, "log-rohlik")
        XCTAssertEqual(secondEdit.numberOfUnits, 3)
    }

    func testEditingAnEntryGarminAcceptedButHasntReadBackIsRefused() async throws {
        let h = makeHarness()
        let original = try await h.outbox.logFood(date: day, mealType: .lunch, foodId: "4242", servingId: "serving-r", numberOfUnits: 1)
        _ = await h.outbox.drain(using: AlwaysSucceedsFoodDeliverer())
        let row = MealDashboard.pendingEntry(original, food: nil, mealType: .lunch)

        await assertEditError(.stillSyncing) {
            try await h.coordinator.edit(row, date: self.day, newQuantity: 2, newMeal: .lunch)
        }
        let stored = await h.outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [original.id], "a refused edit changes nothing")
    }

    func testAnEditedEntryIsNamedFromTheCacheBeforeGarminReadsItBack() async throws {
        let h = makeHarness()

        _ = try await h.coordinator.edit(syncedRohlik(), date: day, newQuantity: 2, newMeal: .lunch)

        let cached = await h.foodCache.food(forId: "4242")
        XCTAssertEqual(cached?.name, "Rohlík")
        XCTAssertEqual(cached?.servings.map(\.id), ["serving-r"])
    }

    // MARK: - Duplicate

    func testDuplicatingLogsTheSameFoodAgainAndRemembersItsSource() async throws {
        let h = makeHarness()

        let queued = try await h.coordinator.duplicate(syncedRohlik(quantity: 2), date: day)

        XCTAssertEqual(queued.mealType, .lunch)
        XCTAssertEqual(queued.numberOfUnits, 2)
        XCTAssertEqual(queued.foodId, "4242")
        XCTAssertEqual(queued.servingId, "serving-r")
        XCTAssertNil(queued.replaces, "a duplicate is an ordinary add")
        XCTAssertEqual(queued.duplicateOf, "log-rohlik", "so Reconciliation never deletes the second coffee as an excess copy of the first")
        let events = await h.usageHistory.all()
        XCTAssertEqual(events.count, 1, "a duplicate IS another thing eaten")
    }

    // MARK: - Copy a past meal (D4)

    private func sourceDay() throws -> DailyFoodLog {
        let json = """
        { "mealDetails": [
          { "meal": { "mealName": "BREAKFAST" }, "loggedFoods": [
            { "logId": "b1", "servingQty": 1,
              "foodMetaData": { "foodId": "111", "foodName": "Oats", "source": "FATSECRET", "regionCode": "US", "languageCode": "en" },
              "nutritionContent": { "servingId": "s111", "servingUnit": "G", "numberOfUnits": 40, "calories": 150 } },
            { "logId": "b2", "servingQty": 0.5,
              "foodMetaData": { "foodId": "0123456789abcdef0123456789abcdef", "foodName": "Ginger shot", "source": "GARMIN", "regionCode": "CZ", "languageCode": "cs" },
              "nutritionContent": { "servingId": "s222", "servingUnit": "shot", "numberOfUnits": 1, "calories": 20 } },
            { "logId": "b3", "servingQty": 1,
              "foodMetaData": { "foodId": "", "foodName": "Quick add" },
              "nutritionContent": { "calories": 300 } }
          ] },
          { "meal": { "mealName": "LUNCH" }, "loggedFoods": [
            { "logId": "l1", "servingQty": 1,
              "foodMetaData": { "foodId": "999", "foodName": "Soup" },
              "nutritionContent": { "servingId": "s999", "calories": 200 } }
          ] }
        ] }
        """
        return try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    func testThePlanSplitsCopyableItemsFromQuickAdds() throws {
        let plan = CopyMealPlanner.plan(log: try sourceDay(), mealType: .breakfast)

        XCTAssertEqual(plan.copyable.map(\.id), ["b1", "b2"], "only the chosen meal, in Garmin's order")
        XCTAssertEqual(plan.notCopyable.map(\.id), ["b3"])
        XCTAssertEqual(plan.notCopyable.first?.reason, CopyMealPlanner.quickAddReason)

        let oats = try XCTUnwrap(plan.copyable.first)
        XCTAssertEqual(oats.foodId, "111")
        XCTAssertEqual(oats.servingId, "s111")
        XCTAssertEqual(oats.servingQty, 1)
        XCTAssertEqual(oats.source, .fatSecret)
        XCTAssertEqual(oats.calories, 150)

        let shot = plan.copyable[1]
        XCTAssertEqual(shot.servingQty, 0.5)
        XCTAssertEqual(shot.source, .garmin)
        XCTAssertEqual(shot.regionCode, "CZ", "a custom food is copied under its own region (fix-custom-food-log-region)")
        XCTAssertEqual(shot.calories, 10)
    }

    func testANilLogIsAnEmptyPlan() {
        XCTAssertTrue(CopyMealPlanner.plan(log: nil, mealType: .dinner).isEmpty)
    }

    func testCopyingLogsEachKeptItemIntoTheTargetMealAndDay() async throws {
        let h = makeHarness()
        let plan = CopyMealPlanner.plan(log: try sourceDay(), mealType: .breakfast)
        let now = Date(timeIntervalSince1970: 1_789_100_000)

        let entries = try await h.coordinator.copyMeal(plan.copyable, to: .breakfast, date: "2026-09-17", now: now)

        XCTAssertEqual(entries.count, 2)
        let stored = await h.outbox.allEntries()
        XCTAssertEqual(stored.map(\.foodId), ["111", "0123456789abcdef0123456789abcdef"])
        XCTAssertEqual(stored.map(\.numberOfUnits), [1, 0.5], "original servings and quantities")
        XCTAssertEqual(stored.map(\.servingId), ["s111", "s222"])
        XCTAssertTrue(stored.allSatisfy { $0.date == "2026-09-17" && $0.mealType == .breakfast && $0.state == .pending })
        XCTAssertTrue(stored.allSatisfy { $0.replaces == nil && $0.duplicateOf == nil }, "ordinary adds")
        XCTAssertEqual(stored.last?.regionCode, "CZ")
        let events = await h.usageHistory.all()
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Day view overlay (D3)

    private func dayWithRohlik(extraLunchFoods: String = "") throws -> DailyFoodLog {
        let extra = extraLunchFoods.isEmpty ? "" : ", " + extraLunchFoods
        let json = """
        { "dailyNutritionContent": { "calories": 150, "carbs": 28, "protein": 5, "fat": 2 },
          "mealDetails": [
          { "meal": { "mealName": "LUNCH" }, "mealNutritionContent": { "calories": 150, "carbs": 28, "protein": 5, "fat": 2 },
            "loggedFoods": [
            { "logId": "log-rohlik", "servingQty": 1,
              "foodMetaData": { "foodId": "4242", "foodName": "Rohlík", "source": "FATSECRET" },
              "nutritionContent": { "servingId": "serving-r", "servingUnit": "piece", "numberOfUnits": 1, "calories": 150, "carbs": 28, "protein": 5, "fat": 2 } }\(extra)
          ] }
        ] }
        """
        return try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    func testAPendingEditHidesTheOldRowAndShowsTheNewAmountAsPending() throws {
        let replace = OutboxEntry(
            date: day, mealType: .lunch, foodId: "4242", servingId: "serving-r", numberOfUnits: 2,
            replaces: ReplacedLog(date: day, logId: "log-rohlik")
        )

        let dashboard = MealDashboard.build(date: day, log: try dayWithRohlik(), outboxEntries: [replace], foods: [:])

        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))
        XCTAssertEqual(lunch.entries.count, 1, "the old 1-piece row is replaced, not listed next to the new one")
        let row = try XCTUnwrap(lunch.entries.first)
        XCTAssertEqual(row.servingQty, 2)
        XCTAssertEqual(row.status, .syncing(outboxId: replace.id), "marked pending")
        XCTAssertEqual(row.replacesLogId, "log-rohlik")
        XCTAssertEqual(row.name, "Rohlík", "named from the entry it replaces when the food isn't cached")
        XCTAssertEqual(row.calories, 300)
        XCTAssertEqual(lunch.totals.calories.consumed, 300, accuracy: 0.001, "Garmin's 150 minus the hidden 150 plus the pending 300")
        XCTAssertEqual(dashboard.totals.calories.consumed, 300, accuracy: 0.001)
    }

    func testAMovedEntryDisappearsFromItsOldMealAtOnce() throws {
        let move = OutboxEntry(
            date: day, mealType: .snacks, foodId: "4242", servingId: "serving-r", numberOfUnits: 1,
            replaces: ReplacedLog(date: day, logId: "log-rohlik")
        )

        let dashboard = MealDashboard.build(date: day, log: try dayWithRohlik(), outboxEntries: [move], foods: [:])

        XCTAssertEqual(dashboard.section(for: .lunch)?.entries.count, 0)
        XCTAssertEqual(dashboard.section(for: .snacks)?.entries.map(\.servingQty), [1])
        XCTAssertEqual(dashboard.totals.calories.consumed, 150, accuracy: 0.001, "moved, not doubled")
    }

    func testWhileTheOldEntryAwaitsDeletionTheNewCopyIsNotCountedTwice() throws {
        // The corrected entry is already in Garmin ("log-new"); the old one
        // is still there until the delete lands.
        var replace = OutboxEntry(
            date: day, mealType: .lunch, foodId: "4242", servingId: "serving-r", numberOfUnits: 2,
            replaces: ReplacedLog(date: day, logId: "log-rohlik")
        )
        replace.state = .createdAwaitingDelete
        let newCopy = """
        { "logId": "log-new", "servingQty": 2,
          "foodMetaData": { "foodId": "4242", "foodName": "Rohlík" },
          "nutritionContent": { "servingId": "serving-r", "servingUnit": "piece", "numberOfUnits": 1, "calories": 150, "carbs": 28, "protein": 5, "fat": 2 } }
        """

        let dashboard = MealDashboard.build(date: day, log: try dayWithRohlik(extraLunchFoods: newCopy), outboxEntries: [replace], foods: [:])

        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))
        XCTAssertEqual(lunch.entries.map(\.id), ["log-new"], "old hidden; the new copy shown once, as synced")
    }

    func testAParkedReplaceShowsTheOldEntryAgain() throws {
        // The delete gave up: both entries really are in Garmin, so the day
        // view must not hide the duplicate.
        var replace = OutboxEntry(
            date: day, mealType: .lunch, foodId: "4242", servingId: "serving-r", numberOfUnits: 2,
            replaces: ReplacedLog(date: day, logId: "log-rohlik")
        )
        replace.state = .createdAwaitingDelete
        replace.parkedAt = Date()

        let dashboard = MealDashboard.build(date: day, log: try dayWithRohlik(), outboxEntries: [replace], foods: [:])

        XCTAssertTrue(dashboard.section(for: .lunch)?.entries.contains { $0.id == "log-rohlik" } ?? false)
    }

    func testSyncedRowsCarryWhatReloggingNeeds() throws {
        let dashboard = MealDashboard.build(date: day, log: try dayWithRohlik(), outboxEntries: [], foods: [:])

        let row = try XCTUnwrap(dashboard.section(for: .lunch)?.entries.first)
        XCTAssertTrue(row.canRelog)
        XCTAssertEqual(row.mealType, .lunch)
        XCTAssertEqual(row.servingId, "serving-r")
        XCTAssertEqual(row.source, .fatSecret)
        XCTAssertEqual(row.serving?.calories, 150)
        XCTAssertEqual(row.calories(forQuantity: 3), 450)
    }

    // MARK: - Helpers

    private func assertEditError<T>(
        _ expected: LogEntryEditError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as LogEntryEditError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("expected \(expected), got \(error)", file: file, line: line)
        }
    }

    // MARK: - Deleting a still-queued row (code-review fix)

    func testDeletingAPendingCreateRemovesIt() async throws {
        let h = makeHarness()
        let entry = try await h.outbox.logFood(date: "2026-09-23", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)

        let outcome = try await h.coordinator.deletePending(outboxId: entry.id)

        XCTAssertEqual(outcome, .removed)
        let remaining = await h.outbox.allEntries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testDeletingAPendingEditAlsoDeletesTheOriginalInGarmin() async throws {
        let h = makeHarness()
        let edit = try await h.outbox.logFood(
            date: "2026-09-23", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 2,
            replaces: ReplacedLog(date: "2026-09-23", logId: "original-log")
        )

        let outcome = try await h.coordinator.deletePending(outboxId: edit.id)

        XCTAssertEqual(outcome, .deleteOriginal(date: "2026-09-23", logId: "original-log"),
                       "Delete must not merely undo the edit and bring the old amount back")
        let remaining = await h.outbox.allEntries()
        XCTAssertTrue(remaining.isEmpty, "the corrected entry will never be created")
    }

    func testAnEditGarminHasHalfAppliedIsNotDeletedLocally() async throws {
        let h = makeHarness()
        let edit = try await h.outbox.logFood(
            date: "2026-09-23", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 2,
            replaces: ReplacedLog(date: "2026-09-23", logId: "original-log")
        )
        // Corrected entry created, old one's delete refused and parked.
        _ = await h.outbox.drain(using: HalfAppliedEditDeliverer())
        let parked = await h.outbox.entry(id: edit.id)
        XCTAssertEqual(parked?.state, .createdAwaitingDelete)

        await assertEditError(.stillSyncing) {
            try await h.coordinator.deletePending(outboxId: edit.id)
        }
        let kept = await h.outbox.entry(id: edit.id)
        XCTAssertNotNil(kept, "still tracked, so Retry can finish removing the old entry")
    }

    func testDeletingARowThatIsAlreadyGoneSaysSo() async throws {
        let h = makeHarness()
        await assertEditError(.entryGone) {
            try await h.coordinator.deletePending(outboxId: UUID())
        }
    }
}

/// Lets a real `Outbox.drain` genuinely reach `.sent` without a network, the
/// same way WeightLogCoordinatorTests' deliverer does.
private struct AlwaysSucceedsFoodDeliverer: FoodLogDelivering {
    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs/\(date)")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    }
}

/// Creates fine, but Garmin refuses the old entry's delete permanently (403),
/// so a replace parks in `.createdAwaitingDelete`.
private struct HalfAppliedEditDeliverer: FoodLogDelivering {
    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        throw GarminClientError.httpError(statusCode: 403, body: nil)
    }
}

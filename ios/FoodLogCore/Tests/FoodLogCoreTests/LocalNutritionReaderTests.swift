// LocalNutritionReaderTests.swift
//
// add-standalone-mode 2.3 (design D3, local-food-log spec): golden tests of
// the local read seam THROUGH the code both modes share -- entries are
// written by the real `LocalLogEntryCoordinator` into a real
// `LocalFoodLogStore` on a temp directory, read back by
// `LocalNutritionReader`, and then judged by `MealDashboard.build` and
// `CopyMealPlanner` exactly as the Today tab and "Copy from…" judge a
// Garmin day. No mocks.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LocalNutritionReaderTests: XCTestCase {
    private let day = "2026-09-25"
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Harness {
        let store: LocalFoodLogStore
        let coordinator: LocalLogEntryCoordinator
        let reader: LocalNutritionReader
    }

    private func makeHarness(goals: @escaping LocalNutritionReader.GoalsForDay = LocalNutritionReader.noGoalsYet) -> Harness {
        let tmp = FileManager.default.temporaryDirectory
        let store = LocalFoodLogStore(directoryURL: tmp.appendingPathComponent("local-reader-log-\(UUID().uuidString)"))
        let coordinator = LocalLogEntryCoordinator(
            store: store,
            usageHistory: UsageHistoryStore(fileURL: tmp.appendingPathComponent("local-reader-usage-\(UUID().uuidString).json")),
            servingDefaults: ServingDefaultStore(fileURL: tmp.appendingPathComponent("local-reader-servings-\(UUID().uuidString).json")),
            foodCache: FoodCacheStore(fileURL: tmp.appendingPathComponent("local-reader-cache-\(UUID().uuidString).json"))
        )
        return Harness(store: store, coordinator: coordinator, reader: LocalNutritionReader(store: store, goalsForDay: goals))
    }

    private func food(_ id: String, kcal: Double, name: String? = nil, sodium: Double? = nil, vitaminB1: Double? = nil) -> Food {
        Food(
            id: id,
            name: name ?? id,
            source: .garmin,
            servings: [Serving(id: "\(id)-100g", unit: "g", numberOfUnits: 100, calories: kcal, carbs: 10, protein: 5, fat: 2, sodium: sodium, vitaminB1: vitaminB1)]
        )
    }

    @discardableResult
    private func log(_ food: Food, quantity: Double = 1, meal: MealType, on date: String? = nil, using harness: Harness) async throws -> OutboxEntry {
        try await harness.coordinator.confirm(food: food, serving: food.servings[0], numberOfUnits: quantity, mealType: meal, date: date ?? day, now: now)
    }

    private func dashboard(_ harness: Harness, date: String? = nil) async throws -> DayDashboard {
        let date = date ?? day
        let dayLog = try await harness.reader.dailyFoodLog(date: date)
        let meals = try await harness.reader.mealsForDate(date: date).meals ?? []
        return MealDashboard.build(date: date, log: dayLog, meals: meals, outboxEntries: [], foods: [:])
    }

    private func firstRow(_ harness: Harness, _ meal: MealType) async throws -> MealEntry {
        let built = try await dashboard(harness)
        return try XCTUnwrap(built.section(for: meal)?.entries.first)
    }

    private let twoThousand: LocalNutritionReader.GoalsForDay = { _ in NutritionGoals(calories: 2000) }

    // MARK: MealDashboard (spec: "Day totals")

    func testTheDashboardShowsTheDayAndMealTotalsAgainstTheLocalGoal() async throws {
        let harness = makeHarness(goals: twoThousand)
        let first = try await log(food("rohlik", kcal: 300), meal: .breakfast, using: harness)
        let second = try await log(food("jogurt", kcal: 200), meal: .breakfast, using: harness)
        let third = try await log(food("svickova", kcal: 600), meal: .lunch, using: harness)

        let built = try await dashboard(harness)

        XCTAssertEqual(built.totals.calories.consumed, 1100, accuracy: 0.0001)
        XCTAssertEqual(built.totals.calories.goal, 2000)
        XCTAssertEqual(built.section(for: .breakfast)?.totals.calories.consumed ?? 0, 500, accuracy: 0.0001)
        XCTAssertEqual(built.section(for: .lunch)?.totals.calories.consumed ?? 0, 600, accuracy: 0.0001)
        XCTAssertEqual(built.sections.map(\.mealType), [.breakfast, .lunch, .dinner, .snacks])
        XCTAssertEqual(built.section(for: .breakfast)?.entries.map(\.status), [
            .synced(logId: first.id.uuidString), .synced(logId: second.id.uuidString),
        ])
        XCTAssertEqual(built.section(for: .lunch)?.entries.first?.status, .synced(logId: third.id.uuidString))
        XCTAssertFalse(built.sections.contains { $0.hasPendingEntries }, "nothing local is ever 'syncing'")
        XCTAssertTrue(built.hasGarminData, "the local log is the system of record: never 'not loaded'")
        XCTAssertTrue(built.windows.isEmpty, "no meal windows -- the clock picks the meal")
    }

    func testARowCarriesWhatEditingNeedsAndItsServingSize() async throws {
        let harness = makeHarness()
        let receipt = try await log(food("jogurt", kcal: 200, name: "Jogurt"), quantity: 1.5, meal: .snacks, using: harness)

        let row = try await firstRow(harness, .snacks)

        XCTAssertEqual(row.id, receipt.id.uuidString)
        XCTAssertEqual(row.name, "Jogurt")
        XCTAssertEqual(row.servingQty, 1.5)
        XCTAssertEqual(row.calories ?? 0, 300, accuracy: 0.0001)
        XCTAssertEqual(row.serving?.calories ?? 0, 200, accuracy: 0.0001, "per serving, for the edit sheet's live kcal")
        XCTAssertEqual(row.servingDescription, "100 g")
        XCTAssertEqual(row.mealType, .snacks)
        XCTAssertEqual(row.servingId, "jogurt-100g")
        XCTAssertTrue(row.canRelog)
    }

    func testNoLocalGoalMeansNoTargetYet() async throws {
        let harness = makeHarness()
        try await log(food("rohlik", kcal: 300), meal: .breakfast, using: harness)

        let built = try await dashboard(harness)

        XCTAssertNil(built.totals.calories.goal, "wave 4's LocalGoalStore supplies targets; until then there are none")
        XCTAssertEqual(built.totals.calories.consumed, 300, accuracy: 0.0001)
    }

    func testAnEmptyDayIsAnEmptyLogNotAMissingOne() async throws {
        let harness = makeHarness(goals: twoThousand)

        let dayLog = try await harness.reader.dailyFoodLog(date: day)

        XCTAssertEqual(dayLog?.mealDetails?.count, 4)
        XCTAssertEqual(dayLog?.dailyNutritionContent?.calories, 0)
        XCTAssertEqual(dayLog?.dailyNutritionGoals?.calories, 2000)
        let built = try await dashboard(harness)
        XCTAssertEqual(built.totals.calories.consumed, 0)
        XCTAssertTrue(built.sections.allSatisfy { $0.entries.isEmpty })
    }

    // MARK: Edit / move / delete round trips (spec scenarios)

    func testEditingAnAmountRaisesTheDayTotal() async throws {
        let harness = makeHarness()
        try await log(food("buchta", kcal: 200), meal: .dinner, using: harness)
        let before = try await dashboard(harness)
        let row = try XCTUnwrap(before.section(for: .dinner)?.entries.first)

        _ = try await harness.coordinator.edit(row, date: day, newQuantity: 1.5, newMeal: .dinner, now: now)

        let after = try await dashboard(harness)
        XCTAssertEqual(after.section(for: .dinner)?.entries.first?.calories ?? 0, 300, accuracy: 0.0001)
        XCTAssertEqual(after.totals.calories.consumed - before.totals.calories.consumed, 100, accuracy: 0.0001)
    }

    func testMovingAnEntryMovesItBetweenMeals() async throws {
        let harness = makeHarness()
        try await log(food("banan", kcal: 105), meal: .breakfast, using: harness)
        let row = try await firstRow(harness, .breakfast)

        _ = try await harness.coordinator.edit(row, date: day, newQuantity: row.servingQty, newMeal: .snacks, now: now)

        let after = try await dashboard(harness)
        XCTAssertEqual(after.section(for: .breakfast)?.entries.count, 0)
        XCTAssertEqual(after.section(for: .snacks)?.entries.map(\.id), [row.id])
        XCTAssertEqual(after.totals.calories.consumed, 105, accuracy: 0.0001)
    }

    func testDuplicatingARowAddsItAgain() async throws {
        let harness = makeHarness()
        try await log(food("kava", kcal: 40), meal: .breakfast, using: harness)
        let row = try await firstRow(harness, .breakfast)

        _ = try await harness.coordinator.duplicate(row, date: day, now: now)

        let after = try await dashboard(harness)
        XCTAssertEqual(after.section(for: .breakfast)?.entries.count, 2)
        XCTAssertEqual(after.totals.calories.consumed, 80, accuracy: 0.0001)
    }

    func testDeletingARowRemovesItAndItsCalories() async throws {
        let harness = makeHarness()
        try await log(food("rohlik", kcal: 300), meal: .lunch, using: harness)
        try await log(food("polevka", kcal: 150), meal: .lunch, using: harness)
        let row = try await firstRow(harness, .lunch)
        let logId = try XCTUnwrap(row.syncedLogId)

        try await harness.coordinator.deleteCommitted(logId: logId, date: day)

        let after = try await dashboard(harness)
        XCTAssertEqual(after.section(for: .lunch)?.entries.map(\.name), ["polevka"])
        XCTAssertEqual(after.totals.calories.consumed, 150, accuracy: 0.0001)
    }

    // MARK: Nutrients

    func testMicronutrientsSumButOffOnlyKindsStayOutOfTheDashboard() async throws {
        let harness = makeHarness()
        try await log(food("syr", kcal: 100, sodium: 200, vitaminB1: 0.3), meal: .dinner, using: harness)
        try await log(food("chleba", kcal: 250, sodium: 400), quantity: 2, meal: .dinner, using: harness)
        try await log(food("jablko", kcal: 50), meal: .dinner, using: harness)

        let built = try await dashboard(harness)
        let section = try XCTUnwrap(built.section(for: .dinner))

        let sodium = section.nutrients.first { $0.kind == .sodium }?.value
        XCTAssertEqual(sodium ?? 0, 1000, accuracy: 0.0001, "200 + 2 x 400; the apple didn't say")
        XCTAssertNil(section.nutrients.first { $0.kind == .fiber }, "no entry stated fibre: not shown, never a fake 0")
        XCTAssertNil(section.nutrients.first { $0.kind == .vitaminB1 }, "the day/meal aggregate never carries OFF-only kinds")
        let stored = try await harness.store.entries(forDay: day)
        XCTAssertEqual(stored.first?.amount(.vitaminB1), 0.3, "but the snapshot keeps it")
    }

    func testLocalEntriesReadAsThisAppsOwnWithTheirLoggingTime() async throws {
        let harness = makeHarness()
        try await log(food("rohlik", kcal: 300), meal: .breakfast, using: harness)

        let dayLog = try await harness.reader.dailyFoodLog(date: day)
        let logged = try XCTUnwrap(dayLog?.mealDetails?.first?.loggedFoods?.first)

        XCTAssertTrue(logged.isFromThisApp)
        let parsed = try XCTUnwrap(logged.logTimestamp.flatMap(FastingLogMoments.parseTimestamp))
        XCTAssertEqual(parsed.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
        let unwrapped = try XCTUnwrap(dayLog)
        let moments = FastingLogMoments.moments(fromGarminLog: unwrapped, date: day, calendar: Calendar(identifier: .gregorian))
        XCTAssertTrue(moments.isEmpty, "already counted from the usage history, like this app's delivered entries")
    }

    // MARK: CopyMealPlanner

    func testCopyFromALocalDayPlansEveryEntryAndCopiesTheSameCalories() async throws {
        let harness = makeHarness()
        try await log(food("vejce", kcal: 150), quantity: 2, meal: .breakfast, on: "2026-09-24", using: harness)
        let draft = CustomFoodDraft(
            name: "Babiččiny buchty", servingUnit: "piece", numberOfUnits: 1, calories: 220, carbs: 30, protein: 5, fat: 8,
            backingFoodId: "g", backingFoodName: "g", backingServingId: "g"
        )
        _ = try await harness.coordinator.confirmCustomFood(draft, quantity: 1, mealType: .breakfast, date: "2026-09-24", now: now)
        let sourceLog = try await harness.reader.dailyFoodLog(date: "2026-09-24")

        let plan = CopyMealPlanner.plan(log: sourceLog, mealType: .breakfast)

        XCTAssertEqual(plan.copyable.count, 2)
        XCTAssertTrue(plan.notCopyable.isEmpty)
        XCTAssertEqual(plan.copyable.map(\.servingQty), [2, 1])
        XCTAssertEqual(plan.copyable.last?.foodId, draft.id.uuidString)
        XCTAssertEqual(plan.copyable.last?.servingId, CustomFoodDraft.servingId)

        _ = try await harness.coordinator.copyMeal(plan.copyable, to: .lunch, date: day, now: now)

        let today = try await dashboard(harness)
        XCTAssertEqual(today.section(for: .lunch)?.entries.count, 2)
        XCTAssertEqual(today.totals.calories.consumed, 520, accuracy: 0.0001)
        let copied = try await harness.store.entries(forDay: day)
        XCTAssertEqual(copied.last?.customFoodId, draft.id, "a copied custom food stays that custom food")
    }

    // MARK: Other reads

    func testMealsForDateAreTheFourDefaultMealsWithoutWindows() async throws {
        let meals = try await makeHarness().reader.mealsForDate(date: day).meals ?? []

        XCTAssertEqual(meals.map(\.mealName), ["BREAKFAST", "LUNCH", "DINNER", "SNACKS"])
        XCTAssertTrue(meals.allSatisfy { $0.startTime == nil && $0.endTime == nil })
    }

    func testTheCalorieSummaryListsLoggedDaysWithTheGoalOfEachDay() async throws {
        let harness = makeHarness(goals: { day in NutritionGoals(calories: day < "2026-09-01" ? 1800 : 2000) })
        try await log(food("a", kcal: 500), meal: .lunch, on: "2026-08-31", using: harness)
        try await log(food("b", kcal: 700), meal: .dinner, on: "2026-09-02", using: harness)
        try await log(food("c", kcal: 100), meal: .snacks, on: "2026-09-02", using: harness)
        try await log(food("d", kcal: 999), meal: .snacks, on: "2026-09-10", using: harness)

        let summary = try await harness.reader.calorieSummaryDaily(startDate: "2026-08-30", endDate: "2026-09-05")

        let days = summary.dailyNutritionContents ?? []
        XCTAssertEqual(days.map(\.mealDate), ["2026-08-31", "2026-09-02"], "only logged days in range, across the month boundary")
        XCTAssertEqual(days.map { $0.nutritionContent?.calories }, [500, 800])
        XCTAssertEqual(days.map { $0.nutritionGoals?.calories }, [1800, 2000])
    }

    func testThereIsNoActivitySummaryWithoutGarmin() async throws {
        do {
            _ = try await makeHarness().reader.dailyUserSummary(date: day)
            XCTFail("expected a throw")
        } catch let error as LocalNutritionReaderError {
            XCTAssertEqual(error, .unavailable)
        }
    }
}

// MealDashboardTests.swift
//
// The meal-dashboard spec's scenarios, against hand-written logs shaped like
// GET /nutrition-service/food/logs/{date} as observed on 2026-09-16. All ids
// and names are synthetic.

import XCTest
@testable import FoodLogCore
import GarminKit

final class MealDashboardTests: XCTestCase {
    private let day = "2026-09-16"

    // MARK: Fixtures

    private func log(_ json: String) throws -> DailyFoodLog {
        try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    private func meals(_ json: String) throws -> [Meal] {
        try JSONDecoder().decode(MealsForDate.self, from: Data(json.utf8)).meals ?? []
    }

    private func mealJSON(
        _ name: String,
        start: String? = nil,
        end: String? = nil,
        displayOrder: Int? = nil,
        goals: String = "{}",
        content: String = "{}",
        foods: String = ""
    ) -> String {
        var meal = "\"mealName\": \"\(name)\""
        if let start { meal += ", \"startTime\": \"\(start)\"" }
        if let end { meal += ", \"endTime\": \"\(end)\"" }
        if let displayOrder { meal += ", \"displayOrder\": \(displayOrder)" }
        return "{ \"meal\": { \(meal) }, \"mealNutritionGoals\": \(goals), \"mealNutritionContent\": \(content), \"loggedFoods\": [\(foods)] }"
    }

    private func foodJSON(logId: String, foodId: String, servingId: String, name: String, qty: Double, calories: Double) -> String {
        "{ \"logId\": \"\(logId)\", \"servingQty\": \(qty), "
            + "\"foodMetaData\": { \"foodId\": \"\(foodId)\", \"foodName\": \"\(name)\" }, "
            + "\"nutritionContent\": { \"servingId\": \"\(servingId)\", \"servingUnit\": \"G\", \"numberOfUnits\": 100, "
            + "\"calories\": \(calories), \"carbs\": 10, \"protein\": 2, \"fat\": 1 } }"
    }

    private func dayLog(meals mealDetails: [String], extra: String = "") throws -> DailyFoodLog {
        let prefix = extra.isEmpty ? "" : extra + ", "
        return try log("{ " + prefix + "\"mealDetails\": [" + mealDetails.joined(separator: ", ") + "] }")
    }

    private func pending(
        _ meal: MealType,
        state: OutboxEntryState = .pending,
        date: String? = nil,
        lastError: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 1_789_000_000)
    ) -> OutboxEntry {
        OutboxEntry(
            date: date ?? day,
            mealType: meal,
            foodId: "food-p",
            servingId: "serving-p",
            numberOfUnits: 2,
            state: state,
            lastError: lastError,
            createdAt: createdAt
        )
    }

    private let cachedFood = Food(
        id: "food-p",
        name: "Banana",
        source: .fatSecret,
        servings: [Serving(id: "serving-p", unit: "medium", numberOfUnits: 1, calories: 105, carbs: 27, protein: 1.3, fat: 0.4)]
    )

    private var foods: [String: Food] { ["food-p": cachedFood] }

    // MARK: Sections and order

    func testEveryMealHasASectionInGarminOrderEvenWhenEmpty() throws {
        let breakfast = mealJSON(
            "BREAKFAST",
            content: "{\"calories\": 300}",
            foods: foodJSON(logId: "a", foodId: "f1", servingId: "s1", name: "Oats", qty: 1, calories: 300)
        )

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [breakfast]), outboxEntries: [], foods: [:])

        XCTAssertEqual(dashboard.sections.map(\.mealType), [.breakfast, .lunch, .dinner, .snacks])
        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))
        XCTAssertEqual(lunch.totals.calories.consumed, 0)
        XCTAssertTrue(lunch.entries.isEmpty)
    }

    func testGarminsDisplayOrderIsUsedWhenEveryMealHasOne() throws {
        let details = [
            mealJSON("BREAKFAST", displayOrder: 1),
            mealJSON("LUNCH", displayOrder: 2),
            mealJSON("DINNER", displayOrder: 4),
            mealJSON("SNACKS", displayOrder: 3),
        ]

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: details), outboxEntries: [], foods: [:])

        XCTAssertEqual(dashboard.sections.map(\.mealType), [.breakfast, .lunch, .snacks, .dinner])
    }

    func testAPartialDisplayOrderFallsBackToTheDefault() throws {
        let details = [mealJSON("SNACKS", displayOrder: 1), mealJSON("BREAKFAST")]

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: details), outboxEntries: [], foods: [:])

        XCTAssertEqual(dashboard.sections.map(\.mealType), MealDashboard.defaultOrder)
    }

    // MARK: Targets

    func testTheAdjustedTargetIsPreferred() throws {
        let lunchJSON = mealJSON("LUNCH", goals: "{\"calories\": 500, \"adjustedCalories\": 560, \"protein\": 30}")

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [lunchJSON]), outboxEntries: [], foods: [:])
        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))

        XCTAssertEqual(lunch.totals.calories.goal, 560)
        XCTAssertEqual(lunch.totals.protein.goal, 30, "falls back to the base value when no adjusted one exists")
    }

    // 2026-09-21 bug fix: `remaining` used to guard only `goal != nil`
    // while `fraction`/`state` both guard `goal > 0` -- a `goal` of exactly
    // `0` (not `nil`) used to make `fraction`/`state` correctly report "no
    // usable goal" while `remaining` still returned a large, misleading
    // negative number for the same value.
    func testAZeroGoalIsTreatedAsNoGoalByRemainingTooNotJustFractionAndState() {
        let progress = MacroProgress(consumed: 1800, goal: 0)

        XCTAssertNil(progress.fraction)
        XCTAssertEqual(progress.state, .noGoal)
        XCTAssertNil(progress.remaining, "a zero goal must agree with fraction/state that there is no usable target")
    }

    func testAMealWithoutGoalsShowsConsumedOnly() throws {
        let dinnerJSON = mealJSON("DINNER", content: "{\"calories\": 250}")

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [dinnerJSON]), outboxEntries: [], foods: [:])
        let dinner = try XCTUnwrap(dashboard.section(for: .dinner))

        XCTAssertNil(dinner.totals.calories.goal)
        XCTAssertEqual(dinner.totals.calories.state, .noGoal)
        XCTAssertNil(dinner.totals.calories.fraction)
        XCTAssertEqual(dinner.totals.calories.consumed, 250)
    }

    func testAnEmptyContentObjectCountsAsZero() throws {
        let snacksJSON = mealJSON("SNACKS", goals: "{\"calories\": 230}", content: "{}")

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [snacksJSON]), outboxEntries: [], foods: [:])
        let snacks = try XCTUnwrap(dashboard.section(for: .snacks))

        XCTAssertEqual(snacks.totals.calories.consumed, 0)
        XCTAssertEqual(snacks.totals.protein.consumed, 0)
        XCTAssertEqual(snacks.totals.calories.state, .under)
    }

    func testDayTotalsUseTheDailyTargets() throws {
        let extra = "\"dailyNutritionGoals\": { \"calories\": 2300, \"adjustedCalories\": 2463, \"protein\": 115 }, "
            + "\"dailyNutritionContent\": { \"calories\": 2300, \"protein\": 50 }"

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [], extra: extra), outboxEntries: [], foods: [:])

        XCTAssertEqual(dashboard.totals.calories.goal, 2463)
        XCTAssertEqual(dashboard.totals.calories.state, .onTarget, "2300 of 2463 is within 10%")
        XCTAssertEqual(dashboard.totals.protein.state, .under)
        XCTAssertTrue(dashboard.hasGarminData)
    }

    // MARK: Logged foods

    func testALoggedFoodIsScaledByItsServingQuantity() throws {
        // Observed 2026-09-16: summing nutritionContent.calories x servingQty
        // reproduces Garmin's meal total; summing the raw values does not.
        let lunchJSON = mealJSON("LUNCH", foods: foodJSON(logId: "log-1", foodId: "f1", servingId: "s1", name: "Rice", qty: 1.5, calories: 120))

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [lunchJSON]), outboxEntries: [], foods: [:])
        let entry = try XCTUnwrap(dashboard.section(for: .lunch)?.entries.first)

        XCTAssertEqual(entry.calories, 180)
        XCTAssertEqual(entry.carbs, 15)
        XCTAssertEqual(entry.servingQty, 1.5)
        XCTAssertEqual(entry.servingDescription, "100 g")
        XCTAssertEqual(entry.status, .synced(logId: "log-1"))
        XCTAssertEqual(entry.name, "Rice")
    }

    func testDetailedNutrientsAppearOnlyWhenGarminReturnsThem() throws {
        let content = "{\"calories\": 230, \"carbs\": 20, \"protein\": 10, \"fat\": 5, \"fiber\": 4, \"sodium\": 300}"
        let dinnerJSON = mealJSON("DINNER", content: content)

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [dinnerJSON]), outboxEntries: [], foods: [:])
        let dinner = try XCTUnwrap(dashboard.section(for: .dinner))

        XCTAssertEqual(dinner.nutrients.map(\.kind), [.calories, .carbs, .fiber, .protein, .fat, .sodium])
        XCTAssertEqual(dinner.nutrients.first { $0.kind == .sodium }?.value, 300)
    }

    // MARK: New micronutrients ceiling (implement-micronutrients, 2026-09-22)

    /// `DailyNutritionContent` (Garmin's own daily/meal aggregate) has no
    /// vitaminB1...omega6 fields at all, so `MealDashboard.nutrients` must
    /// never surface them here even though the enum now has cases for them
    /// -- that richer panel only exists per-food, via `Serving.
    /// detailedNutrients` (FoodTests.swift), never synthesized into a day
    /// total Garmin never actually returned.
    func testNewMicronutrientKindsNeverAppearInTheGarminFedMealDashboardEvenWhenEverythingElseIsPresent() throws {
        let content = "{\"calories\": 230, \"carbs\": 20, \"protein\": 10, \"fat\": 5, \"fiber\": 4, \"sugar\": 2, "
            + "\"saturatedFat\": 1, \"monounsaturatedFat\": 1, \"polyunsaturatedFat\": 1, \"cholesterol\": 10, "
            + "\"sodium\": 300, \"potassium\": 200, \"vitaminA\": 5, \"vitaminC\": 10, \"calcium\": 8, \"iron\": 6}"
        let dinnerJSON = mealJSON("DINNER", content: content)

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: [dinnerJSON]), outboxEntries: [], foods: [:])
        let dinner = try XCTUnwrap(dashboard.section(for: .dinner))

        let newKinds: Set<NutrientKind> = [
            .vitaminB1, .vitaminB2, .vitaminB3, .vitaminB5, .vitaminB6, .vitaminB9, .vitaminB12,
            .vitaminD, .vitaminE, .vitaminK,
            .magnesium, .zinc, .phosphorus, .selenium, .copper, .manganese, .iodine,
            .omega3, .omega6,
        ]
        XCTAssertTrue(newKinds.isDisjoint(with: Set(dinner.nutrients.map(\.kind))))
    }

    // MARK: Queued entries

    func testAQueuedEntryAppearsInItsMealAndCountsTowardTheTotals() throws {
        let lunchJSON = mealJSON("LUNCH", content: "{\"calories\": 100}")
        let dayData = try dayLog(meals: [lunchJSON], extra: "\"dailyNutritionContent\": { \"calories\": 100 }")

        let dashboard = MealDashboard.build(date: day, log: dayData, outboxEntries: [pending(.lunch)], foods: foods)
        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))
        let entry = try XCTUnwrap(lunch.entries.first)

        XCTAssertEqual(entry.name, "Banana")
        XCTAssertEqual(entry.calories, 210)
        XCTAssertEqual(entry.servingDescription, "medium")
        guard case .syncing = entry.status else { return XCTFail("expected syncing, got \(entry.status)") }
        XCTAssertTrue(lunch.hasPendingEntries)
        XCTAssertEqual(lunch.totals.calories.consumed, 310)
        XCTAssertEqual(dashboard.totals.calories.consumed, 310)
    }

    func testAQueuedEntryForAnUncachedFoodStillShows() throws {
        let dashboard = MealDashboard.build(date: day, log: nil, outboxEntries: [pending(.dinner)], foods: [:])
        let entry = try XCTUnwrap(dashboard.section(for: .dinner)?.entries.first)

        XCTAssertEqual(entry.name, "Syncing…")
        XCTAssertNil(entry.calories)
        XCTAssertFalse(dashboard.hasGarminData)
    }

    func testADeliveredEntryAlreadyInTheLogIsShownOnce() throws {
        let copy = foodJSON(logId: "log-9", foodId: "food-p", servingId: "serving-p", name: "Banana", qty: 2, calories: 105)
        let dayData = try dayLog(meals: [mealJSON("LUNCH", foods: copy)])

        let dashboard = MealDashboard.build(date: day, log: dayData, outboxEntries: [pending(.lunch, state: .sent)], foods: foods)
        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))

        XCTAssertEqual(lunch.entries.count, 1)
        XCTAssertEqual(lunch.entries.first?.status, .synced(logId: "log-9"))
    }

    func testADeliveredEntryNotYetInTheLogStillShows() throws {
        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: []), outboxEntries: [pending(.lunch, state: .sent)], foods: foods)
        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))

        XCTAssertEqual(lunch.entries.count, 1)
        XCTAssertFalse(lunch.entries[0].isSynced)
    }

    func testOneLoggedCopyAbsorbsOnlyOneDelivery() throws {
        let copy = foodJSON(logId: "x", foodId: "food-p", servingId: "serving-p", name: "Banana", qty: 2, calories: 105)
        let dayData = try dayLog(meals: [mealJSON("LUNCH", foods: copy)])
        let first = pending(.lunch, state: .sent, createdAt: Date(timeIntervalSince1970: 1))
        let second = pending(.lunch, state: .sent, createdAt: Date(timeIntervalSince1970: 2))

        let dashboard = MealDashboard.build(date: day, log: dayData, outboxEntries: [first, second], foods: foods)
        let lunch = try XCTUnwrap(dashboard.section(for: .lunch))

        XCTAssertEqual(lunch.entries.count, 2, "one synced copy plus the delivery it couldn't absorb")
    }

    func testAFailedEntryCarriesItsReason() throws {
        let dashboard = MealDashboard.build(date: day, log: nil, outboxEntries: [pending(.snacks, state: .failed, lastError: "HTTP 400")], foods: [:])
        let entry = try XCTUnwrap(dashboard.section(for: .snacks)?.entries.first)

        guard case .failed(_, let reason) = entry.status else { return XCTFail("expected failed, got \(entry.status)") }
        XCTAssertEqual(reason, "HTTP 400")
    }

    func testEntriesForOtherDatesAreIgnored() {
        let dashboard = MealDashboard.build(date: day, log: nil, outboxEntries: [pending(.lunch, date: "2026-09-15")], foods: [:])

        XCTAssertTrue(dashboard.sections.allSatisfy { $0.entries.isEmpty })
    }

    // MARK: Windows

    func testWindowsComeFromTheLog() throws {
        let details = [mealJSON("LUNCH", start: "10:00:00", end: "12:00:00"), mealJSON("SNACKS")]

        let dashboard = MealDashboard.build(date: day, log: try dayLog(meals: details), outboxEntries: [], foods: [:])

        XCTAssertEqual(dashboard.section(for: .lunch)?.window, MealWindow(mealType: .lunch, start: 36_000, end: 43_200))
        XCTAssertNil(dashboard.section(for: .snacks)?.window)
    }

    func testWindowsFallBackToTheMealsRouteWithoutALog() throws {
        let mealsJSON = "{ \"meals\": [ { \"mealId\": 7, \"mealName\": \"BREAKFAST\", \"startTime\": \"04:00:00\", \"endTime\": \"07:00:00\" } ] }"

        let dashboard = MealDashboard.build(date: day, log: nil, meals: try meals(mealsJSON), outboxEntries: [], foods: [:])

        XCTAssertEqual(dashboard.windows, [MealWindow(mealType: .breakfast, start: 14_400, end: 25_200)])
    }

    // MARK: MacroProgress

    func testMacroProgressStates() {
        XCTAssertEqual(MacroProgress(consumed: 95, goal: 100).state, .onTarget)
        XCTAssertEqual(MacroProgress(consumed: 111, goal: 100).state, .over)
        XCTAssertEqual(MacroProgress(consumed: 89, goal: 100).state, .under)
        XCTAssertEqual(MacroProgress(consumed: 10, goal: 0).state, .noGoal)
        XCTAssertEqual(MacroProgress(consumed: 150, goal: 100).fraction, 1)
        XCTAssertEqual(MacroProgress(consumed: 30, goal: 100).remaining, 70)
    }

    // MARK: Default meal

    func testTheDefaultMealFollowsGarminsWindows() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let windows = [
            MealWindow(mealType: .breakfast, start: 14_400, end: 25_200),
            MealWindow(mealType: .lunch, start: 36_000, end: 43_200),
            MealWindow(mealType: .dinner, start: 50_400, end: 61_200),
        ]
        let lunchTime = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 11, minute: 15)))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 8, minute: 30)))
        let dinnerStart = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 14, minute: 0)))

        XCTAssertEqual(MealWindowDefaulting.mealType(at: lunchTime, windows: windows, calendar: calendar), .lunch)
        XCTAssertEqual(MealWindowDefaulting.mealType(at: morning, windows: windows, calendar: calendar), .snacks)
        XCTAssertEqual(MealWindowDefaulting.mealType(at: dinnerStart, windows: windows, calendar: calendar), .dinner)
        XCTAssertEqual(
            MealWindowDefaulting.mealType(at: morning, windows: [], calendar: calendar),
            MealTypeDefaulting.defaultMealType(for: morning, calendar: calendar),
            "no windows falls back to the hour table"
        )
    }
}

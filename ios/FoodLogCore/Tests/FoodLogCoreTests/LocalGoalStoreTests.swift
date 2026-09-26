// LocalGoalStoreTests.swift
//
// add-standalone-mode 4.1 (local-nutrition-goals spec): the goal in effect
// per day, and editing that keeps history. A real `LocalGoalStore` on a
// unique temp file per test (no mocks), plus the reader wiring through a
// real `LocalFoodLogStore` so a local day's log carries the goal and
// `GoalStatusEvaluator` judges it like a Garmin day.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LocalGoalStoreTests: XCTestCase {
    private func makeStore(fileURL: URL? = nil) -> (LocalGoalStore, URL) {
        let url = fileURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("local-goals-\(UUID().uuidString).json")
        return (LocalGoalStore(fileURL: url), url)
    }

    // MARK: Goal in effect per day

    func testNoGoalBeforeTheFirstOneStarts() async throws {
        let (store, _) = makeStore()
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-20", calories: 1900))

        let before = await store.goal(on: "2026-09-19")
        let onTheDay = await store.goal(on: "2026-09-20")
        let later = await store.goal(on: "2026-10-03")
        XCTAssertNil(before, "skipped/absent goal: no target, no goal-met status")
        XCTAssertEqual(onTheDay?.calories, 1900)
        XCTAssertEqual(later?.calories, 1900, "a goal applies until the next one starts")
    }

    func testEditingAGoalKeepsHistory() async throws {
        // Spec: 1900 -> 1800 today; yesterday keeps 1900.
        let (store, _) = makeStore()
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 1900, proteinG: 90))
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800, proteinG: 95))

        let yesterday = await store.goal(on: "2026-09-24")
        let today = await store.goal(on: "2026-09-25")
        let tomorrow = await store.goal(on: "2026-09-26")
        XCTAssertEqual(yesterday?.calories, 1900)
        XCTAssertEqual(yesterday?.proteinG, 90)
        XCTAssertEqual(today?.calories, 1800)
        XCTAssertEqual(tomorrow?.calories, 1800)
        let all = await store.all()
        XCTAssertEqual(all.map(\.effectiveFrom), ["2026-09-01", "2026-09-25"])
    }

    func testSavingTwiceOnTheSameDayReplacesThatDay() async throws {
        let (store, _) = makeStore()
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800))
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1750, fatG: 60))

        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.calories, 1750)
        XCTAssertEqual(all.first?.fatG, 60)
    }

    func testAGoalSavedOutOfOrderStillResolvesByDay() async throws {
        let (store, _) = makeStore()
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800))
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-10", calories: 2000))

        let mid = await store.goal(on: "2026-09-15")
        let late = await store.goal(on: "2026-09-28")
        XCTAssertEqual(mid?.calories, 2000)
        XCTAssertEqual(late?.calories, 1800)
    }

    func testTheHistorySurvivesARelaunch() async throws {
        let (store, url) = makeStore()
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 1900, proteinG: 90, carbsG: 200, fatG: 60))
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800))

        let (reopened, _) = makeStore(fileURL: url)
        let all = await reopened.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first, LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 1900, proteinG: 90, carbsG: 200, fatG: 60))
    }

    func testAnInvalidGoalIsRefusedAndNothingChanges() async throws {
        let (store, _) = makeStore()
        try await store.save(LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 1900))

        for bad in [
            LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 0),
            LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: -5),
            LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: .nan),
            LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800, proteinG: -1),
            LocalNutritionGoals(effectiveFrom: "25.9.2026", calories: 1800),
        ] {
            do {
                try await store.save(bad)
                XCTFail("expected \(bad) to be refused")
            } catch let error as LocalGoalError {
                XCTAssertEqual(error, .invalidGoal)
            }
        }
        let all = await store.all()
        XCTAssertEqual(all.map(\.calories), [1900])
    }

    func testAFileWithUnknownKeysAndMissingMacrosStillDecodes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("local-goals-\(UUID().uuidString).json")
        let json = #"[{"effectiveFrom":"2026-09-01","calories":1900,"futureField":true},{"effectiveFrom":"2026-09-20","calories":1850,"proteinG":88,"mealSplit":{"BREAKFAST":0.3}}]"#
        try Data(json.utf8).write(to: url)

        let (store, _) = makeStore(fileURL: url)
        let first = await store.goal(on: "2026-09-05")
        let second = await store.goal(on: "2026-09-21")
        XCTAssertEqual(first?.calories, 1900)
        XCTAssertNil(first?.proteinG)
        XCTAssertEqual(second?.proteinG, 88)
        XCTAssertEqual(second?.mealSplit?["BREAKFAST"], 0.3)
    }

    // MARK: Pure history rules

    func testHistoryRulesArePure() {
        let history = [
            LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 1900),
            LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800),
        ]
        XCTAssertNil(LocalGoalHistory.goal(on: "2026-08-31", in: history))
        XCTAssertEqual(LocalGoalHistory.goal(on: "2026-09-24", in: history)?.calories, 1900)
        XCTAssertEqual(LocalGoalHistory.goal(on: "2026-09-25", in: history)?.calories, 1800)
        let replaced = LocalGoalHistory.setting(LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 2000), in: history)
        XCTAssertEqual(replaced.map(\.calories), [2000, 1800])
    }

    // MARK: Through the reader (spec: "Goal met from local data")

    func testTheLocalReaderPutsTheGoalInEffectOnEachDay() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let log = LocalFoodLogStore(directoryURL: tmp.appendingPathComponent("local-goals-log-\(UUID().uuidString)"))
        let (goals, _) = makeStore()
        try await goals.save(LocalNutritionGoals(effectiveFrom: "2026-09-01", calories: 1900))
        try await goals.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800, proteinG: 80))
        let reader = LocalNutritionReader(store: log, goalStore: goals)

        let yesterday = try await reader.dailyFoodLog(date: "2026-09-24")
        let today = try await reader.dailyFoodLog(date: "2026-09-25")
        let beforeAny = try await reader.dailyFoodLog(date: "2026-08-15")
        XCTAssertEqual(yesterday?.dailyNutritionGoals?.calories, 1900)
        XCTAssertEqual(today?.dailyNutritionGoals?.calories, 1800)
        XCTAssertEqual(today?.dailyNutritionGoals?.protein, 80)
        XCTAssertNil(beforeAny?.dailyNutritionGoals, "no goal set: intake without a target")
    }

    func testALocalDayNearItsGoalIsJudgedMetLikeAGarminDay() async throws {
        let tmp = FileManager.default.temporaryDirectory
        let log = LocalFoodLogStore(directoryURL: tmp.appendingPathComponent("local-goals-log-\(UUID().uuidString)"))
        let (goals, _) = makeStore()
        try await goals.save(LocalNutritionGoals(effectiveFrom: "2026-09-25", calories: 1800))
        let food = LocalFoodRef(id: "gulas", source: .garmin, name: "Guláš")
        try await log.append([
            LocalLogEntry(day: "2026-09-25", mealType: .lunch, loggedAt: Date(timeIntervalSince1970: 1_790_000_000), food: food, servingId: "s", quantity: 1, nutrients: [NutrientKind.calories.rawValue: 1790]),
        ])
        let reader = LocalNutritionReader(store: log, goalStore: goals)

        let read = try await reader.dailyFoodLog(date: "2026-09-25")
        let day = try XCTUnwrap(read)
        let judgement = try XCTUnwrap(GoalStatusEvaluator.evaluate(day))
        XCTAssertTrue(judgement.metCalorieGoal, "1790 of 1800 kcal is on target, as in Garmin mode")
    }
}

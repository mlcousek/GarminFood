import XCTest
@testable import Gamification
import FoodLogCore

final class LifetimeStatsStoreTests: XCTestCase {
    private func makeStore() -> LifetimeStatsStore {
        LifetimeStatsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-lifetime-\(UUID().uuidString).json"))
    }

    private func event(_ foodId: String, day: Int, hour: Int = 12) -> UsageEvent {
        UsageEvent(foodId: foodId, servingId: "s1", numberOfUnits: 1, timestamp: TestClock.date(2026, 1, day, hour: hour))
    }

    private func goalStatus(day: Int, protein: Bool = false) -> DailyGoalStatus {
        DailyGoalStatus(date: String(format: "2026-01-%02d", day), metCalorieGoal: false, metProteinGoal: protein, metCarbGoal: false, metFatGoal: false)
    }

    func testRecordLogAccumulatesTotalsAndFirstLogDate() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 500, now: TestClock.date(2026, 1, 1))
        try await store.recordLog(nutritionDay: "2026-01-01", calories: 300, now: TestClock.date(2026, 1, 1, hour: 18))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 2)
        XCTAssertEqual(snapshot.totalCaloriesEver, 800)
        XCTAssertEqual(snapshot.firstLogDate, TestClock.date(2026, 1, 1))
    }

    func testMaxSingleDayCaloriesTracksTheRunningDayTotalAcrossMultipleLogs() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 2000, now: TestClock.date(2026, 1, 5))
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 3500, now: TestClock.date(2026, 1, 5, hour: 20))
        // A later log on a DIFFERENT (smaller) day must not lower the
        // already-recorded max.
        try await store.recordLog(nutritionDay: "2026-01-06", calories: 400, now: TestClock.date(2026, 1, 6))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.maxSingleDayCalories, 5500)
    }

    func testMaxSingleDayCaloriesHandlesABackdatedLogReturningToAnEarlierDay() async throws {
        let store = makeStore()
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 1000, now: TestClock.date(2026, 1, 5))
        try await store.recordLog(nutritionDay: "2026-01-06", calories: 200, now: TestClock.date(2026, 1, 6))
        // Logged now, but backdated to the 5th -- should ADD to that day's
        // already-accumulated running total, not start a fresh one.
        try await store.recordLog(nutritionDay: "2026-01-05", calories: 4600, now: TestClock.date(2026, 1, 6, hour: 21))

        let snapshot = await store.current()
        XCTAssertEqual(snapshot.maxSingleDayCalories, 5600, "revisiting an earlier tracked day must accumulate onto its existing total, not reset it")
    }

    func testRecordGoalStatusCountsEachDayAtMostOncePerMacro() async throws {
        let store = makeStore()
        try await store.recordGoalStatus(goalStatus(day: 1, protein: true))
        try await store.recordGoalStatus(goalStatus(day: 1, protein: true)) // re-fetch of the same day
        try await store.recordGoalStatus(goalStatus(day: 2, protein: true))

        let count = await store.goalHitDays(.protein)
        XCTAssertEqual(count, 2, "re-recording the same day must not double-count")
    }

    func testBackfillSeedsFromRetainedHistoryOnlyWhenTheLedgerIsEmpty() async throws {
        let store = makeStore()
        let events = [event("a", day: 1), event("b", day: 3)]
        let goals = [goalStatus(day: 1, protein: true), goalStatus(day: 3, protein: true)]

        try await store.backfillIfEmpty(events: events, goalStatuses: goals)
        var snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 2)
        XCTAssertEqual(snapshot.firstLogDate, TestClock.date(2026, 1, 1))
        let proteinDays = await store.goalHitDays(.protein)
        XCTAssertEqual(proteinDays, 2)

        // A real log then arrives; a second backfill call must not
        // overwrite or double-count the now-nonempty ledger.
        try await store.recordLog(nutritionDay: "2026-01-10", calories: nil, now: TestClock.date(2026, 1, 10))
        try await store.backfillIfEmpty(events: events, goalStatuses: goals)
        snapshot = await store.current()
        XCTAssertEqual(snapshot.totalLogsEver, 3, "backfill must not re-run once the ledger has real data")
    }
}

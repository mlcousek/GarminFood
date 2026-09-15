import XCTest
@testable import Gamification

final class GoalStatusStoreTests: XCTestCase {
    private func makeStore() -> GoalStatusStore {
        GoalStatusStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-goals-\(UUID().uuidString).json"))
    }

    func testRecordAndReadBack() async throws {
        let store = makeStore()
        try await store.record(DailyGoalStatus(date: "2026-01-01", metCalorieGoal: true, metProteinGoal: false, metCarbGoal: false, metFatGoal: true))
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.date, "2026-01-01")
        XCTAssertTrue(all.first?.anyGoalMet ?? false)
    }

    func testRecordingTheSameDayTwiceOverwritesRatherThanDuplicates() async throws {
        let store = makeStore()
        try await store.record(DailyGoalStatus(date: "2026-01-01", metCalorieGoal: false, metProteinGoal: false, metCarbGoal: false, metFatGoal: false))
        try await store.record(DailyGoalStatus(date: "2026-01-01", metCalorieGoal: true, metProteinGoal: true, metCarbGoal: true, metFatGoal: true))
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
        XCTAssertTrue(all.first?.metCalorieGoal ?? false)
    }

    func testPersistsAcrossInstancesPointingAtTheSameFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("gamification-goals-\(UUID().uuidString).json")
        let store1 = GoalStatusStore(fileURL: fileURL)
        try await store1.record(DailyGoalStatus(date: "2026-01-01", metCalorieGoal: true, metProteinGoal: true, metCarbGoal: false, metFatGoal: false))

        let store2 = GoalStatusStore(fileURL: fileURL)
        let all = await store2.all()
        XCTAssertEqual(all.count, 1)
    }

    func testOldestDaysAreTrimmedPastTheCap() async throws {
        let store = makeStore()
        for i in 1...(GoalStatusStore.maxStoredDays + 5) {
            try await store.record(DailyGoalStatus(date: String(format: "2026-%03d", i), metCalorieGoal: false, metProteinGoal: false, metCarbGoal: false, metFatGoal: false))
        }
        let all = await store.all()
        XCTAssertEqual(all.count, GoalStatusStore.maxStoredDays)
        XCTAssertEqual(all.first?.date, "2026-006", "the oldest 5 entries should have been trimmed")
    }

    func testAnyGoalMetIsFalseWhenNoGoalWasMet() {
        let status = DailyGoalStatus(date: "2026-01-01", metCalorieGoal: false, metProteinGoal: false, metCarbGoal: false, metFatGoal: false)
        XCTAssertFalse(status.anyGoalMet)
    }

    func testMetHelperReadsTheRightMacro() {
        let status = DailyGoalStatus(date: "2026-01-01", metCalorieGoal: false, metProteinGoal: true, metCarbGoal: false, metFatGoal: false)
        XCTAssertTrue(status.met(.protein))
        XCTAssertFalse(status.met(.calories))
    }
}

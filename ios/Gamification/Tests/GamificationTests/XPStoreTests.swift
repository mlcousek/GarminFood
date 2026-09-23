import XCTest
@testable import Gamification

final class XPStoreTests: XCTestCase {
    private func makeStore() -> XPStore {
        XPStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("gamification-xp-\(UUID().uuidString).json"))
    }

    func testFlatXPIsAwardedForEveryLogRegardlessOfStreakOrGoal() async throws {
        let store = makeStore()
        let result = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: false)
        XCTAssertEqual(result.xpAwarded, XPAward.flatPerLog)
        XCTAssertEqual(result.totalXPAfter, XPAward.flatPerLog)
    }

    func testMultipleLogsTheSameDayEachAwardTheFlatAmount() async throws {
        // Levels spec: "each entry awards the flat per-log XP amount,
        // without an escalating bonus for logging multiple entries at
        // once."
        let store = makeStore()
        _ = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: true, goalMetToday: false)
        let second = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: false)
        let third = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: false)
        XCTAssertEqual(second.xpAwarded, XPAward.flatPerLog)
        XCTAssertEqual(third.xpAwarded, XPAward.flatPerLog)
    }

    func testStreakBonusIsOnlyAwardedOncePerNutritionDay() async throws {
        let store = makeStore()
        let first = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: true, goalMetToday: false)
        XCTAssertTrue(first.streakBonusAwarded)
        XCTAssertEqual(first.xpAwarded, XPAward.flatPerLog + XPAward.streakExtensionBonus)

        // A caller mistakenly (or a retried request) claiming the streak
        // extended AGAIN the same day must not double-pay the bonus.
        let second = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: true, goalMetToday: false)
        XCTAssertFalse(second.streakBonusAwarded)
        XCTAssertEqual(second.xpAwarded, XPAward.flatPerLog)
    }

    func testGoalBonusIsOnlyAwardedOncePerNutritionDay() async throws {
        let store = makeStore()
        let first = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: true)
        XCTAssertTrue(first.goalBonusAwarded)
        let second = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: true)
        XCTAssertFalse(second.goalBonusAwarded)
    }

    func testBothBonusesCanApplyOnTheSameDayForDifferentReasons() async throws {
        let store = makeStore()
        let result = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: true, goalMetToday: true)
        XCTAssertEqual(result.xpAwarded, XPAward.flatPerLog + XPAward.streakExtensionBonus + XPAward.goalHitBonus)
    }

    func testBonusesResetOnANewNutritionDay() async throws {
        let store = makeStore()
        _ = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: true, goalMetToday: true)
        let nextDay = try await store.recordLog(nutritionDay: "2026-01-02", streakExtendedToday: true, goalMetToday: true)
        XCTAssertTrue(nextDay.streakBonusAwarded)
        XCTAssertTrue(nextDay.goalBonusAwarded)
    }

    func testTotalXPPersistsAcrossStoreInstancesPointingAtTheSameFile() async throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("gamification-xp-\(UUID().uuidString).json")
        let store1 = XPStore(fileURL: fileURL)
        _ = try await store1.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: false)

        let store2 = XPStore(fileURL: fileURL)
        let total = await store2.currentTotal()
        XCTAssertEqual(total, XPAward.flatPerLog)
    }

    func testDidLevelUpIsTrueOnlyOnTheLogThatCrossesTheThreshold() async throws {
        let store = makeStore()
        let threshold = LevelCurve.xpRequired(afterLevel: 1)
        let logsNeeded = Int((Double(threshold) / Double(XPAward.flatPerLog)).rounded(.up))

        var lastResult: XPAwardResult?
        for i in 1...logsNeeded {
            let result = try await store.recordLog(nutritionDay: "day-\(i)", streakExtendedToday: false, goalMetToday: false)
            if i < logsNeeded {
                XCTAssertFalse(result.didLevelUp, "should not level up before the \(logsNeeded)th log")
            }
            lastResult = result
        }
        XCTAssertTrue(lastResult?.didLevelUp ?? false, "the log that reaches/crosses the threshold must trigger a level-up")
    }

    func testChallengeCompletionAwardsItsOwnBonus() async throws {
        let store = makeStore()
        let result = try await store.recordChallengeCompletion()
        XCTAssertEqual(result.xpAwarded, XPAward.challengeCompletionBonus)
    }

    /// openspec/changes/fix-silent-store-wipe: an undecodable XP ledger used
    /// to start at 0 and then be overwritten by the very next log, wiping
    /// the user's lifetime XP with no copy anywhere else. The original
    /// bytes must now survive, moved aside next to the ledger file.
    func testUndecodableLedgerIsQuarantinedNotOverwrittenByTheNextLog() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gamification-xp-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("xp-ledger.json")
        let garbage = Data(#"{"totalXP":"lots"}"#.utf8)
        try garbage.write(to: fileURL)

        let store = XPStore(fileURL: fileURL)
        let before = await store.currentTotal()
        XCTAssertEqual(before, 0)

        _ = try await store.recordLog(nutritionDay: "2026-01-01", streakExtendedToday: false, goalMetToday: false)

        let after = await store.currentTotal()
        XCTAssertEqual(after, XPAward.flatPerLog)
        let quarantined = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("xp-ledger.unreadable-") && $0.pathExtension == "json" }
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, garbage)
    }
}

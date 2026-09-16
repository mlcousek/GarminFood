import XCTest
@testable import Gamification

final class ChallengeHistoryStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("challenge-history-\(UUID().uuidString).json")
    }

    func testCompletionsAreListedNewestFirst() async throws {
        let store = ChallengeHistoryStore(fileURL: tempURL())
        try await store.record(CompletedChallenge(templateId: "perfect-week", completedAt: TestClock.date(2026, 1, 7), xpAwarded: 50))
        try await store.record(CompletedChallenge(templateId: "explorer", completedAt: TestClock.date(2026, 1, 17), xpAwarded: 50))

        let all = await store.all()

        XCTAssertEqual(all.map(\.templateId), ["explorer", "perfect-week"])
    }

    func testCompletionsSurviveARelaunch() async throws {
        let url = tempURL()
        try await ChallengeHistoryStore(fileURL: url).record(
            CompletedChallenge(templateId: "goal-getter", completedAt: TestClock.date(2026, 1, 3), xpAwarded: 75)
        )

        let reopened = await ChallengeHistoryStore(fileURL: url).all()

        XCTAssertEqual(reopened.count, 1)
        XCTAssertEqual(reopened.first?.templateId, "goal-getter")
        XCTAssertEqual(reopened.first?.xpAwarded, 75)
        XCTAssertEqual(reopened.first?.completedAt, TestClock.date(2026, 1, 3))
    }

    func testHistoryIsCapped() async throws {
        let store = ChallengeHistoryStore(fileURL: tempURL())
        for index in 0..<(ChallengeHistoryStore.maxStoredRecords + 5) {
            try await store.record(CompletedChallenge(templateId: "t\(index)", completedAt: Date(timeIntervalSince1970: Double(index)), xpAwarded: 1))
        }

        let all = await store.all()

        XCTAssertEqual(all.count, ChallengeHistoryStore.maxStoredRecords)
        XCTAssertEqual(all.first?.templateId, "t\(ChallengeHistoryStore.maxStoredRecords + 4)")
        XCTAssertEqual(all.last?.templateId, "t5", "the oldest records are the ones dropped")
    }

    func testAMissingFileIsAnEmptyHistory() async {
        let all = await ChallengeHistoryStore(fileURL: tempURL()).all()

        XCTAssertTrue(all.isEmpty)
    }
}

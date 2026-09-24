// FoodLoggingTests.swift
//
// add-standalone-mode 1.4 (design D4): the write seam must change nothing
// in Garmin mode. `ModeRoutingFoodLogging` forwards to the Garmin
// `LogEntryCoordinator` with every argument intact, and the synced-row
// delete moved out of `DayLogLoader` still makes exactly the one Garmin
// call it made before. Real `Outbox` per test (LogEntryCoordinatorTests'
// pattern); the Garmin delete is recorded by a fake `FoodLogReconciling`,
// since the real one is the network.

import XCTest
@testable import FoodLogCore
import GarminKit

final class FoodLoggingTests: XCTestCase {
    private actor RecordingGarminLog: FoodLogReconciling {
        private(set) var deletes: [(logIds: [String], date: String)] = []

        func dailyFoodLog(date: String) async throws -> DailyFoodLog? { nil }

        @discardableResult
        func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
            deletes.append((logIds, date))
            return HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        }
    }

    private let food = Food(id: "food-1", name: "Test food", source: .garmin, servings: [Serving(id: "serving-1", unit: "g", numberOfUnits: 100)])

    private func makeOutbox() -> Outbox {
        Outbox(processName: "foodlogging-test-\(UUID().uuidString)")
    }

    private func makeCoordinator(outbox: Outbox, garminLog: (any FoodLogReconciling)? = nil) -> LogEntryCoordinator {
        let tmp = FileManager.default.temporaryDirectory
        return LogEntryCoordinator(
            outbox: outbox,
            usageHistory: UsageHistoryStore(fileURL: tmp.appendingPathComponent("foodlogging-usage-\(UUID().uuidString).json")),
            servingDefaults: ServingDefaultStore(fileURL: tmp.appendingPathComponent("foodlogging-servings-\(UUID().uuidString).json")),
            garminLog: garminLog
        )
    }

    func testRouterForwardsAConfirmToTheGarminOutboxUnchanged() async throws {
        let outbox = makeOutbox()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: outbox))

        let entry = try await router.confirm(
            food: food, serving: food.servings[0], numberOfUnits: 2, mealType: .lunch, date: "2026-09-24",
            regionCode: "CZ", languageCode: "cs"
        )

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertEqual(stored.first?.numberOfUnits, 2)
        XCTAssertEqual(stored.first?.regionCode, "CZ")
        XCTAssertEqual(stored.first?.languageCode, "cs")
    }

    func testRouterForwardsAPendingDeleteToTheGarminOutbox() async throws {
        let outbox = makeOutbox()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: outbox))
        let entry = try await router.confirm(food: food, serving: food.servings[0], numberOfUnits: 1, mealType: .breakfast, date: "2026-09-24")

        let outcome = try await router.deletePending(outboxId: entry.id)

        XCTAssertEqual(outcome, .removed)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testDeleteCommittedDeletesExactlyThatLogIdInGarmin() async throws {
        let garminLog = RecordingGarminLog()
        let router = ModeRoutingFoodLogging(garmin: makeCoordinator(outbox: makeOutbox(), garminLog: garminLog))

        try await router.deleteCommitted(logId: "abc123", date: "2026-09-24")

        let deletes = await garminLog.deletes
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.logIds, ["abc123"])
        XCTAssertEqual(deletes.first?.date, "2026-09-24")
    }

    func testDeleteCommittedWithoutAGarminLogThrowsInsteadOfPretending() async throws {
        let coordinator = makeCoordinator(outbox: makeOutbox())

        do {
            try await coordinator.deleteCommitted(logId: "abc123", date: "2026-09-24")
            XCTFail("expected a throw")
        } catch let error as CommittedDeleteError {
            XCTAssertEqual(error, .noSystemOfRecord)
        }
    }
}

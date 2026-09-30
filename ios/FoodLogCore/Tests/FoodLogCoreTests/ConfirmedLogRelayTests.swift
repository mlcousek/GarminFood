// ConfirmedLogRelayTests.swift
//
// fix-review-findings-2026-09 finding 1: a quick-pick Control / Siri log
// must reach the app's gamification award exactly once -- never skipped
// (the bug: it bypassed `GamificationEngine` entirely) and never doubled.
// `QuickPickCommit` is the testable core of `QuickPickControlAction.
// performLog`; it runs here against a REAL `LogEntryCoordinator` and outbox
// (same pattern as LogEntryCoordinatorTests), with the relay's handler
// standing in for `GamificationEngine.handleLogConfirmed`.

import XCTest
@testable import FoodLogCore
import GarminKit

final class ConfirmedLogRelayTests: XCTestCase {
    private let food = Food(id: "garmin-1", name: "Synthetic roll", source: .fatSecret, servings: [
        Serving(id: "s-piece", unit: "piece", numberOfUnits: 1, calories: 130)
    ])

    private let customFood = CustomFoodDraft(
        name: "Synthetic bowl",
        servingUnit: "bowl",
        numberOfUnits: 1,
        calories: 180,
        backingFoodId: "garmin-42",
        backingFoodName: "Synthetic backing",
        backingServingId: "garmin-serving-7",
        backingQuantityMultiplier: 2
    )

    private func makeCoordinator() -> (LogEntryCoordinator, Outbox) {
        let tmp = FileManager.default.temporaryDirectory
        let outbox = Outbox(processName: "relay-test-\(UUID().uuidString)")
        let coordinator = LogEntryCoordinator(
            outbox: outbox,
            usageHistory: UsageHistoryStore(fileURL: tmp.appendingPathComponent("relay-usage-\(UUID().uuidString).json")),
            servingDefaults: ServingDefaultStore(fileURL: tmp.appendingPathComponent("relay-defaults-\(UUID().uuidString).json"))
        )
        return (coordinator, outbox)
    }

    /// Collects what the handler (the engine, in the app) was given.
    private final class Awards {
        var logs: [ConfirmedLog] = []
    }

    @MainActor
    func testAQuickPickLogIsAwardedExactlyOnceWhenTheAppIsRunning() async throws {
        let (coordinator, outbox) = makeCoordinator()
        let relay = ConfirmedLogRelay()
        let awards = Awards()
        await relay.attach { awards.logs.append($0) }

        let entry = try await QuickPickCommit.commit(
            .catalog(food: food, serving: food.servings[0], numberOfUnits: 2),
            using: coordinator, mealType: .lunch, date: "2026-09-30", relay: relay
        )

        let committed = await outbox.allEntries()
        XCTAssertEqual(committed.map(\.id), [entry.id], "the entry is committed durably")
        XCTAssertEqual(awards.logs.map(\.id), [entry.id], "and handed to gamification exactly once")
        XCTAssertEqual(awards.logs.first?.calories, 260, "the same calories the confirm screen would award (130 x 2)")
    }

    @MainActor
    func testALogMadeBeforeTheAppAttachesIsHeldThenAwardedOnce() async throws {
        let (coordinator, _) = makeCoordinator()
        let relay = ConfirmedLogRelay()

        let entry = try await QuickPickCommit.commit(
            .custom(customFood, quantity: 1.5),
            using: coordinator, mealType: .breakfast, date: "2026-09-30", relay: relay
        )
        XCTAssertEqual(relay.pendingCount, 1, "no handler yet: held, not dropped")

        let awards = Awards()
        await relay.attach { awards.logs.append($0) }
        XCTAssertEqual(awards.logs.map(\.id), [entry.id])
        XCTAssertEqual(awards.logs.first?.calories, 270, "a custom food's own calories x quantity (180 x 1.5)")
        XCTAssertEqual(relay.pendingCount, 0)

        // A second attach (or any later reconcile) must not replay it.
        let later = Awards()
        await relay.attach { later.logs.append($0) }
        XCTAssertTrue(later.logs.isEmpty, "never awarded twice")
    }

    @MainActor
    func testTheSameLogReportedTwiceIsAwardedOnce() async {
        let relay = ConfirmedLogRelay()
        let awards = Awards()
        await relay.attach { awards.logs.append($0) }
        let log = ConfirmedLog(id: UUID(), calories: 100, loggedAt: Date())

        await relay.report(log)
        await relay.report(log)

        XCTAssertEqual(awards.logs.count, 1)
    }

    @MainActor
    func testAFailedCommitAwardsNothing() async {
        let (coordinator, _) = makeCoordinator()
        let relay = ConfirmedLogRelay()
        let awards = Awards()
        await relay.attach { awards.logs.append($0) }

        // An invalid quantity is refused by the coordinator before anything
        // is written (LogQuantity bounds).
        do {
            try await QuickPickCommit.commit(
                .catalog(food: food, serving: food.servings[0], numberOfUnits: -1),
                using: coordinator, mealType: .lunch, date: "2026-09-30", relay: relay
            )
            XCTFail("expected the coordinator to refuse a negative quantity")
        } catch {
            XCTAssertTrue(awards.logs.isEmpty, "nothing committed, nothing awarded")
        }
    }
}

// StandaloneWeightWaterTests.swift
//
// add-standalone-mode 4.4 (data-mode spec, "Weight and water stay on the
// phone in standalone mode"): with `deliversToGarmin` false the weight and
// hydration coordinators commit to their local store only -- no outbox
// entry, no Garmin delete, no negative correction -- and the standalone
// display helpers read only local entries. Real stores and outboxes on
// unique temp files / process names (no mocks), as in the coordinators'
// own tests.

import XCTest
@testable import FoodLogCore
import GarminKit

final class StandaloneWeightWaterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func weight(deliversToGarmin: Bool) -> (WeightLogCoordinator, WeightStore, WeightOutbox) {
        let store = WeightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("standalone-weight-\(UUID().uuidString).json"))
        let outbox = WeightOutbox(processName: "standalone-weight-\(UUID().uuidString)")
        return (WeightLogCoordinator(store: store, outbox: outbox, deliversToGarmin: { deliversToGarmin }), store, outbox)
    }

    private func water(deliversToGarmin: Bool) -> (HydrationLogCoordinator, HydrationStore, HydrationOutbox) {
        let store = HydrationStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("standalone-water-\(UUID().uuidString).json"))
        let outbox = HydrationOutbox(processName: "standalone-water-\(UUID().uuidString)")
        return (HydrationLogCoordinator(store: store, outbox: outbox, deliversToGarmin: { deliversToGarmin }), store, outbox)
    }

    // MARK: Weight

    func testAStandaloneWeighInIsLocalOnly() async throws {
        let (coordinator, store, outbox) = weight(deliversToGarmin: false)
        let entry = try await coordinator.logWeight(weightKg: 61.4, loggedAt: now, now: now)

        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id])
        XCTAssertNil(entry.outboxEntryId)
        XCTAssertTrue(queued.isEmpty, "nothing is ever sent in standalone mode")
    }

    func testDeletingAStandaloneWeighInQueuesNoGarminDelete() async throws {
        let (coordinator, store, outbox) = weight(deliversToGarmin: false)
        let entry = try await coordinator.logWeight(weightKg: 61.4, loggedAt: now, now: now)
        let row = try XCTUnwrap(WeightAndWaterOverview.standaloneWeightRows(localEntries: [entry]).first)

        let result = try await coordinator.delete(row)

        XCTAssertEqual(result, .cancelledBeforeDelivery)
        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertTrue(queued.isEmpty)
    }

    func testGarminModeStillQueuesTheWeighIn() async throws {
        let (coordinator, _, outbox) = weight(deliversToGarmin: true)
        let entry = try await coordinator.logWeight(weightKg: 80, loggedAt: now, now: now)
        let queued = await outbox.allEntries()
        let outboxId = try XCTUnwrap(entry.outboxEntryId)
        XCTAssertEqual(queued.map(\.id), [outboxId])
    }

    func testTheFlagIsReadOnEveryCall() async throws {
        let store = WeightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("standalone-weight-\(UUID().uuidString).json"))
        let outbox = WeightOutbox(processName: "standalone-weight-\(UUID().uuidString)")
        let flag = Flag(true)
        let coordinator = WeightLogCoordinator(store: store, outbox: outbox, deliversToGarmin: { flag.value })

        _ = try await coordinator.logWeight(weightKg: 80, loggedAt: now, now: now)
        flag.value = false
        _ = try await coordinator.logWeight(weightKg: 79, loggedAt: now, now: now)

        let queued = await outbox.allEntries()
        let stored = await store.all()
        XCTAssertEqual(queued.count, 1, "only the weigh-in logged in Garmin mode is queued")
        XCTAssertEqual(stored.count, 2)
    }

    func testStandaloneRowsAreLocalAndUnbadged() {
        let entries = [
            WeightEntry(weightKg: 62, loggedAt: now.addingTimeInterval(-86_400), createdAt: now, outboxEntryId: UUID()),
            WeightEntry(weightKg: 61.5, loggedAt: now, createdAt: now),
        ]
        let rows = WeightAndWaterOverview.standaloneWeightRows(localEntries: entries)
        XCTAssertEqual(rows.map(\.weightKg), [61.5, 62], "newest first")
        XCTAssertTrue(rows.allSatisfy { $0.syncState == .synced }, "no 'not in Garmin yet' badge in standalone mode")
    }

    func testTheStandaloneWeightGoalStartsAtTheFirstWeighIn() throws {
        let entries = [
            WeightEntry(weightKg: 61.5, loggedAt: now, createdAt: now),
            WeightEntry(weightKg: 64, loggedAt: now.addingTimeInterval(-30 * 86_400), createdAt: now),
        ]
        let goal = try XCTUnwrap(WeightAndWaterOverview.standaloneWeightGoal(targetOverrideKg: 58, startOverrideKg: nil, localEntries: entries))
        XCTAssertEqual(goal.targetKg, 58)
        XCTAssertEqual(goal.startKg, 64)
        XCTAssertNil(WeightAndWaterOverview.standaloneWeightGoal(targetOverrideKg: nil, startOverrideKg: nil, localEntries: entries), "no target set")
    }

    // MARK: Water (spec: "Logging water standalone")

    func testLoggingWaterStandaloneRaisesTheLocalTotalAndLeavesTheOutboxEmpty() async throws {
        let (coordinator, store, outbox) = water(deliversToGarmin: false)
        _ = try await coordinator.logHydration(valueInML: 500, loggedAt: now, now: now)
        let first = await store.all()
        let before = WeightAndWaterOverview.standaloneWaterTotalML(entries: first, on: now)
        _ = try await coordinator.logHydration(valueInML: 250, loggedAt: now, now: now)
        let second = await store.all()
        let after = WeightAndWaterOverview.standaloneWaterTotalML(entries: second, on: now)

        XCTAssertEqual(after - before, 250)
        let queued = await outbox.allEntries()
        XCTAssertTrue(queued.isEmpty)
    }

    func testRemovingADrinkStandaloneQueuesNoCorrection() async throws {
        let (coordinator, store, outbox) = water(deliversToGarmin: false)
        let drink = try await coordinator.logHydration(valueInML: 300, loggedAt: now, now: now)

        let result = try await coordinator.removeHydration(drink)

        XCTAssertEqual(result, .cancelledBeforeDelivery)
        let stored = await store.all()
        let queued = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
        XCTAssertTrue(queued.isEmpty, "no negative correction without Garmin")
    }

    func testTheStandaloneWaterGoalIsTheOverrideOr2000() {
        XCTAssertEqual(WeightAndWaterOverview.standaloneWaterGoal(overrideML: nil).milliliters, 2000)
        XCTAssertEqual(WeightAndWaterOverview.standaloneWaterGoal(overrideML: 2500).milliliters, 2500)
    }
}

/// A mutable flag a `@Sendable` closure can read (the test flips the mode).
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

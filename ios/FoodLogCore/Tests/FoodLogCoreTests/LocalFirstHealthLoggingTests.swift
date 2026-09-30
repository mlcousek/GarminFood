// LocalFirstHealthLoggingTests.swift
//
// fix-review-findings-2026-09 finding 4: a weigh-in or drink whose LOCAL
// save failed (the user saw an error) must never be delivered to Garmin
// later. The coordinators used to enqueue first and save second, so a
// failed save left an unacknowledged entry in the outbox. The local store
// here is failure-injected: its file sits "inside" a regular file, so every
// write fails, exactly like a full or unwritable disk.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LocalFirstHealthLoggingTests: XCTestCase {
    /// A file URL no write can ever succeed at (its parent is a file).
    private func unwritableURL(_ name: String) throws -> URL {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("blocker-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blocker)
        return blocker.appendingPathComponent(name)
    }

    func testAFailedLocalWeightSaveQueuesNothingForGarmin() async throws {
        let store = WeightStore(fileURL: try unwritableURL("weight.json"))
        let outbox = WeightOutbox(processName: "local-first-weight-\(UUID().uuidString)")
        let coordinator = WeightLogCoordinator(store: store, outbox: outbox)

        do {
            try await coordinator.logWeight(weightKg: 71.4)
            XCTFail("the local save must fail in this test")
        } catch {
            let queued = await outbox.allEntries()
            XCTAssertTrue(queued.isEmpty, "a save the user saw fail must never sync")
            let listed = await store.all()
            XCTAssertTrue(listed.isEmpty, "and it isn't listed from memory either")
        }
    }

    func testAFailedLocalDrinkSaveQueuesNothingForGarmin() async throws {
        let store = HydrationStore(fileURL: try unwritableURL("hydration.json"))
        let outbox = HydrationOutbox(processName: "local-first-water-\(UUID().uuidString)")
        let coordinator = HydrationLogCoordinator(store: store, outbox: outbox)

        do {
            try await coordinator.logHydration(valueInML: 330)
            XCTFail("the local save must fail in this test")
        } catch {
            let queued = await outbox.allEntries()
            XCTAssertTrue(queued.isEmpty, "a save the user saw fail must never sync")
            let listed = await store.all()
            XCTAssertTrue(listed.isEmpty)
        }
    }

    func testASuccessfulSaveStillLinksTheLocalRecordToItsQueuedEntry() async throws {
        let store = HydrationStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("local-first-ok-\(UUID().uuidString).json"))
        let outbox = HydrationOutbox(processName: "local-first-ok-\(UUID().uuidString)")
        let coordinator = HydrationLogCoordinator(store: store, outbox: outbox)

        let entry = try await coordinator.logHydration(valueInML: 330)

        let queued = await outbox.allEntries()
        XCTAssertEqual(queued.map(\.id), [try XCTUnwrap(entry.outboxEntryId)])
        XCTAssertEqual(queued.first?.valueInML, 330)
    }
}

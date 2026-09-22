// HydrationLogCoordinatorTests.swift
//
// Confirm-and-commit flow tests for hydration, mirroring
// WeightLogCoordinatorTests.swift's own rationale: uses REAL `GarminKit.
// HydrationOutbox`/`HydrationStore` instances via their public
// initializers (uniquely-named/pathed per test), never mocks.
// `HydrationOutbox.logHydration` never touches the network (same as
// `WeightOutbox.logWeight`), so this stays a fast, offline unit test.

import XCTest
@testable import FoodLogCore
import GarminKit

final class HydrationLogCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> (coordinator: HydrationLogCoordinator, store: HydrationStore, outbox: HydrationOutbox) {
        let store = HydrationStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("hydration-coordinator-store-\(UUID().uuidString).json"))
        let outbox = HydrationOutbox(processName: "hydration-coordinator-test-\(UUID().uuidString)")
        let coordinator = HydrationLogCoordinator(store: store, outbox: outbox)
        return (coordinator, store, outbox)
    }

    func testLogHydrationCommitsLocallyAndEnqueuesDurably() async throws {
        let (coordinator, store, outbox) = makeCoordinator()

        let entry = try await coordinator.logHydration(valueInML: 250)

        let storedEntries = await store.all()
        XCTAssertEqual(storedEntries.map(\.id), [entry.id])
        XCTAssertEqual(storedEntries.first?.valueInML, 250)

        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.count, 1)
        XCTAssertEqual(outboxEntries.first?.id, entry.outboxEntryId, "the local entry links back to the exact outbox entry it enqueued")
        XCTAssertEqual(outboxEntries.first?.valueInML, 250)
        XCTAssertEqual(outboxEntries.first?.state, .pending, "logging does not itself deliver -- that's the outbox drain's job")
    }

    func testLogHydrationHonoursABackdatedLoggedAt() async throws {
        let (coordinator, _, outbox) = makeCoordinator()
        let backdated = Date(timeIntervalSince1970: 1_700_000_000)

        let entry = try await coordinator.logHydration(valueInML: 500, loggedAt: backdated)

        XCTAssertEqual(entry.loggedAt, backdated)
        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.first?.loggedAt, backdated, "the backdated time is what gets sent to Garmin")
    }

    func testDeleteHydrationRemovesBothLocalRecordAndAStillPendingOutboxEntry() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let entry = try await coordinator.logHydration(valueInML: 250)

        try await coordinator.deleteHydration(entry)

        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty)
        let outboxEntries = await outbox.allEntries()
        XCTAssertTrue(outboxEntries.isEmpty, "an undelivered entry must never be sent after its local record was deleted")
    }

    func testDeleteHydrationLeavesAnAlreadySentOutboxEntryAlone() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let entry = try await coordinator.logHydration(valueInML: 250)

        // Actually deliver it, via a real drain against a fake that always
        // succeeds, so the outbox entry genuinely reaches `.sent` rather
        // than being faked in-memory.
        _ = await outbox.drain(using: AlwaysSucceedsHydrationDeliverer())
        let beforeDelete = await outbox.allEntries()
        XCTAssertEqual(beforeDelete.first?.state, .sent, "precondition: delivery must have actually succeeded")

        try await coordinator.deleteHydration(entry)

        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty, "the local record is still removed")
        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.count, 1, "an already-delivered outbox entry is left alone -- it can't be recalled from Garmin")
        XCTAssertEqual(outboxEntries.first?.state, .sent)
    }
}

/// A `HydrationDelivering` fake that always succeeds -- lets a test drive a
/// real `HydrationOutbox.drain` to genuinely reach `.sent` state, mirroring
/// `WeightLogCoordinatorTests.swift`'s own `AlwaysSucceedsWeighInDeliverer`.
private struct AlwaysSucceedsHydrationDeliverer: HydrationDelivering {
    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/usersummary-service/usersummary/hydration/log")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

// WeightLogCoordinatorTests.swift
//
// Confirm-and-commit flow tests for weight, mirroring
// LogEntryCoordinatorTests.swift's own rationale: uses REAL `GarminKit.
// WeightOutbox`/`WeightStore` instances via their public initializers
// (uniquely-named/pathed per test), never mocks. `WeightOutbox.logWeight`
// never touches the network (GarminKit's own doc comment on `Outbox.logFood`
// says the same, and `WeightOutbox` mirrors it exactly), so this stays a
// fast, offline unit test.

import XCTest
@testable import FoodLogCore
import GarminKit

final class WeightLogCoordinatorTests: XCTestCase {
    private func makeCoordinator() -> (coordinator: WeightLogCoordinator, store: WeightStore, outbox: WeightOutbox) {
        let store = WeightStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("weight-coordinator-store-\(UUID().uuidString).json"))
        let outbox = WeightOutbox(processName: "weight-coordinator-test-\(UUID().uuidString)")
        let coordinator = WeightLogCoordinator(store: store, outbox: outbox)
        return (coordinator, store, outbox)
    }

    func testLogWeightCommitsLocallyAndEnqueuesDurably() async throws {
        let (coordinator, store, outbox) = makeCoordinator()

        let entry = try await coordinator.logWeight(weightKg: 75.5, note: "after breakfast")

        let storedEntries = await store.all()
        XCTAssertEqual(storedEntries.map(\.id), [entry.id])
        XCTAssertEqual(storedEntries.first?.weightKg, 75.5)
        XCTAssertEqual(storedEntries.first?.note, "after breakfast")

        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.count, 1)
        XCTAssertEqual(outboxEntries.first?.id, entry.outboxEntryId, "the local entry links back to the exact outbox entry it enqueued")
        XCTAssertEqual(outboxEntries.first?.weightKg, 75.5)
        XCTAssertEqual(outboxEntries.first?.state, .pending, "logging does not itself deliver -- that's the outbox drain's job")
    }

    func testLogWeightHonoursABackdatedLoggedAt() async throws {
        let (coordinator, _, outbox) = makeCoordinator()
        let backdated = Date(timeIntervalSince1970: 1_700_000_000)

        let entry = try await coordinator.logWeight(weightKg: 74, loggedAt: backdated)

        XCTAssertEqual(entry.loggedAt, backdated)
        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.first?.loggedAt, backdated, "the backdated time is what gets sent to Garmin")
    }

    func testDeleteWeightRemovesBothLocalRecordAndAStillPendingOutboxEntry() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let entry = try await coordinator.logWeight(weightKg: 75)

        try await coordinator.deleteWeight(entry)

        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty)
        let outboxEntries = await outbox.allEntries()
        XCTAssertTrue(outboxEntries.isEmpty, "an undelivered entry must never be sent after its local record was deleted")
    }

    func testDeleteWeightLeavesAnAlreadySentOutboxEntryAlone() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let entry = try await coordinator.logWeight(weightKg: 75)

        // Actually deliver it, via a real drain against a fake that always
        // succeeds, so the outbox entry genuinely reaches `.sent` rather
        // than being faked in-memory.
        _ = await outbox.drain(using: AlwaysSucceedsWeighInDeliverer())
        let beforeDelete = await outbox.allEntries()
        XCTAssertEqual(beforeDelete.first?.state, .sent, "precondition: delivery must have actually succeeded")

        try await coordinator.deleteWeight(entry)

        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty, "the local record is still removed")
        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.count, 1, "an already-delivered outbox entry is left alone -- it can't be recalled from Garmin")
        XCTAssertEqual(outboxEntries.first?.state, .sent)
    }
}

/// A `WeighInDelivering` fake that always succeeds -- lets a test drive a
/// real `WeightOutbox.drain` to genuinely reach `.sent` state, rather than
/// faking that state in memory (which `WeightOutboxEntry`'s public API
/// deliberately has no way to do -- `retry(id:)` only ever resets TO
/// `.pending`).
private struct AlwaysSucceedsWeighInDeliverer: WeighInDelivering {
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/user-weight")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

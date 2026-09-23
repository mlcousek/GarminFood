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

    // MARK: - delete(_:) on the merged history (sync-weight-hydration-with-garmin, D3)

    private func sample(pk: Int = 1_790_149_333_817, kg: Double = 83.9, at date: Date = Date(timeIntervalSince1970: 1_790_149_291.732)) -> GarminWeighIn {
        GarminWeighIn(samplePk: pk, calendarDate: "2026-09-23", weightGrams: kg * 1000, timestampGMT: date.timeIntervalSince1970 * 1000)
    }

    func testDeletingAGarminWeighInQueuesAGarminDeleteWithoutAnyNetworkCall() async throws {
        let (coordinator, _, outbox) = makeCoordinator()
        let garminOnly = WeighInDisplayEntry(source: .garmin(sample(), matchedLocalEntry: nil), syncState: .synced, outboxEntryId: nil)

        let result = try await coordinator.delete(garminOnly)

        XCTAssertEqual(result, .garminDeleteQueued)
        let queued = await outbox.allEntries()
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.kind, .delete)
        XCTAssertEqual(queued.first?.samplePk, 1_790_149_333_817)
        XCTAssertEqual(queued.first?.calendarDate, "2026-09-23")
        XCTAssertEqual(queued.first?.state, .pending, "queued, delivered later by the drain")
    }

    func testTheDeletedSampleIsHiddenFromTheMergedHistoryAtOnce() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let garminSample = sample()
        let row = WeighInDisplayEntry(source: .garmin(garminSample, matchedLocalEntry: nil), syncState: .synced, outboxEntryId: nil)

        try await coordinator.delete(row)

        let localEntries = await store.all()
        let outboxEntries = await outbox.allEntries()
        let merged = WeightHistoryMerge.merge(
            garminWeighIns: [garminSample],
            garminDayFetchedAt: ["2026-09-23": Date()],
            localEntries: localEntries,
            outboxEntries: outboxEntries
        )
        XCTAssertTrue(merged.isEmpty)
    }

    func testDeletingAGarminWeighInLoggedHereAlsoRemovesTheLocalRecord() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let local = try await coordinator.logWeight(weightKg: 83.9, loggedAt: Date(timeIntervalSince1970: 1_790_149_291.732))
        _ = await outbox.drain(using: AlwaysSucceedsWeighInDeliverer())
        let row = WeighInDisplayEntry(source: .garmin(sample(), matchedLocalEntry: local), syncState: .synced, outboxEntryId: nil)

        try await coordinator.delete(row)

        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty, "the app's own copy goes too, so it can't resurface")
        let deletes = await outbox.allEntries().filter { $0.kind == .delete }
        XCTAssertEqual(deletes.count, 1)
    }

    func testDeletingAPendingLocalEntryJustCancelsIt() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let local = try await coordinator.logWeight(weightKg: 80)
        let row = WeighInDisplayEntry(source: .local(local), syncState: .pending, outboxEntryId: local.outboxEntryId)

        let result = try await coordinator.delete(row)

        XCTAssertEqual(result, .cancelledBeforeDelivery)
        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty)
        let outboxEntries = await outbox.allEntries()
        XCTAssertTrue(outboxEntries.isEmpty, "no delete is queued for something Garmin never had")
    }

    func testDeletingAgainAfterAFailedDeleteRetriesItInsteadOfQueueingASecond() async throws {
        let (coordinator, _, outbox) = makeCoordinator()
        let row = WeighInDisplayEntry(source: .garmin(sample(), matchedLocalEntry: nil), syncState: .synced, outboxEntryId: nil)
        try await coordinator.delete(row)
        // `WeightOutbox(processName:)`'s default maxAttempts is 5; zero
        // jitter makes every backoff 0 s, so each drain retries at once.
        for _ in 0..<5 {
            _ = await outbox.drain(using: AlwaysFailsWeighInDeliverer(), randomJitter: { 0 })
        }
        let failed = await outbox.allEntries()
        XCTAssertEqual(failed.first?.state, .failed, "precondition: the delete gave up")

        try await coordinator.delete(row)

        let after = await outbox.allEntries()
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.state, .pending)
        XCTAssertEqual(after.first?.attemptCount, 0)
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

    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/weight/\(date)/byversion/\(samplePk)")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    }
}

/// Always fails with a server error -- drives a queued delete to `.failed`.
private struct AlwaysFailsWeighInDeliverer: WeighInDelivering {
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        throw GarminClientError.httpError(statusCode: 500, body: nil)
    }

    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse {
        throw GarminClientError.httpError(statusCode: 500, body: nil)
    }
}

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

    func testRemovingAnUndeliveredDrinkCancelsItWithoutAnyCorrection() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let entry = try await coordinator.logHydration(valueInML: 250)

        let result = try await coordinator.removeHydration(entry)

        XCTAssertEqual(result, .cancelledBeforeDelivery)
        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty)
        let outboxEntries = await outbox.allEntries()
        XCTAssertTrue(outboxEntries.isEmpty, "an undelivered entry must never be sent after its local record was deleted, and needs no correction")
    }

    func testRemovingADeliveredDrinkQueuesANegativeCorrectionForItsOwnTime() async throws {
        let (coordinator, store, outbox) = makeCoordinator()
        let loggedAt = Date(timeIntervalSince1970: 1_789_000_000)
        let entry = try await coordinator.logHydration(valueInML: 250, loggedAt: loggedAt)

        // Actually deliver it, via a real drain against a fake that always
        // succeeds, so the outbox entry genuinely reaches `.sent` rather
        // than being faked in-memory.
        _ = await outbox.drain(using: AlwaysSucceedsHydrationDeliverer())
        let beforeRemove = await outbox.allEntries()
        XCTAssertEqual(beforeRemove.first?.state, .sent, "precondition: delivery must have actually succeeded")

        let result = try await coordinator.removeHydration(entry)

        XCTAssertEqual(result, .correctionQueued)
        let storedEntries = await store.all()
        XCTAssertTrue(storedEntries.isEmpty, "the drink leaves the local list")
        let outboxEntries = await outbox.allEntries()
        XCTAssertEqual(outboxEntries.count, 2, "the delivered drink stays as history, plus one correction")
        let correction = try XCTUnwrap(outboxEntries.first { $0.state == .pending })
        XCTAssertEqual(correction.valueInML, -250, "Garmin's additive log route subtracts via a negative value")
        XCTAssertEqual(correction.loggedAt, loggedAt, "the correction lands on the drink's own day")
    }

    func testTheShownTotalDropsAsSoonAsADeliveredDrinkIsRemoved() async throws {
        let (coordinator, _, outbox) = makeCoordinator()
        let loggedAt = Date()
        let entry = try await coordinator.logHydration(valueInML: 250, loggedAt: loggedAt)
        // Captured AFTER logging, so the new entry is already due.
        let deliveredAt = Date()
        _ = await outbox.drain(using: AlwaysSucceedsHydrationDeliverer(), now: deliveredAt)
        // Garmin read AFTER the delivery: its 1750 already includes the 250.
        let garmin = HydrationDaily(valueInML: 1750, goalInML: 2800)
        let fetchedAt = deliveredAt.addingTimeInterval(60)
        let entriesBefore = await outbox.allEntries()
        let before = HydrationDayTotal.total(garminDaily: garmin, garminFetchedAt: fetchedAt, outboxEntries: entriesBefore, on: loggedAt)
        XCTAssertEqual(before, 1750)

        try await coordinator.removeHydration(entry)

        let entriesAfter = await outbox.allEntries()
        let after = HydrationDayTotal.total(garminDaily: garmin, garminFetchedAt: fetchedAt, outboxEntries: entriesAfter, on: loggedAt)
        XCTAssertEqual(after, 1500, "the queued -250 counts immediately, before it is even delivered")
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

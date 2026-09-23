// HydrationSyncTests.swift
//
// Pure logic tests for `HydrationOutbox`'s retry/backoff/rate-limit/auth-
// failure behaviour -- the hydration equivalent of WeightSyncTests.swift,
// covering the same scenarios against `HydrationOutbox` instead of
// `WeightOutbox` since the two are independent actors with independent
// state (HydrationSync.swift's own header explains why). No network access,
// no real device -- `FakeHydrationDeliverer` never touches `URLSession`.

import XCTest
@testable import GarminKit

private actor FakeHydrationDeliverer: HydrationDelivering {
    enum Outcome {
        case succeed
        case fail(Error)
    }

    private var outcomes: [Outcome]
    private(set) var receivedRequests: [AddHydrationRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var callCount: Int { receivedRequests.count }

    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse {
        receivedRequests.append(request)
        let index = receivedRequests.count - 1
        let outcome = index < outcomes.count ? outcomes[index] : .succeed
        switch outcome {
        case .succeed:
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/usersummary-service/usersummary/hydration/log")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        case .fail(let error):
            throw error
        }
    }
}

final class HydrationSyncTests: XCTestCase {
    private func makeOutbox(maxAttempts: Int = 3) -> HydrationOutbox {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-hydration-outbox-test-\(UUID().uuidString).json")
        return HydrationOutbox(store: HydrationOutboxStore(fileURL: url), maxAttempts: maxAttempts, backoffBase: 0.5, backoffCap: 8)
    }

    // MARK: - Successful delivery

    func testSuccessfulDeliveryMarksEntrySentAndReturnsItAsDelivered() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logHydration(valueInML: 250)
        let deliverer = FakeHydrationDeliverer(outcomes: [.succeed])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(result.stoppedDueToRateLimit)
        XCTAssertEqual(result.authOutcome, .none)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    func testDeliveredRequestCarriesTheAmountAndLoggedAtTime() async throws {
        let outbox = makeOutbox()
        let loggedAt = Date(timeIntervalSince1970: 1_789_000_000)
        _ = try await outbox.logHydration(valueInML: 500, loggedAt: loggedAt)
        let deliverer = FakeHydrationDeliverer(outcomes: [.succeed])

        _ = await outbox.drain(using: deliverer)

        let received = await deliverer.receivedRequests
        XCTAssertEqual(received.first?.valueInML, 500)
        XCTAssertEqual(received.first?.loggedAt, loggedAt)
    }

    // MARK: - Bounded retry with backoff

    func testFailureBelowMaxAttemptsStaysPendingWithFutureBackoff() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        _ = try await outbox.logHydration(valueInML: 250)
        let deliverer = FakeHydrationDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))])

        let now = Date()
        let result = await outbox.drain(using: deliverer, now: now, randomJitter: { 1.0 })

        XCTAssertTrue(result.delivered.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 1)
        XCTAssertGreaterThan(stored.first!.nextAttemptAt, now)
    }

    func testFailureAtMaxAttemptsIsMarkedFailedAndSurfaced() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        _ = try await outbox.logHydration(valueInML: 250)

        for _ in 0..<3 {
            _ = await outbox.drain(
                using: FakeHydrationDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]),
                randomJitter: { 0 }
            )
        }

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed)
        XCTAssertEqual(stored.first?.attemptCount, 3)
    }

    // MARK: - Rate limiting (429)

    func testRateLimitStopsRestOfDrainCycleEntirely() async throws {
        let outbox = makeOutbox()
        let first = try await outbox.logHydration(valueInML: 250)
        let second = try await outbox.logHydration(valueInML: 500)
        let deliverer = FakeHydrationDeliverer(outcomes: [.fail(GarminClientError.rateLimited(retryAfterSeconds: 30)), .succeed])

        let result = await outbox.drain(using: deliverer)

        XCTAssertTrue(result.stoppedDueToRateLimit)
        let callCount = await deliverer.callCount
        XCTAssertEqual(callCount, 1, "the second entry must never be attempted once a 429 is seen")

        let stored = await outbox.allEntries()
        let secondStored = stored.first { $0.id == second.id }
        XCTAssertEqual(secondStored?.state, .pending)
        XCTAssertEqual(secondStored?.attemptCount, 0)
        XCTAssertNotNil(stored.first { $0.id == first.id })
    }

    // MARK: - Auth failures stop the cycle without burning retry attempts

    func testLongLivedTokenExpiredStopsCycleWithoutCountingAsAttempt() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logHydration(valueInML: 250)
        let deliverer = FakeHydrationDeliverer(outcomes: [.fail(GarminAuthError.longLivedTokenExpired)])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.authOutcome, .longLivedTokenExpired)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 0, "an auth failure must not consume one of the bounded retry attempts")
    }

    // MARK: - Manual retry / delete

    func testManualRetryResetsFailedEntryToPending() async throws {
        let outbox = makeOutbox(maxAttempts: 1)
        let entry = try await outbox.logHydration(valueInML: 250)
        _ = await outbox.drain(using: FakeHydrationDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]))

        var stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed)

        try await outbox.retry(id: entry.id)
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 0)
    }

    func testDeleteRemovesEntry() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logHydration(valueInML: 250)
        try await outbox.delete(id: entry.id)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Backdated entries are still immediately eligible for delivery

    func testBackdatedLoggedAtStillAttemptsDeliveryNow() async throws {
        let outbox = makeOutbox()
        let yesterday = Date().addingTimeInterval(-86_400)
        _ = try await outbox.logHydration(valueInML: 250, loggedAt: yesterday)
        let deliverer = FakeHydrationDeliverer(outcomes: [.succeed])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.count, 1, "nextAttemptAt is the real enqueue moment, not the backdated loggedAt")
    }

    // MARK: - Persistence survives "relaunch"

    func testEntriesSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-hydration-outbox-persist-\(UUID().uuidString).json")
        let outbox1 = HydrationOutbox(store: HydrationOutboxStore(fileURL: url))
        let entry = try await outbox1.logHydration(valueInML: 250)

        let outbox2 = HydrationOutbox(store: HydrationOutboxStore(fileURL: url))
        let reloaded = await outbox2.allEntries()

        XCTAssertEqual(reloaded.map(\.id), [entry.id])
    }

    // MARK: - Negative corrections (sync-weight-hydration-with-garmin, D4)

    func testNegativeCorrectionIsDeliveredWithItsNegativeValue() async throws {
        let outbox = makeOutbox()
        let loggedAt = Date(timeIntervalSince1970: 1_789_000_000)
        let correction = try await outbox.logHydration(valueInML: -250, loggedAt: loggedAt)
        XCTAssertTrue(correction.isCorrection)
        let now = Date()

        let result = await outbox.drain(using: FakeHydrationDeliverer(outcomes: [.succeed]), now: now)

        XCTAssertEqual(result.delivered.map(\.id), [correction.id])
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.valueInML, -250)
        XCTAssertEqual(stored.first?.deliveredAt, now, "deliveredAt is stamped on delivery")
    }

    func testNegativeCorrectionWireBodyCarriesTheNegativeValue() {
        let body = HydrationWriteBody.make(
            for: AddHydrationRequest(valueInML: -250, loggedAt: Date(timeIntervalSince1970: 1_789_000_000)),
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertEqual(body.valueInML, -250, "the additive log route subtracts via a negative valueInML")
    }

    /// The exact shape a pre-2026-09-23 build wrote (no `deliveredAt`) must
    /// still decode, or `PersistedJSON` would quarantine the whole file.
    func testOutboxFileWrittenBeforeDeliveredAtStillDecodes() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-hydration-outbox-legacy-\(UUID().uuidString).json")
        let legacyJSON = """
        [
          {"id":"6F1C2D3E-0000-4000-8000-000000000011","valueInML":250,"loggedAt":"2026-09-23T07:00:00Z","state":"sent","attemptCount":0,"nextAttemptAt":"2026-09-23T07:00:01Z"},
          {"id":"6F1C2D3E-0000-4000-8000-000000000012","valueInML":500,"loggedAt":"2026-09-23T09:00:00Z","state":"pending","attemptCount":0,"nextAttemptAt":"2026-09-23T09:00:01Z"}
        ]
        """
        try Data(legacyJSON.utf8).write(to: url)

        let outbox = HydrationOutbox(store: HydrationOutboxStore(fileURL: url))
        let entries = await outbox.allEntries()

        XCTAssertEqual(entries.map(\.valueInML), [250, 500])
        XCTAssertNil(entries.first?.deliveredAt)
        XCTAssertEqual(entries.first?.state, .sent)
        XCTAssertNil(entries.first?.removalRequested, "fields added by the 2026-09-23 race fix are optional too")
        XCTAssertNil(entries.first?.correctsEntryId)
    }

    // MARK: - Removal vs an in-flight delivery (2026-09-23 race fix)

    func testCancellingADrinkThatIsNotInFlightRemovesIt() async throws {
        let outbox = makeOutbox()
        let drink = try await outbox.logHydration(valueInML: 500)

        let cancellation = try await outbox.cancelQueued(id: drink.id)

        XCTAssertEqual(cancellation, .removed)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testCancellingADeliveredDrinkIsRefusedSoTheCallerQueuesACorrection() async throws {
        let outbox = makeOutbox()
        let drink = try await outbox.logHydration(valueInML: 500)
        _ = await outbox.drain(using: FakeHydrationDeliverer(outcomes: [.succeed]))

        do {
            try await outbox.cancelQueued(id: drink.id)
            XCTFail("expected alreadyDelivered")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .alreadyDelivered)
        }
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.state), [.sent], "nothing changes when it is refused")
    }

    /// The reviewed race: the drink is removed while its POST is on the
    /// wire and Garmin then ACCEPTS it. Before the fix the entry was deleted
    /// mid-flight and Garmin kept the 500 ml forever. Now the same drain
    /// sends the -500 correction right after.
    func testRemovingADrinkWhileItsPostIsInFlightSendsACorrectionOnceGarminAcceptsIt() async throws {
        let outbox = makeOutbox()
        let loggedAt = Date(timeIntervalSince1970: 1_789_000_000)
        let drink = try await outbox.logHydration(valueInML: 500, loggedAt: loggedAt)
        let deliverer = GatedHydrationDeliverer()

        let drain = Task { await outbox.drain(using: deliverer) }
        await deliverer.waitUntilFirstCallIsInFlight()

        let cancellation = try await outbox.cancelQueued(id: drink.id)
        XCTAssertEqual(cancellation, .compensateAfterDelivery, "in flight: flagged, not deleted out from under the POST")
        let flagged = await outbox.allEntries()
        XCTAssertEqual(flagged.first?.isWithdrawn, true)

        deliverer.releaseFirstCall()
        let result = await drain.value

        let requests = await deliverer.receivedRequests
        XCTAssertEqual(requests.map(\.valueInML), [500, -500], "Garmin got the drink, then its correction, in the same drain")
        XCTAssertEqual(requests.last?.loggedAt, loggedAt, "the correction lands on the drink's own day")
        XCTAssertEqual(result.delivered.count, 2)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.state == .sent })
        let correction = try XCTUnwrap(stored.first { $0.isCorrection })
        XCTAssertEqual(correction.correctsEntryId, drink.id)
    }

    /// Same race, but Garmin REJECTS the in-flight POST: the removed drink is
    /// dropped instead of retried, and no correction is sent.
    func testRemovingADrinkWhileItsPostIsInFlightDropsItIfGarminRejectsIt() async throws {
        let outbox = makeOutbox()
        let drink = try await outbox.logHydration(valueInML: 500)
        let deliverer = GatedHydrationDeliverer(firstCallFailsWith: GarminClientError.httpError(statusCode: 500, body: "boom"))

        let drain = Task { await outbox.drain(using: deliverer) }
        await deliverer.waitUntilFirstCallIsInFlight()
        try await outbox.cancelQueued(id: drink.id)
        deliverer.releaseFirstCall()
        let result = await drain.value

        let requests = await deliverer.receivedRequests
        XCTAssertEqual(requests.count, 1, "no correction for a drink Garmin never accepted")
        XCTAssertTrue(result.delivered.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty, "never retried after the user removed it")
    }
}

/// Holds the FIRST `addHydration` call open until the test releases it, so
/// a test can act while a delivery is genuinely in flight; later calls
/// succeed at once. Signalled with `AsyncStream`s (buffered, so neither
/// side can miss the other's signal) rather than sleeps.
private actor GatedHydrationDeliverer: HydrationDelivering {
    private(set) var receivedRequests: [AddHydrationRequest] = []
    private let firstCallError: Error?
    private let started = AsyncStream<Void>.makeStream()
    private let release = AsyncStream<Void>.makeStream()

    init(firstCallFailsWith error: Error? = nil) {
        self.firstCallError = error
    }

    nonisolated func waitUntilFirstCallIsInFlight() async {
        _ = await started.stream.first(where: { _ in true })
    }

    nonisolated func releaseFirstCall() {
        release.continuation.yield(())
    }

    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse {
        receivedRequests.append(request)
        if receivedRequests.count == 1 {
            started.continuation.yield(())
            _ = await release.stream.first(where: { _ in true })
            if let firstCallError { throw firstCallError }
        }
        return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/usersummary-service/usersummary/hydration/log")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }
}

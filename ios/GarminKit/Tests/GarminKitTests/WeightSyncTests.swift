// WeightSyncTests.swift
//
// Pure logic tests for `WeightOutbox`'s retry/backoff/rate-limit/auth-
// failure behaviour -- the weight equivalent of OutboxTests.swift, covering
// the same scenarios against `WeightOutbox` instead of `Outbox` since the
// two are independent actors with independent state (WeightSync.swift's own
// header explains why they aren't unified). No network access, no real
// device -- `FakeWeighInDeliverer` never touches `URLSession`.

import XCTest
@testable import GarminKit

private actor FakeWeighInDeliverer: WeighInDelivering {
    enum Outcome {
        case succeed
        case fail(Error)
    }

    private var outcomes: [Outcome]
    private(set) var receivedRequests: [AddWeighInRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var callCount: Int { receivedRequests.count }

    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        receivedRequests.append(request)
        let index = receivedRequests.count - 1
        let outcome = index < outcomes.count ? outcomes[index] : .succeed
        switch outcome {
        case .succeed:
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/user-weight")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        case .fail(let error):
            throw error
        }
    }
}

final class WeightSyncTests: XCTestCase {
    private func makeOutbox(maxAttempts: Int = 3) -> WeightOutbox {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-weight-outbox-test-\(UUID().uuidString).json")
        return WeightOutbox(store: WeightOutboxStore(fileURL: url), maxAttempts: maxAttempts, backoffBase: 0.5, backoffCap: 8)
    }

    // MARK: - Successful delivery

    func testSuccessfulDeliveryMarksEntrySentAndReturnsItAsDelivered() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logWeight(weightKg: 75.5)
        let deliverer = FakeWeighInDeliverer(outcomes: [.succeed])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(result.stoppedDueToRateLimit)
        XCTAssertEqual(result.authOutcome, .none)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    func testDeliveredRequestCarriesTheWeightAndLoggedAtTime() async throws {
        let outbox = makeOutbox()
        let loggedAt = Date(timeIntervalSince1970: 1_789_000_000)
        _ = try await outbox.logWeight(weightKg: 82.3, loggedAt: loggedAt)
        let deliverer = FakeWeighInDeliverer(outcomes: [.succeed])

        _ = await outbox.drain(using: deliverer)

        let received = await deliverer.receivedRequests
        XCTAssertEqual(received.first?.weightKg, 82.3)
        XCTAssertEqual(received.first?.loggedAt, loggedAt)
    }

    // MARK: - Bounded retry with backoff

    func testFailureBelowMaxAttemptsStaysPendingWithFutureBackoff() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        _ = try await outbox.logWeight(weightKg: 75)
        let deliverer = FakeWeighInDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))])

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
        _ = try await outbox.logWeight(weightKg: 75)

        for _ in 0..<3 {
            _ = await outbox.drain(
                using: FakeWeighInDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]),
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
        let first = try await outbox.logWeight(weightKg: 75)
        let second = try await outbox.logWeight(weightKg: 76)
        let deliverer = FakeWeighInDeliverer(outcomes: [.fail(GarminClientError.rateLimited(retryAfterSeconds: 30)), .succeed])

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
        _ = try await outbox.logWeight(weightKg: 75)
        let deliverer = FakeWeighInDeliverer(outcomes: [.fail(GarminAuthError.longLivedTokenExpired)])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.authOutcome, .longLivedTokenExpired)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 0, "an auth failure must not consume one of the bounded retry attempts")
    }

    // MARK: - Manual retry / delete

    func testManualRetryResetsFailedEntryToPending() async throws {
        let outbox = makeOutbox(maxAttempts: 1)
        let entry = try await outbox.logWeight(weightKg: 75)
        _ = await outbox.drain(using: FakeWeighInDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]))

        var stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed)

        try await outbox.retry(id: entry.id)
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 0)
    }

    func testDeleteRemovesEntry() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logWeight(weightKg: 75)
        try await outbox.delete(id: entry.id)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Backdated weigh-ins are still immediately eligible for delivery

    func testBackdatedLoggedAtStillAttemptsDeliveryNow() async throws {
        let outbox = makeOutbox()
        let yesterday = Date().addingTimeInterval(-86_400)
        _ = try await outbox.logWeight(weightKg: 75, loggedAt: yesterday)
        let deliverer = FakeWeighInDeliverer(outcomes: [.succeed])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.count, 1, "nextAttemptAt is the real enqueue moment, not the backdated loggedAt")
    }

    // MARK: - Persistence survives "relaunch"

    func testEntriesSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-weight-outbox-persist-\(UUID().uuidString).json")
        let outbox1 = WeightOutbox(store: WeightOutboxStore(fileURL: url))
        let entry = try await outbox1.logWeight(weightKg: 75)

        let outbox2 = WeightOutbox(store: WeightOutboxStore(fileURL: url))
        let reloaded = await outbox2.allEntries()

        XCTAssertEqual(reloaded.map(\.id), [entry.id])
    }
}

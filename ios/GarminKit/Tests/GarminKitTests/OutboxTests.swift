// OutboxTests.swift
//
// Pure logic tests for the outbox's retry/backoff/rate-limit/auth-failure
// behavior (tasks 9.3-9.6, garmin-sync spec's "Delivery retries are bounded
// and rate-limit aware" requirement). No network access, no real device --
// `FakeDeliverer` below never touches `URLSession`.

import XCTest
@testable import GarminKit

/// A `FoodLogDelivering` that returns a scripted sequence of outcomes and
/// records what it was called with, so tests can assert both on results
/// and on *whether a call was even made*.
private actor FakeDeliverer: FoodLogDelivering {
    enum Outcome {
        case succeed
        case fail(Error)
    }

    private var outcomes: [Outcome]
    private(set) var receivedRequests: [CreateFoodLogEntryRequest] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var callCount: Int { receivedRequests.count }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        receivedRequests.append(entry)
        let index = receivedRequests.count - 1
        let outcome = index < outcomes.count ? outcomes[index] : .succeed
        switch outcome {
        case .succeed:
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        case .fail(let error):
            throw error
        }
    }
}

final class OutboxTests: XCTestCase {
    private func makeOutbox(maxAttempts: Int = 3) -> Outbox {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-test-\(UUID().uuidString).json")
        return Outbox(store: OutboxStore(fileURL: url), maxAttempts: maxAttempts, backoffBase: 0.5, backoffCap: 8)
    }

    // MARK: - Successful delivery

    func testSuccessfulDeliveryMarksEntrySentAndReturnsItAsDelivered() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1)
        let deliverer = FakeDeliverer(outcomes: [.succeed])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
        XCTAssertTrue(result.failed.isEmpty)
        XCTAssertFalse(result.stoppedDueToRateLimit)
        XCTAssertEqual(result.authOutcome, .none)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    // MARK: - Bounded retry with backoff

    func testFailureBelowMaxAttemptsStaysPendingWithFutureBackoff() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        _ = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)
        let deliverer = FakeDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))])

        let now = Date()
        let result = await outbox.drain(using: deliverer, now: now, randomJitter: { 1.0 })

        XCTAssertTrue(result.delivered.isEmpty)
        XCTAssertTrue(result.failed.isEmpty)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 1)
        XCTAssertGreaterThan(stored.first!.nextAttemptAt, now)
    }

    func testEntryNotYetDueIsSkippedByDrain() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)
        let now = Date()
        // First failure schedules a future retry.
        _ = await outbox.drain(using: FakeDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]), now: now, randomJitter: { 1.0 })

        // Draining again "now" (before the backoff has elapsed) must not
        // attempt delivery at all.
        let deliverer = FakeDeliverer(outcomes: [.succeed])
        let result = await outbox.drain(using: deliverer, now: now)
        let callCount = await deliverer.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertTrue(result.delivered.isEmpty)
    }

    func testFailureAtMaxAttemptsIsMarkedFailedAndSurfaced() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        _ = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)

        // jitter: 0 means each backoff resolves to 0s, so the entry is
        // immediately due again on the next drain call.
        for _ in 0..<3 {
            _ = await outbox.drain(
                using: FakeDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]),
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
        let first = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "s1", numberOfUnits: 1)
        let second = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "2", servingId: "s2", numberOfUnits: 1)
        let deliverer = FakeDeliverer(outcomes: [.fail(GarminClientError.rateLimited(retryAfterSeconds: 30)), .succeed])

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

    func testRateLimitHonoursRetryAfterHeader() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "s1", numberOfUnits: 1)
        let now = Date()

        _ = await outbox.drain(using: FakeDeliverer(outcomes: [.fail(GarminClientError.rateLimited(retryAfterSeconds: 42))]), now: now)

        let stored = await outbox.allEntries()
        let scheduled = stored.first!.nextAttemptAt.timeIntervalSince(now)
        XCTAssertEqual(scheduled, 42, accuracy: 0.01)
    }

    // MARK: - Auth failures stop the cycle without burning retry attempts

    func testLongLivedTokenExpiredStopsCycleWithoutCountingAsAttempt() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "s1", numberOfUnits: 1)
        let deliverer = FakeDeliverer(outcomes: [.fail(GarminAuthError.longLivedTokenExpired)])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.authOutcome, .longLivedTokenExpired)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 0, "an auth failure must not consume one of the bounded retry attempts")
    }

    func testNotSignedInStopsCycle() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "s1", numberOfUnits: 1)
        let deliverer = FakeDeliverer(outcomes: [.fail(GarminAuthError.notSignedIn)])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.authOutcome, .notSignedIn)
    }

    // MARK: - Manual retry / delete

    func testManualRetryResetsFailedEntryToPending() async throws {
        let outbox = makeOutbox(maxAttempts: 1)
        let entry = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1)
        _ = await outbox.drain(using: FakeDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]))

        var stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed)

        try await outbox.retry(id: entry.id)
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending)
        XCTAssertEqual(stored.first?.attemptCount, 0)
    }

    func testDeleteRemovesEntry() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1)
        try await outbox.delete(id: entry.id)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    // MARK: - Persistence survives "relaunch" (a fresh OutboxStore instance, same file)

    func testEntriesSurviveAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-persist-\(UUID().uuidString).json")
        let outbox1 = Outbox(store: OutboxStore(fileURL: url))
        let entry = try await outbox1.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1)

        // Simulate a relaunch: a brand new Outbox/OutboxStore pointed at the
        // same file, nothing shared in memory with outbox1.
        let outbox2 = Outbox(store: OutboxStore(fileURL: url))
        let reloaded = await outbox2.allEntries()

        XCTAssertEqual(reloaded.map(\.id), [entry.id])
    }

    // MARK: - Pure backoff function (task 9.3: "capped at 8s")

    func testBackoffDelayGrowsExponentiallyThenCaps() {
        XCTAssertEqual(Outbox.backoffDelay(attempt: 1, jitter: 1, base: 0.5, cap: 8), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Outbox.backoffDelay(attempt: 2, jitter: 1, base: 0.5, cap: 8), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Outbox.backoffDelay(attempt: 3, jitter: 1, base: 0.5, cap: 8), 2.0, accuracy: 0.0001)
        XCTAssertEqual(Outbox.backoffDelay(attempt: 4, jitter: 1, base: 0.5, cap: 8), 4.0, accuracy: 0.0001)
        XCTAssertEqual(Outbox.backoffDelay(attempt: 5, jitter: 1, base: 0.5, cap: 8), 8.0, accuracy: 0.0001)
        // However many attempts, it never exceeds the cap.
        XCTAssertEqual(Outbox.backoffDelay(attempt: 50, jitter: 1, base: 0.5, cap: 8), 8.0, accuracy: 0.0001)
    }

    func testBackoffJitterScalesLinearlyAndIsClamped() {
        XCTAssertEqual(Outbox.backoffDelay(attempt: 5, jitter: 0, base: 0.5, cap: 8), 0, accuracy: 0.0001)
        XCTAssertEqual(Outbox.backoffDelay(attempt: 5, jitter: 0.5, base: 0.5, cap: 8), 4.0, accuracy: 0.0001)
        // Out-of-range jitter values are clamped to [0, 1] rather than trusted.
        XCTAssertEqual(Outbox.backoffDelay(attempt: 5, jitter: 5, base: 0.5, cap: 8), 8.0, accuracy: 0.0001)
        XCTAssertEqual(Outbox.backoffDelay(attempt: 5, jitter: -5, base: 0.5, cap: 8), 0, accuracy: 0.0001)
    }
}

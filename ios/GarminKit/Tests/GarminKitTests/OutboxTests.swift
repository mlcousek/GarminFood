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
    private var deleteOutcomes: [Outcome]
    private(set) var receivedRequests: [CreateFoodLogEntryRequest] = []
    /// add-log-entry-editing: every delete call, as (logIds, date).
    private(set) var receivedDeletes: [(logIds: [String], date: String)] = []

    init(outcomes: [Outcome], deleteOutcomes: [Outcome] = []) {
        self.outcomes = outcomes
        self.deleteOutcomes = deleteOutcomes
    }

    var callCount: Int { receivedRequests.count }
    var deleteCallCount: Int { receivedDeletes.count }
    var deletedLogIds: [String] { receivedDeletes.flatMap { $0.logIds } }

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

    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        receivedDeletes.append((logIds: logIds, date: date))
        let index = receivedDeletes.count - 1
        let outcome = index < deleteOutcomes.count ? deleteOutcomes[index] : .succeed
        switch outcome {
        case .succeed:
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs/\(date)")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
        case .fail(let error):
            throw error
        }
    }
}

/// add-log-entry-editing: reads the outbox FILE (not the in-memory store)
/// from inside the delete call, to prove D1's ordering -- the
/// `.createdAwaitingDelete` state is on disk before the delete goes out.
private actor FileObservingDeliverer: FoodLogDelivering {
    private let fileURL: URL
    private(set) var stateSeenDuringDelete: OutboxEntryState?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
        let data = try Data(contentsOf: fileURL)
        let entries = try JSONDecoder().decode([OutboxEntry].self, from: data)
        stateSeenDuringDelete = entries.first?.state
        return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs/\(date)")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
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

    // MARK: - add-log-entry-editing: old files still decode

    func testAnOutboxFileWrittenBeforeEditingExistedStillDecodes() async throws {
        // Exactly the shape an older build persisted: no `replaces`,
        // `duplicateOf` or `parkedAt` keys at all. Dates in
        // JSONEncoder's default (seconds since the reference date).
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-legacy-\(UUID().uuidString).json")
        let legacy = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-09-14","mealType":"BREAKFAST","foodId":"1","servingId":"2",
          "numberOfUnits":1.5,"source":"FATSECRET","regionCode":"CZ","languageCode":"en","state":"failed","attemptCount":5,
          "lastError":"HTTP 500","createdAt":780000000,"nextAttemptAt":780000000}]
        """
        try Data(legacy.utf8).write(to: url)

        let entries = await Outbox(store: OutboxStore(fileURL: url)).allEntries()

        XCTAssertEqual(entries.count, 1, "an old outbox file must not be quarantined by the new optional fields")
        XCTAssertNil(entries.first?.replaces)
        XCTAssertNil(entries.first?.duplicateOf)
        XCTAssertNil(entries.first?.parkedAt)
        XCTAssertEqual(entries.first?.state, .failed)
        XCTAssertEqual(entries.first?.numberOfUnits, 1.5)
    }

    func testAReplaceRoundTripsThroughTheFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-replace-\(UUID().uuidString).json")
        let first = Outbox(store: OutboxStore(fileURL: url))
        let entry = try await first.logFood(
            date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 2,
            replaces: ReplacedLog(date: "2026-09-14", logId: "old-log"), duplicateOf: "source-log"
        )

        let reloaded = await Outbox(store: OutboxStore(fileURL: url)).allEntries()

        XCTAssertEqual(reloaded.map(\.id), [entry.id])
        XCTAssertEqual(reloaded.first?.replaces, ReplacedLog(date: "2026-09-14", logId: "old-log"))
        XCTAssertEqual(reloaded.first?.duplicateOf, "source-log")
    }

    // MARK: - add-log-entry-editing D1: replace = create, then delete

    private func makeReplace(in outbox: Outbox, logId: String = "old-log") async throws -> OutboxEntry {
        try await outbox.logFood(
            date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 2,
            replaces: ReplacedLog(date: "2026-09-14", logId: logId)
        )
    }

    func testAReplaceCreatesTheNewEntryThenDeletesTheOldOne() async throws {
        let outbox = makeOutbox()
        let entry = try await makeReplace(in: outbox)
        let deliverer = FakeDeliverer(outcomes: [.succeed])

        let result = await outbox.drain(using: deliverer)

        let creates = await deliverer.callCount
        let deletes = await deliverer.receivedDeletes
        XCTAssertEqual(creates, 1)
        XCTAssertEqual(deletes.map { $0.logIds }, [["old-log"]])
        XCTAssertEqual(deletes.map { $0.date }, ["2026-09-14"], "the delete route takes the old entry's date in its path")
        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    func testAFailedCreateNeverDeletesTheOldEntry() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        _ = try await makeReplace(in: outbox)
        let deliverer = FakeDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))])

        let result = await outbox.drain(using: deliverer, randomJitter: { 1.0 })

        let deletes = await deliverer.deleteCallCount
        XCTAssertEqual(deletes, 0, "deleting before the corrected entry exists could lose the food")
        XCTAssertTrue(result.delivered.isEmpty)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending, "a failed create follows the ordinary retry rules")
        XCTAssertEqual(stored.first?.attemptCount, 1)
    }

    func testAFailedDeleteIsRetriedWithoutCreatingAgain() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        let entry = try await makeReplace(in: outbox)
        let now = Date()

        // Create succeeds, delete fails.
        let first = FakeDeliverer(outcomes: [.succeed], deleteOutcomes: [.fail(GarminClientError.httpError(statusCode: 503, body: nil))])
        let firstResult = await outbox.drain(using: first, now: now, randomJitter: { 1.0 })

        XCTAssertTrue(firstResult.delivered.isEmpty)
        var stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .createdAwaitingDelete)
        XCTAssertEqual(stored.first?.attemptCount, 1)
        XCTAssertNotNil(stored.first?.lastError, "the pending removal must be visible in the sync queue")
        XCTAssertGreaterThan(stored.first!.nextAttemptAt, now, "backs off like any other failure")

        // Next drain (after the backoff): only the delete is retried.
        let second = FakeDeliverer(outcomes: [])
        let secondResult = await outbox.drain(using: second, now: now.addingTimeInterval(60))

        let secondCreates = await second.callCount
        let secondDeletes = await second.deletedLogIds
        XCTAssertEqual(secondCreates, 0, "the corrected entry is already in Garmin; creating it again would duplicate it")
        XCTAssertEqual(secondDeletes, ["old-log"])
        XCTAssertEqual(secondResult.delivered.map(\.id), [entry.id])
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
        XCTAssertNil(stored.first?.lastError)
    }

    func testAReplaceResumesAtTheDeleteAfterARelaunch() async throws {
        // The crash-between-requests case: the create was accepted and
        // `.createdAwaitingDelete` persisted, then the process died.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-resume-\(UUID().uuidString).json")
        let beforeCrash = Outbox(store: OutboxStore(fileURL: url))
        let entry = try await makeReplace(in: beforeCrash)
        var persisted = entry
        persisted.state = .createdAwaitingDelete
        try await beforeCrash.requeue(persisted)

        let afterRelaunch = Outbox(store: OutboxStore(fileURL: url))
        let deliverer = FakeDeliverer(outcomes: [])
        let result = await afterRelaunch.drain(using: deliverer)

        let creates = await deliverer.callCount
        let deletes = await deliverer.deletedLogIds
        XCTAssertEqual(creates, 0, "a relaunch must never re-send a create Garmin already accepted")
        XCTAssertEqual(deletes, ["old-log"])
        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
    }

    func testTheAwaitingDeleteStateIsPersistedBeforeTheDeleteIsSent() async throws {
        // Observe the file from inside the delete call: by then a fresh
        // store on the same file must already read `.createdAwaitingDelete`.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-order-\(UUID().uuidString).json")
        let outbox = Outbox(store: OutboxStore(fileURL: url))
        _ = try await makeReplace(in: outbox)
        let spy = FileObservingDeliverer(fileURL: url)

        _ = await outbox.drain(using: spy)

        let observed = await spy.stateSeenDuringDelete
        XCTAssertEqual(observed, .createdAwaitingDelete)
    }

    func testA404OnTheDeleteCountsAsSuccess() async throws {
        let outbox = makeOutbox()
        let entry = try await makeReplace(in: outbox)
        let deliverer = FakeDeliverer(outcomes: [.succeed], deleteOutcomes: [.fail(GarminClientError.httpError(statusCode: 404, body: nil))])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.map(\.id), [entry.id], "the old entry is already gone -- exactly what the replace wanted")
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    func testAPermanentlyRejectedDeleteIsParkedNotFailed() async throws {
        let outbox = makeOutbox()
        let entry = try await makeReplace(in: outbox)
        let deliverer = FakeDeliverer(outcomes: [.succeed], deleteOutcomes: [.fail(GarminClientError.httpError(statusCode: 400, body: "nope"))])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.failed.map(\.id), [entry.id], "a parked replace needs the user, so it's surfaced")
        var stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .createdAwaitingDelete, "never `.failed`: a manual retry from there would create the food again")
        XCTAssertNotNil(stored.first?.parkedAt)
        XCTAssertEqual(stored.first?.needsManualRetry, true)

        // Parked: a later drain leaves it alone.
        let idle = FakeDeliverer(outcomes: [])
        _ = await outbox.drain(using: idle, now: Date().addingTimeInterval(3600))
        let idleCreates = await idle.callCount
        let idleDeletes = await idle.deleteCallCount
        XCTAssertEqual(idleCreates + idleDeletes, 0)

        // Manual retry re-arms ONLY the delete.
        try await outbox.retry(id: entry.id)
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .createdAwaitingDelete)
        XCTAssertNil(stored.first?.parkedAt)
        let retried = FakeDeliverer(outcomes: [])
        _ = await outbox.drain(using: retried)
        let retriedCreates = await retried.callCount
        let retriedDeletes = await retried.deletedLogIds
        XCTAssertEqual(retriedCreates, 0)
        XCTAssertEqual(retriedDeletes, ["old-log"])
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    func testARepeatedlyFailingDeleteIsParkedAfterMaxAttempts() async throws {
        let outbox = makeOutbox(maxAttempts: 2)
        _ = try await makeReplace(in: outbox)
        let serverError = GarminClientError.httpError(statusCode: 500, body: nil)

        _ = await outbox.drain(using: FakeDeliverer(outcomes: [.succeed], deleteOutcomes: [.fail(serverError)]), randomJitter: { 0 })
        var stored = await outbox.allEntries()
        XCTAssertNil(stored.first?.parkedAt, "one transient failure just backs off")

        _ = await outbox.drain(using: FakeDeliverer(outcomes: [], deleteOutcomes: [.fail(serverError)]), randomJitter: { 0 })
        stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .createdAwaitingDelete)
        XCTAssertNotNil(stored.first?.parkedAt)
    }

    func testAnAuthFailureOnTheDeleteStopsTheCycleWithoutCountingAnAttempt() async throws {
        let outbox = makeOutbox()
        _ = try await makeReplace(in: outbox)
        let deliverer = FakeDeliverer(outcomes: [.succeed], deleteOutcomes: [.fail(GarminAuthError.notSignedIn)])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.authOutcome, .notSignedIn)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .createdAwaitingDelete)
        XCTAssertEqual(stored.first?.attemptCount, 0)
        XCTAssertNil(stored.first?.parkedAt)
    }

    // MARK: - add-log-entry-editing: editing a still-queued entry

    func testReplaceQueuedSwapsAPendingEntryAndKeepsItsIdentity() async throws {
        let outbox = makeOutbox()
        let original = try await outbox.logFood(
            date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1,
            source: .fatSecret, regionCode: "CZ", languageCode: "cs",
            replaces: ReplacedLog(date: "2026-09-14", logId: "garmin-original")
        )

        let replacement = try await outbox.replaceQueued(id: original.id, mealType: .snacks, numberOfUnits: 3)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [replacement.id], "one entry, never both and never neither")
        XCTAssertNotEqual(replacement.id, original.id)
        XCTAssertEqual(replacement.mealType, .snacks)
        XCTAssertEqual(replacement.numberOfUnits, 3)
        XCTAssertEqual(replacement.foodId, "1")
        XCTAssertEqual(replacement.source, .fatSecret)
        XCTAssertEqual(replacement.regionCode, "CZ")
        XCTAssertEqual(replacement.replaces?.logId, "garmin-original", "an edit of an edit must still delete the original Garmin entry")
        XCTAssertEqual(replacement.state, .pending)
    }

    func testReplaceQueuedRefusesAnEntryGarminAlreadyAccepted() async throws {
        let outbox = makeOutbox()
        var entry = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)
        entry.state = .sent
        try await outbox.requeue(entry)

        do {
            _ = try await outbox.replaceQueued(id: entry.id, mealType: .lunch, numberOfUnits: 2)
            XCTFail("expected alreadyDelivered")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .alreadyDelivered)
        }
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [entry.id], "a refused edit changes nothing")
    }

    func testCancelQueuedRemovesAPendingEntry() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)

        try await outbox.cancelQueued(id: entry.id)

        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testAnEntryBeingSentCannotBeEditedUnderneathTheDrain() async throws {
        let store = OutboxStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-claim-\(UUID().uuidString).json"))
        let outbox = Outbox(store: store)
        let entry = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)

        // What `drain` does right before sending.
        let claimed = await store.claim(id: entry.id, now: Date())
        XCTAssertEqual(claimed?.id, entry.id)

        do {
            _ = try await outbox.replaceQueued(id: entry.id, mealType: .lunch, numberOfUnits: 2)
            XCTFail("expected entryInFlight")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .entryInFlight)
        }
        do {
            try await outbox.cancelQueued(id: entry.id)
            XCTFail("expected entryInFlight")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .entryInFlight)
        }

        await store.release(id: entry.id)
        try await outbox.cancelQueued(id: entry.id)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    func testDrainSkipsAnEntryEditedAwayAfterItsSnapshot() async throws {
        // An entry that no longer exists when its turn comes is not sent.
        let store = OutboxStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-outbox-gone-\(UUID().uuidString).json"))
        let entry = OutboxEntry(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)
        try await store.enqueue(entry)
        try await store.cancel(id: entry.id)

        let claimed = await store.claim(id: entry.id, now: Date())
        XCTAssertNil(claimed)
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

    // MARK: - Offline is not a delivery failure (scenario-review finding)

    func testOfflineNeverCountsAnAttemptNorMarksFailed() async throws {
        let outbox = makeOutbox(maxAttempts: 3)
        let first = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)
        let second = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "3", servingId: "4", numberOfUnits: 1)
        let offline = FakeDeliverer.Outcome.fail(URLError(.notConnectedToInternet))
        let deliverer = FakeDeliverer(outcomes: Array(repeating: offline, count: 10))

        // Far more drains than maxAttempts, all while offline.
        for _ in 0..<10 {
            let result = await outbox.drain(using: deliverer, randomJitter: { 1.0 })
            XCTAssertTrue(result.delivered.isEmpty)
            XCTAssertTrue(result.failed.isEmpty, "offline never gives up on an entry")
        }
        let callsWhileOffline = await deliverer.callCount
        XCTAssertEqual(callsWhileOffline, 10, "each cycle stops at the first offline error instead of trying every entry")

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.state), [.pending, .pending])
        XCTAssertEqual(stored.first?.attemptCount, 0)
        XCTAssertEqual(stored.first?.lastError?.hasPrefix("offline"), true)

        // Back online: both go out on the very next drain.
        let result = await outbox.drain(using: deliverer)
        XCTAssertEqual(Set(result.delivered.map(\.id)), [first.id, second.id])
    }

    func testTimeoutAndLostConnectionAreOfflineButA500IsNot() {
        XCTAssertTrue(ConnectivityFailure.matches(URLError(.timedOut)))
        XCTAssertTrue(ConnectivityFailure.matches(URLError(.networkConnectionLost)))
        XCTAssertTrue(ConnectivityFailure.matches(URLError(.cannotFindHost)))
        XCTAssertFalse(ConnectivityFailure.matches(URLError(.cancelled)))
        XCTAssertFalse(ConnectivityFailure.matches(URLError(.badServerResponse)))
        XCTAssertFalse(ConnectivityFailure.matches(GarminClientError.httpError(statusCode: 500, body: nil)))
    }

    func testAReplaceWhoseDeleteHitsOfflineIsNeverParked() async throws {
        let outbox = makeOutbox(maxAttempts: 2)
        let entry = try await makeReplace(in: outbox)
        let offline = FakeDeliverer.Outcome.fail(URLError(.notConnectedToInternet))
        let deliverer = FakeDeliverer(outcomes: [.succeed], deleteOutcomes: Array(repeating: offline, count: 5))

        for _ in 0..<5 {
            _ = await outbox.drain(using: deliverer, randomJitter: { 1.0 })
        }

        let stored = await outbox.entry(id: entry.id)
        XCTAssertEqual(stored?.state, .createdAwaitingDelete)
        XCTAssertNil(stored?.parkedAt, "offline doesn't use up the delete's attempts")
        XCTAssertEqual(stored?.attemptCount, 0)
        let creates = await deliverer.callCount
        XCTAssertEqual(creates, 1, "the corrected entry is never created twice")

        let result = await outbox.drain(using: deliverer)
        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
    }
}

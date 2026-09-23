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
    private(set) var receivedDeletes: [(date: String, samplePk: Int)] = []
    private(set) var receivedDayReads: [String] = []
    /// What the dayview read returns (filtered by `calendarDate`). Reads
    /// don't consume `outcomes`.
    private let samples: [GarminWeighIn]

    init(outcomes: [Outcome], samples: [GarminWeighIn] = []) {
        self.outcomes = outcomes
        self.samples = samples
    }

    func weighInSamples(on date: String) async throws -> [GarminWeighIn] {
        receivedDayReads.append(date)
        return samples.filter { $0.calendarDate == date }
    }

    /// Adds and deletes share one outcome sequence, in call order.
    var callCount: Int { receivedRequests.count + receivedDeletes.count }

    private func nextOutcome() -> Outcome {
        let index = callCount - 1
        return index < outcomes.count ? outcomes[index] : .succeed
    }

    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        receivedRequests.append(request)
        switch nextOutcome() {
        case .succeed:
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/user-weight")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        case .fail(let error):
            throw error
        }
    }

    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse {
        receivedDeletes.append((date: date, samplePk: samplePk))
        switch nextOutcome() {
        case .succeed:
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/weight/\(date)/byversion/\(samplePk)")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
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

    // MARK: - Delete operation (sync-weight-hydration-with-garmin, D3)

    func testDeleteEntryIsDeliveredAsADeleteWithItsSamplePkAndDate() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logDelete(samplePk: 1_790_149_333_817, calendarDate: "2026-09-23", weightKg: 83.9, loggedAt: Date())
        let deliverer = FakeWeighInDeliverer(outcomes: [.succeed])

        let now = Date()
        let result = await outbox.drain(using: deliverer, now: now)

        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
        let deletes = await deliverer.receivedDeletes
        XCTAssertEqual(deletes.count, 1)
        XCTAssertEqual(deletes.first?.samplePk, 1_790_149_333_817)
        XCTAssertEqual(deletes.first?.date, "2026-09-23")
        let adds = await deliverer.receivedRequests
        XCTAssertTrue(adds.isEmpty, "a delete must never be sent as an add")

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
        XCTAssertEqual(stored.first?.kind, .delete)
        XCTAssertEqual(stored.first?.deliveredAt, now, "deliveredAt is stamped on delivery")
    }

    func testDeleteThatFailsIsRetriedAndThenSurfacedAsFailed() async throws {
        let outbox = makeOutbox(maxAttempts: 2)
        _ = try await outbox.logDelete(samplePk: 42, calendarDate: "2026-09-23", weightKg: 83.9, loggedAt: Date())

        for _ in 0..<2 {
            _ = await outbox.drain(
                using: FakeWeighInDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil))]),
                randomJitter: { 0 }
            )
        }

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed, "a failed delete is kept and surfaced, never silently dropped")
        XCTAssertNotNil(stored.first?.lastError)
    }

    func testDeleteOfAnAlreadyGoneSampleCountsAsDelivered() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logDelete(samplePk: 42, calendarDate: "2026-09-23", weightKg: 83.9, loggedAt: Date())
        let deliverer = FakeWeighInDeliverer(outcomes: [.fail(GarminClientError.httpError(statusCode: 404, body: nil))])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.count, 1)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    func testAddEntryGetsDeliveredAtAndAddKind() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logWeight(weightKg: 80)
        let now = Date()

        _ = await outbox.drain(using: FakeWeighInDeliverer(outcomes: [.succeed]), now: now)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.kind, .add)
        XCTAssertEqual(stored.first?.deliveredAt, now)
    }

    // MARK: - Backward compatibility with outbox files on the owner's phone

    /// The exact shape a pre-2026-09-23 build wrote (no `operation`,
    /// `samplePk`, `calendarDate` or `deliveredAt`). It must still decode --
    /// otherwise `PersistedJSON` would quarantine the file and every
    /// undelivered weigh-in in it would vanish from the queue.
    func testOutboxFileWrittenBeforeDeleteSupportStillDecodesAsAdds() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-weight-outbox-legacy-\(UUID().uuidString).json")
        let legacyJSON = """
        [
          {"id":"6F1C2D3E-0000-4000-8000-000000000001","weightKg":83.9,"loggedAt":"2026-09-22T06:30:00Z","state":"sent","attemptCount":0,"nextAttemptAt":"2026-09-22T06:30:05Z"},
          {"id":"6F1C2D3E-0000-4000-8000-000000000002","weightKg":82.8,"loggedAt":"2026-09-23T06:30:00Z","state":"pending","attemptCount":1,"lastError":"timed out","nextAttemptAt":"2026-09-23T06:31:00Z"}
        ]
        """
        try Data(legacyJSON.utf8).write(to: url)

        let outbox = WeightOutbox(store: WeightOutboxStore(fileURL: url))
        let entries = await outbox.allEntries()

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.kind), [.add, .add], "a missing operation means add")
        XCTAssertNil(entries.first?.operation)
        XCTAssertNil(entries.first?.samplePk)
        XCTAssertNil(entries.first?.deliveredAt)
        XCTAssertEqual(entries.last?.state, .pending)
        XCTAssertEqual(entries.last?.lastError, "timed out")
        XCTAssertNil(entries.first?.removalRequested, "the 2026-09-23 race-fix field is optional too")
    }

    // MARK: - Delete by match (2026-09-23 review fix)

    /// 2026-09-23 08:21:31 CEST -- the owner's real 83.9 kg weigh-in.
    private let morning = Date(timeIntervalSince1970: 1_790_149_291.732)

    private func sample(_ pk: Int, kg: Double, at date: Date, day: String = "2026-09-23") -> GarminWeighIn {
        GarminWeighIn(samplePk: pk, calendarDate: day, weightGrams: (kg * 1000).rounded(), timestampGMT: date.timeIntervalSince1970 * 1000)
    }

    func testDeleteByMatchResolvesTheClosestMatchingSampleAndDeletesIt() async throws {
        let outbox = makeOutbox()
        let entry = try await outbox.logDeleteMatching(weightKg: 83.9, loggedAt: morning, calendarDate: "2026-09-23")
        XCTAssertTrue(entry.isDeleteByMatch)
        let deliverer = FakeWeighInDeliverer(outcomes: [.succeed], samples: [
            sample(1, kg: 83.9, at: morning.addingTimeInterval(90)),   // matches, but further away
            sample(2, kg: 83.9, at: morning.addingTimeInterval(2)),    // the closest match
            sample(3, kg: 84.0, at: morning),                          // 0.1 kg off: a different weigh-in
            sample(4, kg: 83.9, at: morning.addingTimeInterval(-600))  // 10 min off: a different weigh-in
        ])

        let result = await outbox.drain(using: deliverer)

        XCTAssertEqual(result.delivered.map(\.id), [entry.id])
        let reads = await deliverer.receivedDayReads
        XCTAssertEqual(reads, ["2026-09-23"], "resolved from Garmin's own day view")
        let deletes = await deliverer.receivedDeletes
        XCTAssertEqual(deletes.map(\.samplePk), [2])
        XCTAssertEqual(deletes.first?.date, "2026-09-23")
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
        XCTAssertEqual(stored.first?.samplePk, 2, "the resolved samplePk is kept")
    }

    func testDeleteByMatchWithNoMatchingSampleIsRetriedThenSurfacedNeverGuessed() async throws {
        let outbox = makeOutbox(maxAttempts: 2)
        _ = try await outbox.logDeleteMatching(weightKg: 83.9, loggedAt: morning, calendarDate: "2026-09-23")
        let deliverer = FakeWeighInDeliverer(outcomes: [], samples: [sample(3, kg: 84.2, at: morning)])

        let first = await outbox.drain(using: deliverer, randomJitter: { 0 })
        XCTAssertTrue(first.delivered.isEmpty)
        let afterFirst = await outbox.allEntries()
        XCTAssertEqual(afterFirst.first?.state, .pending, "Garmin may just not list a fresh add yet -- retried")
        XCTAssertNotNil(afterFirst.first?.lastError)
        XCTAssertNil(afterFirst.first?.samplePk)

        _ = await outbox.drain(using: deliverer, randomJitter: { 0 })

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed, "visible in the sync queue, not silently dropped")
        let deletes = await deliverer.receivedDeletes
        XCTAssertTrue(deletes.isEmpty, "never deletes a sample that doesn't match")
    }

    /// The resolved samplePk is stored even when the DELETE itself fails,
    /// so a retry (e.g. after a lost response) re-sends that SAME sample --
    /// a 404 then means done -- instead of matching a second one.
    func testARetriedDeleteByMatchReusesTheSampleItAlreadyResolved() async throws {
        let outbox = makeOutbox()
        _ = try await outbox.logDeleteMatching(weightKg: 83.9, loggedAt: morning, calendarDate: "2026-09-23")
        let deliverer = FakeWeighInDeliverer(
            outcomes: [.fail(GarminClientError.httpError(statusCode: 500, body: nil)), .succeed],
            samples: [sample(2, kg: 83.9, at: morning)]
        )

        _ = await outbox.drain(using: deliverer, randomJitter: { 0 })
        let afterFailure = await outbox.allEntries()
        XCTAssertEqual(afterFailure.first?.samplePk, 2)

        _ = await outbox.drain(using: deliverer, randomJitter: { 0 })

        let reads = await deliverer.receivedDayReads
        XCTAssertEqual(reads.count, 1, "not re-resolved on retry")
        let deletes = await deliverer.receivedDeletes
        XCTAssertEqual(deletes.map(\.samplePk), [2, 2])
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .sent)
    }

    // MARK: - Deleting vs an in-flight delivery (2026-09-23 race fix)

    func testCancellingAnIdleAddRemovesIt() async throws {
        let outbox = makeOutbox()
        let add = try await outbox.logWeight(weightKg: 83.9)

        let cancellation = try await outbox.cancelQueued(id: add.id)

        XCTAssertEqual(cancellation, .removed)
        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty)
    }

    /// The reviewed race: the weigh-in is deleted while its POST is on the
    /// wire and Garmin then ACCEPTS it. Before the fix it landed in Garmin
    /// with nothing left to delete it. Now the same drain resolves and
    /// deletes it again.
    func testDeletingAWeighInWhileItsPostIsInFlightDeletesItFromGarminOnceAccepted() async throws {
        let outbox = makeOutbox()
        let add = try await outbox.logWeight(weightKg: 83.9, loggedAt: morning)
        let day = WeightOutbox.localCalendarDate(of: morning)
        let deliverer = GatedWeighInDeliverer(samples: [sample(7, kg: 83.9, at: morning.addingTimeInterval(1), day: day)])

        let drain = Task { await outbox.drain(using: deliverer) }
        await deliverer.waitUntilFirstAddIsInFlight()

        let cancellation = try await outbox.cancelQueued(id: add.id)
        XCTAssertEqual(cancellation, .compensateAfterDelivery)

        deliverer.releaseFirstAdd()
        _ = await drain.value

        let deletes = await deliverer.receivedDeletes
        XCTAssertEqual(deletes.map(\.samplePk), [7], "the accepted weigh-in is deleted again in the same drain")
        XCTAssertEqual(deletes.first?.date, day)
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.count, 2)
        XCTAssertTrue(stored.allSatisfy { $0.state == .sent })
    }

    func testDeletingAWeighInWhileItsPostIsInFlightDropsItIfGarminRejectsIt() async throws {
        let outbox = makeOutbox()
        let add = try await outbox.logWeight(weightKg: 83.9, loggedAt: morning)
        let deliverer = GatedWeighInDeliverer(samples: [], firstAddFailsWith: GarminClientError.httpError(statusCode: 500, body: nil))

        let drain = Task { await outbox.drain(using: deliverer) }
        await deliverer.waitUntilFirstAddIsInFlight()
        try await outbox.cancelQueued(id: add.id)
        deliverer.releaseFirstAdd()
        _ = await drain.value

        let stored = await outbox.allEntries()
        XCTAssertTrue(stored.isEmpty, "never retried after the user deleted it")
        let deletes = await deliverer.receivedDeletes
        XCTAssertTrue(deletes.isEmpty)
    }

    func testCancellingADeleteThatIsInFlightIsRefused() async throws {
        let store = WeightOutboxStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-weight-outbox-claim-\(UUID().uuidString).json"))
        let outbox = WeightOutbox(store: store)
        let delete = try await outbox.logDelete(samplePk: 42, calendarDate: "2026-09-23", weightKg: 83.9, loggedAt: morning)
        let claimed = await store.claim(id: delete.id, now: Date())
        XCTAssertNotNil(claimed)

        do {
            try await outbox.cancelQueued(id: delete.id)
            XCTFail("expected entryInFlight")
        } catch let error as OutboxEditError {
            XCTAssertEqual(error, .entryInFlight, "a sample being deleted right now can't be kept")
        }
        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.map(\.id), [delete.id], "nothing changes when refused")
    }
}

/// Holds the FIRST `addWeighIn` call open until the test releases it (same
/// idea as HydrationSyncTests' `GatedHydrationDeliverer`); deletes and day
/// reads answer at once.
private actor GatedWeighInDeliverer: WeighInDelivering {
    private(set) var addCount = 0
    private(set) var receivedDeletes: [(date: String, samplePk: Int)] = []
    private let samples: [GarminWeighIn]
    private let firstAddError: Error?
    private let started = AsyncStream<Void>.makeStream()
    private let release = AsyncStream<Void>.makeStream()

    init(samples: [GarminWeighIn], firstAddFailsWith error: Error? = nil) {
        self.samples = samples
        self.firstAddError = error
    }

    nonisolated func waitUntilFirstAddIsInFlight() async {
        _ = await started.stream.first(where: { _ in true })
    }

    nonisolated func releaseFirstAdd() {
        release.continuation.yield(())
    }

    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        addCount += 1
        if addCount == 1 {
            started.continuation.yield(())
            _ = await release.stream.first(where: { _ in true })
            if let firstAddError { throw firstAddError }
        }
        return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/user-weight")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    }

    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse {
        receivedDeletes.append((date: date, samplePk: samplePk))
        return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/weight-service/weight/\(date)/byversion/\(samplePk)")!, statusCode: 204, httpVersion: nil, headerFields: nil)!
    }

    func weighInSamples(on date: String) async throws -> [GarminWeighIn] {
        samples.filter { $0.calendarDate == date }
    }
}

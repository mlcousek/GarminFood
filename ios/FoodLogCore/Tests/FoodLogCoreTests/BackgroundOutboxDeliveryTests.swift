// BackgroundOutboxDeliveryTests.swift
//
// fix-review-findings-2026-09 finding 3: the background refresh must move
// a weight-only or water-only queue, not just food, and a refresh must stay
// scheduled while any kind is still waiting. Finding 8: a food entry Garmin
// accepted whose re-read failed (`.sent`) must be reconciled by a LATER
// background pass, and keep a refresh scheduled until it is. Runs `BackgroundOutboxDelivery`
// (the code BackgroundRefresh.run calls) against REAL outboxes on unique
// temp files and a fake Garmin that never touches the network.

import XCTest
@testable import FoodLogCore
import GarminKit

final class BackgroundOutboxDeliveryTests: XCTestCase {
    private struct Queues {
        let outbox: Outbox
        let reconciliation: Reconciliation
        let weight: WeightOutbox
        let hydration: HydrationOutbox
    }

    private func makeQueues() -> Queues {
        let id = UUID().uuidString
        let outbox = Outbox(processName: "bg-food-\(id)")
        return Queues(
            outbox: outbox,
            reconciliation: Reconciliation(outbox: outbox),
            weight: WeightOutbox(processName: "bg-weight-\(id)"),
            hydration: HydrationOutbox(processName: "bg-water-\(id)")
        )
    }

    private func run<Client: FoodLogDelivering & FoodLogReconciling & WeighInDelivering & HydrationDelivering>(_ q: Queues, _ client: Client) async -> BackgroundOutboxDelivery.Outcome {
        await BackgroundOutboxDelivery.run(
            outbox: q.outbox,
            reconciliation: q.reconciliation,
            weightOutbox: q.weight,
            hydrationOutbox: q.hydration,
            client: client
        )
    }

    func testAWeightOnlyQueueIsDeliveredInTheBackground() async throws {
        let q = makeQueues()
        try await q.weight.logWeight(weightKg: 70.2)

        let outcome = await run(q, FakeGarmin(online: true))

        let weights = await q.weight.allEntries()
        XCTAssertEqual(weights.map(\.state), [.sent], "the weigh-in reached Garmin without the app in front")
        XCTAssertFalse(outcome.needsAnotherRefresh)
        XCTAssertEqual(outcome.authOutcome, DrainAuthOutcome.none)
    }

    func testAWaterOnlyQueueIsDeliveredInTheBackground() async throws {
        let q = makeQueues()
        try await q.hydration.logHydration(valueInML: 300)

        let outcome = await run(q, FakeGarmin(online: true))

        let drinks = await q.hydration.allEntries()
        XCTAssertEqual(drinks.map(\.state), [.sent])
        XCTAssertFalse(outcome.needsAnotherRefresh)
    }

    func testAWeightOrWaterOnlyQueueKeepsTheRefreshScheduledWhileGarminIsUnreachable() async throws {
        let weightOnly = makeQueues()
        try await weightOnly.weight.logWeight(weightKg: 70.2)
        let waterOnly = makeQueues()
        try await waterOnly.hydration.logHydration(valueInML: 300)

        let weightOutcome = await run(weightOnly, FakeGarmin(online: false))
        let waterOutcome = await run(waterOnly, FakeGarmin(online: false))

        XCTAssertTrue(weightOutcome.needsAnotherRefresh, "a pending weigh-in asks iOS for another refresh")
        XCTAssertTrue(waterOutcome.needsAnotherRefresh, "so does a pending drink")
    }

    func testAnAcceptedFoodEntryWhoseReReadFailedIsReconciledByALaterBackgroundPass() async throws {
        let q = makeQueues()
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-14T08:00:00Z"))
        try await q.outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "synthetic-food", servingId: "synthetic-serving", numberOfUnits: 1, createdAt: createdAt)

        // Pass 1: Garmin accepts the POST, but the day re-read fails.
        let first = await run(q, ReadScriptedGarmin(readSucceeds: false))
        let afterFirst = await q.outbox.allEntries()
        XCTAssertEqual(afterFirst.map(\.state), [.sent], "accepted, not reconciled yet")
        XCTAssertTrue(first.needsAnotherRefresh, "an unreconciled accepted entry keeps a refresh scheduled")

        // Pass 2: nothing new to deliver, but the stranded entry is picked up.
        let second = await run(q, ReadScriptedGarmin(readSucceeds: true))
        let afterSecond = await q.outbox.allEntries()
        XCTAssertTrue(afterSecond.isEmpty, "confirmed against Garmin's log and done")
        XCTAssertFalse(second.needsAnotherRefresh)
    }

    func testBacklogCountsEveryKindButNotFailedOrSentEntries() {
        let pendingWeight = WeightOutboxEntry(weightKg: 70)
        let pendingDrink = HydrationOutboxEntry(valueInML: 250)

        XCTAssertTrue(OutboxBacklog.needsDelivery(food: [], weight: [pendingWeight], hydration: []))
        XCTAssertTrue(OutboxBacklog.needsDelivery(food: [], weight: [], hydration: [pendingDrink]))
        XCTAssertFalse(OutboxBacklog.needsDelivery(food: [], weight: [], hydration: []))
        XCTAssertFalse(OutboxBacklog.needsDelivery(
            food: [],
            weight: [WeightOutboxEntry(weightKg: 70, state: .failed)],
            hydration: [HydrationOutboxEntry(valueInML: 250, state: .sent)]
        ), "failed entries wait for the user in the sync queue; sent ones are done")
    }
}

/// Garmin for this test: weight and water succeed (or fail as offline);
/// the food routes are never reached, since no food is queued.
private struct FakeGarmin: FoodLogDelivering, FoodLogReconciling, WeighInDelivering, HydrationDelivering {
    let online: Bool

    private func ok(_ path: String) throws -> HTTPURLResponse {
        guard online else { throw URLError(.notConnectedToInternet) }
        return HTTPURLResponse(url: URL(string: "https://example.invalid\(path)")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse { try ok("/food") }
    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse { try ok("/food") }
    func dailyFoodLog(date: String) async throws -> DailyFoodLog? { nil }
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse { try ok("/weight") }
    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse { try ok("/weight") }
    func weighInSamples(on date: String) async throws -> [GarminWeighIn] { [] }
    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse { try ok("/water") }
}

/// Food delivery succeeds; the day re-read fails or returns the delivered
/// entry (its `logTimestamp` is the entry's own `createdAt`, as Garmin
/// echoes it). Synthetic ids only.
private struct ReadScriptedGarmin: FoodLogDelivering, FoodLogReconciling, WeighInDelivering, HydrationDelivering {
    let readSucceeds: Bool

    private func ok() -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.invalid/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse { ok() }
    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse { ok() }
    func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
        guard readSucceeds else { throw URLError(.timedOut) }
        let json = """
        { "mealDetails": [ { "meal": { "mealName": "BREAKFAST" }, "loggedFoods": [ {
            "logId": "synthetic-log-1",
            "logTimestamp": "2026-09-14T08:00:00.000Z",
            "servingQty": 1.0,
            "foodMetaData": { "foodId": "synthetic-food" },
            "nutritionContent": { "servingId": "synthetic-serving", "numberOfUnits": 1.0 }
        } ] } ] }
        """
        return try JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse { ok() }
    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse { ok() }
    func weighInSamples(on date: String) async throws -> [GarminWeighIn] { [] }
    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse { ok() }
}

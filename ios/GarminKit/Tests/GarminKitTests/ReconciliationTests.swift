// ReconciliationTests.swift
//
// Pure duplicate-matching logic tests (tasks 10.1-10.3, garmin-sync spec's
// "Delivered entries are reconciled against Garmin, not against local
// state" requirement). Builds `DailyFoodLog` fixtures by decoding hand-written
// JSON shaped exactly like docs/garmin-food-log-contract.md's confirmed
// read shape -- no network access, no real device.

import XCTest
@testable import GarminKit

final class ReconciliationTests: XCTestCase {
    private struct LoggedEntryFixture {
        let mealName: String
        let foodId: String
        let servingId: String
        let logId: String
        let servingQty: Double?
        let contentNumberOfUnits: Double?
        let timestamp: String
    }

    private func makeLog(_ fixtures: [LoggedEntryFixture]) -> DailyFoodLog {
        let byMeal = Dictionary(grouping: fixtures, by: \.mealName)
        let mealDetailsJSON = byMeal.map { mealName, group -> String in
            let foodsJSON = group.map { fixture -> String in
                let servingQtyField = fixture.servingQty.map { "\"servingQty\": \($0)," } ?? ""
                let contentUnitsField = fixture.contentNumberOfUnits.map { "\($0)" } ?? "null"
                return """
                {
                    "logId": "\(fixture.logId)",
                    "logTimestamp": "\(fixture.timestamp)",
                    \(servingQtyField)
                    "foodMetaData": { "foodId": "\(fixture.foodId)" },
                    "nutritionContent": { "servingId": "\(fixture.servingId)", "numberOfUnits": \(contentUnitsField) }
                }
                """
            }.joined(separator: ",")
            return "{ \"meal\": { \"mealName\": \"\(mealName)\" }, \"loggedFoods\": [\(foodsJSON)] }"
        }.joined(separator: ",")

        let json = "{ \"mealDetails\": [\(mealDetailsJSON)] }"
        return try! JSONDecoder().decode(DailyFoodLog.self, from: Data(json.utf8))
    }

    private func makeEntry(mealType: MealType = .breakfast, foodId: String = "1", servingId: String = "2", numberOfUnits: Double = 1.0) -> OutboxEntry {
        OutboxEntry(date: "2026-09-14", mealType: mealType, foodId: foodId, servingId: servingId, numberOfUnits: numberOfUnits)
    }

    // MARK: - No match

    func testNoMatchWhenFoodIdDiffers() {
        let log = makeLog([LoggedEntryFixture(mealName: "BREAKFAST", foodId: "999", servingId: "2", logId: "log1", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "t")])
        let entry = makeEntry(foodId: "17926789", servingId: "2")

        XCTAssertTrue(Reconciliation.matchingLoggedFoods(for: entry, in: log).isEmpty)
    }

    func testNoMatchWhenServingIdDiffers() {
        let log = makeLog([LoggedEntryFixture(mealName: "BREAKFAST", foodId: "1", servingId: "999", logId: "log1", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "t")])
        let entry = makeEntry(foodId: "1", servingId: "2")

        XCTAssertTrue(Reconciliation.matchingLoggedFoods(for: entry, in: log).isEmpty)
    }

    func testNoMatchWhenMealTypeDiffers() {
        let log = makeLog([LoggedEntryFixture(mealName: "DINNER", foodId: "1", servingId: "2", logId: "log1", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "t")])
        let entry = makeEntry(mealType: .lunch, foodId: "1", servingId: "2")

        XCTAssertTrue(Reconciliation.matchingLoggedFoods(for: entry, in: log).isEmpty)
    }

    func testMatchingAgainstNilLogReturnsNoMatches() {
        XCTAssertTrue(Reconciliation.matchingLoggedFoods(for: makeEntry(), in: nil).isEmpty)
    }

    // MARK: - Single match (happy path)

    func testSingleMatchByFoodServingMealAndQuantity() {
        let log = makeLog([LoggedEntryFixture(mealName: "BREAKFAST", foodId: "17926789", servingId: "16904392", logId: "log1", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "t")])
        let entry = makeEntry(mealType: .breakfast, foodId: "17926789", servingId: "16904392", numberOfUnits: 1.0)

        let matches = Reconciliation.matchingLoggedFoods(for: entry, in: log)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.logId, "log1")
    }

    // MARK: - Deliberately tolerant quantity matching (contract's unconfirmed field)

    func testQuantityMatchAcceptsTopLevelServingQty() {
        let log = makeLog([LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log1", servingQty: 0.7, contentNumberOfUnits: 100, timestamp: "t")])
        let entry = makeEntry(mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 0.7)

        XCTAssertEqual(Reconciliation.matchingLoggedFoods(for: entry, in: log).count, 1)
    }

    func testQuantityMatchAcceptsNestedNutritionContentNumberOfUnitsWhenServingQtyIsAbsent() {
        let log = makeLog([LoggedEntryFixture(mealName: "LUNCH", foodId: "1", servingId: "2", logId: "log1", servingQty: nil, contentNumberOfUnits: 3.0, timestamp: "t")])
        let entry = makeEntry(mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 3.0)

        XCTAssertEqual(Reconciliation.matchingLoggedFoods(for: entry, in: log).count, 1)
    }

    func testQuantityMismatchOnBothFieldsDoesNotMatch() {
        let log = makeLog([LoggedEntryFixture(mealName: "LUNCH", foodId: "1", servingId: "2", logId: "log1", servingQty: 5.0, contentNumberOfUnits: 100, timestamp: "t")])
        let entry = makeEntry(mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1.0)

        XCTAssertTrue(Reconciliation.matchingLoggedFoods(for: entry, in: log).isEmpty)
    }

    // MARK: - Duplicate detection

    func testDuplicateDetectionFindsBothCopies() {
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log-a", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log-b", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:05:00Z"),
        ])
        let entry = makeEntry(mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0)

        let matches = Reconciliation.matchingLoggedFoods(for: entry, in: log)
        XCTAssertEqual(matches.count, 2, "reconciliation must see both copies in order to delete one")
        XCTAssertEqual(Set(matches.compactMap(\.logId)), Set(["log-a", "log-b"]))
    }

    func testDuplicatesAcrossDifferentUnrelatedEntriesAreNotConfused() {
        // Two distinct real entries, plus one accidental duplicate of the
        // second -- matching must isolate exactly the duplicated one.
        let log = makeLog([
            LoggedEntryFixture(mealName: "BREAKFAST", foodId: "1", servingId: "2", logId: "log-1", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "t1"),
            LoggedEntryFixture(mealName: "LUNCH", foodId: "5", servingId: "6", logId: "log-2a", servingQty: 2.0, contentNumberOfUnits: 100, timestamp: "t2"),
            LoggedEntryFixture(mealName: "LUNCH", foodId: "5", servingId: "6", logId: "log-2b", servingQty: 2.0, contentNumberOfUnits: 100, timestamp: "t3"),
        ])

        let breakfastEntry = makeEntry(mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1.0)
        let lunchEntry = makeEntry(mealType: .lunch, foodId: "5", servingId: "6", numberOfUnits: 2.0)

        XCTAssertEqual(Reconciliation.matchingLoggedFoods(for: breakfastEntry, in: log).count, 1)
        XCTAssertEqual(Reconciliation.matchingLoggedFoods(for: lunchEntry, in: log).count, 2)
    }

    // MARK: - End-to-end reconcile() with a fake client (still no network)

    private actor FakeReconcilingClient: FoodLogReconciling {
        private let log: DailyFoodLog?
        private(set) var deletedLogIds: [String] = []

        init(log: DailyFoodLog?) {
            self.log = log
        }

        func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
            log
        }

        func deleteFoodLogEntries(logIds: [String]) async throws -> HTTPURLResponse {
            deletedLogIds.append(contentsOf: logIds)
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }
    }

    func testReconcileDeletesAllButOneDuplicate() async throws {
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log-a", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log-b", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:05:00Z"),
        ])
        let client = FakeReconcilingClient(log: log)
        let outbox = Outbox(store: OutboxStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-reconcile-\(UUID().uuidString).json")))
        let reconciliation = Reconciliation(outbox: outbox)
        let entry = OutboxEntry(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0, state: .sent)

        let outcomes = await reconciliation.reconcile(delivered: [entry], using: client)

        XCTAssertEqual(outcomes.count, 1)
        guard case .duplicateResolved(let kept, let deleted) = outcomes[0].verdict else {
            return XCTFail("expected .duplicateResolved, got \(outcomes[0].verdict)")
        }
        XCTAssertEqual(kept, "log-a", "the earliest-timestamped copy should be kept")
        XCTAssertEqual(deleted, ["log-b"])
        let actuallyDeleted = await client.deletedLogIds
        XCTAssertEqual(actuallyDeleted, ["log-b"])
    }

    func testGenuinelyDuplicateLocalEntriesBothSurviveReconciliation() async throws {
        // Two DISTINCT local entries that happen to share the exact same
        // match key (date, mealType, foodId, servingId, numberOfUnits) --
        // e.g. the user genuinely logged the same snack twice. Both were
        // delivered, so Garmin's re-read legitimately shows two matching
        // entries (B1). Resolving these independently (the pre-fix
        // behavior) had each of the two per-entry resolutions independently
        // see "2 Garmin matches" and each try to delete the second copy down
        // to 1 -- net-deleting one of the two real entries. Grouped
        // resolution must instead see "2 locally expected, 2 found" and
        // confirm both without deleting anything.
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log-a", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "log-b", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:05:00Z"),
        ])
        let client = FakeReconcilingClient(log: log)
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-reconcile-\(UUID().uuidString).json")
        let outbox = Outbox(store: OutboxStore(fileURL: storeURL))
        let reconciliation = Reconciliation(outbox: outbox)

        let firstEntry = try await outbox.logFood(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0)
        let secondEntry = try await outbox.logFood(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0)
        var sentFirst = firstEntry
        sentFirst.state = .sent
        var sentSecond = secondEntry
        sentSecond.state = .sent
        try await outbox.requeue(sentFirst)
        try await outbox.requeue(sentSecond)

        let outcomes = await reconciliation.reconcile(delivered: [sentFirst, sentSecond], using: client)

        XCTAssertEqual(outcomes.count, 2)
        var confirmedLogIds: Set<String> = []
        for outcome in outcomes {
            guard case .confirmed(let logId?) = outcome.verdict else {
                return XCTFail("both genuinely-distinct duplicates must be confirmed (with a non-nil logId), not treated as an excess duplicate to delete; got \(outcome.verdict)")
            }
            confirmedLogIds.insert(logId)
        }
        XCTAssertEqual(confirmedLogIds, Set(["log-a", "log-b"]), "each entry should be confirmed against one of the two real Garmin copies")

        let actuallyDeleted = await client.deletedLogIds
        XCTAssertTrue(actuallyDeleted.isEmpty, "neither of two genuinely-distinct local entries sharing a match key may be deleted from Garmin")
    }

    func testReconcileConfirmsASingleMatch() async throws {
        let log = makeLog([LoggedEntryFixture(mealName: "BREAKFAST", foodId: "1", servingId: "2", logId: "log-1", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "t")])
        let client = FakeReconcilingClient(log: log)
        let outbox = Outbox(store: OutboxStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-reconcile-\(UUID().uuidString).json")))
        let reconciliation = Reconciliation(outbox: outbox)
        let entry = OutboxEntry(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1.0, state: .sent)

        let outcomes = await reconciliation.reconcile(delivered: [entry], using: client)

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].verdict, .confirmed(logId: "log-1"))
    }

    func testReconcileRequeuesWhenAnEntryIsMissingFromTheReRead() async throws {
        let log = makeLog([]) // nothing logged at all -- the 2xx lied
        let client = FakeReconcilingClient(log: log)
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-reconcile-\(UUID().uuidString).json")
        let outbox = Outbox(store: OutboxStore(fileURL: storeURL))
        let entry = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1.0)
        // Simulate that this entry was already marked `.sent` by a prior drain.
        var sentEntry = entry
        sentEntry.state = .sent
        try await outbox.requeue(sentEntry)

        let reconciliation = Reconciliation(outbox: outbox)
        let outcomes = await reconciliation.reconcile(delivered: [sentEntry], using: client)

        XCTAssertEqual(outcomes.count, 1)
        XCTAssertEqual(outcomes[0].verdict, .missingRequeued)

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .pending, "a missing entry must be re-queued for delivery, not left sent-but-absent")
        XCTAssertEqual(stored.first?.attemptCount, 0)
    }
}

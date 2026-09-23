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

    private func tempStoreURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("garminkit-reconcile-\(UUID().uuidString).json")
    }

    private func instant(_ iso: String) -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
    }

    private func loggedFood(timestamp: String) -> LoggedFood {
        try! JSONDecoder().decode(LoggedFood.self, from: Data("{ \"logTimestamp\": \"\(timestamp)\" }".utf8))
    }

    /// Before every 2026-09-14 fixture below. Entries created "now" would
    /// sit after those fixtures, and the delivery guard would correctly
    /// refuse to treat anything logged before them as their own.
    private var queuedBeforeFixtures: Date { instant("2026-09-14T05:00:00Z") }

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
        private(set) var deleteDates: [String] = []

        init(log: DailyFoodLog?) {
            self.log = log
        }

        func dailyFoodLog(date: String) async throws -> DailyFoodLog? {
            log
        }

        func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse {
            deletedLogIds.append(contentsOf: logIds)
            deleteDates.append(date)
            return HTTPURLResponse(url: URL(string: "https://connectapi.garmin.com/nutrition-service/food/logs/\(date)")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
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
        let entry = OutboxEntry(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0, state: .sent, createdAt: queuedBeforeFixtures)

        let outcomes = await reconciliation.reconcile(delivered: [entry], using: client)

        XCTAssertEqual(outcomes.count, 1)
        guard case .duplicateResolved(let kept, let deleted) = outcomes[0].verdict else {
            return XCTFail("expected .duplicateResolved, got \(outcomes[0].verdict)")
        }
        XCTAssertEqual(kept, "log-a", "the earliest-timestamped copy should be kept")
        XCTAssertEqual(deleted, ["log-b"])
        let actuallyDeleted = await client.deletedLogIds
        XCTAssertEqual(actuallyDeleted, ["log-b"])
        let deleteDates = await client.deleteDates
        XCTAssertEqual(deleteDates, ["2026-09-14"], "the delete route takes the entry's date in its path")
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

        let firstEntry = try await outbox.logFood(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0, createdAt: queuedBeforeFixtures)
        let secondEntry = try await outbox.logFood(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0, createdAt: queuedBeforeFixtures)
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
        XCTAssertEqual(stored.first?.attemptCount, 1, "a miss must count toward maxAttempts, or a write Garmin accepts but files elsewhere is re-sent forever")
    }

    // MARK: - Only this app's own deliveries count

    func testAnIdenticalEntryLoggedBeforeThisAppQueuedItIsNeverDeleted() async throws {
        // The user logged this exact snack in the official app at 06:00, then
        // the same snack again in this app at 09:00. Both match the key, but
        // only the second can be this app's delivery. Counting the first
        // made it look like one excess duplicate -- and the excess deleted
        // is the LATER copy: the one just logged here.
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "official", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00.000Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "ours", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T09:00:00.000Z"),
        ])
        let client = FakeReconcilingClient(log: log)
        let reconciliation = Reconciliation(outbox: Outbox(store: OutboxStore(fileURL: tempStoreURL())))
        let entry = OutboxEntry(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0, state: .sent, createdAt: instant("2026-09-14T09:00:00Z"))

        let outcomes = await reconciliation.reconcile(delivered: [entry], using: client)

        XCTAssertEqual(outcomes.map(\.verdict), [.confirmed(logId: "ours")])
        let deleted = await client.deletedLogIds
        XCTAssertTrue(deleted.isEmpty, "an entry logged before this app queued anything can't be this app's duplicate, and must never be deleted")
    }

    func testTheDeliveryGuardRulesOutOnlyWhatWasLoggedClearlyEarlier() {
        let queued = instant("2026-09-14T09:00:00Z")

        XCTAssertTrue(Reconciliation.couldBeThisAppsDelivery(loggedFood(timestamp: "2026-09-14T09:00:00.000Z"), notBefore: queued))
        XCTAssertTrue(Reconciliation.couldBeThisAppsDelivery(loggedFood(timestamp: "2026-09-14T09:03:12.500Z"), notBefore: queued))
        XCTAssertTrue(
            Reconciliation.couldBeThisAppsDelivery(loggedFood(timestamp: "2026-09-14T08:55:00Z"), notBefore: queued),
            "a few minutes early is clock skew between the phone and Garmin, not proof it isn't ours"
        )
        XCTAssertFalse(Reconciliation.couldBeThisAppsDelivery(loggedFood(timestamp: "2026-09-14T06:00:00.000Z"), notBefore: queued))
    }

    func testAnUnreadableTimestampStillCounts() {
        XCTAssertTrue(
            Reconciliation.couldBeThisAppsDelivery(loggedFood(timestamp: "t"), notBefore: instant("2026-09-14T09:00:00Z")),
            "the guard fails open: what it can't read, it can't rule out"
        )
    }

    // MARK: - add-log-entry-editing D2

    func testAReplacedEntrysOldCopyIsNeverCountedOrDeleted() async throws {
        // The user edited "old" (1 serving) to 2 servings; the replace is
        // still queued, so "old" is expected to vanish. An unrelated `.sent`
        // entry X with the same key as "old" must not see it as an excess
        // copy of itself -- deleting the LATER copy (X's own delivery) and
        // then having the replace delete "old" too would lose both.
        let outbox = Outbox(store: OutboxStore(fileURL: tempStoreURL()))
        _ = try await outbox.logFood(
            date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 2,
            replaces: ReplacedLog(date: "2026-09-14", logId: "old")
        )
        var x = try await outbox.logFood(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1, createdAt: queuedBeforeFixtures)
        x.state = .sent
        try await outbox.requeue(x)
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "old", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "x-delivery", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:05:00Z"),
        ])
        let client = FakeReconcilingClient(log: log)

        let outcomes = await Reconciliation(outbox: outbox).reconcile(delivered: [x], using: client)

        XCTAssertEqual(outcomes.map(\.verdict), [.confirmed(logId: "x-delivery")])
        let deleted = await client.deletedLogIds
        XCTAssertTrue(deleted.isEmpty, "the replace deletes its own old entry; reconciliation must not delete anything here")
    }

    func testATemporaryDuplicateFromAnAwaitingDeleteReplaceIsNotDeletedAgain() async throws {
        // A replace already created its corrected entry ("r-created", same
        // key as X) and is waiting to delete "old-half". X is `.sent`. Two
        // copies of the key are exactly what's expected right now.
        let outbox = Outbox(store: OutboxStore(fileURL: tempStoreURL()))
        var replace = try await outbox.logFood(
            date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1,
            replaces: ReplacedLog(date: "2026-09-14", logId: "old-half"), createdAt: queuedBeforeFixtures
        )
        replace.state = .createdAwaitingDelete
        try await outbox.requeue(replace)
        var x = try await outbox.logFood(date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1, createdAt: queuedBeforeFixtures)
        x.state = .sent
        try await outbox.requeue(x)
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "x-delivery", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "r-created", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:05:00Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "old-half", servingQty: 0.5, contentNumberOfUnits: 100, timestamp: "2026-09-14T05:30:00Z"),
        ])
        let client = FakeReconcilingClient(log: log)

        let outcomes = await Reconciliation(outbox: outbox).reconcile(delivered: [x], using: client)

        XCTAssertEqual(outcomes.count, 1)
        guard case .confirmed = outcomes[0].verdict else {
            return XCTFail("expected confirmed, got \(outcomes[0].verdict)")
        }
        let deleted = await client.deletedLogIds
        XCTAssertTrue(deleted.isEmpty, "the replace's own corrected entry is not an excess copy")
        let remaining = await outbox.allEntries()
        XCTAssertEqual(remaining.map(\.id), [replace.id], "X is done; the replace still owes its delete")
    }

    func testADuplicatesSourceIsNotMistakenForItsDelivery() async throws {
        // "Second coffee": duplicated 2 minutes after the first, well inside
        // the clock tolerance, so the source would otherwise count -- and
        // the excess copy deleted would be the duplicate itself.
        let log = makeLog([
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "source", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T09:00:00.000Z"),
            LoggedEntryFixture(mealName: "SNACKS", foodId: "1", servingId: "2", logId: "dup", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T09:02:00.000Z"),
        ])
        let client = FakeReconcilingClient(log: log)
        let reconciliation = Reconciliation(outbox: Outbox(store: OutboxStore(fileURL: tempStoreURL())))
        let entry = OutboxEntry(
            date: "2026-09-14", mealType: .snacks, foodId: "1", servingId: "2", numberOfUnits: 1.0,
            duplicateOf: "source", state: .sent, createdAt: instant("2026-09-14T09:02:00Z")
        )

        let outcomes = await reconciliation.reconcile(delivered: [entry], using: client)

        XCTAssertEqual(outcomes.map(\.verdict), [.confirmed(logId: "dup")])
        let deleted = await client.deletedLogIds
        XCTAssertTrue(deleted.isEmpty)
    }

    func testAnExcludedEntryIsStillCountedWhenItIsTheOnlyWayToAccountForADelivery() async throws {
        // O was delivered as "o-delivery" but not reconciled yet; the user
        // already edited that row, so a replace names it. Excluding it would
        // make O look missing and send it AGAIN.
        let outbox = Outbox(store: OutboxStore(fileURL: tempStoreURL()))
        var o = try await outbox.logFood(date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1, createdAt: queuedBeforeFixtures)
        o.state = .sent
        try await outbox.requeue(o)
        _ = try await outbox.logFood(
            date: "2026-09-14", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 2,
            replaces: ReplacedLog(date: "2026-09-14", logId: "o-delivery")
        )
        let log = makeLog([
            LoggedEntryFixture(mealName: "LUNCH", foodId: "1", servingId: "2", logId: "o-delivery", servingQty: 1.0, contentNumberOfUnits: 100, timestamp: "2026-09-14T06:00:00Z"),
        ])
        let client = FakeReconcilingClient(log: log)

        let outcomes = await Reconciliation(outbox: outbox).reconcile(delivered: [o], using: client)

        XCTAssertEqual(outcomes.map(\.verdict), [.confirmed(logId: "o-delivery")], "must not be re-queued as missing")
    }

    // MARK: - Missed deliveries are bounded

    func testAnEntryThatKeepsGoingMissingIsEventuallyMarkedFailed() async throws {
        let client = FakeReconcilingClient(log: makeLog([]))
        let outbox = Outbox(store: OutboxStore(fileURL: tempStoreURL()), maxAttempts: 2)
        let reconciliation = Reconciliation(outbox: outbox)

        var entry = try await outbox.logFood(date: "2026-09-14", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1.0)
        entry.state = .sent
        try await outbox.requeue(entry)

        let first = await reconciliation.reconcile(delivered: [entry], using: client)
        XCTAssertEqual(first.map(\.verdict), [.missingRequeued])

        let afterFirst = await outbox.allEntries()
        var redelivered = try XCTUnwrap(afterFirst.first)
        redelivered.state = .sent
        try await outbox.requeue(redelivered)

        let second = await reconciliation.reconcile(delivered: [redelivered], using: client)
        XCTAssertEqual(second.map(\.verdict), [.missingGaveUp])

        let stored = await outbox.allEntries()
        XCTAssertEqual(stored.first?.state, .failed, "a delivery that keeps vanishing must stop being re-sent")
        XCTAssertEqual(stored.first?.attemptCount, 2)
        XCTAssertNotNil(stored.first?.lastError, "the reason has to survive for the app's delivery banner")
    }
}

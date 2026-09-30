// DeliverySafetyTests.swift
//
// fix-review-findings-2026-09:
//   - finding 9: queued entries are stamped with the Garmin account they
//     were logged under and never delivered to another account (held, not
//     dropped); signing out ties unstamped ones to the outgoing account.
//   - finding 16: an entry whose 2xx could not be recorded (the store
//     write failed, then the process died) is never blindly POSTed again
//     after a restart.
// The "crash" is simulated on real stores: a deliverer that accepts the
// request, snapshots the outbox file as it was on disk at that moment
// (the send marker saved, the outcome not) and then makes the directory
// unwritable; the "restart" puts that snapshot back and opens a fresh
// store on it. Synthetic data only.

import XCTest
@testable import GarminKit

final class DeliverySafetyTests: XCTestCase {
    // MARK: - Helpers

    /// Mutable account key for an outbox's provider.
    private final class KeyBox: @unchecked Sendable {
        var value: String?
        init(_ value: String?) { self.value = value }
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("delivery-safety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The disk as it was at the simulated crash, restored for a restart.
    private func restore(_ snapshot: Data, to fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try snapshot.write(to: fileURL)
    }

    private let loggedAt = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - Finding 9: account scope

    func testAFoodEntryIsOnlyDeliveredToTheAccountItWasLoggedUnder() async throws {
        let key = KeyBox("account-a")
        let outbox = Outbox(store: OutboxStore(fileURL: try tempDir().appendingPathComponent("outbox.json")), accountKey: { key.value })
        let entry = try await outbox.logFood(date: "2026-09-30", mealType: .lunch, foodId: "synthetic-1", servingId: "s-1", numberOfUnits: 1)
        XCTAssertEqual(entry.accountKey, "account-a", "stamped at enqueue")

        let deliverer = RecordingFoodDeliverer()
        key.value = "account-b"
        _ = await outbox.drain(using: deliverer)
        key.value = nil // a new sign-in whose profile isn't known yet
        _ = await outbox.drain(using: deliverer)
        var sends = await deliverer.creates
        XCTAssertEqual(sends, 0, "never sent to another (or an unknown) account")
        let held = await outbox.allEntries()
        XCTAssertEqual(held.map(\.state), [.pending], "held, not dropped")

        key.value = "account-a"
        _ = await outbox.drain(using: deliverer)
        sends = await deliverer.creates
        XCTAssertEqual(sends, 1, "delivered once its own account is back")
    }

    func testWeightAndWaterAreHeldForTheirOwnAccountToo() async throws {
        let key = KeyBox("account-a")
        let dir = try tempDir()
        let weight = WeightOutbox(store: WeightOutboxStore(fileURL: dir.appendingPathComponent("weight.json")), accountKey: { key.value })
        let water = HydrationOutbox(store: HydrationOutboxStore(fileURL: dir.appendingPathComponent("water.json")), accountKey: { key.value })
        try await weight.logWeight(weightKg: 72.5, loggedAt: loggedAt)
        try await water.logHydration(valueInML: 300, loggedAt: loggedAt)

        key.value = "account-b"
        let weighIns = RecordingWeighInDeliverer(samples: [])
        let drinks = RecordingHydrationDeliverer()
        _ = await weight.drain(using: weighIns)
        _ = await water.drain(using: drinks)

        let weightSends = await weighIns.adds
        let waterSends = await drinks.adds
        XCTAssertEqual(weightSends, 0)
        XCTAssertEqual(waterSends, 0)
        let weightStates = await weight.allEntries().map(\.state)
        let waterStates = await water.allEntries().map(\.state)
        XCTAssertEqual(weightStates, [.pending])
        XCTAssertEqual(waterStates, [.pending])
    }

    func testSigningOutTiesUnstampedEntriesToTheOutgoingAccount() async throws {
        let key = KeyBox(nil)
        let outbox = Outbox(store: OutboxStore(fileURL: try tempDir().appendingPathComponent("outbox.json")), accountKey: { key.value })
        // Logged while no account was known (or by an older build).
        try await outbox.logFood(date: "2026-09-30", mealType: .dinner, foodId: "synthetic-2", servingId: "s-2", numberOfUnits: 1)

        try await outbox.assignUnscopedEntries(to: "account-a")
        key.value = "account-b"
        let deliverer = RecordingFoodDeliverer()
        _ = await outbox.drain(using: deliverer)

        let sends = await deliverer.creates
        XCTAssertEqual(sends, 0, "account B never receives what was queued before A signed out")
        let stamps = await outbox.allEntries().map(\.accountKey)
        XCTAssertEqual(stamps, ["account-a"])
    }

    func testTheRememberedAccountIsOnlyTrustedForTheTokenItWasLearnedWith() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "delivery-safety-\(UUID().uuidString)"))
        let profile = try JSONDecoder().decode(SocialProfile.self, from: Data(#"{"userName":"synthetic.user","displayName":"00000000-0000-4000-8000-000000000000"}"#.utf8))
        let expected = try XCTUnwrap(GarminAccountKey.key(for: profile))

        GarminAccountKey.record(profile: profile, tokenFingerprint: "token-1", defaults: defaults)

        XCTAssertEqual(GarminAccountKey.current(tokenFingerprint: "token-1", defaults: defaults), expected)
        XCTAssertNil(GarminAccountKey.current(tokenFingerprint: "token-2", defaults: defaults), "a new sign-in is unknown until its profile is read")
        XCTAssertNil(GarminAccountKey.current(tokenFingerprint: nil, defaults: defaults))
        XCTAssertEqual(GarminAccountKey.lastRecorded(defaults: defaults), expected)
        XCTAssertEqual(expected.count, 64, "a SHA-256, never the identifier itself")
        XCTAssertFalse(expected.contains("synthetic"))
        GarminAccountKey.clear(defaults: defaults)
        XCTAssertNil(GarminAccountKey.lastRecorded(defaults: defaults))
    }

    func testTheScopeRule() {
        XCTAssertTrue(AccountScope.mayDeliver(entryKey: nil, currentKey: nil))
        XCTAssertTrue(AccountScope.mayDeliver(entryKey: nil, currentKey: "b"))
        XCTAssertTrue(AccountScope.mayDeliver(entryKey: "a", currentKey: "a"))
        XCTAssertFalse(AccountScope.mayDeliver(entryKey: "a", currentKey: "b"))
        XCTAssertFalse(AccountScope.mayDeliver(entryKey: "a", currentKey: nil))
    }

    // MARK: - Finding 16: no blind re-send after an unrecorded 2xx

    func testAWeighInAcceptedButNotRecordedIsLookedUpNotResentAfterARestart() async throws {
        let fileURL = try tempDir().appendingPathComponent("weight.json")
        let outbox = WeightOutbox(store: WeightOutboxStore(fileURL: fileURL))
        try await outbox.logWeight(weightKg: 72.5, loggedAt: loggedAt)

        let crashing = CrashAfterAcceptDeliverer(fileURL: fileURL)
        _ = await outbox.drain(using: crashing)
        let captured = await crashing.snapshot
        try restore(try XCTUnwrap(captured), to: fileURL)

        // Restart: a fresh store on the file as it was at the crash.
        let restarted = WeightOutbox(store: WeightOutboxStore(fileURL: fileURL))
        let pending = await restarted.allEntries()
        XCTAssertEqual(pending.map(\.state), [.pending], "the 2xx never reached the disk")
        XCTAssertNotNil(pending.first?.sendStartedAt, "but the send marker did")

        let garmin = RecordingWeighInDeliverer(samples: [
            GarminWeighIn(samplePk: 11, calendarDate: "2026-09-21", weightGrams: 72_500, timestampGMT: loggedAt.timeIntervalSince1970 * 1000)
        ])
        _ = await restarted.drain(using: garmin)

        let resent = await garmin.adds
        XCTAssertEqual(resent, 0, "Garmin already has it: no second weigh-in")
        let after = await restarted.allEntries()
        XCTAssertEqual(after.map(\.state), [.sent])
        XCTAssertNil(after.first?.sendStartedAt)
    }

    func testAWeighInGarminDoesNotHaveIsSentAgainAfterARestart() async throws {
        let fileURL = try tempDir().appendingPathComponent("weight.json")
        let outbox = WeightOutbox(store: WeightOutboxStore(fileURL: fileURL))
        try await outbox.logWeight(weightKg: 72.5, loggedAt: loggedAt)
        let crashing = CrashAfterAcceptDeliverer(fileURL: fileURL)
        _ = await outbox.drain(using: crashing)
        let captured = await crashing.snapshot
        try restore(try XCTUnwrap(captured), to: fileURL)

        let restarted = WeightOutbox(store: WeightOutboxStore(fileURL: fileURL))
        let garmin = RecordingWeighInDeliverer(samples: [])
        _ = await restarted.drain(using: garmin)

        let sends = await garmin.adds
        XCTAssertEqual(sends, 1, "not in Garmin's day view: sending it is correct")
    }

    func testADrinkAcceptedButNotRecordedIsNeverResentBlindly() async throws {
        let fileURL = try tempDir().appendingPathComponent("water.json")
        let outbox = HydrationOutbox(store: HydrationOutboxStore(fileURL: fileURL))
        try await outbox.logHydration(valueInML: 300, loggedAt: loggedAt)
        let crashing = CrashAfterAcceptDeliverer(fileURL: fileURL)
        _ = await outbox.drain(using: crashing)
        let captured = await crashing.snapshot
        try restore(try XCTUnwrap(captured), to: fileURL)

        let restarted = HydrationOutbox(store: HydrationOutboxStore(fileURL: fileURL))
        let garmin = RecordingHydrationDeliverer()
        _ = await restarted.drain(using: garmin)

        let sends = await garmin.adds
        XCTAssertEqual(sends, 0, "Garmin keeps only a day total: a re-send could count it twice")
        let after = await restarted.allEntries()
        XCTAssertEqual(after.map(\.state), [.failed], "left for the user to check, in the sync queue")
        XCTAssertEqual(after.first?.lastError, PossiblyDelivered.note)
    }

    func testAFoodEntryAcceptedButNotRecordedGoesToReconciliationNotBackToGarmin() async throws {
        let fileURL = try tempDir().appendingPathComponent("outbox.json")
        let outbox = Outbox(store: OutboxStore(fileURL: fileURL))
        try await outbox.logFood(date: "2026-09-30", mealType: .breakfast, foodId: "synthetic-3", servingId: "s-3", numberOfUnits: 1)
        let crashing = CrashAfterAcceptDeliverer(fileURL: fileURL)
        _ = await outbox.drain(using: crashing)
        let captured = await crashing.snapshot
        try restore(try XCTUnwrap(captured), to: fileURL)

        let restarted = Outbox(store: OutboxStore(fileURL: fileURL))
        let garmin = RecordingFoodDeliverer()
        let result = await restarted.drain(using: garmin)

        let sends = await garmin.creates
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(result.delivered.count, 1, "handed to Reconciliation, which re-reads the day")
        let states = await restarted.allEntries().map(\.state)
        XCTAssertEqual(states, [.sent])
    }

    func testASendThatCantBeRecordedFirstIsNotMade() async throws {
        let fileURL = try tempDir().appendingPathComponent("water.json")
        let outbox = HydrationOutbox(store: HydrationOutboxStore(fileURL: fileURL))
        try await outbox.logHydration(valueInML: 300, loggedAt: loggedAt)
        // The store can no longer write (its directory is now a file).
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: dir)
        try Data("blocked".utf8).write(to: dir)

        let garmin = RecordingHydrationDeliverer()
        _ = await outbox.drain(using: garmin)

        let sends = await garmin.adds
        XCTAssertEqual(sends, 0, "no request goes out without its marker on disk")
    }
}

// MARK: - Deliverers (synthetic, no network)

private func ok() -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.invalid/")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
}

private actor RecordingFoodDeliverer: FoodLogDelivering {
    private(set) var creates = 0
    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse {
        creates += 1
        return ok()
    }
    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse { ok() }
}

private actor RecordingWeighInDeliverer: WeighInDelivering {
    private let samples: [GarminWeighIn]
    private(set) var adds = 0
    init(samples: [GarminWeighIn]) { self.samples = samples }
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse {
        adds += 1
        return ok()
    }
    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse { ok() }
    func weighInSamples(on date: String) async throws -> [GarminWeighIn] { samples }
}

private actor RecordingHydrationDeliverer: HydrationDelivering {
    private(set) var adds = 0
    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse {
        adds += 1
        return ok()
    }
}

/// Accepts every request (2xx), but first captures the outbox file as it is
/// on disk at that instant -- the send marker saved, the outcome not yet --
/// and then makes every later write fail, like a process that dies (or a
/// disk that fills) right after Garmin answered.
private actor CrashAfterAcceptDeliverer: FoodLogDelivering, WeighInDelivering, HydrationDelivering {
    private let fileURL: URL
    private(set) var snapshot: Data?

    init(fileURL: URL) { self.fileURL = fileURL }

    private func acceptAndCrash() throws -> HTTPURLResponse {
        if snapshot == nil {
            snapshot = try Data(contentsOf: fileURL)
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.removeItem(at: dir)
            try Data("crashed".utf8).write(to: dir)
        }
        return ok()
    }

    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse { try acceptAndCrash() }
    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse { ok() }
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse { try acceptAndCrash() }
    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse { ok() }
    func weighInSamples(on date: String) async throws -> [GarminWeighIn] { [] }
    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse { try acceptAndCrash() }
}

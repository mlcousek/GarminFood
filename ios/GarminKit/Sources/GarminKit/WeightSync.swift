// WeightSync.swift
//
// The weight equivalent of Outbox.swift's durable per-process delivery
// queue -- same reliability shape (durable local commit first, bounded
// retry with capped exponential backoff, a 429 stops the whole drain cycle
// entirely, an auth failure stops the cycle WITHOUT burning a retry
// attempt), but its own actor and its own file, because a weigh-in's wire
// shape has nothing in common with `OutboxEntry`'s food-log fields
// (mealType/foodId/servingId/numberOfUnits vs a single weightKg+timestamp)
// -- see GarminModels.swift's weight section and GarminClient.addWeighIn.
//
// Deliberately REUSES `Outbox.backoffDelay` (same module, package-internal
// visibility) rather than duplicating that pure function -- it's the one
// piece of `Outbox` that has nothing food-specific about it. Everything
// else here is a parallel actor, not a shared one: `Outbox`'s own
// `OutboxEntry`/`DrainResult` types are hard-wired to
// `CreateFoodLogEntryRequest` and can't represent a weigh-in without
// changing food logging's own on-disk format for every existing user.
//
// One instance per process, same as `Outbox` -- see `AppServices.swift`.
// `OutboxEntryState`/`DrainAuthOutcome` (Outbox.swift) are reused as-is:
// pending/sent/failed and none/longLivedTokenExpired/notSignedIn mean
// exactly the same thing here as they do for a food-log entry.
//
// sync-weight-hydration-with-garmin (2026-09-23) adds a second OPERATION to
// the same queue: deleting a Garmin weigh-in by its `samplePk` (design.md
// D3). A delete goes through this durable queue for the same reasons an
// add does -- the UI hides the sample at once and never waits on the
// network, the delete survives being offline, and a failure is retried
// with backoff and then surfaced (WeightView row + SyncQueueView) instead
// of being lost. Every new field on `WeightOutboxEntry` is OPTIONAL, so an
// outbox file written by an older build (adds only, no `operation`) still
// decodes: a missing `operation` means `.add`.
//
// 2026-09-23 review fixes:
// - DELETE BY MATCH. A weigh-in that reached Garmin but is still shown as
//   the app's own row (Garmin not re-read since, so its `samplePk` is
//   unknown -- the add route returns none) used to be deleted locally only:
//   it stayed in Garmin and reappeared on the next read. Deleting it now
//   queues a `.delete` WITHOUT a `samplePk`; the drain resolves it from the
//   live-confirmed dayview read (`weighInSamples(on:)`) with design.md D1's
//   same-weigh-in rule (`WeighInMatching`: |dt| <= 2 min, |dw| <= 0.05 kg),
//   stores the resolved `samplePk` BEFORE sending the DELETE (so a retry
//   after a lost response 404s instead of matching a second sample), and
//   retries -- then surfaces as `.failed` -- when no sample matches yet. An
//   older build decodes such an entry and marks it failed as malformed
//   rather than quarantining the whole file.
// - IN-FLIGHT CLAIM, same as HydrationSync.swift/the food `OutboxStore`:
//   deleting a weigh-in whose add is being POSTed right now flags it
//   (`removalRequested`); if Garmin accepts the add, `settle` queues a
//   delete-by-match for it in the same write, and the same drain sends it.
//   A queued DELETE that is in flight can't be cancelled ("Keep in Garmin")
//   -- that is refused with `OutboxEditError.entryInFlight`.

import Foundation

/// The subset of `GarminClient` this outbox needs to deliver a weigh-in.
/// Mirrors `FoodLogDelivering`'s reason for existing: lets `WeightOutbox.
/// drain(using:)` be unit-tested with a fake that never touches the network
/// -- see GarminKitTests/WeightSyncTests.swift.
public protocol WeighInDelivering: Sendable {
    @discardableResult
    func addWeighIn(_ request: AddWeighInRequest) async throws -> HTTPURLResponse

    /// `DELETE /weight-service/weight/{date}/byversion/{samplePk}` --
    /// live-confirmed 2026-09-23 (see `GarminClient.deleteWeighIn`).
    @discardableResult
    func deleteWeighIn(date: String, samplePk: Int) async throws -> HTTPURLResponse

    /// `GET /weight-service/weight/dayview/{date}?includeAll=true`'s
    /// samples -- live-probed read-only 2026-09-23 (`GarminClient.
    /// weighIns(on:)`). Only used to resolve a delete-by-match's `samplePk`.
    func weighInSamples(on date: String) async throws -> [GarminWeighIn]
}

/// design.md D1's "same weigh-in" rule, shared by this outbox's
/// delete-by-match and FoodLogCore's `WeightHistoryMerge`, so the sample a
/// delete resolves to is exactly the one the merged history showed as that
/// weigh-in.
public enum WeighInMatching {
    public static let timeTolerance: TimeInterval = 120
    public static let weightToleranceKg: Double = 0.05

    public static func isSame(weightKg: Double, at date: Date, as sample: GarminWeighIn) -> Bool {
        abs(date.timeIntervalSince(sample.timestamp)) <= timeTolerance
            && abs(weightKg - sample.weightKg) <= weightToleranceKg + 1e-9
    }

    /// The matching sample closest in time, skipping `excluded` samplePks.
    public static func closest(weightKg: Double, at date: Date, in samples: [GarminWeighIn], excluding excluded: Set<Int> = []) -> GarminWeighIn? {
        samples
            .filter { !excluded.contains($0.samplePk) && isSame(weightKg: weightKg, at: date, as: $0) }
            .min { abs(date.timeIntervalSince($0.timestamp)) < abs(date.timeIntervalSince($1.timestamp)) }
    }
}

/// What a `WeightOutboxEntry` asks Garmin to do.
public enum WeightOutboxOperation: String, Codable, Sendable, Equatable {
    /// POST a new weigh-in (`addWeighIn`) -- the only operation before
    /// 2026-09-23, and what a missing `operation` field decodes as.
    case add
    /// DELETE an existing Garmin sample by `samplePk` (`deleteWeighIn`).
    case delete
}

/// One queued weigh-in plus its own delivery bookkeeping -- same shape as
/// `OutboxEntry`, just carrying a weight instead of a food.
public struct WeightOutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// For `.add`: the weight to send. For `.delete`: the deleted sample's
    /// weight, kept purely so the sync queue can say what is being deleted.
    public let weightKg: Double
    /// What the user says the weigh-in time was -- sent to Garmin as BOTH
    /// `dateTimestamp` and (converted) `gmtTimestamp`. May be backdated (the
    /// Add Weight screen allows picking a past date/time for a missed
    /// entry) -- unlike `OutboxEntry.createdAt`, which is always the real
    /// moment of the confirm tap and doubles as the queue's own
    /// eligible-for-delivery anchor, this value is NOT used for that:
    /// `nextAttemptAt` below defaults independently to the real enqueue
    /// moment, so a backdated weigh-in still attempts delivery immediately
    /// rather than waiting on its own (already-past, but conceptually
    /// unrelated) `loggedAt`.
    public let loggedAt: Date

    public var state: OutboxEntryState
    public var attemptCount: Int
    public var lastError: String?
    /// Not attempted again before this time -- same backoff/Retry-After
    /// representation `OutboxEntry` uses.
    public var nextAttemptAt: Date

    /// `nil` in files written before 2026-09-23 -- read `kind` instead,
    /// which maps `nil` to `.add`.
    public let operation: WeightOutboxOperation?
    /// `.delete` only: the Garmin sample to delete. `nil` for `.add`, and
    /// for a delete-by-match until the drain resolves it (see this file's
    /// header) -- then `weightKg`/`loggedAt` are what it is matched on.
    public var samplePk: Int?
    /// `.delete` only: the sample's own Garmin `calendarDate`
    /// (`yyyy-MM-dd`), the `{date}` segment of the delete route.
    public let calendarDate: String?
    /// When Garmin accepted this entry (set by `drain` alongside `.sent`).
    /// `nil` for anything not yet delivered AND for entries delivered by a
    /// build older than 2026-09-23. FoodLogCore's merge logic compares it
    /// with when Garmin's data was last fetched, to tell "delivered after
    /// the last read, so the read can't contain it yet" from "delivered
    /// before the last read, so the read is authoritative".
    public var deliveredAt: Date?
    /// `.add` only: `true` once the user deleted this weigh-in while a drain
    /// was sending it (`WeightOutbox.cancelQueued` ->
    /// `.compensateAfterDelivery`). That drain drops it, or -- if Garmin
    /// accepted it -- queues a delete-by-match for it. Optional so older
    /// outbox files still decode.
    public var removalRequested: Bool?

    public init(
        id: UUID = UUID(),
        weightKg: Double,
        loggedAt: Date = Date(),
        state: OutboxEntryState = .pending,
        attemptCount: Int = 0,
        lastError: String? = nil,
        nextAttemptAt: Date = Date(),
        operation: WeightOutboxOperation? = nil,
        samplePk: Int? = nil,
        calendarDate: String? = nil,
        deliveredAt: Date? = nil,
        removalRequested: Bool? = nil
    ) {
        self.id = id
        self.weightKg = weightKg
        self.loggedAt = loggedAt
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.nextAttemptAt = nextAttemptAt
        self.operation = operation
        self.samplePk = samplePk
        self.calendarDate = calendarDate
        self.deliveredAt = deliveredAt
        self.removalRequested = removalRequested
    }

    /// The operation, with a pre-2026-09-23 `nil` read as `.add`.
    public var kind: WeightOutboxOperation { operation ?? .add }

    /// A `.delete` whose `samplePk` is not known yet -- resolved by the
    /// drain from Garmin's day view (see this file's header).
    public var isDeleteByMatch: Bool { kind == .delete && samplePk == nil }

    var addRequest: AddWeighInRequest {
        AddWeighInRequest(weightKg: weightKg, loggedAt: loggedAt)
    }
}

/// Thrown (and recorded as the entry's `lastError`) when a `.delete` entry
/// is missing the `calendarDate` it needs -- only possible from a
/// hand-edited file, since `logDelete`/`logDeleteMatching` always set it.
struct WeightOutboxMalformedEntry: Error, CustomStringConvertible {
    var description: String { "delete entry is missing its calendarDate" }
}

/// A delete-by-match found no Garmin sample matching the weigh-in (yet --
/// Garmin may not list a just-accepted add immediately). Retried with the
/// normal backoff, then surfaced as `.failed` in the sync queue.
struct WeighInToDeleteNotFound: Error, CustomStringConvertible {
    let weightKg: Double
    let loggedAt: Date
    let calendarDate: String

    var description: String {
        "couldn't find the \(weightKg) kg weigh-in at \(loggedAt) in Garmin's \(calendarDate) weigh-ins to delete it"
    }
}

// MARK: - Persistence

/// JSON-file-backed store, one file per process -- same rationale as
/// `OutboxStore` (Outbox.swift): trivially inspectable by hand (no
/// interactive debugger for this project), and deliberately NOT in an App
/// Group container, since there isn't one.
actor WeightOutboxStore {
    private let fileURL: URL
    private var entries: [WeightOutboxEntry] = []
    private var loaded = false
    /// Entries a drain is sending right now -- see `HydrationOutboxStore.
    /// claimedIds` / the food `OutboxStore`'s.
    private var claimedIds: Set<UUID> = []

    init(fileURL: URL = WeightOutboxStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(processName: String = "default") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GarminKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("weight-outbox-\(processName).json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = PersistedJSON.load([WeightOutboxEntry].self, from: fileURL, decoder: decoder, category: "WeightOutboxStore")
        entries = result.value ?? []
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
    }

    private func persist() throws {
        try write(entries)
    }

    private func write(_ list: [WeightOutboxEntry]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "WeightOutboxStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(list)
        try data.write(to: fileURL, options: .atomic)
        // Matches `OutboxStore.persist()`: readable before first unlock in a
        // session (a background drain), still encrypted at rest once the
        // device is off/rebooted.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    func all() -> [WeightOutboxEntry] {
        loadIfNeeded()
        return entries
    }

    func pending(now: Date) -> [WeightOutboxEntry] {
        loadIfNeeded()
        return entries.filter { $0.state == .pending && $0.nextAttemptAt <= now }
    }

    @discardableResult
    func enqueue(_ entry: WeightOutboxEntry) throws -> WeightOutboxEntry {
        loadIfNeeded()
        entries.append(entry)
        try persist()
        return entry
    }

    func update(_ entry: WeightOutboxEntry) throws {
        loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        try persist()
    }

    func remove(id: UUID) throws {
        loadIfNeeded()
        entries.removeAll { $0.id == id }
        try persist()
    }

    /// Marks `id` in flight and returns its CURRENT value, or `nil` if it
    /// is gone, already claimed, or no longer due.
    func claim(id: UUID, now: Date) -> WeightOutboxEntry? {
        loadIfNeeded()
        guard !claimedIds.contains(id),
              let entry = entries.first(where: { $0.id == id }),
              entry.state == .pending,
              entry.nextAttemptAt <= now
        else { return nil }
        claimedIds.insert(id)
        return entry
    }

    /// Writes back a claimed entry after one delivery attempt and releases
    /// the claim -- `HydrationOutboxStore.settle`'s twin. A flagged add
    /// Garmin did NOT accept is dropped; one Garmin DID accept is stored as
    /// `.sent` with a delete-by-match for it appended in the same write, due
    /// at once so the same drain sends it.
    func settle(_ attempted: WeightOutboxEntry, accepted: Bool) -> WeightSettlement {
        loadIfNeeded()
        claimedIds.remove(attempted.id)
        guard let index = entries.firstIndex(where: { $0.id == attempted.id }) else { return .gone }
        let settlement: WeightSettlement
        if entries[index].removalRequested == true {
            if accepted {
                var sent = attempted
                sent.removalRequested = true
                entries[index] = sent
                if attempted.kind == .add {
                    entries.append(WeightOutboxEntry(
                        weightKg: attempted.weightKg,
                        loggedAt: attempted.loggedAt,
                        nextAttemptAt: attempted.nextAttemptAt,
                        operation: .delete,
                        samplePk: nil,
                        calendarDate: WeightOutbox.localCalendarDate(of: attempted.loggedAt)
                    ))
                    settlement = .deleteQueued
                } else {
                    settlement = .written
                }
            } else {
                entries.remove(at: index)
                settlement = .dropped
            }
        } else {
            entries[index] = attempted
            settlement = .written
        }
        do {
            try persist()
        } catch {
            DiagnosticsLog.log(.error, category: "WeightOutboxStore", "couldn't persist a delivery result: \(error)")
        }
        return settlement
    }

    /// Removes a not-yet-delivered entry. If a drain is sending it right
    /// now, an ADD is flagged instead (see `settle`), while a DELETE is
    /// refused with `OutboxEditError.entryInFlight` -- a sample can't be
    /// un-deleted. `.alreadyDelivered` for a `.sent` entry, `.entryNotFound`
    /// for an unknown id; nothing changes when it throws.
    func cancel(id: UUID) throws -> OutboxCancellation {
        loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw OutboxEditError.entryNotFound }
        guard entries[index].state != .sent else { throw OutboxEditError.alreadyDelivered }
        var updated = entries
        let result: OutboxCancellation
        if claimedIds.contains(id) {
            guard entries[index].kind == .add else { throw OutboxEditError.entryInFlight }
            updated[index].removalRequested = true
            result = .compensateAfterDelivery
        } else {
            updated.remove(at: index)
            result = .removed
        }
        try write(updated)
        entries = updated
        return result
    }
}

/// How `WeightOutboxStore.settle` resolved one delivery attempt.
enum WeightSettlement: Sendable, Equatable {
    case written
    case dropped
    case deleteQueued
    /// The entry vanished while claimed (only an unconditional `delete`).
    case gone
}

// MARK: - Drain

public struct WeightDrainResult: Sendable, Equatable {
    public let delivered: [WeightOutboxEntry]
    public let failed: [WeightOutboxEntry]
    public let stoppedDueToRateLimit: Bool
    public let authOutcome: DrainAuthOutcome
}

/// Drains one process's own weight outbox. An actor for the same reentrancy
/// reason as `Outbox`: two overlapping `drain()` calls (a foreground drain
/// racing a background-refresh drain) must not both attempt the same
/// pending entry before either writes its new state back.
public actor WeightOutbox {
    private let store: WeightOutboxStore
    public let maxAttempts: Int
    private let backoffBase: TimeInterval
    private let backoffCap: TimeInterval
    private var isDraining = false

    /// The initializer every real caller (currently just the app; a widget
    /// extension has no reason to log weight) uses. `processName` becomes
    /// part of this process's own outbox file name, mirroring `Outbox.init`.
    public init(
        processName: String = "default",
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8
    ) {
        self.store = WeightOutboxStore(fileURL: WeightOutboxStore.defaultFileURL(processName: processName))
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
    }

    /// Test-only entry point, mirroring `Outbox`'s internal `(store:)`
    /// initializer -- lets GarminKitTests point this at an isolated temp
    /// file instead of this process's real Application Support directory.
    init(
        store: WeightOutboxStore,
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8
    ) {
        self.store = store
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
    }

    /// Enqueues a new entry. Like `Outbox.logFood`, a successful return here
    /// is durable and makes no network call -- callers may treat it as safe
    /// to show in the UI immediately.
    @discardableResult
    public func logWeight(weightKg: Double, loggedAt: Date = Date()) async throws -> WeightOutboxEntry {
        let entry = WeightOutboxEntry(weightKg: weightKg, loggedAt: loggedAt, operation: .add)
        return try await store.enqueue(entry)
    }

    /// Enqueues deleting Garmin sample `samplePk` (dated `calendarDate`,
    /// both straight from a `GarminWeighIn`). Same contract as `logWeight`:
    /// a successful return is durable and made no network call. `weightKg`/
    /// `loggedAt` describe the sample being deleted, for display only.
    @discardableResult
    public func logDelete(samplePk: Int, calendarDate: String, weightKg: Double, loggedAt: Date) async throws -> WeightOutboxEntry {
        let entry = WeightOutboxEntry(
            weightKg: weightKg,
            loggedAt: loggedAt,
            operation: .delete,
            samplePk: samplePk,
            calendarDate: calendarDate
        )
        return try await store.enqueue(entry)
    }

    /// Enqueues deleting the Garmin copy of a weigh-in whose `samplePk` is
    /// not known (delivered, but Garmin not re-read since). The drain
    /// resolves it from Garmin's `calendarDate` day view by `weightKg` +
    /// `loggedAt` (`WeighInMatching`). Durable on return, no network call.
    @discardableResult
    public func logDeleteMatching(weightKg: Double, loggedAt: Date, calendarDate: String) async throws -> WeightOutboxEntry {
        let entry = WeightOutboxEntry(
            weightKg: weightKg,
            loggedAt: loggedAt,
            operation: .delete,
            samplePk: nil,
            calendarDate: calendarDate
        )
        return try await store.enqueue(entry)
    }

    /// Removes an entry Garmin has not accepted yet -- or, for an add a
    /// drain is sending right now, flags it so that drain drops it or
    /// deletes it again from Garmin (`OutboxCancellation`). Local only.
    /// Throws `OutboxEditError.alreadyDelivered`, `.entryNotFound`, or
    /// `.entryInFlight` (a DELETE being sent right now); nothing changes
    /// when it throws.
    @discardableResult
    public func cancelQueued(id: UUID) async throws -> OutboxCancellation {
        try await store.cancel(id: id)
    }

    /// `yyyy-MM-dd` of `date` in the device's time zone -- the day a weigh-in
    /// logged here lands on in Garmin (same as FoodLogCore's `NutritionDate`).
    static func localCalendarDate(of date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public func allEntries() async -> [WeightOutboxEntry] {
        await store.all()
    }

    public func pendingCount(now: Date = Date()) async -> Int {
        await store.pending(now: now).count
    }

    /// User-initiated retry of a `.failed` entry.
    public func retry(id: UUID) async throws {
        guard var entry = await store.all().first(where: { $0.id == id }) else { return }
        entry.state = .pending
        entry.attemptCount = 0
        entry.lastError = nil
        entry.nextAttemptAt = Date()
        try await store.update(entry)
    }

    public func delete(id: UUID) async throws {
        try await store.remove(id: id)
    }

    /// Attempts delivery of every currently-due pending entry once. Retry/
    /// rate-limit/auth-failure behaviour is identical to `Outbox.drain` --
    /// see that method's doc comment for the full rationale; it isn't
    /// repeated here since it's exactly the same policy, just applied to a
    /// weigh-in instead of a food log entry.
    @discardableResult
    public func drain(
        using deliverer: some WeighInDelivering,
        now: Date = Date(),
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) },
        clock: @Sendable () -> Date = { Date() }
    ) async -> WeightDrainResult {
        guard !isDraining else {
            return WeightDrainResult(delivered: [], failed: [], stoppedDueToRateLimit: false, authOutcome: .none)
        }
        isDraining = true
        defer { isDraining = false }

        var delivered: [WeightOutboxEntry] = []
        var failed: [WeightOutboxEntry] = []
        var stoppedDueToRateLimit = false
        var authOutcome: DrainAuthOutcome = .none
        // Re-read every step, each entry attempted at most once -- same as
        // `HydrationOutbox.drain`, so a delete `settle` queues for an add
        // deleted mid-flight goes out in this same drain.
        var attempted = Set<UUID>()

        while true {
            guard let next = await store.pending(now: now).first(where: { !attempted.contains($0.id) }) else { break }
            attempted.insert(next.id)
            guard var entry = await store.claim(id: next.id, now: now) else { continue }

            var accepted = false
            var stop = false
            do {
                switch entry.kind {
                case .add:
                    try await deliverer.addWeighIn(entry.addRequest)
                case .delete:
                    guard let calendarDate = entry.calendarDate else {
                        throw WeightOutboxMalformedEntry()
                    }
                    let samplePk: Int
                    if let known = entry.samplePk {
                        samplePk = known
                    } else {
                        // Delete-by-match: resolve against Garmin's own
                        // list for that day. Stored on `entry` (written back
                        // by `settle` whatever happens next), so a retry
                        // after a lost DELETE response re-sends THIS
                        // samplePk (404 -> done) instead of matching again.
                        let samples = try await deliverer.weighInSamples(on: calendarDate)
                        // Never a sample another delete already targets
                        // (Garmin may still list one it just deleted).
                        let entryId = entry.id
                        let queued = await store.all()
                        let targeted = Set(queued.compactMap { other -> Int? in
                            other.id != entryId && other.kind == .delete ? other.samplePk : nil
                        })
                        guard let match = WeighInMatching.closest(weightKg: entry.weightKg, at: entry.loggedAt, in: samples, excluding: targeted) else {
                            throw WeighInToDeleteNotFound(weightKg: entry.weightKg, loggedAt: entry.loggedAt, calendarDate: calendarDate)
                        }
                        samplePk = match.samplePk
                        entry.samplePk = match.samplePk
                    }
                    do {
                        try await deliverer.deleteWeighIn(date: calendarDate, samplePk: samplePk)
                    } catch GarminClientError.httpError(let statusCode, _) where statusCode == 404 {
                        // The sample is already gone (e.g. deleted in Garmin
                        // Connect meanwhile) -- the delete's goal is met, so
                        // this counts as delivered rather than burning
                        // retries on something that can never succeed. The
                        // route's 404 behaviour itself is NOT confirmed (the
                        // 2026-09-23 probe only saw 204); logged so a real
                        // occurrence is visible.
                        DiagnosticsLog.log(.info, category: "WeightOutbox", "delete of sample \(samplePk) on \(calendarDate) returned 404 -- treating as already deleted")
                    }
                }
                accepted = true
                entry.state = .sent
                entry.lastError = nil
                // When Garmin ACCEPTED it, not when this drain started:
                // FoodLogCore compares it with when Garmin was last read
                // (see `deliveredAt`), and a read that started mid-drain
                // must not be taken to include an entry accepted after it.
                entry.deliveredAt = clock()
            } catch GarminClientError.rateLimited(let retryAfterSeconds) {
                entry.attemptCount += 1
                entry.lastError = "rate limited (429)"
                entry.nextAttemptAt = now.addingTimeInterval(
                    retryAfterSeconds ?? Outbox.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                )
                stoppedDueToRateLimit = true
                stop = true
            } catch GarminAuthError.longLivedTokenExpired {
                entry.lastError = "auth: long-lived token expired"
                authOutcome = .longLivedTokenExpired
                stop = true
            } catch GarminAuthError.notSignedIn {
                entry.lastError = "auth: not signed in"
                authOutcome = .notSignedIn
                stop = true
            } catch {
                entry.attemptCount += 1
                entry.lastError = String(String(describing: error).prefix(300))
                if entry.attemptCount >= maxAttempts {
                    entry.state = .failed
                } else {
                    entry.nextAttemptAt = now.addingTimeInterval(
                        Outbox.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                    )
                }
            }

            switch await store.settle(entry, accepted: accepted) {
            case .written, .gone:
                if accepted {
                    delivered.append(entry)
                } else if entry.state == .failed {
                    failed.append(entry)
                }
            case .deleteQueued:
                delivered.append(entry)
            case .dropped:
                // Deleted by the user mid-flight and never accepted.
                break
            }
            if stop { break }
        }

        if !delivered.isEmpty || !failed.isEmpty || authOutcome != .none {
            DiagnosticsLog.log(
                delivered.isEmpty && !failed.isEmpty ? .warning : .info,
                category: "WeightOutbox",
                "drain: \(delivered.count) delivered, \(failed.count) gave up, rateLimited=\(stoppedDueToRateLimit), authOutcome=\(authOutcome)"
            )
        }
        return WeightDrainResult(delivered: delivered, failed: failed, stoppedDueToRateLimit: stoppedDueToRateLimit, authOutcome: authOutcome)
    }
}

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
    /// `.delete` only: the Garmin sample to delete. `nil` for `.add`.
    public let samplePk: Int?
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
        deliveredAt: Date? = nil
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
    }

    /// The operation, with a pre-2026-09-23 `nil` read as `.add`.
    public var kind: WeightOutboxOperation { operation ?? .add }

    var addRequest: AddWeighInRequest {
        AddWeighInRequest(weightKg: weightKg, loggedAt: loggedAt)
    }
}

/// Thrown (and recorded as the entry's `lastError`) when a `.delete` entry
/// is missing the `samplePk`/`calendarDate` it needs -- only possible from a
/// hand-edited file, since `logDelete` always sets both.
struct WeightOutboxMalformedEntry: Error, CustomStringConvertible {
    var description: String { "delete entry is missing samplePk/calendarDate" }
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
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "WeightOutboxStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
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
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) }
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

        for var entry in await store.pending(now: now) {
            do {
                switch entry.kind {
                case .add:
                    try await deliverer.addWeighIn(entry.addRequest)
                case .delete:
                    guard let samplePk = entry.samplePk, let calendarDate = entry.calendarDate else {
                        throw WeightOutboxMalformedEntry()
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
                entry.state = .sent
                entry.lastError = nil
                entry.deliveredAt = now
                try? await store.update(entry)
                delivered.append(entry)
            } catch GarminClientError.rateLimited(let retryAfterSeconds) {
                entry.attemptCount += 1
                entry.lastError = "rate limited (429)"
                entry.nextAttemptAt = now.addingTimeInterval(
                    retryAfterSeconds ?? Outbox.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                )
                try? await store.update(entry)
                stoppedDueToRateLimit = true
                break
            } catch GarminAuthError.longLivedTokenExpired {
                entry.lastError = "auth: long-lived token expired"
                try? await store.update(entry)
                authOutcome = .longLivedTokenExpired
                break
            } catch GarminAuthError.notSignedIn {
                entry.lastError = "auth: not signed in"
                try? await store.update(entry)
                authOutcome = .notSignedIn
                break
            } catch {
                entry.attemptCount += 1
                entry.lastError = String(String(describing: error).prefix(300))
                if entry.attemptCount >= maxAttempts {
                    entry.state = .failed
                    try? await store.update(entry)
                    failed.append(entry)
                } else {
                    entry.nextAttemptAt = now.addingTimeInterval(
                        Outbox.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                    )
                    try? await store.update(entry)
                }
            }
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

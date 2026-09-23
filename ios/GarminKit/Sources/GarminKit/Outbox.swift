// Outbox.swift
//
// The per-process durable outbox (design.md D5, tasks 9.1-9.6). Each
// process that can log food -- the app, a widget extension, a future
// Control -- instantiates its OWN `Outbox` backed by its OWN JSON file in
// its OWN sandboxed container. There is deliberately no attempt to share
// this across processes (no App Group exists to share it through anyway,
// per design.md D3's confirmed negative result) -- reconciliation
// (Reconciliation.swift) checks against Garmin, never against a sibling
// process's local state, which is what makes per-process queues safe
// rather than a source of split-brain bugs.
//
// A client-generated UUID is the idempotency key: Garmin's private API has
// no idempotency key of its own (design.md D5), so de-duplication is this
// package's problem, resolved after the fact by Reconciliation, not
// prevented up front.

import Foundation

/// The subset of `GarminClient` the outbox needs to deliver an entry.
/// Exists so `Outbox.drain(using:)` can be unit-tested with a fake that
/// never touches the network -- see GarminKitTests/OutboxTests.swift.
public protocol FoodLogDelivering: Sendable {
    @discardableResult
    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse
}

public enum OutboxEntryState: String, Codable, Sendable, Equatable {
    case pending
    case sent
    case failed
}

/// One queued food-log entry plus its own delivery bookkeeping. Per
/// design.md D5, the entry IS the outbox record -- this package has no UI
/// layer of its own, so there's no separate "food entry" model to keep in
/// lockstep; the app layer (a later phase) treats a successful `Outbox.logFood`
/// call as "durable, safe to show in the UI immediately" per the
/// garmin-sync spec's durability requirement.
public struct OutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// `YYYY-MM-DD`, local nutrition-day date -- NOT necessarily calendar
    /// midnight-to-midnight, per docs/garmin-food-log-contract.md's
    /// dayStartTime/dayEndTime finding. Callers are responsible for
    /// resolving "today" against Garmin's own day window before enqueuing.
    public let date: String
    public let mealType: MealType
    public let foodId: String
    public let servingId: String
    public let numberOfUnits: Double
    /// Optional, and must stay so: entries queued by a build that predates
    /// this field are already sitting in users' outbox files, and a
    /// synthesized `Decodable` only tolerates a missing key for an Optional.
    /// `nil` falls back to inferring the namespace from `foodId`'s shape.
    public let source: GarminFoodSource?
    /// The account's real region/language at the moment this entry was
    /// enqueued, captured then rather than re-read at delivery time so a
    /// custom food logs under the same region/language it was actually
    /// created under even if the cached account settings change later
    /// (fix-custom-food-log-region, 2026-09-22). `nil` (entries queued by
    /// an older build, or when the account settings hadn't loaded yet)
    /// falls back to `FoodLogWriteBody`'s hardcoded `"US"`/`"en"`.
    public let regionCode: String?
    public let languageCode: String?

    public var state: OutboxEntryState
    public var attemptCount: Int
    public var lastError: String?
    public let createdAt: Date
    /// Not attempted again before this time -- how backoff/Retry-After are
    /// represented, rather than an in-process sleep (see `Outbox.drain`).
    public var nextAttemptAt: Date

    public init(
        id: UUID = UUID(),
        date: String,
        mealType: MealType,
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        source: GarminFoodSource? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil,
        state: OutboxEntryState = .pending,
        attemptCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        nextAttemptAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
        self.source = source
        self.regionCode = regionCode
        self.languageCode = languageCode
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
    }

    var createRequest: CreateFoodLogEntryRequest {
        CreateFoodLogEntryRequest(
            date: date,
            mealType: mealType,
            foodId: foodId,
            servingId: servingId,
            numberOfUnits: numberOfUnits,
            source: source,
            loggedAt: createdAt,
            regionCode: regionCode,
            languageCode: languageCode
        )
    }
}

// MARK: - Persistence

/// JSON-file-backed store, one file per process (task 9.1: "`UserDefaults`
/// or a JSON file" -- JSON file chosen here so the whole outbox is trivially
/// inspectable/debuggable by hand, which matters a lot given there is no
/// debugger available for this project per design.md D9).
///
/// Deliberately NOT in an App Group container -- there isn't one (D3) --
/// just this process's own Application Support directory, which every
/// process (app or extension) gets its own private copy of automatically,
/// which is exactly the isolation design.md D3 calls for.
actor OutboxStore {
    private let fileURL: URL
    private var entries: [OutboxEntry] = []
    private var loaded = false

    init(fileURL: URL = OutboxStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// `processName` lets a single process host more than one logical
    /// outbox if it ever needs to (not currently exercised), and makes the
    /// file's purpose obvious if someone inspects the container by hand.
    static func defaultFileURL(processName: String = "default") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GarminKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("outbox-\(processName).json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        entries = PersistedJSON.load([OutboxEntry].self, from: fileURL, decoder: JSONDecoder(), category: "OutboxStore") ?? []
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
        // design.md D3's consequence for the desktop-widget requirement:
        // `.completeUntilFirstUserAuthentication` (not `.complete`) so a
        // background drain can still read/write this file before the user
        // has unlocked their phone in the current session, while the file
        // is still encrypted at rest once the device is off/rebooted.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    func all() -> [OutboxEntry] {
        loadIfNeeded()
        return entries
    }

    func pending(now: Date) -> [OutboxEntry] {
        loadIfNeeded()
        return entries.filter { $0.state == .pending && $0.nextAttemptAt <= now }
    }

    func pendingCount(now: Date) -> Int {
        pending(now: now).count
    }

    @discardableResult
    func enqueue(_ entry: OutboxEntry) throws -> OutboxEntry {
        loadIfNeeded()
        entries.append(entry)
        try persist()
        return entry
    }

    func update(_ entry: OutboxEntry) throws {
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

public struct DrainResult: Sendable, Equatable {
    public let delivered: [OutboxEntry]
    public let failed: [OutboxEntry]
    public let stoppedDueToRateLimit: Bool
    public let authOutcome: DrainAuthOutcome
}

/// Deliberately a plain enum (not a wrapped `Error`) so `DrainResult` stays
/// a simple, `Equatable`, `Sendable` value the app can pattern-match on
/// without worrying about `Error`'s own lack of a general `Sendable`/`Equatable`
/// conformance. The caller maps this back to `GarminAuthError` if it wants
/// to feed `GarminAuthState.report(_:)`.
public enum DrainAuthOutcome: Sendable, Equatable {
    case none
    case longLivedTokenExpired
    case notSignedIn
}

/// Drains one process's own outbox. An actor: state (the backing store) is
/// this process's alone, matching design.md D4 -- there is no cross-process
/// lock here because there is nothing cross-process to lock (D3's negative
/// result).
public actor Outbox {
    private let store: OutboxStore
    public let maxAttempts: Int
    private let backoffBase: TimeInterval
    private let backoffCap: TimeInterval
    /// Reentrancy guard (R1). An actor's own methods can still interleave
    /// across `await` suspension points -- two overlapping `drain()` calls
    /// (e.g. a foreground drain racing a `BGAppRefreshTask` drain) would
    /// otherwise both read the same `.pending` entries before either has
    /// written a `.sent`/`.failed` state back, and both would attempt
    /// delivery of the same entry. Checked and set at the very top of
    /// `drain()`, cleared unconditionally (including on early return) via
    /// `defer`.
    private var isDraining = false

    /// The initializer every real caller (app, widget extension, Control)
    /// uses. `processName` becomes part of this process's own outbox file
    /// name (`OutboxStore.defaultFileURL(processName:)`) -- each process
    /// gets its own file in its own sandboxed Application Support
    /// directory (design.md D3: no App Group, nothing shared), and a
    /// self-documenting name matters given design.md D9's "no interactive
    /// debugger" constraint if someone ever needs to inspect the container
    /// by hand.
    ///
    /// `maxAttempts: 5` matches design.md's Risks section ("cap retry
    /// attempts, mark entries failed after a bounded number") and task 9.4.
    /// `backoffCap: 8` matches task 9.3's "capped at 8s" exactly.
    public init(
        processName: String = "default",
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8
    ) {
        self.store = OutboxStore(fileURL: OutboxStore.defaultFileURL(processName: processName))
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
    }

    /// Test-only entry point so GarminKitTests can point the outbox at an
    /// isolated temp file instead of this process's real Application
    /// Support directory. Deliberately NOT `public` -- `OutboxStore` is an
    /// internal implementation detail, not part of this package's public
    /// API surface; tests reach this initializer via `@testable import`.
    init(
        store: OutboxStore,
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8
    ) {
        self.store = store
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
    }

    /// Enqueues a new entry. Per design.md D5 / the garmin-sync spec's
    /// durability requirement, a caller may treat a successful return here
    /// as "durable" and show it in the UI immediately -- no network call is
    /// made or waited on by this method.
    @discardableResult
    public func logFood(
        date: String,
        mealType: MealType,
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        source: GarminFoodSource? = nil,
        regionCode: String? = nil,
        languageCode: String? = nil,
        createdAt: Date = Date()
    ) async throws -> OutboxEntry {
        let entry = OutboxEntry(
            date: date,
            mealType: mealType,
            foodId: foodId,
            servingId: servingId,
            numberOfUnits: numberOfUnits,
            source: source,
            regionCode: regionCode,
            languageCode: languageCode,
            createdAt: createdAt,
            nextAttemptAt: createdAt
        )
        return try await store.enqueue(entry)
    }

    public func allEntries() async -> [OutboxEntry] {
        await store.all()
    }

    public func pendingCount(now: Date = Date()) async -> Int {
        await store.pendingCount(now: now)
    }

    /// User-initiated retry of a `.failed` entry (garmin-sync spec:
    /// "presented to the user for manual retry or deletion").
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

    /// Used by Reconciliation to put an entry back to `.pending` after
    /// discovering a "successful" POST didn't actually persist
    /// (garmin-sync spec's "a successful response was not actually
    /// persisted" scenario). Internal: Reconciliation is the only intended
    /// caller, and it lives in the same module.
    func requeue(_ entry: OutboxEntry) async throws {
        try await store.update(entry)
    }

    /// Reconciliation's "Garmin said 2xx, but the re-read can't find it"
    /// path. Unlike a plain `requeue`, this COUNTS the miss against
    /// `maxAttempts` and gives up once they're spent.
    ///
    /// It has to: a drain that succeeds never increments `attemptCount`, and
    /// the old re-queue reset it to 0, so an entry Garmin accepts but files
    /// somewhere the matcher doesn't look would be re-sent on every drain,
    /// forever -- one more real copy in the user's diary each time. That was
    /// harmless only while no write could succeed. Capped, the worst case is
    /// `maxAttempts` copies and an entry marked `.failed` with the reason,
    /// which the app's delivery banner then shows.
    @discardableResult
    func requeueMissingAfterDelivery(_ entry: OutboxEntry, reason: String, now: Date = Date()) async throws -> OutboxEntry {
        var updated = entry
        updated.attemptCount += 1
        updated.lastError = reason
        if updated.attemptCount >= maxAttempts {
            updated.state = .failed
        } else {
            updated.state = .pending
            updated.nextAttemptAt = now
        }
        try await store.update(updated)
        return updated
    }

    /// Attempts delivery of every currently-due pending entry once.
    ///
    /// - Honors `Retry-After` (via `GarminClientError.rateLimited`) and, per
    ///   the garmin-sync spec, stops attempting delivery ENTIRELY for the
    ///   rest of this drain cycle on the first 429 -- entries not yet
    ///   attempted this cycle are left untouched and pending.
    /// - On any other failure, backs off exponentially with jitter (capped
    ///   at `backoffCap`) before that specific entry is eligible again, and
    ///   marks it `.failed` once `maxAttempts` is reached.
    /// - On an auth failure (`GarminAuthError.notSignedIn` /
    ///   `.longLivedTokenExpired`), stops the cycle immediately WITHOUT
    ///   counting it as a delivery failure against the entry -- retrying a
    ///   dead credential burns through `maxAttempts` for no reason, and
    ///   design.md D7 / the garmin-auth spec require entries to keep
    ///   accumulating and drain once the session is restored, not to be
    ///   marked `.failed` because the user hasn't reconnected yet.
    @discardableResult
    public func drain(
        using deliverer: some FoodLogDelivering,
        now: Date = Date(),
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) async -> DrainResult {
        // R1: a drain already in flight on this actor wins; a second,
        // overlapping caller gets an immediate, harmless no-op result
        // instead of interleaving with the first and double-delivering.
        guard !isDraining else {
            return DrainResult(delivered: [], failed: [], stoppedDueToRateLimit: false, authOutcome: .none)
        }
        isDraining = true
        defer { isDraining = false }

        var delivered: [OutboxEntry] = []
        var failed: [OutboxEntry] = []
        var stoppedDueToRateLimit = false
        var authOutcome: DrainAuthOutcome = .none

        for var entry in await store.pending(now: now) {
            do {
                try await deliverer.createFoodLogEntry(entry.createRequest)
                entry.state = .sent
                entry.lastError = nil
                try? await store.update(entry)
                delivered.append(entry)
            } catch GarminClientError.rateLimited(let retryAfterSeconds) {
                entry.attemptCount += 1
                entry.lastError = "rate limited (429)"
                entry.nextAttemptAt = now.addingTimeInterval(
                    retryAfterSeconds ?? Self.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
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
                // Truncated to 300 chars, matching
                // `TokenProvider.refreshAccessToken`'s convention (R8) --
                // an untruncated error description has no bound (some
                // wrapped errors embed full response bodies) and this field
                // is rewritten into the whole-array `OutboxStore.persist()`
                // on every attempt.
                entry.lastError = String(String(describing: error).prefix(300))
                if entry.attemptCount >= maxAttempts {
                    entry.state = .failed
                    try? await store.update(entry)
                    failed.append(entry)
                } else {
                    entry.nextAttemptAt = now.addingTimeInterval(
                        Self.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                    )
                    try? await store.update(entry)
                }
            }
        }

        if !delivered.isEmpty || !failed.isEmpty || authOutcome != .none {
            DiagnosticsLog.log(
                delivered.isEmpty && !failed.isEmpty ? .warning : .info,
                category: "Outbox",
                "drain: \(delivered.count) delivered, \(failed.count) gave up, rateLimited=\(stoppedDueToRateLimit), authOutcome=\(authOutcome)"
            )
        }
        return DrainResult(delivered: delivered, failed: failed, stoppedDueToRateLimit: stoppedDueToRateLimit, authOutcome: authOutcome)
    }

    /// Exponential backoff with full jitter, capped at `cap` (task 9.3:
    /// "exponential backoff with jitter capped at 8 s"). `jitter` must be
    /// in `[0, 1)`; the caller supplies it so this stays a pure, deterministic,
    /// unit-testable function rather than depending on the global RNG.
    /// `attempt` is 1-based (the count AFTER the failing attempt).
    static func backoffDelay(attempt: Int, jitter: Double, base: TimeInterval, cap: TimeInterval) -> TimeInterval {
        let exponent = Double(max(0, attempt - 1))
        let exponential = base * pow(2.0, exponent)
        let capped = min(exponential, cap)
        let clampedJitter = min(max(jitter, 0), 1)
        return capped * clampedJitter
    }
}

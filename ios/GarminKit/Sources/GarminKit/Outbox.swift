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
//
// add-log-entry-editing (design.md D1): an entry may also carry `replaces`,
// the Garmin `logId` it supersedes. Garmin has no edit route, so an edit is
// delivered as "create the corrected entry, THEN delete the old one" --
// never the reverse, so the worst failure is a temporary, visible duplicate
// rather than a lost food. The intermediate `.createdAwaitingDelete` state is
// persisted BEFORE the delete is sent, so a crash between the two requests
// resumes at the delete and never re-sends the create. Both routes are the
// ones this app already used before editing existed (create confirmed
// 2026-09-16; delete per garmin_mcp's live e2e test, docs/garmin-routes.json)
// -- no edit/update route is invented here.
//
// Also add-log-entry-editing: an edit of an entry that is STILL QUEUED (never
// reached Garmin) is a plain local swap (`replaceQueued`/`cancelQueued`),
// guarded against a drain that is sending that very entry at the same moment
// (`OutboxStore.claim`).

import Foundation

/// The subset of `GarminClient` the outbox needs to deliver an entry.
/// Exists so `Outbox.drain(using:)` can be unit-tested with a fake that
/// never touches the network -- see GarminKitTests/OutboxTests.swift.
public protocol FoodLogDelivering: Sendable {
    @discardableResult
    func createFoodLogEntry(_ entry: CreateFoodLogEntryRequest) async throws -> HTTPURLResponse
    /// DELETE `/nutrition-service/food/logs/{date}` with `{ "logIds": [...] }`
    /// -- the second half of a replace (add-log-entry-editing D1). The same
    /// route `DayLogLoader`'s delete and Reconciliation's duplicate removal
    /// already call; returned 204 in garmin_mcp's live e2e test.
    @discardableResult
    func deleteFoodLogEntries(logIds: [String], date: String) async throws -> HTTPURLResponse
}

/// Shared by the food, weight and hydration outboxes. Only the food outbox
/// ever produces `.createdAwaitingDelete`.
///
/// Adding a case is decode-safe for every file already on a phone: those
/// files can only contain the three original raw values, all still here.
/// (The reverse is not true -- a build that predates this case can't decode
/// a file containing it, and `PersistedJSON` would quarantine that file --
/// so sideloading an older build while a replace is mid-flight is unsafe.)
public enum OutboxEntryState: String, Codable, Sendable, Equatable {
    case pending
    case sent
    case failed
    /// add-log-entry-editing D1: a replace whose corrected entry Garmin has
    /// already accepted, but whose old entry is not yet deleted. Retried
    /// with backoff; never marked `.failed` (a manual retry from `.failed`
    /// would re-send the create and duplicate the food) -- after
    /// `maxAttempts`, or on a permanent 4xx, it is parked (`parkedAt`) until
    /// the user retries it from the sync queue.
    case createdAwaitingDelete
}

/// The Garmin entry an edit supersedes (add-log-entry-editing D1). `date` is
/// the delete route's path component; `logId` the hex id from the read-back.
public struct ReplacedLog: Codable, Sendable, Equatable, Hashable {
    public let date: String
    public let logId: String

    public init(date: String, logId: String) {
        self.date = date
        self.logId = logId
    }
}

/// Why an edit to a still-queued entry (`Outbox.replaceQueued`/
/// `cancelQueued`) was refused. Every case means "nothing was changed".
public enum OutboxEditError: Error, Sendable, Equatable {
    /// No entry with that id -- already delivered and reconciled away, or
    /// deleted from the sync queue.
    case entryNotFound
    /// A drain is sending this exact entry right now. Swapping it out from
    /// under the in-flight request would leave whatever Garmin accepts
    /// untracked by anything local.
    case entryInFlight
    /// Garmin has already accepted this entry's create (`.sent` /
    /// `.createdAwaitingDelete`); the local copy can no longer stand in for
    /// what is in Garmin.
    case alreadyDelivered
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
    /// add-log-entry-editing: set for an edit or a move -- the old Garmin
    /// entry to delete once this one has been created (design.md D1).
    /// Optional for the same reason as `source`: files written before this
    /// field existed must still decode.
    public let replaces: ReplacedLog?
    /// add-log-entry-editing: the read-back `logId` this entry was
    /// duplicated from. That entry pre-dates this one with an identical
    /// match key, so Reconciliation must never count it as this entry's
    /// delivery -- or, worse, delete this entry's real delivery as an
    /// "excess" copy of it (design.md D2). Optional, decode-safe.
    public let duplicateOf: String?

    public var state: OutboxEntryState
    public var attemptCount: Int
    public var lastError: String?
    public let createdAt: Date
    /// Not attempted again before this time -- how backoff/Retry-After are
    /// represented, rather than an in-process sleep (see `Outbox.drain`).
    public var nextAttemptAt: Date
    /// add-log-entry-editing D1 fallback: when a `.createdAwaitingDelete`
    /// entry stopped retrying its delete (a permanent 4xx, or `maxAttempts`
    /// spent). `nil` otherwise. Parked entries are skipped by `drain` until
    /// `Outbox.retry` clears this -- the replace's equivalent of `.failed`,
    /// kept separate because a parked replace must never go back through
    /// the create step. Optional, decode-safe.
    public var parkedAt: Date?

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
        replaces: ReplacedLog? = nil,
        duplicateOf: String? = nil,
        state: OutboxEntryState = .pending,
        attemptCount: Int = 0,
        lastError: String? = nil,
        createdAt: Date = Date(),
        nextAttemptAt: Date = Date(),
        parkedAt: Date? = nil
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
        self.replaces = replaces
        self.duplicateOf = duplicateOf
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
        self.parkedAt = parkedAt
    }

    /// A replace whose delete step gave up and waits for the user
    /// (add-log-entry-editing D1 fallback). The corrected entry IS in
    /// Garmin; the old one still is too.
    public var isParkedReplace: Bool {
        state == .createdAwaitingDelete && parkedAt != nil
    }

    /// Needs the user: a create that exhausted its retries, or a parked
    /// replace. What the sync queue offers "Retry" for.
    public var needsManualRetry: Bool {
        state == .failed || isParkedReplace
    }

    /// Whether `drain` should attempt this entry at `now`: a pending create,
    /// or an unparked replace still owing its delete.
    func isDue(now: Date) -> Bool {
        guard nextAttemptAt <= now else { return false }
        switch state {
        case .pending:
            return true
        case .createdAwaitingDelete:
            return parkedAt == nil
        case .sent, .failed:
            return false
        }
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
    /// Entries a drain is sending right now (add-log-entry-editing).
    /// Claimed and checked on THIS actor, in the same serialized step as the
    /// swap/removal an edit makes, so "is it in flight?" and "replace it"
    /// can never interleave -- `Outbox` itself can't give that guarantee,
    /// since every store call it makes is an `await` it can be re-entered
    /// across.
    private var claimedIds: Set<UUID> = []

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

    /// An unreadable file (e.g. before first unlock) leaves `loaded` unset,
    /// so the next access retries instead of keeping an empty queue for the
    /// rest of this process -- see PersistedJSON.swift's header.
    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load([OutboxEntry].self, from: fileURL, decoder: JSONDecoder(), category: "OutboxStore")
        entries = result.value ?? []
        loaded = !result.isUnreadable
    }

    private func persist() throws {
        try write(entries)
    }

    /// Every save funnels through here, so this is the one place that
    /// refuses to replace a file this process never managed to read.
    private func write(_ list: [OutboxEntry]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "OutboxStore")
        let data = try JSONEncoder().encode(list)
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

    /// Everything `drain` should attempt at `now`: pending creates and
    /// unparked replaces still owing their delete (`OutboxEntry.isDue`).
    func pending(now: Date) -> [OutboxEntry] {
        loadIfNeeded()
        return entries.filter { $0.isDue(now: now) }
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

    /// Marks `id` in flight and returns its CURRENT value, or `nil` if it
    /// is gone, already claimed, or no longer due -- `drain` works from a
    /// snapshot, and an edit may have swapped the entry out since.
    func claim(id: UUID, now: Date) -> OutboxEntry? {
        loadIfNeeded()
        guard !claimedIds.contains(id),
              let entry = entries.first(where: { $0.id == id }),
              entry.isDue(now: now)
        else { return nil }
        claimedIds.insert(id)
        return entry
    }

    func release(id: UUID) {
        claimedIds.remove(id)
    }

    /// Swaps a not-yet-delivered entry for `newEntry` in ONE write, so a
    /// crash can never leave both (a duplicate) or neither (a lost food).
    /// The in-memory copy changes only once that write has succeeded.
    func replace(id: UUID, with newEntry: OutboxEntry) throws {
        loadIfNeeded()
        let index = try editableIndex(of: id)
        var updated = entries
        updated.remove(at: index)
        updated.append(newEntry)
        try write(updated)
        entries = updated
    }

    /// Removes a not-yet-delivered entry, refusing one that is in flight.
    func cancel(id: UUID) throws {
        loadIfNeeded()
        let index = try editableIndex(of: id)
        var updated = entries
        updated.remove(at: index)
        try write(updated)
        entries = updated
    }

    private func editableIndex(of id: UUID) throws -> Int {
        guard !claimedIds.contains(id) else { throw OutboxEditError.entryInFlight }
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw OutboxEditError.entryNotFound }
        switch entries[index].state {
        case .pending, .failed:
            return index
        case .sent, .createdAwaitingDelete:
            throw OutboxEditError.alreadyDelivered
        }
    }
}

// MARK: - Drain

public struct DrainResult: Sendable, Equatable {
    public let delivered: [OutboxEntry]
    /// Entries that now need the user: creates marked `.failed`, and
    /// replaces parked after their delete step gave up.
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
    ///
    /// `replaces` turns the entry into an edit of an existing Garmin entry
    /// (add-log-entry-editing D1: created first, then the old one deleted);
    /// `duplicateOf` names the read-back entry a duplicate was copied from
    /// (D2). Both default to `nil`: an ordinary add.
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
        replaces: ReplacedLog? = nil,
        duplicateOf: String? = nil,
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
            replaces: replaces,
            duplicateOf: duplicateOf,
            createdAt: createdAt,
            nextAttemptAt: createdAt
        )
        return try await store.enqueue(entry)
    }

    public func allEntries() async -> [OutboxEntry] {
        await store.all()
    }

    public func entry(id: UUID) async -> OutboxEntry? {
        await store.all().first { $0.id == id }
    }

    public func pendingCount(now: Date = Date()) async -> Int {
        await store.pendingCount(now: now)
    }

    /// User-initiated retry of an entry that needs the user
    /// (`OutboxEntry.needsManualRetry`; garmin-sync spec: "presented to the
    /// user for manual retry or deletion").
    ///
    /// A parked replace (add-log-entry-editing) stays
    /// `.createdAwaitingDelete` and only has its delete re-armed: its
    /// corrected entry is already in Garmin, so going back to `.pending`
    /// would create it a second time.
    public func retry(id: UUID) async throws {
        guard var entry = await store.all().first(where: { $0.id == id }) else { return }
        if entry.state != .createdAwaitingDelete {
            entry.state = .pending
        }
        entry.parkedAt = nil
        entry.attemptCount = 0
        entry.lastError = nil
        entry.nextAttemptAt = Date()
        try await store.update(entry)
    }

    public func delete(id: UUID) async throws {
        try await store.remove(id: id)
    }

    /// add-log-entry-editing: edits an entry that has NOT reached Garmin yet
    /// (`.pending` or `.failed`) by swapping it for a fresh pending entry
    /// with the new meal/quantity -- no Garmin call is involved, since there
    /// is nothing in Garmin to replace. Everything else (food, serving,
    /// namespace, region, and any `replaces`/`duplicateOf` the old entry
    /// carried) is kept, so an edit of an edit still deletes the original
    /// Garmin entry. Local only; throws `OutboxEditError` and changes
    /// nothing if the entry is gone, already delivered, or in flight.
    @discardableResult
    public func replaceQueued(
        id: UUID,
        mealType: MealType,
        numberOfUnits: Double,
        createdAt: Date = Date()
    ) async throws -> OutboxEntry {
        guard let old = await store.all().first(where: { $0.id == id }) else {
            throw OutboxEditError.entryNotFound
        }
        let replacement = OutboxEntry(
            date: old.date,
            mealType: mealType,
            foodId: old.foodId,
            servingId: old.servingId,
            numberOfUnits: numberOfUnits,
            source: old.source,
            regionCode: old.regionCode,
            languageCode: old.languageCode,
            replaces: old.replaces,
            duplicateOf: old.duplicateOf,
            createdAt: createdAt,
            nextAttemptAt: createdAt
        )
        // Re-validates state and in-flight status atomically on the store.
        try await store.replace(id: id, with: replacement)
        return replacement
    }

    /// add-log-entry-editing: removes an entry that has NOT reached Garmin
    /// yet, refusing (with `OutboxEditError`) one a drain is sending right
    /// now or one Garmin already accepted. Unlike `delete(id:)`, which the
    /// sync queue uses to drop an entry unconditionally.
    public func cancelQueued(id: UUID) async throws {
        try await store.cancel(id: id)
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

    /// How one entry's delivery attempt in `drain` ended.
    private enum StepResult {
        case delivered
        case retryLater
        /// Now needs the user: `.failed`, or a parked replace.
        case needsUser
        case stoppedRateLimited
        case stoppedAuth(DrainAuthOutcome)
    }

    /// Attempts delivery of every currently-due entry once.
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
    /// - A replace (add-log-entry-editing D1) is created, persisted as
    ///   `.createdAwaitingDelete`, and only then has its old entry deleted;
    ///   an entry already in that state skips straight to the delete. It
    ///   counts as delivered only once the delete succeeded (or 404'd).
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

        for snapshot in await store.pending(now: now) {
            // Re-read under a claim: an edit may have swapped or removed
            // this entry since the snapshot, and while claimed no edit can.
            guard var entry = await store.claim(id: snapshot.id, now: now) else { continue }
            let result = await deliver(&entry, using: deliverer, now: now, randomJitter: randomJitter)
            await store.release(id: entry.id)

            var stop = false
            switch result {
            case .delivered:
                delivered.append(entry)
            case .retryLater:
                break
            case .needsUser:
                failed.append(entry)
            case .stoppedRateLimited:
                stoppedDueToRateLimit = true
                stop = true
            case .stoppedAuth(let outcome):
                authOutcome = outcome
                stop = true
            }
            if stop { break }
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

    /// One entry's attempt: the create (unless a replace already got past
    /// it), then -- for a replace -- the delete of the old entry.
    private func deliver(
        _ entry: inout OutboxEntry,
        using deliverer: some FoodLogDelivering,
        now: Date,
        randomJitter: @Sendable () -> Double
    ) async -> StepResult {
        if entry.state != .createdAwaitingDelete {
            do {
                try await deliverer.createFoodLogEntry(entry.createRequest)
            } catch GarminClientError.rateLimited(let retryAfterSeconds) {
                entry.attemptCount += 1
                entry.lastError = "rate limited (429)"
                entry.nextAttemptAt = now.addingTimeInterval(
                    retryAfterSeconds ?? Self.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                )
                try? await store.update(entry)
                return .stoppedRateLimited
            } catch GarminAuthError.longLivedTokenExpired {
                entry.lastError = "auth: long-lived token expired"
                try? await store.update(entry)
                return .stoppedAuth(.longLivedTokenExpired)
            } catch GarminAuthError.notSignedIn {
                entry.lastError = "auth: not signed in"
                try? await store.update(entry)
                return .stoppedAuth(.notSignedIn)
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
                    return .needsUser
                }
                entry.nextAttemptAt = now.addingTimeInterval(
                    Self.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                )
                try? await store.update(entry)
                return .retryLater
            }

            guard entry.replaces != nil else {
                entry.state = .sent
                entry.lastError = nil
                try? await store.update(entry)
                return .delivered
            }

            // D1: the corrected entry is in Garmin. Record that durably
            // BEFORE the delete goes out, so a crash from here on resumes at
            // the delete instead of creating the food a second time. If this
            // write fails the delete waits for the next drain (the in-memory
            // copy already says `.createdAwaitingDelete`); a crash before
            // then re-creates it, which Reconciliation's excess-duplicate
            // removal cleans up.
            entry.state = .createdAwaitingDelete
            entry.attemptCount = 0
            entry.lastError = nil
            entry.nextAttemptAt = now
            do {
                try await store.update(entry)
            } catch {
                DiagnosticsLog.log(.warning, category: "Outbox", "replace: corrected entry created but its state couldn't be saved (\(error)); deleting the old entry on the next drain")
                return .retryLater
            }
        }

        return await deleteReplacedEntry(&entry, using: deliverer, now: now, randomJitter: randomJitter)
    }

    /// D1's second step. A 404 counts as success (the old entry is already
    /// gone -- deleted in Connect, or an earlier attempt landed but its
    /// response was lost). Never marks the entry `.failed`: it parks it.
    private func deleteReplacedEntry(
        _ entry: inout OutboxEntry,
        using deliverer: some FoodLogDelivering,
        now: Date,
        randomJitter: @Sendable () -> Double
    ) async -> StepResult {
        guard let replaced = entry.replaces else {
            // Only a replace ever reaches `.createdAwaitingDelete`; if a
            // hand-edited file says otherwise, there is nothing to delete.
            entry.state = .sent
            entry.lastError = nil
            try? await store.update(entry)
            return .delivered
        }

        do {
            try await deliverer.deleteFoodLogEntries(logIds: [replaced.logId], date: replaced.date)
        } catch GarminClientError.httpError(let statusCode, _) where statusCode == 404 {
            DiagnosticsLog.log(.info, category: "Outbox", "replace: old entry on \(replaced.date) was already gone (404); treating as removed")
        } catch GarminClientError.rateLimited(let retryAfterSeconds) {
            entry.attemptCount += 1
            entry.lastError = "old entry not removed yet: rate limited (429)"
            entry.nextAttemptAt = now.addingTimeInterval(
                retryAfterSeconds ?? Self.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
            )
            try? await store.update(entry)
            return .stoppedRateLimited
        } catch GarminAuthError.longLivedTokenExpired {
            entry.lastError = "auth: long-lived token expired"
            try? await store.update(entry)
            return .stoppedAuth(.longLivedTokenExpired)
        } catch GarminAuthError.notSignedIn {
            entry.lastError = "auth: not signed in"
            try? await store.update(entry)
            return .stoppedAuth(.notSignedIn)
        } catch {
            entry.attemptCount += 1
            entry.lastError = "old entry not removed yet: " + String(String(describing: error).prefix(260))
            if Self.isPermanentDeleteRejection(error) || entry.attemptCount >= maxAttempts {
                entry.parkedAt = now
                try? await store.update(entry)
                DiagnosticsLog.log(.error, category: "Outbox", "replace: corrected entry is in Garmin but the old entry on \(replaced.date) couldn't be removed after \(entry.attemptCount) attempt(s); waiting for a manual retry")
                return .needsUser
            }
            entry.nextAttemptAt = now.addingTimeInterval(
                Self.backoffDelay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
            )
            try? await store.update(entry)
            return .retryLater
        }

        entry.state = .sent
        entry.lastError = nil
        entry.parkedAt = nil
        try? await store.update(entry)
        return .delivered
    }

    /// A 4xx that retrying won't fix (design.md's Fallback: "rejects the
    /// delete step permanently (a 4xx other than 404)"). 404 is success,
    /// 408 is a timeout, 429 is handled as rate limiting before this.
    static func isPermanentDeleteRejection(_ error: Error) -> Bool {
        guard let clientError = error as? GarminClientError,
              case .httpError(let statusCode, _) = clientError
        else { return false }
        return (400..<500).contains(statusCode) && statusCode != 404 && statusCode != 408
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

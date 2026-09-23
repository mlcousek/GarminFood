// HydrationSync.swift
//
// The hydration equivalent of WeightSync.swift -- same durable per-process
// delivery queue shape (durable local commit first, bounded retry with
// capped exponential backoff, a 429 stops the whole drain cycle, an auth
// failure stops it without burning a retry attempt), its own actor and file
// because a hydration entry's wire shape has nothing in common with
// `OutboxEntry`'s food-log fields or `WeightOutboxEntry`'s weight field --
// see GarminModels.swift's hydration section and GarminClient.addHydration.
//
// Deliberately REUSES `Outbox.backoffDelay` (same module, package-internal
// visibility), exactly like `WeightOutbox` does -- see that file's header
// for the full reasoning, which applies here unchanged.
//
// One instance per process, same as `Outbox`/`WeightOutbox` -- see
// `AppServices.swift`. `OutboxEntryState`/`DrainAuthOutcome` (Outbox.swift)
// are reused as-is.
//
// sync-weight-hydration-with-garmin (2026-09-23): `valueInML` may be
// NEGATIVE. Garmin keeps only a day total and its log route is additive, so
// removing a drink that already reached Garmin is a queued `-value`
// correction (design.md D4), delivered exactly like a drink. `deliveredAt`
// (new, optional, so older outbox files still decode) records when Garmin
// accepted an entry, which FoodLogCore's `HydrationDayTotal` compares with
// when Garmin's total was last read.
//
// Race fix (2026-09-23 review): a drain CLAIMS each entry before sending it
// and writes the result back under that claim (`settle`), the same claim
// mechanism as the food `OutboxStore`. Removing a drink goes through
// `cancelQueued`, which checks the claim in the same actor step: a drink not
// in flight is simply removed; one in flight is only FLAGGED
// (`removalRequested`), and `settle` then either drops it (Garmin did not
// accept it) or appends the `-value` correction itself (Garmin did). Before
// this, a drink removed while its POST was on the wire was deleted from the
// queue, the POST still landed, and Garmin's total kept 500 ml the app no
// longer knew about -- with no correction ever queued.

import Foundation

/// The subset of `GarminClient` this outbox needs to deliver a hydration
/// entry. Mirrors `WeighInDelivering`'s reason for existing: lets
/// `HydrationOutbox.drain(using:)` be unit-tested with a fake that never
/// touches the network -- see GarminKitTests/HydrationSyncTests.swift.
public protocol HydrationDelivering: Sendable {
    @discardableResult
    func addHydration(_ request: AddHydrationRequest) async throws -> HTTPURLResponse
}

/// One queued hydration entry plus its own delivery bookkeeping -- same
/// shape as `WeightOutboxEntry`, just carrying an ml amount instead of a
/// weight.
public struct HydrationOutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Positive for a drink; NEGATIVE for a correction that removes an
    /// already-delivered drink from Garmin's day total (see this file's
    /// header).
    public let valueInML: Double
    /// What the user says the drink happened -- sent to Garmin as BOTH
    /// `calendarDate` and `timestampLocal`. May be backdated -- same
    /// "`nextAttemptAt` defaults independently to the real enqueue moment"
    /// reasoning as `WeightOutboxEntry.loggedAt`.
    public let loggedAt: Date

    public var state: OutboxEntryState
    public var attemptCount: Int
    public var lastError: String?
    public var nextAttemptAt: Date
    /// When Garmin accepted this entry (set by `drain` alongside `.sent`);
    /// `nil` when undelivered or delivered by a build older than
    /// 2026-09-23. Same role as `WeightOutboxEntry.deliveredAt`.
    public var deliveredAt: Date?
    /// `true` once the user removed this drink while a drain was sending it
    /// (`HydrationOutbox.cancelQueued` -> `.compensateAfterDelivery`). The
    /// drain that holds it then drops it, or -- if Garmin accepted it --
    /// queues its correction. Optional so older outbox files still decode.
    public var removalRequested: Bool?
    /// For a correction: the `id` of the drink entry it cancels out, when
    /// known. Lets a correction Garmin keeps rejecting be discarded with
    /// the drink restored to the local list (FoodLogCore's
    /// `HydrationLogCoordinator.discardQueued`). Optional for the same
    /// decode reason.
    public let correctsEntryId: UUID?

    public init(
        id: UUID = UUID(),
        valueInML: Double,
        loggedAt: Date = Date(),
        state: OutboxEntryState = .pending,
        attemptCount: Int = 0,
        lastError: String? = nil,
        nextAttemptAt: Date = Date(),
        deliveredAt: Date? = nil,
        removalRequested: Bool? = nil,
        correctsEntryId: UUID? = nil
    ) {
        self.id = id
        self.valueInML = valueInML
        self.loggedAt = loggedAt
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.nextAttemptAt = nextAttemptAt
        self.deliveredAt = deliveredAt
        self.removalRequested = removalRequested
        self.correctsEntryId = correctsEntryId
    }

    /// `true` for a queued correction (removing a delivered drink).
    public var isCorrection: Bool { valueInML < 0 }

    /// Removed by the user while in flight and not (yet) accepted by Garmin:
    /// counts for nothing -- it is either dropped or, once delivered,
    /// cancelled out by its own correction.
    public var isWithdrawn: Bool { removalRequested == true && state != .sent }

    var addRequest: AddHydrationRequest {
        AddHydrationRequest(valueInML: valueInML, loggedAt: loggedAt)
    }
}

// MARK: - Persistence

/// JSON-file-backed store, one file per process -- same rationale as
/// `WeightOutboxStore`.
actor HydrationOutboxStore {
    private let fileURL: URL
    private var entries: [HydrationOutboxEntry] = []
    private var loaded = false
    /// Entries a drain is sending right now -- the food `OutboxStore`'s
    /// `claimedIds`, for the same reason: "is it in flight?" and "remove
    /// it" must happen in ONE step on this actor, which `HydrationOutbox`
    /// itself can't guarantee across its own `await`s.
    private var claimedIds: Set<UUID> = []

    init(fileURL: URL = HydrationOutboxStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL(processName: String = "default") -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("GarminKit", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hydration-outbox-\(processName).json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = PersistedJSON.load([HydrationOutboxEntry].self, from: fileURL, decoder: decoder, category: "HydrationOutboxStore")
        entries = result.value ?? []
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
    }

    private func persist() throws {
        try write(entries)
    }

    private func write(_ list: [HydrationOutboxEntry]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "HydrationOutboxStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(list)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    func all() -> [HydrationOutboxEntry] {
        loadIfNeeded()
        return entries
    }

    func pending(now: Date) -> [HydrationOutboxEntry] {
        loadIfNeeded()
        return entries.filter { $0.state == .pending && $0.nextAttemptAt <= now }
    }

    @discardableResult
    func enqueue(_ entry: HydrationOutboxEntry) throws -> HydrationOutboxEntry {
        loadIfNeeded()
        entries.append(entry)
        try persist()
        return entry
    }

    func update(_ entry: HydrationOutboxEntry) throws {
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
    /// snapshot, and a removal may have happened since.
    func claim(id: UUID, now: Date) -> HydrationOutboxEntry? {
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
    /// the claim, honouring a removal requested while it was in flight:
    /// - not flagged: `attempted` is stored as-is (`.written`);
    /// - flagged, Garmin did NOT accept it: dropped (`.dropped`) -- it
    ///   never reached Garmin and the user no longer wants it;
    /// - flagged, Garmin accepted it: stored as `.sent` AND its `-value`
    ///   correction is appended in the same write (`.correctionQueued`),
    ///   due at once so the same drain delivers it.
    /// Like `update`, the in-memory copy changes even if the write fails
    /// (logged): this process then still behaves correctly until relaunch.
    func settle(_ attempted: HydrationOutboxEntry, accepted: Bool) -> HydrationSettlement {
        loadIfNeeded()
        claimedIds.remove(attempted.id)
        guard let index = entries.firstIndex(where: { $0.id == attempted.id }) else { return .gone }
        let settlement: HydrationSettlement
        if entries[index].removalRequested == true {
            if accepted {
                var sent = attempted
                sent.removalRequested = true
                entries[index] = sent
                entries.append(HydrationOutboxEntry(
                    valueInML: -attempted.valueInML,
                    loggedAt: attempted.loggedAt,
                    nextAttemptAt: attempted.nextAttemptAt,
                    correctsEntryId: attempted.id
                ))
                settlement = .correctionQueued
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
            DiagnosticsLog.log(.error, category: "HydrationOutboxStore", "couldn't persist a delivery result: \(error)")
        }
        return settlement
    }

    /// Removes a not-yet-delivered entry, or flags it if a drain is sending
    /// it right now (see `settle`). Throws `OutboxEditError.alreadyDelivered`
    /// for a `.sent` entry and `.entryNotFound` for an unknown id; nothing
    /// changes when it throws. The in-memory copy changes only once the
    /// write succeeded.
    func cancel(id: UUID) throws -> OutboxCancellation {
        loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { throw OutboxEditError.entryNotFound }
        guard entries[index].state != .sent else { throw OutboxEditError.alreadyDelivered }
        var updated = entries
        let result: OutboxCancellation
        if claimedIds.contains(id) {
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

/// How `HydrationOutboxStore.settle` resolved one delivery attempt.
enum HydrationSettlement: Sendable, Equatable {
    case written
    case dropped
    case correctionQueued
    /// The entry vanished while claimed (only an unconditional `delete`).
    case gone
}

// MARK: - Drain

public struct HydrationDrainResult: Sendable, Equatable {
    public let delivered: [HydrationOutboxEntry]
    public let failed: [HydrationOutboxEntry]
    public let stoppedDueToRateLimit: Bool
    public let authOutcome: DrainAuthOutcome
}

/// Drains one process's own hydration outbox. An actor for the same
/// reentrancy reason as `Outbox`/`WeightOutbox`.
public actor HydrationOutbox {
    private let store: HydrationOutboxStore
    public let maxAttempts: Int
    private let backoffBase: TimeInterval
    private let backoffCap: TimeInterval
    private var isDraining = false

    public init(
        processName: String = "default",
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8
    ) {
        self.store = HydrationOutboxStore(fileURL: HydrationOutboxStore.defaultFileURL(processName: processName))
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
    }

    /// Test-only entry point, mirroring `WeightOutbox`'s internal
    /// `(store:)` initializer.
    init(
        store: HydrationOutboxStore,
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 0.5,
        backoffCap: TimeInterval = 8
    ) {
        self.store = store
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
    }

    /// Enqueues a drink (positive `valueInML`) or a correction (negative --
    /// see this file's header). Durable on return, no network call.
    /// `correctsEntryId`: for a correction, the drink entry it cancels out
    /// (see `HydrationOutboxEntry.correctsEntryId`).
    @discardableResult
    public func logHydration(valueInML: Double, loggedAt: Date = Date(), correctsEntryId: UUID? = nil) async throws -> HydrationOutboxEntry {
        let entry = HydrationOutboxEntry(valueInML: valueInML, loggedAt: loggedAt, correctsEntryId: correctsEntryId)
        return try await store.enqueue(entry)
    }

    /// Removes a drink that Garmin has not accepted yet -- or, if a drain is
    /// sending it right now, flags it so that drain drops it or follows it
    /// with a correction (`OutboxCancellation`). Local only. Throws
    /// `OutboxEditError.alreadyDelivered` (`.sent`: queue a correction
    /// instead) or `.entryNotFound`; nothing changes when it throws.
    @discardableResult
    public func cancelQueued(id: UUID) async throws -> OutboxCancellation {
        try await store.cancel(id: id)
    }

    public func allEntries() async -> [HydrationOutboxEntry] {
        await store.all()
    }

    public func pendingCount(now: Date = Date()) async -> Int {
        await store.pending(now: now).count
    }

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

    /// Identical retry/rate-limit/auth-failure policy to
    /// `WeightOutbox.drain`/`Outbox.drain` -- see those for the full
    /// rationale.
    @discardableResult
    public func drain(
        using deliverer: some HydrationDelivering,
        now: Date = Date(),
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) },
        clock: @Sendable () -> Date = { Date() }
    ) async -> HydrationDrainResult {
        guard !isDraining else {
            return HydrationDrainResult(delivered: [], failed: [], stoppedDueToRateLimit: false, authOutcome: .none)
        }
        isDraining = true
        defer { isDraining = false }

        var delivered: [HydrationOutboxEntry] = []
        var failed: [HydrationOutboxEntry] = []
        var stoppedDueToRateLimit = false
        var authOutcome: DrainAuthOutcome = .none
        // Each entry is attempted at most once per drain. The due list is
        // re-read every step (not one up-front snapshot) so a correction
        // `settle` appends for a drink removed mid-flight goes out in this
        // same drain instead of waiting for the next trigger.
        var attempted = Set<UUID>()

        while true {
            guard let next = await store.pending(now: now).first(where: { !attempted.contains($0.id) }) else { break }
            attempted.insert(next.id)
            // Re-read under a claim: it may have been removed since, and
            // while claimed a removal only flags it (see `settle`).
            guard var entry = await store.claim(id: next.id, now: now) else { continue }

            var accepted = false
            var stop = false
            do {
                try await deliverer.addHydration(entry.addRequest)
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
            } catch let error as URLError where ConnectivityFailure.matches(error) {
                // Offline is not a delivery failure (ConnectivityFailure.swift,
                // same rule as `Outbox.drain`): no attempt counted, no
                // backoff, rest of the cycle skipped -- the next drain retries.
                entry.lastError = "offline: " + String(error.localizedDescription.prefix(200))
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
            case .correctionQueued:
                delivered.append(entry)
            case .dropped:
                // Removed by the user mid-flight and never accepted: gone,
                // nothing to report.
                break
            }
            if stop { break }
        }

        if !delivered.isEmpty || !failed.isEmpty || authOutcome != .none {
            DiagnosticsLog.log(
                delivered.isEmpty && !failed.isEmpty ? .warning : .info,
                category: "HydrationOutbox",
                "drain: \(delivered.count) delivered, \(failed.count) gave up, rateLimited=\(stoppedDueToRateLimit), authOutcome=\(authOutcome)"
            )
        }
        return HydrationDrainResult(delivered: delivered, failed: failed, stoppedDueToRateLimit: stoppedDueToRateLimit, authOutcome: authOutcome)
    }
}

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

    public init(
        id: UUID = UUID(),
        valueInML: Double,
        loggedAt: Date = Date(),
        state: OutboxEntryState = .pending,
        attemptCount: Int = 0,
        lastError: String? = nil,
        nextAttemptAt: Date = Date(),
        deliveredAt: Date? = nil
    ) {
        self.id = id
        self.valueInML = valueInML
        self.loggedAt = loggedAt
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.nextAttemptAt = nextAttemptAt
        self.deliveredAt = deliveredAt
    }

    /// `true` for a queued correction (removing a delivered drink).
    public var isCorrection: Bool { valueInML < 0 }

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
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = PersistedJSON.load([HydrationOutboxEntry].self, from: fileURL, decoder: decoder, category: "HydrationOutboxStore") ?? []
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entries)
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
    @discardableResult
    public func logHydration(valueInML: Double, loggedAt: Date = Date()) async throws -> HydrationOutboxEntry {
        let entry = HydrationOutboxEntry(valueInML: valueInML, loggedAt: loggedAt)
        return try await store.enqueue(entry)
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
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) }
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

        for var entry in await store.pending(now: now) {
            do {
                try await deliverer.addHydration(entry.addRequest)
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
                category: "HydrationOutbox",
                "drain: \(delivered.count) delivered, \(failed.count) gave up, rateLimited=\(stoppedDueToRateLimit), authOutcome=\(authOutcome)"
            )
        }
        return HydrationDrainResult(delivered: delivered, failed: failed, stoppedDueToRateLimit: stoppedDueToRateLimit, authOutcome: authOutcome)
    }
}

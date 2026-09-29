// DurableQueue.swift
//
// A generic, durable, per-process delivery queue (add-vault-connection
// design D7, spec "Vault writes are durable, create-only and idempotent").
// The Garmin outbox pattern already exists three times (food, weight,
// hydration, all in GarminKit); a fourth copy for vault writes would be one
// too many, so this is the generic form, keeping their proven rules:
//
//   - one JSON file per queue, loaded through `PersistedJSON` (quarantine,
//     never wipe; `ensureSafeToWrite` on every save), created LAZILY on the
//     first enqueue -- an install that never queues anything never gets one;
//   - states `pending`, `sent`, `failed`, with `attemptCount`,
//     `nextAttemptAt`, `lastError`;
//   - `drain(using:)` hands each due entry to a `DurableQueueDelivering`,
//     which answers `.delivered`, `.retry`, `.stopCycle(...)` or
//     `.failedPermanently`;
//   - an auth failure or no connection stops the cycle WITHOUT spending an
//     attempt (a dead credential or airplane mode is not the entry's fault;
//     ConnectivityFailure's 2026-09-23 lesson); a rate limit stops the whole
//     cycle and parks the entry until the reset, also without spending an
//     attempt; any other failure backs off (`RetryBackoff`) and after
//     `maxAttempts` (5) the entry is `failed` -- visible, and retryable by
//     hand (`retry(id:)`);
//   - an `isDraining` guard, so overlapping triggers share one drain;
//   - logs under the `vault` category.
//
// NOTHING ENQUEUES IN PRODUCTION in this change: the queue and the
// create-only uploader are designed and tested now so add-training-checkins
// starts from proven code. The Garmin outboxes are NOT migrated onto this
// (their on-disk formats are pinned by fixtures; proposal non-goals).
//
// Depended on by: (later) add-training-checkins. Tests: DurableQueueTests,
// StoreFixtureTests (`write-queue.json`).

import Foundation
import GarminKit

public enum DurableQueueEntryState: String, Codable, Sendable, Equatable {
    case pending
    case sent
    case failed
}

public struct DurableQueueEntry<Record: Codable & Sendable>: Codable, Sendable, Identifiable {
    public let id: UUID
    public let record: Record
    public var state: DurableQueueEntryState
    public var attemptCount: Int
    public var lastError: String?
    public let createdAt: Date
    public var nextAttemptAt: Date

    public init(id: UUID = UUID(), record: Record, state: DurableQueueEntryState = .pending, attemptCount: Int = 0, lastError: String? = nil, createdAt: Date = Date(), nextAttemptAt: Date? = nil) {
        self.id = id
        self.record = record
        self.state = state
        self.attemptCount = attemptCount
        self.lastError = lastError
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt ?? createdAt
    }

    func isDue(now: Date) -> Bool {
        state == .pending && nextAttemptAt <= now
    }
}

extension DurableQueueEntry: Equatable where Record: Equatable {}

/// Why a delivery stopped the whole cycle.
public enum DurableQueueStop: Equatable, Sendable {
    case auth
    case rateLimited(until: Date)
    case offline
}

/// What one delivery attempt achieved.
public enum DurableQueueDelivery: Equatable, Sendable {
    case delivered
    /// Try this entry again later: after `after` seconds, or after the
    /// backoff when `nil`. Spends an attempt.
    case retry(after: TimeInterval?, reason: String)
    /// Stop the cycle; spends no attempt.
    case stopCycle(DurableQueueStop)
    /// Never retried automatically; visible and retryable by hand.
    case failedPermanently(reason: String)
}

public protocol DurableQueueDelivering: Sendable {
    associatedtype Record: Codable & Sendable
    func deliver(_ record: Record) async -> DurableQueueDelivery
}

public struct DurableQueueDrainResult: Equatable, Sendable {
    public var delivered: [UUID] = []
    /// Entries that just became `failed`.
    public var failed: [UUID] = []
    public var stoppedBy: DurableQueueStop?
    /// `true` when another drain was already running and this one did nothing.
    public var skippedBecauseDraining = false

    public init() {}
}

public enum DurableQueueError: Error, Equatable, Sendable {
    case entryInFlight
}

public actor DurableQueue<Record: Codable & Sendable> {
    public let maxAttempts: Int
    private let fileURL: URL
    private let backoffBase: TimeInterval
    private let backoffCap: TimeInterval
    /// Delivered entries are kept this long (visible history), then pruned.
    private let sentRetention: TimeInterval
    private var entries: [DurableQueueEntry<Record>] = []
    private var loaded = false
    private var isDraining = false
    private var inFlight: Set<UUID> = []

    public init(
        fileURL: URL,
        maxAttempts: Int = 5,
        backoffBase: TimeInterval = 2,
        backoffCap: TimeInterval = 300,
        sentRetention: TimeInterval = 7 * 86_400
    ) {
        self.fileURL = fileURL
        self.maxAttempts = maxAttempts
        self.backoffBase = backoffBase
        self.backoffCap = backoffCap
        self.sentRetention = sentRetention
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = PersistedJSON.load([DurableQueueEntry<Record>].self, from: fileURL, decoder: VaultStorage.makeDecoder(), category: VaultLog.category)
        entries = result.value ?? []
        loaded = !result.isUnreadable
    }

    /// Every save funnels through here (the one place that refuses to
    /// replace a file this process never managed to read).
    private func write(_ list: [DurableQueueEntry<Record>]) throws {
        try PersistedJSON.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: VaultLog.category)
        try VaultStorage.write(try VaultStorage.makeEncoder().encode(list), to: fileURL)
        entries = list
    }

    public func all() -> [DurableQueueEntry<Record>] {
        loadIfNeeded()
        return entries
    }

    public func pendingCount() -> Int {
        loadIfNeeded()
        return entries.filter { $0.state == .pending }.count
    }

    /// Durable on return: a caller may treat success as "will be delivered".
    @discardableResult
    public func enqueue(_ record: Record, now: Date = Date()) throws -> DurableQueueEntry<Record> {
        loadIfNeeded()
        let entry = DurableQueueEntry(record: record, createdAt: now)
        try write(entries + [entry])
        return entry
    }

    /// The user's manual retry of a `failed` entry.
    public func retry(id: UUID, now: Date = Date()) throws {
        loadIfNeeded()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var updated = entries
        updated[index].state = .pending
        updated[index].attemptCount = 0
        updated[index].lastError = nil
        updated[index].nextAttemptAt = now
        try write(updated)
    }

    public func remove(id: UUID) throws {
        loadIfNeeded()
        guard !inFlight.contains(id) else { throw DurableQueueError.entryInFlight }
        guard entries.contains(where: { $0.id == id }) else { return }
        try write(entries.filter { $0.id != id })
    }

    /// Attempts every due entry once, oldest first. See this file's header.
    @discardableResult
    public func drain<Deliverer: DurableQueueDelivering>(
        using deliverer: Deliverer,
        now: Date = Date(),
        randomJitter: @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) async -> DurableQueueDrainResult where Deliverer.Record == Record {
        var result = DurableQueueDrainResult()
        guard !isDraining else {
            result.skippedBecauseDraining = true
            return result
        }
        isDraining = true
        defer { isDraining = false }

        loadIfNeeded()
        let due = entries.filter { $0.isDue(now: now) }.sorted { $0.createdAt < $1.createdAt }
        for snapshot in due {
            // Re-read: the entry may have been removed while an earlier
            // delivery was awaited.
            guard let current = entries.first(where: { $0.id == snapshot.id }), current.isDue(now: now) else { continue }
            inFlight.insert(current.id)
            let delivery = await deliverer.deliver(current.record)
            inFlight.remove(current.id)

            guard var entry = entries.first(where: { $0.id == current.id }) else { continue }
            var stop: DurableQueueStop?
            switch delivery {
            case .delivered:
                entry.state = .sent
                entry.lastError = nil
                result.delivered.append(entry.id)
            case .retry(let after, let reason):
                entry.attemptCount += 1
                entry.lastError = String(reason.prefix(300))
                if entry.attemptCount >= maxAttempts {
                    entry.state = .failed
                    result.failed.append(entry.id)
                } else {
                    let delay = after ?? RetryBackoff.delay(attempt: entry.attemptCount, jitter: randomJitter(), base: backoffBase, cap: backoffCap)
                    entry.nextAttemptAt = now.addingTimeInterval(delay)
                }
            case .stopCycle(let reason):
                switch reason {
                case .auth:
                    entry.lastError = "stopped: auth"
                case .offline:
                    entry.lastError = "stopped: offline"
                case .rateLimited(let until):
                    entry.lastError = "stopped: rate limited"
                    entry.nextAttemptAt = max(entry.nextAttemptAt, until)
                }
                stop = reason
            case .failedPermanently(let reason):
                entry.state = .failed
                entry.lastError = String(reason.prefix(300))
                result.failed.append(entry.id)
                VaultLog.log(.error, "write queue: an entry failed permanently (\(entry.lastError ?? ""))")
            }
            save(entry)
            if let stop {
                result.stoppedBy = stop
                break
            }
        }

        pruneSent(now: now)
        if !result.delivered.isEmpty || !result.failed.isEmpty || result.stoppedBy != nil {
            VaultLog.log(
                result.failed.isEmpty ? .info : .warning,
                "write queue drain: \(result.delivered.count) delivered, \(result.failed.count) failed, stopped=\(result.stoppedBy.map { "\($0)" } ?? "no")"
            )
        }
        return result
    }

    /// Persists one entry's new state. A failed save is logged: the entry
    /// then keeps its old state on disk and is simply attempted again.
    private func save(_ entry: DurableQueueEntry<Record>) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entries
        updated[index] = entry
        do {
            try write(updated)
        } catch {
            VaultLog.log(.warning, "write queue: could not save an entry's state (\(type(of: error)))")
        }
    }

    private func pruneSent(now: Date) {
        let cutoff = now.addingTimeInterval(-sentRetention)
        let kept = entries.filter { !($0.state == .sent && $0.createdAt < cutoff) }
        guard kept.count != entries.count else { return }
        try? write(kept)
    }
}

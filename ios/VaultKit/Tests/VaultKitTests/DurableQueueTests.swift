// DurableQueueTests.swift
//
// add-vault-connection task 2.8 (design D7, spec "Vault writes are durable,
// create-only and idempotent"): the generic queue with a real store on a
// temp file -- delivered, retry with backoff, auth and offline stop the
// cycle without spending an attempt, a rate limit stops the whole cycle,
// five attempts turn an entry `failed`, manual retry, the `isDraining`
// guard, quarantine of a bad file, and the file only appearing on the
// first enqueue.

import XCTest
@testable import VaultKit

private struct Note: Codable, Sendable, Equatable {
    let text: String
}

/// Answers each delivery from a script (per record text), recording calls.
private final class ScriptedDeliverer: DurableQueueDelivering, @unchecked Sendable {
    typealias Record = Note

    private let lock = NSLock()
    private var script: [String: [DurableQueueDelivery]]
    private var fallback: DurableQueueDelivery
    private(set) var delivered: [String] = []
    private var startedCount = 0
    /// When set, `deliver` waits on it (to overlap two drains).
    var gate: AsyncGate?

    init(_ script: [String: [DurableQueueDelivery]] = [:], fallback: DurableQueueDelivery = .delivered) {
        self.script = script
        self.fallback = fallback
    }

    func deliver(_ record: Note) async -> DurableQueueDelivery {
        markStarted()
        if let gate { await gate.wait() }
        return next(for: record)
    }

    private func markStarted() {
        lock.lock()
        startedCount += 1
        lock.unlock()
    }

    var started: Int {
        lock.lock()
        defer { lock.unlock() }
        return startedCount
    }

    private func next(for record: Note) -> DurableQueueDelivery {
        lock.lock()
        defer { lock.unlock() }
        delivered.append(record.text)
        if var queue = script[record.text], !queue.isEmpty {
            let answer = queue.removeFirst()
            script[record.text] = queue
            return answer
        }
        return fallback
    }

    var calls: [String] {
        lock.lock()
        defer { lock.unlock() }
        return delivered
    }
}

/// A one-shot latch for overlapping two drains deterministically.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

final class DurableQueueTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeQueue(maxAttempts: Int = 5) throws -> (DurableQueue<Note>, URL) {
        let fileURL = try makeTemporaryDirectory().appendingPathComponent("write-queue.json")
        return (DurableQueue<Note>(fileURL: fileURL, maxAttempts: maxAttempts, backoffBase: 2, backoffCap: 300), fileURL)
    }

    func testFileIsCreatedOnlyOnFirstEnqueue() async throws {
        let (queue, fileURL) = try makeQueue()
        _ = await queue.drain(using: ScriptedDeliverer(), now: now)
        let count = await queue.pendingCount()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "no enqueue, no file")

        try await queue.enqueue(Note(text: "a"), now: now)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDeliveredEntriesAreSentAndSurviveARelaunch() async throws {
        let (queue, fileURL) = try makeQueue()
        try await queue.enqueue(Note(text: "a"), now: now)
        try await queue.enqueue(Note(text: "b"), now: now.addingTimeInterval(1))

        let deliverer = ScriptedDeliverer()
        let result = await queue.drain(using: deliverer, now: now.addingTimeInterval(2))

        XCTAssertEqual(result.delivered.count, 2)
        XCTAssertEqual(deliverer.calls, ["a", "b"], "oldest first")
        let relaunched = DurableQueue<Note>(fileURL: fileURL)
        let states = await relaunched.all().map(\.state)
        XCTAssertEqual(states, [.sent, .sent])
    }

    func testRetryBacksOffAndSpendsAnAttempt() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(Note(text: "a"), now: now)
        let deliverer = ScriptedDeliverer(["a": [.retry(after: nil, reason: "server error (502)")]])

        _ = await queue.drain(using: deliverer, now: now, randomJitter: { 1 })

        let allEntry = await queue.all()

        let entry = try XCTUnwrap(allEntry.first)
        XCTAssertEqual(entry.state, .pending)
        XCTAssertEqual(entry.attemptCount, 1)
        XCTAssertEqual(entry.lastError, "server error (502)")
        XCTAssertEqual(entry.nextAttemptAt, now.addingTimeInterval(2), "RetryBackoff: base 2 s at the first attempt")

        // Not due yet: nothing is attempted.
        _ = await queue.drain(using: deliverer, now: now.addingTimeInterval(1))
        XCTAssertEqual(deliverer.calls, ["a"])

        // Due: delivered on the fallback.
        let second = await queue.drain(using: deliverer, now: now.addingTimeInterval(3))
        XCTAssertEqual(second.delivered.count, 1)
    }

    func testExplicitRetryAfterIsHonoured() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(Note(text: "a"), now: now)
        _ = await queue.drain(using: ScriptedDeliverer(["a": [.retry(after: 90, reason: "x")]]), now: now)
        let allEntry = await queue.all()
        let entry = try XCTUnwrap(allEntry.first)
        XCTAssertEqual(entry.nextAttemptAt, now.addingTimeInterval(90))
    }

    func testAuthStopsTheCycleWithoutSpendingAnAttempt() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(Note(text: "a"), now: now)
        try await queue.enqueue(Note(text: "b"), now: now.addingTimeInterval(1))
        let deliverer = ScriptedDeliverer(["a": [.stopCycle(.auth)]])

        let result = await queue.drain(using: deliverer, now: now.addingTimeInterval(2))

        XCTAssertEqual(result.stoppedBy, .auth)
        XCTAssertEqual(deliverer.calls, ["a"], "the cycle stops at the first entry")
        let entries = await queue.all()
        XCTAssertEqual(entries.map(\.attemptCount), [0, 0])
        XCTAssertEqual(entries.map(\.state), [.pending, .pending])
    }

    func testOfflineStopsAfterTheFirstEntryAndNoAttemptCountChanges() async throws {
        let (queue, _) = try makeQueue()
        for (index, text) in ["a", "b", "c"].enumerated() {
            try await queue.enqueue(Note(text: text), now: now.addingTimeInterval(Double(index)))
        }
        let deliverer = ScriptedDeliverer(fallback: .stopCycle(.offline))

        let result = await queue.drain(using: deliverer, now: now.addingTimeInterval(5))

        XCTAssertEqual(result.stoppedBy, .offline)
        XCTAssertEqual(deliverer.calls, ["a"])
        let attempts = await queue.all().map(\.attemptCount)
        XCTAssertEqual(attempts, [0, 0, 0])
        // Offline never turns anything `failed`, however often it happens.
        for minute in 1...20 {
            _ = await queue.drain(using: deliverer, now: now.addingTimeInterval(Double(60 * minute)))
        }
        let states = await queue.all().map(\.state)
        XCTAssertEqual(states, [.pending, .pending, .pending])
    }

    func testRateLimitStopsTheWholeCycleUntilTheReset() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(Note(text: "a"), now: now)
        try await queue.enqueue(Note(text: "b"), now: now.addingTimeInterval(1))
        let until = now.addingTimeInterval(600)
        let deliverer = ScriptedDeliverer(["a": [.stopCycle(.rateLimited(until: until))]])

        let result = await queue.drain(using: deliverer, now: now.addingTimeInterval(2))

        XCTAssertEqual(result.stoppedBy, .rateLimited(until: until))
        XCTAssertEqual(deliverer.calls, ["a"])
        let allFirst = await queue.all()
        let first = try XCTUnwrap(allFirst.first)
        XCTAssertEqual(first.nextAttemptAt, until)
        XCTAssertEqual(first.attemptCount, 0)
    }

    func testFiveAttemptsTurnAnEntryFailedAndManualRetryRearmsIt() async throws {
        let (queue, _) = try makeQueue(maxAttempts: 5)
        let entry = try await queue.enqueue(Note(text: "a"), now: now)
        let deliverer = ScriptedDeliverer(fallback: .retry(after: 1, reason: "server error (500)"))

        var clock = now
        var failed: [UUID] = []
        for _ in 0..<5 {
            let result = await queue.drain(using: deliverer, now: clock)
            failed += result.failed
            clock = clock.addingTimeInterval(10)
        }
        XCTAssertEqual(failed, [entry.id])
        let allStored = await queue.all()
        var stored = try XCTUnwrap(allStored.first)
        XCTAssertEqual(stored.state, .failed)
        XCTAssertEqual(stored.attemptCount, 5)

        // A failed entry is left alone by later drains...
        _ = await queue.drain(using: deliverer, now: clock)
        XCTAssertEqual(deliverer.calls.count, 5)

        // ...until the user retries it.
        try await queue.retry(id: entry.id, now: clock)
        let reloaded = await queue.all()
        stored = try XCTUnwrap(reloaded.first)
        XCTAssertEqual(stored.state, .pending)
        XCTAssertEqual(stored.attemptCount, 0)
        let result = await queue.drain(using: ScriptedDeliverer(), now: clock)
        XCTAssertEqual(result.delivered, [entry.id])
    }

    func testFailedPermanentlyIsImmediateAndVisible() async throws {
        let log = recordVaultLog()
        let (queue, _) = try makeQueue()
        let entry = try await queue.enqueue(Note(text: "a"), now: now)
        let result = await queue.drain(using: ScriptedDeliverer(["a": [.failedPermanently(reason: "a different file already exists")]]), now: now)
        XCTAssertEqual(result.failed, [entry.id])
        let allStored = await queue.all()
        let stored = try XCTUnwrap(allStored.first)
        XCTAssertEqual(stored.state, .failed)
        XCTAssertEqual(stored.lastError, "a different file already exists")
        XCTAssertFalse(log.errorLines.isEmpty)
    }

    func testOverlappingDrainsShareOneDelivery() async throws {
        let (queue, _) = try makeQueue()
        try await queue.enqueue(Note(text: "a"), now: now)
        let gate = AsyncGate()
        let deliverer = ScriptedDeliverer()
        deliverer.gate = gate

        let start = now
        let first = Task { await queue.drain(using: deliverer, now: start) }
        // Wait until the first drain is inside its (gated) delivery.
        var spins = 0
        while deliverer.started == 0, spins < 5_000 {
            spins += 1
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(deliverer.started, 1)
        let second = await queue.drain(using: deliverer, now: now)
        await gate.open()
        let firstResult = await first.value

        XCTAssertTrue(second.skippedBecauseDraining, "a drain already in flight wins")
        XCTAssertEqual(firstResult.delivered.count + second.delivered.count, 1, "the entry is delivered exactly once")
        XCTAssertEqual(deliverer.calls, ["a"])
    }

    func testUndecodableQueueIsQuarantined() async throws {
        let (queue, fileURL) = try makeQueue()
        try Data("[{\"broken\":".utf8).write(to: fileURL)
        let entries = await queue.all()
        XCTAssertTrue(entries.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: fileURL.deletingLastPathComponent().path)
        XCTAssertTrue(names.contains { $0.hasPrefix("write-queue.unreadable-") }, "\(names)")
        // A new entry can still be queued afterwards.
        try await queue.enqueue(Note(text: "a"), now: now)
        let count = await queue.pendingCount()
        XCTAssertEqual(count, 1)
    }

    func testRemoveDropsAQueuedEntry() async throws {
        let (queue, _) = try makeQueue()
        let entry = try await queue.enqueue(Note(text: "a"), now: now)
        try await queue.remove(id: entry.id)
        let entries = await queue.all()
        XCTAssertTrue(entries.isEmpty)
    }
}

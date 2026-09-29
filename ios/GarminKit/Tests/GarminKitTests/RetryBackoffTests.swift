// RetryBackoffTests.swift
//
// add-vault-connection task 2.2: `RetryBackoff.delay` is the old
// `Outbox.backoffDelay` made public for VaultKit's `DurableQueue`. This pins
// the public name to the exact values the old formula produced (the same
// table `OutboxTests` checks through the old name, which still forwards
// here), so the extraction can never silently change how long the Garmin
// outboxes wait between attempts.

import XCTest
@testable import GarminKit

final class RetryBackoffTests: XCTestCase {
    func testMatchesThePreviousOutboxFormula() {
        // Garmin outbox parameters: base 0.5 s, cap 8 s, full jitter.
        let expected: [(attempt: Int, delay: TimeInterval)] = [
            (0, 0.5), (1, 0.5), (2, 1.0), (3, 2.0), (4, 4.0), (5, 8.0), (6, 8.0), (50, 8.0)
        ]
        for row in expected {
            XCTAssertEqual(RetryBackoff.delay(attempt: row.attempt, jitter: 1, base: 0.5, cap: 8), row.delay, accuracy: 0.0001, "attempt \(row.attempt)")
        }
    }

    func testJitterScalesAndIsClamped() {
        XCTAssertEqual(RetryBackoff.delay(attempt: 5, jitter: 0, base: 0.5, cap: 8), 0, accuracy: 0.0001)
        XCTAssertEqual(RetryBackoff.delay(attempt: 5, jitter: 0.25, base: 0.5, cap: 8), 2.0, accuracy: 0.0001)
        XCTAssertEqual(RetryBackoff.delay(attempt: 5, jitter: 7, base: 0.5, cap: 8), 8.0, accuracy: 0.0001)
        XCTAssertEqual(RetryBackoff.delay(attempt: 5, jitter: -1, base: 0.5, cap: 8), 0, accuracy: 0.0001)
    }

    func testForwarderAndPublicNameAgree() {
        for attempt in 0...12 {
            for jitter in [0.0, 0.3, 0.99, 1.0] {
                XCTAssertEqual(
                    RetryBackoff.delay(attempt: attempt, jitter: jitter, base: 2, cap: 300),
                    Outbox.backoffDelay(attempt: attempt, jitter: jitter, base: 2, cap: 300),
                    accuracy: 0.000001
                )
            }
        }
    }
}

// DailyLedgerTests.swift
//
// add-journeys-and-records design D1/D10: every day is folded into a
// lifetime aggregate exactly once; open days are recomputed, never added.

import XCTest
@testable import Gamification

final class DailyLedgerTests: XCTestCase {
    /// `n` consecutive September day keys ending at `end`.
    private func window(endingAt end: Int, count: Int) -> [String] {
        ((end - count + 1)...end).map { String(format: "2026-09-%02d", $0) }
    }

    func testFirstRunSealsEverythingOlderThanTheOpenWindow() {
        var ledger = DailyLedger<Double>()
        let days = window(endingAt: 10, count: 10)
        let sealed = ledger.advance(windowDays: days) { _ in 1 }

        XCTAssertEqual(sealed.map(\.day), Array(days.prefix(7)))
        XCTAssertEqual(ledger.sealedThrough, "2026-09-07")
        XCTAssertEqual(ledger.openDays?.keys.sorted(), ["2026-09-08", "2026-09-09", "2026-09-10"])
    }

    func testRepeatedRunsOnTheSameDayFoldNothingTwice() {
        var ledger = DailyLedger<Double>()
        let days = window(endingAt: 10, count: 10)
        var total = 0.0
        for _ in 0..<10 {
            total += ledger.advance(windowDays: days) { _ in 5 }.reduce(0) { $0 + $1.value }
        }
        XCTAssertEqual(total, 35)
    }

    func testNextDaySealsExactlyOneMoreDay() {
        var ledger = DailyLedger<Double>()
        _ = ledger.advance(windowDays: window(endingAt: 10, count: 10)) { _ in 1 }
        let sealed = ledger.advance(windowDays: window(endingAt: 11, count: 10)) { _ in 2 }
        XCTAssertEqual(sealed, [DailyLedger<Double>.SealedDay(day: "2026-09-08", value: 2)])
    }

    func testOpenDayIsRecomputedAfterALateLog() {
        var ledger = DailyLedger<Double>()
        let days = window(endingAt: 10, count: 10)
        var yesterday = 20.0
        _ = ledger.advance(windowDays: days) { $0 == "2026-09-09" ? yesterday : 0 }
        XCTAssertEqual(ledger.openDays?["2026-09-09"], 20)

        yesterday = 50 // a late 30 g entry for yesterday
        _ = ledger.advance(windowDays: days) { $0 == "2026-09-09" ? yesterday : 0 }
        XCTAssertEqual(ledger.openDays?["2026-09-09"], 50)

        // Sealed later with its final value, once.
        let sealed = ledger.advance(windowDays: window(endingAt: 12, count: 10)) { $0 == "2026-09-09" ? yesterday : 0 }
        XCTAssertEqual(sealed.first { $0.day == "2026-09-09" }?.value, 50)
    }

    func testDaysWithoutValueContributeNothingButAdvanceTheMark() {
        var ledger = DailyLedger<Double>()
        let sealed = ledger.advance(windowDays: window(endingAt: 10, count: 10)) { _ in nil }
        XCTAssertTrue(sealed.isEmpty)
        XCTAssertEqual(ledger.sealedThrough, "2026-09-07")
    }

    func testOpenDayThatLeftTheWindowIsSealedWithItsLastValue() {
        var ledger = DailyLedger<Double>()
        _ = ledger.advance(windowDays: window(endingAt: 10, count: 5)) { _ in 7 }
        // Weeks later: 09-08..09-10 are no longer in the (short) window.
        let sealed = ledger.advance(windowDays: window(endingAt: 30, count: 5)) { _ in 1 }
        let byDay = Dictionary(uniqueKeysWithValues: sealed.map { ($0.day, $0.value) })
        XCTAssertEqual(byDay["2026-09-08"], 7)
        XCTAssertEqual(byDay["2026-09-10"], 7)
        XCTAssertEqual(byDay["2026-09-26"], 1)
        XCTAssertEqual(ledger.sealedThrough, "2026-09-27")
    }

    func testShortWindowSealsNothing() {
        var ledger = DailyLedger<Double>()
        let sealed = ledger.advance(windowDays: ["2026-09-09", "2026-09-10"]) { _ in 1 }
        XCTAssertTrue(sealed.isEmpty)
        XCTAssertNil(ledger.sealedThrough)
        XCTAssertEqual(ledger.openValues, [1, 1])
    }
}

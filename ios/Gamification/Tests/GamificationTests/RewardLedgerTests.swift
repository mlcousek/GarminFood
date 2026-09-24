// RewardLedgerTests.swift
//
// add-gamification-signals 5.5: a grant key pays out exactly once, freeze
// grants are listed with their day, and the ledger survives a reload.
// Real stores in unique temp files (project convention, never mocks).

import XCTest
@testable import Gamification

final class RewardLedgerTests: XCTestCase {
    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString).json")
    }

    func testSameGrantTwiceAwardsXPOnce() async throws {
        let xp = XPStore(fileURL: tempURL("ledger-xp"))
        let ledger = RewardLedger(fileURL: tempURL("ledger"))
        let grant = RewardGrant(key: "bingo.line.2026-W39.row0", kind: .xp(25))
        let now = TestClock.date(2026, 9, 24)

        let first = try await ledger.apply([grant], day: "2026-09-24", now: now, xpStore: xp)
        XCTAssertEqual(first.applied, [grant])
        XCTAssertEqual(first.xpAwarded, 25)
        XCTAssertEqual(first.xpTotalAfter, 25)

        let second = try await ledger.apply([grant], day: "2026-09-24", now: now, xpStore: xp)
        XCTAssertEqual(second, .empty)
        let total = await xp.currentTotal()
        XCTAssertEqual(total, 25)
    }

    func testDuplicateKeysWithinOneCallCountOnce() async throws {
        let xp = XPStore(fileURL: tempURL("ledger-xp"))
        let ledger = RewardLedger(fileURL: tempURL("ledger"))
        let grant = RewardGrant(key: "records.pr.2026-09-24", kind: .xp(20))
        let result = try await ledger.apply([grant, grant], day: "2026-09-24", now: Date(), xpStore: xp)
        XCTAssertEqual(result.applied.count, 1)
        XCTAssertEqual(result.xpAwarded, 20)
    }

    func testFreezeGrantsAreRecordedWithDayAndNoXP() async throws {
        let xp = XPStore(fileURL: tempURL("ledger-xp"))
        let ledger = RewardLedger(fileURL: tempURL("ledger"))
        let freeze = RewardGrant(key: "bingo.freeze.2026-W39", kind: .streakFreeze)
        let result = try await ledger.apply([freeze], day: "2026-09-27", now: Date(), xpStore: xp)
        XCTAssertEqual(result.applied, [freeze])
        XCTAssertEqual(result.xpAwarded, 0)
        let grants = await ledger.freezeGrants()
        XCTAssertEqual(grants, [RewardLedger.FreezeGrant(key: "bingo.freeze.2026-W39", day: "2026-09-27")])
        let total = await xp.currentTotal()
        XCTAssertEqual(total, 0)
    }

    func testReloadFromDiskKeepsKeys() async throws {
        let xpURL = tempURL("ledger-xp")
        let ledgerURL = tempURL("ledger")
        let grant = RewardGrant(key: "seasonal.event.easter.2026", kind: .xp(50))
        _ = try await RewardLedger(fileURL: ledgerURL)
            .apply([grant], day: "2026-04-05", now: Date(), xpStore: XPStore(fileURL: xpURL))

        let reloaded = RewardLedger(fileURL: ledgerURL)
        let contains = await reloaded.contains(grant.key)
        XCTAssertTrue(contains)
        let again = try await reloaded.apply([grant], day: "2026-04-06", now: Date(), xpStore: XPStore(fileURL: xpURL))
        XCTAssertEqual(again.xpAwarded, 0)
        let total = await XPStore(fileURL: xpURL).currentTotal()
        XCTAssertEqual(total, 50)
        let entries = await reloaded.all()
        XCTAssertEqual(entries.map(\.day), ["2026-04-05"])
    }

    func testCorruptFileIsQuarantinedNotOverwrittenSilently() async throws {
        let ledgerURL = tempURL("ledger")
        try Data("not json".utf8).write(to: ledgerURL)
        let ledger = RewardLedger(fileURL: ledgerURL)
        let entries = await ledger.all()
        XCTAssertEqual(entries, [])
        // A new grant still works after the corrupt file was moved aside.
        let result = try await ledger.apply([RewardGrant(key: "k", kind: .xp(5))], day: "2026-09-24",
                                            now: Date(), xpStore: XPStore(fileURL: tempURL("ledger-xp")))
        XCTAssertEqual(result.xpAwarded, 5)
    }
}

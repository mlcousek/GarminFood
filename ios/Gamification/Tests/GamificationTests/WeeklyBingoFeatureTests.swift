// WeeklyBingoFeatureTests.swift
//
// add-weekly-bingo tasks 2.4 + 3.2 (design D1, D4, D5, D6, D9): the real
// `WeeklyBingoFeature` end to end over a real `BingoStore`, `RewardLedger`
// and `XPStore` in a temp directory -- the card is generated once and kept,
// a line pays 25 XP once across runs, a full card pays 150 XP + one freeze
// grant, moments fire only the first time, completions stay sticky after an
// entry is deleted, last week's card is frozen in the history, and badges
// (first line, blackout, four corners, X) are requested.
//
// Most tests pin the card to `BingoFixtures.fixedCard` by writing it to the
// store before the feature's first run, so the squares are known.

import XCTest
import FoodLogCore
@testable import Gamification

final class WeeklyBingoFeatureTests: XCTestCase {
    private typealias F = BingoFixtures
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = F.tempDirectory("bingo-feature")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    /// A feature whose store already holds `F.fixedCard` for W39.
    private func featureWithFixedCard() async throws -> WeeklyBingoFeature {
        let seed = BingoStore(directory: directory)
        await seed.setCard(BingoCardRecord(taskIds: F.fixedCard), week: F.week)
        try await seed.save()
        return WeeklyBingoFeature(directory: directory)
    }

    private func ledgerAndXP() -> (RewardLedger, XPStore) {
        (
            RewardLedger(fileURL: directory.appendingPathComponent("ledger.json")),
            XPStore(fileURL: directory.appendingPathComponent("xp.json"))
        )
    }

    private var allTicking: [String] {
        F.fixedCard.filter { $0 != BingoTaskCatalog.freeId }
    }

    // MARK: - The card

    func testCardIsGeneratedOnceAndKeptAcrossRunsAndInstances() async throws {
        let first = WeeklyBingoFeature(directory: directory)
        _ = await first.update(F.context(F.snapshot([F.plainDay(0)], today: F.key(0)), now: F.at(0)))
        let monday = await first.currentCard(now: F.at(0), calendar: F.calendar)
        XCTAssertNotNil(monday)
        XCTAssertEqual(monday?.squares.count, 9)
        XCTAssertTrue(monday?.squares[4].isFree ?? false, "free centre")

        // Wednesday, other data, a fresh instance (app relaunch): same card.
        let relaunched = WeeklyBingoFeature(directory: directory)
        let wednesday = F.snapshot(
            [F.plainDay(0), F.day(2, [F.entry("water", on: 2)], waterML: 2000, waterGoalML: 2000)],
            today: F.key(2)
        )
        _ = await relaunched.update(F.context(wednesday, now: F.at(2)))
        let later = await relaunched.currentCard(now: F.at(2), calendar: F.calendar)
        XCTAssertEqual(later?.squares.map { $0.task?.id }, monday?.squares.map { $0.task?.id })
    }

    func testCurrentCardIsNilBeforeTheFirstRun() async {
        let feature = WeeklyBingoFeature(directory: directory)
        let card = await feature.currentCard(now: F.at(1), calendar: F.calendar)
        XCTAssertNil(card)
    }

    // MARK: - Lines

    func testFirstLinePaysOnceAcrossTwoRunsWithOneMoment() async throws {
        let feature = try await featureWithFixedCard()
        let (ledger, xp) = ledgerAndXP()
        let snapshot = F.snapshot([F.day(1, F.entries(ticking: ["e-nuts", "e-soup"]))])

        let first = await feature.update(F.context(snapshot))
        XCTAssertEqual(first.grants, [RewardGrant(key: "bingo.line.2026-W39.row1", kind: .xp(XPAward.bingoLine))])
        XCTAssertEqual(first.moments.count, 1)
        XCTAssertEqual(first.moments.first?.style, .celebration)
        XCTAssertEqual(first.moments.first?.xpAwarded, XPAward.bingoLine)
        XCTAssertEqual(first.unlockBadgeIds, [BingoTaskCatalog.firstLineBadgeId])
        let applied = try await ledger.apply(first.grants, day: F.key(3), now: F.at(3), xpStore: xp)
        XCTAssertEqual(applied.xpAwarded, 25)

        let second = await feature.update(F.context(snapshot, unlocked: [BingoTaskCatalog.firstLineBadgeId]))
        XCTAssertEqual(second.grants, first.grants, "grants are re-emitted; the ledger makes them idempotent")
        XCTAssertTrue(second.moments.isEmpty, "no second BINGO! moment")
        XCTAssertTrue(second.unlockBadgeIds.isEmpty)
        let again = try await ledger.apply(second.grants, day: F.key(3), now: F.at(3), xpStore: xp)
        XCTAssertEqual(again, .empty)
        let total = await xp.currentTotal()
        XCTAssertEqual(total, 25)
        let lines = await feature.store.totalLines()
        XCTAssertEqual(lines, 1, "the lifetime counter is bumped once")
    }

    func testSummaryCountsLinesSquaresAndDaysLeft() async throws {
        let feature = try await featureWithFixedCard()
        let update = await feature.update(F.context(F.snapshot([F.day(1, F.entries(ticking: ["e-nuts", "e-soup"]))])))
        let summary = try XCTUnwrap(update.summary)
        XCTAssertFalse(summary.title.isEmpty)
        XCTAssertEqual(summary.fraction ?? -1, 3.0 / 9.0, accuracy: 0.0001)
        XCTAssertEqual(WeeklyBingoFeature.daysLeft(week: F.week, today: F.key(3), calendar: F.calendar), 4)
        XCTAssertEqual(WeeklyBingoFeature.daysLeft(week: F.week, today: F.key(6), calendar: F.calendar), 1)
        XCTAssertEqual(WeeklyBingoFeature.daysLeft(week: F.week, today: F.key(7), calendar: F.calendar), 0)
    }

    // MARK: - Full card

    func testFullCardPays350XPAndOneFreezeOnce() async throws {
        let feature = try await featureWithFixedCard()
        let (ledger, xp) = ledgerAndXP()
        let snapshot = F.snapshot([F.day(1, F.entries(ticking: allTicking))])

        let first = await feature.update(F.context(snapshot))
        let keys = Set(first.grants.map(\.key))
        XCTAssertEqual(keys.count, 10)
        XCTAssertTrue(keys.contains("bingo.full.2026-W39"))
        XCTAssertTrue(keys.contains("bingo.freeze.2026-W39"))
        XCTAssertTrue(first.grants.contains(RewardGrant(key: "bingo.freeze.2026-W39", kind: .streakFreeze)))
        XCTAssertEqual(first.moments.count, 9, "8 lines + the blackout")
        XCTAssertEqual(
            Set(first.unlockBadgeIds),
            [
                BingoTaskCatalog.firstLineBadgeId, BingoTaskCatalog.blackout1BadgeId,
                BingoTaskCatalog.fourCornersBadgeId, BingoTaskCatalog.xMarksBadgeId,
            ]
        )

        let applied = try await ledger.apply(first.grants, day: F.key(3), now: F.at(3), xpStore: xp)
        XCTAssertEqual(applied.xpAwarded, 8 * 25 + 150)
        let freezes = await ledger.freezeGrants()
        XCTAssertEqual(freezes.map(\.key), ["bingo.freeze.2026-W39"])

        let second = await feature.update(F.context(snapshot, unlocked: Set(first.unlockBadgeIds)))
        XCTAssertTrue(second.moments.isEmpty)
        XCTAssertTrue(second.unlockBadgeIds.isEmpty)
        let again = try await ledger.apply(second.grants, day: F.key(3), now: F.at(3), xpStore: xp)
        XCTAssertEqual(again, .empty)
        let full = await feature.store.fullCards()
        XCTAssertEqual(full, 1)
        let card = await feature.currentCard(now: F.at(3), calendar: F.calendar)
        XCTAssertEqual(card?.isFull, true)
        XCTAssertEqual(card?.doneCount, 9)
    }

    // MARK: - Sticky, week-bound

    func testDeletedEntryLeavesTheSquareDone() async throws {
        let feature = try await featureWithFixedCard()
        _ = await feature.update(F.context(F.snapshot([F.day(1, F.entries(ticking: ["m-fish"]))])))
        // The fish entry is deleted: Tuesday now has only a plain entry.
        _ = await feature.update(F.context(F.snapshot([F.plainDay(1)])))
        let card = await feature.currentCard(now: F.at(3), calendar: F.calendar)
        XCTAssertEqual(card?.squares[6].task?.id, "m-fish")
        XCTAssertEqual(card?.squares[6].completedDay, F.key(1))
        XCTAssertEqual(card?.squares[6].isDone, true)
    }

    func testLastWeeksCardIsFrozenInTheHistory() async throws {
        let seed = BingoStore(directory: directory)
        let lastWeek = try XCTUnwrap(F.week.adding(weeks: -1, calendar: F.calendar))
        let frozen = BingoCardRecord(taskIds: F.fixedCard, completed: ["0": "2026-09-15"])
        await seed.setCard(frozen, week: lastWeek)
        try await seed.save()

        let feature = WeeklyBingoFeature(directory: directory)
        // Fruit on this Monday ticks nothing on last week's card.
        _ = await feature.update(F.context(F.snapshot([F.day(0, F.entries(ticking: ["e-fruit", "e-tea"], on: 0))])))
        let past = await feature.pastCards(now: F.at(3), calendar: F.calendar)
        XCTAssertEqual(past.map(\.week), [lastWeek])
        XCTAssertEqual(past.first?.squares.compactMap(\.completedDay), ["2026-09-15"])
        XCTAssertEqual(past.first?.squares.map { $0.task?.id ?? BingoTaskCatalog.freeId }, F.fixedCard)
        let current = await feature.currentCard(now: F.at(3), calendar: F.calendar)
        XCTAssertEqual(current?.week, F.week)
        XCTAssertEqual(current?.squares.count, 9)
    }

    // MARK: - Status helpers

    func testStatusReadsRowsColumnsAndFreeSquares() {
        let status = WeeklyBingoFeature.status(week: F.week, record: BingoCardRecord(taskIds: F.fixedCard, completed: ["1": F.key(2)]))
        XCTAssertEqual(status.squares.count, 9)
        XCTAssertEqual(status.squares[1].row, 1)
        XCTAssertEqual(status.squares[1].column, 2)
        XCTAssertEqual(status.squares[1].completedDay, F.key(2))
        XCTAssertEqual(status.squares[7].row, 3)
        XCTAssertEqual(status.squares[7].column, 2)
        XCTAssertTrue(status.squares[4].isFree)
        XCTAssertTrue(status.squares[4].isDone)
        XCTAssertEqual(status.doneCount, 2)
        XCTAssertTrue(status.lines.isEmpty)
        XCTAssertFalse(status.isFull)
    }
}

// WeeklyBingoStoreTests.swift
//
// add-weekly-bingo task 3.1 (design D7): the bingo JSON store round-trips,
// keeps only the newest 12 weeks, decodes an older minimal file, survives a
// garbage file, and -- the CI-proven store lesson -- a `save()` on a fresh
// instance that never read the file first loads it rather than replacing
// it with an empty snapshot. Real files in a unique temp directory.

import XCTest
@testable import Gamification

final class WeeklyBingoStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = BingoFixtures.tempDirectory("bingo-store")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func week(_ number: Int) -> WeekKey {
        WeekKey(yearForWeek: 2026, week: number)
    }

    func testRoundTrip() async throws {
        let store = BingoStore(directory: directory)
        let card = BingoCardRecord(
            taskIds: BingoFixtures.fixedCard,
            completed: ["3": BingoFixtures.key(1), "5": BingoFixtures.key(2)],
            linesDone: ["row1"],
            full: false
        )
        await store.setCard(card, week: BingoFixtures.week)
        await store.addLines(1)
        await store.addFullCard()
        try await store.save()

        let reread = BingoStore(directory: directory)
        let stored = await reread.card(week: BingoFixtures.week)
        XCTAssertEqual(stored, card)
        XCTAssertEqual(stored?.completedByIndex, [3: BingoFixtures.key(1), 5: BingoFixtures.key(2)])
        let lines = await reread.totalLines()
        let full = await reread.fullCards()
        XCTAssertEqual(lines, 1)
        XCTAssertEqual(full, 1)
    }

    func testACardWithoutTaskIdsDoesNotSinkTheWholeFile() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"cards":{"2026-W38":{"completed":{"0":"2026-09-15"}},"2026-W39":{"taskIds":["e-fruit","free"]}},"totalLines":7,"fullCards":2}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("bingo.json"))

        let store = BingoStore(directory: directory)
        let broken = await store.card(week: week(38))
        let intact = await store.card(week: week(39))
        let lines = await store.totalLines()
        let full = await store.fullCards()
        XCTAssertEqual(broken?.taskIds, [])
        XCTAssertEqual(intact?.taskIds, ["e-fruit", "free"])
        XCTAssertEqual(lines, 7, "the lifetime counters survive")
        XCTAssertEqual(full, 2)
    }

    func testKeepsOnlyTheNewestTwelveWeeks() async throws {
        let store = BingoStore(directory: directory)
        for number in 26...39 {
            await store.setCard(BingoCardRecord(taskIds: BingoFixtures.fixedCard), week: week(number))
        }
        await store.prune()
        try await store.save()

        let cards = await BingoStore(directory: directory).allCards()
        let weeks = cards.map { $0.week }
        XCTAssertEqual(weeks.count, BingoStore.maxCards)
        XCTAssertEqual(weeks.first, week(39), "newest first")
        XCTAssertEqual(weeks.last, week(28))
    }

    func testDecodesAnOldMinimalFile() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = #"{"cards":{"2026-W39":{"taskIds":["e-fruit","e-tea","e-egg","e-nuts","free","e-soup","m-fish","m-legume","e-fermented"]}}}"#
        try Data(json.utf8).write(to: directory.appendingPathComponent("bingo.json"))

        let store = BingoStore(directory: directory)
        let card = await store.card(week: BingoFixtures.week)
        XCTAssertEqual(card?.taskIds, BingoFixtures.fixedCard)
        XCTAssertNil(card?.completed)
        XCTAssertEqual(card?.completedByIndex, [:])
        XCTAssertEqual(card?.isFull, false)
        let lines = await store.totalLines()
        let full = await store.fullCards()
        XCTAssertEqual(lines, 0)
        XCTAssertEqual(full, 0)
    }

    func testSaveBeforeAnyReadKeepsTheExistingFile() async throws {
        let first = BingoStore(directory: directory)
        await first.setCard(BingoCardRecord(taskIds: BingoFixtures.fixedCard, completed: ["0": BingoFixtures.key(0)]), week: BingoFixtures.week)
        await first.addLines(3)
        try await first.save()

        // A fresh instance saving before anything read the file must load it
        // first -- never write its empty in-memory snapshot over it.
        try await BingoStore(directory: directory).save()

        let reread = BingoStore(directory: directory)
        let card = await reread.card(week: BingoFixtures.week)
        let lines = await reread.totalLines()
        XCTAssertEqual(card?.completedByIndex, [0: BingoFixtures.key(0)])
        XCTAssertEqual(lines, 3)
    }

    func testGarbageFileIsTreatedAsEmptyAndCanBeReplaced() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("bingo.json"))

        let store = BingoStore(directory: directory)
        let before = await store.card(week: BingoFixtures.week)
        XCTAssertNil(before)
        await store.setCard(BingoCardRecord(taskIds: BingoFixtures.fixedCard), week: BingoFixtures.week)
        try await store.save()

        let after = await BingoStore(directory: directory).card(week: BingoFixtures.week)
        XCTAssertEqual(after?.taskIds, BingoFixtures.fixedCard)
    }
}

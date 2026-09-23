// DayNoteTests.swift
//
// DayNoteStore / DayNote (add-day-notes, DayNote.swift) -- same shape as
// FavoriteFoodTests.swift: real store instances at unique temp-file paths,
// never mocked. Covers the two spec scenarios (tag a race day and reopen
// it; clearing a note stores nothing) plus the store's idempotency, which
// the Today card's flush-on-disappear relies on.

import XCTest
@testable import FoodLogCore

final class DayNoteTests: XCTestCase {
    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-daynotes-test-\(UUID().uuidString).json")
    }

    // MARK: - Save and reopen

    func testSavedNoteAndTagsSurviveAFreshStoreAtTheSameFile() async throws {
        let url = makeURL()
        let store1 = DayNoteStore(fileURL: url)
        try await store1.save(day: "2026-09-19", text: "Half marathon PB", tags: [.race])

        let store2 = DayNoteStore(fileURL: url)
        let note = await store2.note(for: "2026-09-19")

        XCTAssertEqual(note?.text, "Half marathon PB")
        XCTAssertEqual(note?.tags, [.race])
    }

    func testNotesAreKeptPerDay() async throws {
        let store = DayNoteStore(fileURL: makeURL())
        try await store.save(day: "2026-09-19", text: "Race", tags: [.race])
        try await store.save(day: "2026-09-20", text: "Recovery", tags: [.restDay])

        let first = await store.note(for: "2026-09-19")
        let second = await store.note(for: "2026-09-20")
        let missing = await store.note(for: "2026-09-21")

        XCTAssertEqual(first?.text, "Race")
        XCTAssertEqual(second?.tags, [.restDay])
        XCTAssertNil(missing)
    }

    func testSavingAgainReplacesTheDaysNote() async throws {
        let store = DayNoteStore(fileURL: makeURL())
        try await store.save(day: "2026-09-19", text: "Half", tags: [.race])
        try await store.save(day: "2026-09-19", text: "Half marathon PB", tags: [.race, .celebration])

        let all = await store.all()

        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.text, "Half marathon PB")
        XCTAssertEqual(all.first?.tags, [.race, .celebration])
    }

    // MARK: - Empty notes

    func testClearingTextAndTagsDeletesTheNote() async throws {
        let url = makeURL()
        let store = DayNoteStore(fileURL: url)
        try await store.save(day: "2026-09-19", text: "Half marathon PB", tags: [.race])

        let result = try await store.save(day: "2026-09-19", text: "", tags: [])

        XCTAssertNil(result)
        let inMemory = await store.note(for: "2026-09-19")
        XCTAssertNil(inMemory)
        let reopened = await DayNoteStore(fileURL: url).all()
        XCTAssertTrue(reopened.isEmpty)
    }

    func testWhitespaceOnlyTextWithNoTagsCountsAsEmpty() async throws {
        let store = DayNoteStore(fileURL: makeURL())

        let result = try await store.save(day: "2026-09-19", text: "  \n\t ", tags: [])

        XCTAssertNil(result)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testTagsAloneWithoutTextAreKept() async throws {
        let store = DayNoteStore(fileURL: makeURL())

        try await store.save(day: "2026-09-19", text: "", tags: [.sick])

        let note = await store.note(for: "2026-09-19")
        XCTAssertEqual(note?.tags, [.sick])
        XCTAssertEqual(note?.text, "")
    }

    func testSavingEmptyForADayWithNothingStoredDoesNotCreateTheFile() async throws {
        let url = makeURL()
        let store = DayNoteStore(fileURL: url)

        try await store.save(day: "2026-09-19", text: "", tags: [])

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: - Idempotency and tag canonicalization

    func testSavingIdenticalContentKeepsTheOriginalUpdatedAt() async throws {
        let store = DayNoteStore(fileURL: makeURL())
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)
        try await store.save(day: "2026-09-19", text: "PB", tags: [.race], now: first)

        let result = try await store.save(day: "2026-09-19", text: "PB", tags: [.race], now: later)

        XCTAssertEqual(result?.updatedAt, first)
    }

    func testTagsAreStoredDeduplicatedInCanonicalOrder() async throws {
        let store = DayNoteStore(fileURL: makeURL())

        try await store.save(day: "2026-09-19", text: "", tags: [.party, .race, .party])

        let note = await store.note(for: "2026-09-19")
        XCTAssertEqual(note?.tags, [.race, .party])
    }

    // MARK: - Range queries and ordering

    func testNotesInRangeAreInclusiveAndOldestFirst() async throws {
        let store = DayNoteStore(fileURL: makeURL())
        try await store.save(day: "2026-09-21", text: "c", tags: [])
        try await store.save(day: "2026-09-01", text: "a", tags: [])
        try await store.save(day: "2026-09-10", text: "b", tags: [])
        try await store.save(day: "2026-08-31", text: "outside", tags: [])

        let inRange = await store.notes(from: "2026-09-01", to: "2026-09-21")

        XCTAssertEqual(inRange.map(\.day), ["2026-09-01", "2026-09-10", "2026-09-21"])
    }

    // MARK: - Delete

    func testDeleteRemovesTheDaysNote() async throws {
        let store = DayNoteStore(fileURL: makeURL())
        try await store.save(day: "2026-09-19", text: "PB", tags: [.race])

        try await store.delete(day: "2026-09-19")

        let note = await store.note(for: "2026-09-19")
        XCTAssertNil(note)
    }

    // MARK: - Decoding

    func testUnknownTagInTheFileIsDroppedRatherThanFailingTheWholeFile() async throws {
        let url = makeURL()
        let json = """
        [{"day":"2026-09-19","text":"PB","tags":["race","somethingRemoved"],"updatedAt":"2026-09-19T10:00:00Z"}]
        """
        try Data(json.utf8).write(to: url)

        let note = await DayNoteStore(fileURL: url).note(for: "2026-09-19")

        XCTAssertEqual(note?.text, "PB")
        XCTAssertEqual(note?.tags, [.race])
    }

    // MARK: - Day key

    func testDayKeyMatchesNutritionDateFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 23, minute: 30))!

        XCTAssertEqual(NutritionDate.string(from: date, calendar: calendar), "2026-09-19")
    }

    // MARK: - Tag metadata

    func testEveryTagHasAnEmojiAndTitle() {
        for tag in DayNoteTag.allCases {
            XCTAssertFalse(tag.emoji.isEmpty, "\(tag) has no emoji")
            XCTAssertFalse(tag.title.isEmpty, "\(tag) has no title")
        }
        XCTAssertEqual(DayNoteTag.allCases.count, 7)
    }
}

// LocalFoodLogStoreTests.swift
//
// add-standalone-mode 2.1 (design D2): the local food log is the system of
// record in standalone mode, so what matters is that a commit survives a
// relaunch, edits/deletes change exactly one entry, months shard into
// their own files, and a file this build can't use is quarantined or
// refused -- never silently wiped. Real `LocalFoodLogStore` on a unique
// temp directory per test (LogEntryCoordinatorTests' pattern), a fresh
// actor instance standing in for a relaunch.

import XCTest
@testable import FoodLogCore
import GarminKit

final class LocalFoodLogStoreTests: XCTestCase {
    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("localfoodlog-\(UUID().uuidString)", isDirectory: true)
    }

    private let loggedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeEntry(day: String, meal: MealType = .breakfast, calories: Double = 120, quantity: Double = 1) -> LocalLogEntry {
        let serving = Serving(id: "s-100g", unit: "g", numberOfUnits: 100, calories: calories, protein: 10)
        return LocalLogEntry(
            day: day,
            mealType: meal,
            loggedAt: loggedAt,
            food: LocalFoodRef(id: "food-1", source: .garmin, name: "Tvaroh", brandName: "Madeta"),
            serving: serving,
            quantity: quantity
        )
    }

    func testACommitSurvivesARelaunch() async throws {
        let directory = makeDirectory()
        let entry = makeEntry(day: "2026-09-25", quantity: 1.5)
        try await LocalFoodLogStore(directoryURL: directory).append([entry])

        let reloaded = try await LocalFoodLogStore(directoryURL: directory).entries(forDay: "2026-09-25")

        XCTAssertEqual(reloaded, [entry])
        XCTAssertEqual(reloaded.first?.amount(.calories) ?? 0, 180, accuracy: 0.0001, "snapshot is serving x quantity")
        XCTAssertEqual(reloaded.first?.servingLabel, "100 g")
    }

    func testEntriesAreKeptPerDayInCommitOrder() async throws {
        let store = LocalFoodLogStore(directoryURL: makeDirectory())
        let first = makeEntry(day: "2026-09-25", meal: .lunch)
        let second = makeEntry(day: "2026-09-25", meal: .breakfast)
        let otherDay = makeEntry(day: "2026-09-24")
        try await store.append([first])
        try await store.append([otherDay, second])

        let day = try await store.entries(forDay: "2026-09-25")

        XCTAssertEqual(day.map(\.id), [first.id, second.id])
    }

    func testUpdateChangesOnlyThatEntry() async throws {
        let directory = makeDirectory()
        let store = LocalFoodLogStore(directoryURL: directory)
        let kept = makeEntry(day: "2026-09-25")
        var edited = makeEntry(day: "2026-09-25")
        try await store.append([kept, edited])

        edited.quantity = 2
        edited.mealType = .dinner
        edited.nutrients = ["calories": 240]
        try await store.update(edited)

        let reloaded = try await LocalFoodLogStore(directoryURL: directory).entries(forDay: "2026-09-25")
        XCTAssertEqual(reloaded, [kept, edited])
    }

    func testUpdatingAnUnknownEntryThrowsAndWritesNothing() async throws {
        let store = LocalFoodLogStore(directoryURL: makeDirectory())
        let stored = makeEntry(day: "2026-09-25")
        try await store.append([stored])

        do {
            try await store.update(makeEntry(day: "2026-09-25"))
            XCTFail("expected entryNotFound")
        } catch {
            XCTAssertEqual(error as? LocalFoodLogError, .entryNotFound)
        }
        let day = try await store.entries(forDay: "2026-09-25")
        XCTAssertEqual(day, [stored])
    }

    func testDeleteRemovesExactlyThatEntry() async throws {
        let directory = makeDirectory()
        let store = LocalFoodLogStore(directoryURL: directory)
        let kept = makeEntry(day: "2026-09-25")
        let removed = makeEntry(day: "2026-09-25")
        try await store.append([kept, removed])

        let returned = try await store.delete(id: removed.id, day: "2026-09-25")

        XCTAssertEqual(returned, removed)
        let reloaded = try await LocalFoodLogStore(directoryURL: directory).entries(forDay: "2026-09-25")
        XCTAssertEqual(reloaded, [kept])
        do {
            try await store.delete(id: removed.id, day: "2026-09-25")
            XCTFail("a second delete must not succeed")
        } catch {
            XCTAssertEqual(error as? LocalFoodLogError, .entryNotFound)
        }
    }

    func testMonthsAreShardedIntoTheirOwnFiles() async throws {
        let directory = makeDirectory()
        let store = LocalFoodLogStore(directoryURL: directory)
        let september = makeEntry(day: "2026-09-30")
        let october = makeEntry(day: "2026-10-01")
        let december = makeEntry(day: "2026-12-31")
        try await store.append([september, october, december])

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(files, ["2026-09.json", "2026-10.json", "2026-12.json"])

        let fresh = LocalFoodLogStore(directoryURL: directory)
        let range = try await fresh.entries(fromDay: "2026-09-30", toDay: "2026-10-31")
        XCTAssertEqual(range.map(\.id), [september.id, october.id])
        let acrossYear = try await fresh.entries(fromDay: "2026-10-01", toDay: "2027-01-15")
        XCTAssertEqual(acrossYear.map(\.id), [october.id, december.id])
    }

    func testAnEntryIsFoundByIdWithoutItsDayAfterARelaunch() async throws {
        let directory = makeDirectory()
        let old = makeEntry(day: "2026-07-02")
        try await LocalFoodLogStore(directoryURL: directory).append([old, makeEntry(day: "2026-09-25")])

        let found = await LocalFoodLogStore(directoryURL: directory).entry(id: old.id)

        XCTAssertEqual(found, old)
        let missing = await LocalFoodLogStore(directoryURL: directory).entry(id: UUID())
        XCTAssertNil(missing)
    }

    func testAnUndecodableMonthIsQuarantinedNotWiped() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let garbage = Data("not json at all".utf8)
        try garbage.write(to: directory.appendingPathComponent("2026-09.json"))
        let store = LocalFoodLogStore(directoryURL: directory)

        let day = try await store.entries(forDay: "2026-09-25")
        XCTAssertTrue(day.isEmpty)

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined = files.filter { $0.hasPrefix("2026-09.unreadable-") }
        XCTAssertEqual(quarantined.count, 1, "the bad file is moved aside, not overwritten")
        let quarantinedName = try XCTUnwrap(quarantined.first)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(quarantinedName)), garbage)

        // The month is usable again afterwards.
        let entry = makeEntry(day: "2026-09-25")
        try await store.append([entry])
        let reloaded = try await LocalFoodLogStore(directoryURL: directory).entries(forDay: "2026-09-25")
        XCTAssertEqual(reloaded, [entry])
    }

    func testAMonthThatCantBeReadRefusesReadsAndSaves() async throws {
        let directory = makeDirectory()
        // A directory where the month file should be: it exists, but can't
        // be read as a file -- the same outcome as a file still locked by
        // data protection before first unlock.
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("2026-09.json", isDirectory: true), withIntermediateDirectories: true)
        let store = LocalFoodLogStore(directoryURL: directory)

        do {
            _ = try await store.entries(forDay: "2026-09-25")
            XCTFail("an unread month must not read as an empty day")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError)
        }
        do {
            try await store.append([makeEntry(day: "2026-09-25")])
            XCTFail("an unread month must not be overwritten")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError)
        }
        // Other months are unaffected.
        try await store.append([makeEntry(day: "2026-10-01")])
        let october = try await store.entries(forDay: "2026-10-01")
        XCTAssertEqual(october.count, 1)
    }

    func testEditAndDeleteInAnUnreadableMonthReportUnreadableNotChanged() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("2026-09.json", isDirectory: true), withIntermediateDirectories: true)
        let store = LocalFoodLogStore(directoryURL: directory)
        let entry = makeEntry(day: "2026-09-25")

        do {
            try await store.update(entry)
            XCTFail("an unread month must not report the entry as changed")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError, "got \(error)")
        }
        do {
            try await store.delete(id: entry.id, day: entry.day)
            XCTFail("an unread month must not report the entry as gone")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError, "got \(error)")
        }
    }

    func testLookupByIdRetriesAMonthThatWasUnreadable() async throws {
        let directory = makeDirectory()
        let unreadable = directory.appendingPathComponent("2026-09.json", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        let store = LocalFoodLogStore(directoryURL: directory)
        let entry = makeEntry(day: "2026-09-25")

        let before = await store.entry(id: entry.id)
        XCTAssertNil(before)

        // The month becomes readable (e.g. the device is unlocked): the same
        // store instance must look again instead of remembering "empty".
        try FileManager.default.removeItem(at: unreadable)
        try await LocalFoodLogStore(directoryURL: directory).append([entry])

        let after = await store.entry(id: entry.id)
        XCTAssertEqual(after, entry)
    }

    func testUnknownKeysAndMissingOptionalFieldsDecode() async throws {
        let directory = makeDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        // Written "by a later build": an extra key everywhere, a food
        // source this build doesn't know, and none of the optional fields.
        let json = """
        [{
          "id": "\(id.uuidString)",
          "day": "2026-09-25",
          "mealType": "LUNCH",
          "loggedAt": 780000000,
          "food": { "id": "abc", "source": "SOMETHING_NEW", "name": "Buchty", "futureField": 1 },
          "servingId": "custom",
          "quantity": 2,
          "nutrients": { "calories": 500, "someFutureNutrient": 3 },
          "moodEmoji": "😋"
        }]
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("2026-09.json"))

        let entries = try await LocalFoodLogStore(directoryURL: directory).entries(forDay: "2026-09-25")

        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.mealType, .lunch)
        XCTAssertNil(entry.food.source)
        XCTAssertEqual(entry.food.name, "Buchty")
        XCTAssertNil(entry.servingUnit)
        XCTAssertNil(entry.editedAt)
        XCTAssertEqual(entry.amount(.calories), 500)
        XCTAssertEqual(entry.nutrients["someFutureNutrient"], 3, "an unknown nutrient is kept, not dropped")
    }

    func testAnInvalidDayIsRefused() async throws {
        let store = LocalFoodLogStore(directoryURL: makeDirectory())
        for bad in ["", "2026-9-25", "2026-13-01", "25.09.2026", "2026-09-25T10:00"] {
            do {
                try await store.append([makeEntry(day: bad)])
                XCTFail("\(bad) must be refused")
            } catch {
                XCTAssertEqual(error as? LocalFoodLogError, .invalidDay(bad))
            }
        }
    }

    func testMonthRangeCrossesTheYear() {
        XCTAssertEqual(LocalFoodLogStore.months(from: "2026-11", to: "2027-02"), ["2026-11", "2026-12", "2027-01", "2027-02"])
        XCTAssertEqual(LocalFoodLogStore.months(from: "2026-09", to: "2026-09"), ["2026-09"])
    }
}

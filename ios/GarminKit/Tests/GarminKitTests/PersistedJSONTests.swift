// PersistedJSONTests.swift
//
// `PersistedJSON.load` (openspec/changes/fix-silent-store-wipe): a missing
// file is a normal first launch, a valid file decodes, and an undecodable
// file is moved aside (never left where the store's next save would
// overwrite it). Plus the store-level regression the helper exists for:
// a corrupt outbox file must survive the outbox's next enqueue.
//
// Each test works in its OWN fresh temp directory, so "exactly one
// quarantined sibling" can be asserted without other tests' files (or a
// shared temp dir's leftovers) interfering.

import XCTest
@testable import GarminKit

final class PersistedJSONTests: XCTestCase {
    private struct Sample: Codable, Equatable {
        let name: String
        let count: Int
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("garminkit-persistedjson-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func quarantinedFiles(for baseName: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(baseName).unreadable-") && $0.pathExtension == "json" }
    }

    // MARK: - Helper

    func testMissingFileReturnsNilAndCreatesNothing() throws {
        let url = directory.appendingPathComponent("sample.json")

        let loaded = PersistedJSON.load([Sample].self, from: url, decoder: JSONDecoder(), category: "Test")

        XCTAssertNil(loaded.value)
        guard case .missing = loaded else { return XCTFail("expected .missing, got \(loaded)") }
        XCTAssertFalse(loaded.isUnreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testValidFileReturnsTheDecodedValueAndIsLeftInPlace() throws {
        let url = directory.appendingPathComponent("sample.json")
        let value = [Sample(name: "a", count: 1), Sample(name: "b", count: 2)]
        try JSONEncoder().encode(value).write(to: url)

        let loaded = PersistedJSON.load([Sample].self, from: url, decoder: JSONDecoder(), category: "Test")

        XCTAssertEqual(loaded.value, value)
        XCTAssertFalse(loaded.isUnreadable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(try quarantinedFiles(for: "sample").isEmpty)
    }

    func testCorruptFileReturnsNilAndIsMovedAsideWithItsOriginalBytes() throws {
        let url = directory.appendingPathComponent("sample.json")
        let garbage = Data("{ this is not the JSON you are looking for".utf8)
        try garbage.write(to: url)

        let loaded = PersistedJSON.load([Sample].self, from: url, decoder: JSONDecoder(), category: "Test")

        XCTAssertNil(loaded.value)
        guard case .undecodable = loaded else { return XCTFail("expected .undecodable, got \(loaded)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "the undecodable file must no longer sit where the next save would overwrite it")
        let quarantined = try quarantinedFiles(for: "sample")
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, garbage)
    }

    func testWellFormedJSONOfTheWrongShapeIsAlsoQuarantined() throws {
        // The realistic case: valid JSON written by an older/newer model
        // that this build's types can no longer decode.
        let url = directory.appendingPathComponent("sample.json")
        let otherShape = Data(#"[{"name":"a","count":"not-a-number"}]"#.utf8)
        try otherShape.write(to: url)

        let loaded = PersistedJSON.load([Sample].self, from: url, decoder: JSONDecoder(), category: "Test")

        XCTAssertNil(loaded.value)
        XCTAssertFalse(loaded.isUnreadable)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let quarantined = try quarantinedFiles(for: "sample")
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, otherShape)
    }

    func testQuarantineDestinationDoesNotCollideWithAnExistingQuarantinedFile() throws {
        let url = directory.appendingPathComponent("sample.json")
        let now = Date()
        let first = PersistedJSON.quarantineDestination(for: url, now: now)
        try Data("x".utf8).write(to: first)

        let second = PersistedJSON.quarantineDestination(for: url, now: now)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.lastPathComponent.hasPrefix("sample.unreadable-"))
        XCTAssertEqual(second.pathExtension, "json")
    }

    // MARK: - Unreadable file (fix/store-unreadable-latch)

    /// A directory where the file should be makes `Data(contentsOf:)` fail
    /// with an error that is NOT "no such file" -- a deterministic stand-in
    /// for a data-protected file before first unlock.
    private func makeUnreadable(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func testUnreadableFileIsReportedAndLeftInPlace() throws {
        let url = directory.appendingPathComponent("sample.json")
        try makeUnreadable(url)

        let loaded = PersistedJSON.load([Sample].self, from: url, decoder: JSONDecoder(), category: "Test")

        XCTAssertTrue(loaded.isUnreadable)
        XCTAssertNil(loaded.value)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "never moved or deleted")
        XCTAssertTrue(try quarantinedFiles(for: "sample").isEmpty, "not quarantined: it may just be locked")
    }

    func testEnsureSafeToWriteThrowsOnlyWhileNotLoaded() {
        let url = directory.appendingPathComponent("sample.json")
        XCTAssertNoThrow(try PersistedJSON.ensureSafeToWrite(loaded: true, fileURL: url, category: "Test"))
        XCTAssertThrowsError(try PersistedJSON.ensureSafeToWrite(loaded: false, fileURL: url, category: "Test")) { error in
            XCTAssertEqual(error as? PersistedJSONUnreadFileError, PersistedJSONUnreadFileError(fileName: "sample.json"))
        }
    }

    /// The actual bug: a store that couldn't read its file (e.g. launched
    /// before first unlock) must neither keep the empty state for the rest
    /// of the process nor overwrite the file on its next save.
    func testUnreadableOutboxRefusesToSaveThenRecoversOnceReadable() async throws {
        // A real queued entry, written by one outbox to a scratch file.
        let sourceURL = directory.appendingPathComponent("outbox-source.json")
        let original = try await Outbox(store: OutboxStore(fileURL: sourceURL), maxAttempts: 3, backoffBase: 0.5, backoffCap: 8)
            .logFood(date: "2026-09-23", mealType: .breakfast, foodId: "1", servingId: "2", numberOfUnits: 1)
        let originalBytes = try Data(contentsOf: sourceURL)

        let url = directory.appendingPathComponent("outbox-locked.json")
        try makeUnreadable(url)
        let outbox = Outbox(store: OutboxStore(fileURL: url), maxAttempts: 3, backoffBase: 0.5, backoffCap: 8)

        let whileLocked = await outbox.allEntries()
        XCTAssertTrue(whileLocked.isEmpty)
        do {
            _ = try await outbox.logFood(date: "2026-09-23", mealType: .lunch, foodId: "3", servingId: "4", numberOfUnits: 1)
            XCTFail("saving over a file that was never read must throw")
        } catch {
            XCTAssertTrue(error is PersistedJSONUnreadFileError, "got \(error)")
        }

        // "Unlock": the real file becomes readable.
        try FileManager.default.removeItem(at: url)
        try originalBytes.write(to: url)

        let afterUnlock = await outbox.allEntries()
        XCTAssertEqual(afterUnlock.map(\.id), [original.id], "the store re-reads instead of keeping the empty state")

        let next = try await outbox.logFood(date: "2026-09-23", mealType: .lunch, foodId: "3", servingId: "4", numberOfUnits: 1)
        let reloaded = await Outbox(store: OutboxStore(fileURL: url), maxAttempts: 3, backoffBase: 0.5, backoffCap: 8).allEntries()
        XCTAssertEqual(Set(reloaded.map(\.id)), [original.id, next.id], "the queued entry survived the next save")
    }

    // MARK: - Store-level regression (the actual bug)

    func testCorruptOutboxFileSurvivesTheNextEnqueue() async throws {
        let url = directory.appendingPathComponent("outbox-test.json")
        let garbage = Data("not an outbox at all".utf8)
        try garbage.write(to: url)

        let outbox = Outbox(store: OutboxStore(fileURL: url), maxAttempts: 3, backoffBase: 0.5, backoffCap: 8)
        let before = await outbox.allEntries()
        XCTAssertTrue(before.isEmpty, "an undecodable file still starts the outbox empty")

        let entry = try await outbox.logFood(date: "2026-09-23", mealType: .lunch, foodId: "1", servingId: "2", numberOfUnits: 1)

        // The new write landed in a fresh file...
        let after = await outbox.allEntries()
        XCTAssertEqual(after.map(\.id), [entry.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // ...and the original bytes were NOT overwritten by it.
        let quarantined = try quarantinedFiles(for: "outbox-test")
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, garbage)
    }
}

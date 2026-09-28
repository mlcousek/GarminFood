// StoreFixtureTests.swift
//
// add-data-safety D2 (docs/data-compatibility.md) for VaultKit's own files
// (add-vault-connection task 2.13, design D12): every file a VaultKit store
// persists has a committed, SYNTHETIC fixture under Fixtures/Stores/ --
// `example` names, device `ios-0000abcd`, a projection body of
// `{"schema":"example"}`, never real vault data -- read back THROUGH THE
// REAL STORE, asserting specific decoded values and that nothing was
// quarantined (a quarantined file reads as empty, which is exactly the
// silent failure these tests exist to catch).
//
// THE RULE (as in GarminKit): never edit or delete an existing fixture. A
// format change adds a new fixture beside the old one, and the old one must
// keep decoding.
//
// `testEveryPersistedFileHasAFixture` scans Sources/VaultKit for literal
// `"<name>.json"` file names and fails, naming the file, when a store file
// has no fixture here (spec "A store without a fixture").

import XCTest
@testable import VaultKit

final class StoreFixtureTests: XCTestCase {
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Stores", isDirectory: true)

    private static let sourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VaultKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // VaultKit
        .appendingPathComponent("Sources/VaultKit", isDirectory: true)

    private static let allFixtures: [String] = [
        "device-identity.json",
        "status.json",
        "fetch-cache.json",
        "write-queue.json",
    ]

    private static let cacheFixture = "cache/656d7a69627eb5f5fc0256a9dbba4a1c2e7b46f7b3fe03bc52dde6528f473840.bin"

    // MARK: - Helpers

    /// Copies fixtures into a fresh directory under their own relative
    /// paths and returns the directory.
    private func copyFixtures(_ names: [String]) throws -> URL {
        let directory = try makeTemporaryDirectory()
        for name in names {
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Self.fixturesDirectory.appendingPathComponent(name), to: destination)
        }
        return directory
    }

    private func assertNothingQuarantined(in directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.contains(".unreadable-") }, "a store quarantined its fixture: \(names)", file: file, line: line)
    }

    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    // MARK: - Fixtures

    func testDeviceIdentityFixture() async throws {
        let directory = try copyFixtures(["device-identity.json"])
        let store = DeviceIdentityStore(directory: directory)
        let current = await store.current()
        let record = try XCTUnwrap(current)
        try assertNothingQuarantined(in: directory)
        XCTAssertEqual(record.deviceId.rawValue, "ios-0000abcd")
        XCTAssertEqual(record.createdAt, iso("2026-09-28T08:00:00Z"))
        XCTAssertEqual(record.nextSequence, 4)
        let next = try await store.reserveSequence(count: 1)
        XCTAssertEqual(next, 4...4)
    }

    func testStatusFixture() async throws {
        let directory = try copyFixtures(["status.json"])
        let status = await VaultStatusStore(directory: directory).current()
        try assertNothingQuarantined(in: directory)
        XCTAssertEqual(status.blockedBy, .tokenRejected)
        XCTAssertEqual(status.lastOutcome, .authFailed(.tokenRejected))
        XCTAssertEqual(status.lastOutcomeAt, iso("2026-09-28T08:05:00Z"))
        XCTAssertEqual(status.lastSuccessAt, iso("2026-09-28T07:00:00Z"))
        XCTAssertEqual(status.rateLimitedUntil, iso("2026-09-28T07:30:00Z"))
        XCTAssertEqual(status.tokenExpiresAt, iso("2027-03-27T00:00:00Z"))
        XCTAssertEqual(status.tokenSavedAt, iso("2026-09-28T06:55:00Z"))
        XCTAssertEqual(status.pendingWrites, 0)
    }

    func testFetchCacheFixtureWithItsBytes() async throws {
        let directory = try copyFixtures(["fetch-cache.json", Self.cacheFixture])
        let sync = ConditionalFileSync(transport: InMemoryVaultTransport(), directory: directory)
        let storedEntry = await sync.entry(for: VaultHub.projectionPath)
        let storedFile = await sync.cachedFile(VaultHub.projectionPath)
        let entry = try XCTUnwrap(storedEntry)
        let cached = try XCTUnwrap(storedFile)
        try assertNothingQuarantined(in: directory)
        XCTAssertEqual(entry.etag, "W/\"example-etag-1\"")
        XCTAssertEqual(entry.rejectedETag, "W/\"example-etag-2\"")
        XCTAssertEqual(entry.fetchedAt, iso("2026-09-28T08:00:00Z"))
        XCTAssertEqual(entry.checkedAt, iso("2026-09-28T08:10:00Z"))
        XCTAssertEqual(entry.fileName, ConditionalFileSync.cacheFileName(for: VaultHub.projectionPath))
        XCTAssertEqual(cached.bytes, Data(#"{"schema":"example"}"#.utf8))
        XCTAssertEqual(cached.fetchedAt, iso("2026-09-28T08:00:00Z"))
    }

    func testWriteQueueFixture() async throws {
        let directory = try copyFixtures(["write-queue.json"])
        let queue = VaultWriteQueue.make(directory: directory)
        let entries = await queue.all()
        try assertNothingQuarantined(in: directory)
        XCTAssertEqual(entries.count, 3)
        guard entries.count == 3 else { return }
        XCTAssertEqual(entries.map(\.state), [.pending, .failed, .sent])
        XCTAssertEqual(entries.map(\.attemptCount), [0, 5, 1])
        XCTAssertEqual(entries[1].lastError, "server error (502)")
        XCTAssertEqual(entries[0].record.path.rawValue, "events/ios-0000abcd/2026/09/20260928T080000Z-1.jsonl")
        XCTAssertEqual(entries[0].record.commitMessage, "app: example event")
        let bytes = entries[0].record.bytes
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "{\"id\":\"00000000-0000-4000-8000-000000000001\",\"type\":\"example\"}\n")
        XCTAssertEqual(entries[0].record.blobSHA, GitBlob.sha1Hex(of: bytes), "the sealed SHA matches the sealed bytes")
        XCTAssertEqual(entries[0].nextAttemptAt, iso("2026-09-28T08:00:00Z"))
    }

    // MARK: - Coverage

    func testEveryPersistedFileHasAFixture() throws {
        let fileManager = FileManager.default
        let onDisk = try fileManager.contentsOfDirectory(atPath: Self.fixturesDirectory.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(Set(onDisk), Set(Self.allFixtures), "Fixtures/Stores and allFixtures disagree -- add a test for a new fixture, never delete an old one")
        XCTAssertTrue(fileManager.fileExists(atPath: Self.fixturesDirectory.appendingPathComponent(Self.cacheFixture).path))

        guard let enumerator = fileManager.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: nil) else {
            return XCTFail("couldn't enumerate \(Self.sourcesDirectory.path)")
        }
        let literalName = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]+)\\.json\"")
        var found = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in literalName.matches(in: text, range: range) {
                if let captured = Range(match.range(at: 1), in: text) {
                    found.insert(String(text[captured]) + ".json")
                }
            }
        }
        // Sanity: the scan sees the stores we know about.
        XCTAssertTrue(found.contains("device-identity.json"), "scan found: \(found)")
        for name in found.sorted() {
            XCTAssertTrue(Self.allFixtures.contains(name), "\(name) is persisted by Sources/VaultKit but has no fixture in Fixtures/Stores")
        }
    }
}

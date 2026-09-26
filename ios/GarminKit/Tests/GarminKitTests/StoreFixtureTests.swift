// StoreFixtureTests.swift
//
// add-data-safety D2 (see docs/data-compatibility.md): every JSON file a
// GarminKit store persists on the owner's phone has a committed fixture under
// Fixtures/Stores/, written exactly as the CURRENT code encodes it (same
// JSONEncoder date strategy, key names, enum raw values, Optional-nil keys
// omitted). Each test copies its fixture into a fresh temp directory under the
// store's real file name and reads it back THROUGH THE REAL STORE -- not a
// bare `JSONDecoder` -- because the failure this guards against is silent:
// `PersistedJSON.load` quarantines an undecodable file (renames it to
// `<name>.unreadable-<stamp>.json`) and the store simply reads as EMPTY. So
// every test asserts specific non-empty decoded values AND that no
// `.unreadable-` file appeared next to the copy.
//
// THE RULE: never edit or delete an existing fixture. A fixture is a frozen
// sample of a file that already exists on a real device. When a store's
// format changes, ADD a new fixture next to the old one (e.g.
// `outbox-app.v2.json`) with its own test, and keep the old one decoding --
// if an old fixture stops decoding, the change is what's wrong, not the
// fixture.
//
// `testEveryPersistedFileHasAFixture` keeps this list honest: it scans
// Sources/GarminKit for literal `"<name>.json"` file names (and interpolated
// per-process `"<prefix>-\(processName).json"` ones) and fails if a store
// file has no fixture, or if a fixture file isn't covered by a test here.
//
// Depends only on GarminKit's stores via `@testable import` (internal
// `OutboxStore`/`WeightOutboxStore`/`HydrationOutboxStore` initializers).
// The fixture directory is excluded from the test target in Package.swift and
// located on disk via `#filePath`, not bundled as a resource.

import XCTest
@testable import GarminKit

final class StoreFixtureTests: XCTestCase {
    // MARK: - Fixture registry

    /// `Fixtures/Stores/`, next to this file.
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Stores", isDirectory: true)

    /// `ios/GarminKit/Sources/GarminKit`, derived from this file's location
    /// (`ios/GarminKit/Tests/GarminKitTests/StoreFixtureTests.swift`).
    private static let sourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // GarminKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // GarminKit (package root)
        .appendingPathComponent("Sources/GarminKit", isDirectory: true)

    /// Every fixture a test below loads. A `.json` file in Fixtures/Stores
    /// that is not listed here is an orphan and fails
    /// `testEveryPersistedFileHasAFixture`.
    private static let allFixtures: [String] = [
        "outbox-app.json",
        "weight-outbox-app.json",
        "hydration-outbox-app.json",
        "diagnostics-log.json",
    ]

    /// Per-process store files whose names are interpolated
    /// (`"outbox-\(processName).json"`), which the literal-name regex can't
    /// see. Fixtures use the app process's name.
    private static let dynamicStoreFixtures: [String] = [
        "outbox-app.json",
        "weight-outbox-app.json",
        "hydration-outbox-app.json",
    ]

    /// Literal `"<name>.json"` strings in Sources/GarminKit that are NOT a
    /// persisted store file (name -> reason). Empty today: the only literal
    /// match is `diagnostics-log.json`, which has a fixture. (The Garth
    /// consumer URL `".../oauth_consumer.json"` doesn't match -- no quote
    /// directly before the name -- and is a network fetch, not a store.)
    private static let exempt: [String: String] = [:]

    // MARK: - Helpers

    /// Copies `name` from Fixtures/Stores into a fresh, unique temp
    /// directory under the same file name and returns the copy's URL.
    private func copyFixture(_ name: String) throws -> URL {
        let source = Self.fixturesDirectory.appendingPathComponent(name)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("garminkit-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return destination
    }

    /// Fails if `PersistedJSON` quarantined anything in `fileURL`'s
    /// directory, or if the fixture copy itself is no longer there.
    private func assertNotQuarantined(_ fileURL: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let directory = fileURL.deletingLastPathComponent()
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let quarantined = names.filter { $0.contains(".unreadable-") }
        XCTAssertTrue(quarantined.isEmpty, "the store could not decode its fixture and quarantined it: \(quarantined)", file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "fixture copy \(fileURL.lastPathComponent) is gone", file: file, line: line)
    }

    /// `.iso8601` JSONEncoder/Decoder use internet date-time, no fractional
    /// seconds -- the same default options as `ISO8601DateFormatter()`.
    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    // MARK: - outbox-app.json (OutboxStore: [OutboxEntry], default JSONEncoder)

    func testOutboxFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("outbox-app.json")

        let outbox = Outbox(store: OutboxStore(fileURL: url))
        let entries = await outbox.allEntries()

        try assertNotQuarantined(url)
        XCTAssertEqual(entries.count, 4)
        guard entries.count == 4 else { return }

        // A plain pending add, no optional fields at all (the pre-`source` shape).
        let pending = entries[0]
        XCTAssertEqual(pending.id, UUID(uuidString: "0B7E5C1A-3F2D-4A8B-9C6E-1D2F3A4B5C01"))
        XCTAssertEqual(pending.date, "2026-09-20")
        XCTAssertEqual(pending.mealType, .breakfast)
        XCTAssertEqual(pending.foodId, "5638212")
        XCTAssertEqual(pending.servingId, "5801234")
        XCTAssertEqual(pending.numberOfUnits, 1.5)
        XCTAssertEqual(pending.state, .pending)
        XCTAssertEqual(pending.attemptCount, 0)
        XCTAssertNil(pending.source)
        XCTAssertNil(pending.regionCode)
        XCTAssertNil(pending.languageCode)
        XCTAssertNil(pending.replaces)
        XCTAssertNil(pending.duplicateOf)
        XCTAssertNil(pending.lastError)
        XCTAssertNil(pending.parkedAt)
        XCTAssertEqual(pending.createdAt, Date(timeIntervalSinceReferenceDate: 811584900.5))
        XCTAssertEqual(pending.nextAttemptAt, Date(timeIntervalSinceReferenceDate: 811584900.5))

        // Sent, with namespace + captured region/language.
        let sent = entries[1]
        XCTAssertEqual(sent.mealType, .lunch)
        XCTAssertEqual(sent.state, .sent)
        XCTAssertEqual(sent.source, .garmin)
        XCTAssertEqual(sent.regionCode, "CZ")
        XCTAssertEqual(sent.languageCode, "cs")
        XCTAssertEqual(sent.numberOfUnits, 2)
        XCTAssertEqual(sent.attemptCount, 1)
        XCTAssertEqual(sent.createdAt, Date(timeIntervalSinceReferenceDate: 811598550.25))
        XCTAssertEqual(sent.nextAttemptAt, Date(timeIntervalSinceReferenceDate: 811598551.75))

        // A parked replace (add-log-entry-editing D1).
        let parked = entries[2]
        XCTAssertEqual(parked.mealType, .dinner)
        XCTAssertEqual(parked.state, .createdAwaitingDelete)
        XCTAssertEqual(parked.source, .fatSecret)
        XCTAssertEqual(parked.replaces, ReplacedLog(date: "2026-09-19", logId: "c0ffee0123456789abcdef0123456789"))
        XCTAssertEqual(parked.attemptCount, 5)
        XCTAssertEqual(parked.lastError, "old entry not removed yet: httpError(statusCode: 403, body: nil)")
        XCTAssertEqual(parked.parkedAt, Date(timeIntervalSinceReferenceDate: 811539700))
        XCTAssertTrue(parked.isParkedReplace)
        XCTAssertTrue(parked.needsManualRetry)

        // A failed duplicate.
        let failed = entries[3]
        XCTAssertEqual(failed.mealType, .snacks)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.duplicateOf, "deadbeef0123456789abcdef01234567")
        XCTAssertNil(failed.replaces)
        XCTAssertEqual(failed.lastError, "httpError(statusCode: 500, body: nil)")
        XCTAssertTrue(failed.needsManualRetry)

        // Only the pending create is due; the parked replace is not.
        let due = await outbox.pendingCount(now: Date(timeIntervalSinceReferenceDate: 811600000))
        XCTAssertEqual(due, 1)
    }

    // MARK: - weight-outbox-app.json (WeightOutboxStore: [WeightOutboxEntry], .iso8601)

    func testWeightOutboxFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("weight-outbox-app.json")

        let outbox = WeightOutbox(store: WeightOutboxStore(fileURL: url))
        let entries = await outbox.allEntries()

        try assertNotQuarantined(url)
        XCTAssertEqual(entries.count, 4)
        guard entries.count == 4 else { return }

        // Pre-2026-09-23 add: no `operation`, no `deliveredAt`.
        let legacy = entries[0]
        XCTAssertEqual(legacy.id, UUID(uuidString: "5A1B2C3D-4E5F-4061-8273-94A5B6C7D801"))
        XCTAssertEqual(legacy.weightKg, 82.4)
        XCTAssertEqual(legacy.loggedAt, iso("2026-09-18T06:30:00Z"))
        XCTAssertEqual(legacy.nextAttemptAt, iso("2026-09-18T06:30:05Z"))
        XCTAssertEqual(legacy.state, .sent)
        XCTAssertNil(legacy.operation)
        XCTAssertEqual(legacy.kind, .add)
        XCTAssertNil(legacy.deliveredAt)
        XCTAssertNil(legacy.removalRequested)
        XCTAssertNil(legacy.samplePk)
        XCTAssertNil(legacy.calendarDate)
        XCTAssertNil(legacy.lastError)

        // Delivered add, removed by the user mid-flight.
        let removed = entries[1]
        XCTAssertEqual(removed.operation, .add)
        XCTAssertEqual(removed.state, .sent)
        XCTAssertEqual(removed.deliveredAt, iso("2026-09-20T06:15:04Z"))
        XCTAssertEqual(removed.removalRequested, true)

        // The delete-by-match that settle queued for it.
        let byMatch = entries[2]
        XCTAssertEqual(byMatch.operation, .delete)
        XCTAssertEqual(byMatch.state, .pending)
        XCTAssertEqual(byMatch.attemptCount, 1)
        XCTAssertNil(byMatch.samplePk)
        XCTAssertTrue(byMatch.isDeleteByMatch)
        XCTAssertEqual(byMatch.calendarDate, "2026-09-20")
        XCTAssertEqual(byMatch.weightKg, 81.9)
        XCTAssertEqual(byMatch.loggedAt, iso("2026-09-20T06:15:00Z"))
        XCTAssertNotNil(byMatch.lastError)

        // A failed delete with a known samplePk.
        let failedDelete = entries[3]
        XCTAssertEqual(failedDelete.kind, .delete)
        XCTAssertEqual(failedDelete.state, .failed)
        XCTAssertEqual(failedDelete.samplePk, 1758092700000)
        XCTAssertEqual(failedDelete.calendarDate, "2026-09-17")
        XCTAssertFalse(failedDelete.isDeleteByMatch)
        XCTAssertEqual(failedDelete.attemptCount, 5)
        XCTAssertEqual(failedDelete.lastError, "httpError(statusCode: 500, body: nil)")

        let due = await outbox.pendingCount(now: iso("2026-09-21T00:00:00Z"))
        XCTAssertEqual(due, 1)
    }

    // MARK: - hydration-outbox-app.json (HydrationOutboxStore: [HydrationOutboxEntry], .iso8601)

    func testHydrationOutboxFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("hydration-outbox-app.json")

        let outbox = HydrationOutbox(store: HydrationOutboxStore(fileURL: url))
        let entries = await outbox.allEntries()

        try assertNotQuarantined(url)
        XCTAssertEqual(entries.count, 4)
        guard entries.count == 4 else { return }

        XCTAssertEqual(entries.map(\.valueInML), [250, 500, -500, 330])
        XCTAssertEqual(entries.map(\.state), [.sent, .sent, .pending, .failed])

        let drink = entries[0]
        XCTAssertEqual(drink.id, UUID(uuidString: "7C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E01"))
        XCTAssertEqual(drink.loggedAt, iso("2026-09-20T07:00:00Z"))
        XCTAssertEqual(drink.nextAttemptAt, iso("2026-09-20T07:00:01Z"))
        XCTAssertEqual(drink.deliveredAt, iso("2026-09-20T07:00:03Z"))
        XCTAssertNil(drink.removalRequested)
        XCTAssertNil(drink.correctsEntryId)
        XCTAssertNil(drink.lastError)
        XCTAssertFalse(drink.isCorrection)

        // Delivered, then removed mid-flight -> its correction follows.
        let removed = entries[1]
        XCTAssertEqual(removed.removalRequested, true)
        XCTAssertFalse(removed.isWithdrawn, "a .sent entry is not withdrawn -- its correction cancels it out")

        let correction = entries[2]
        XCTAssertTrue(correction.isCorrection)
        XCTAssertEqual(correction.correctsEntryId, removed.id)
        XCTAssertNil(correction.deliveredAt)

        let failed = entries[3]
        XCTAssertEqual(failed.attemptCount, 5)
        XCTAssertEqual(failed.lastError, "httpError(statusCode: 500, body: nil)")
        XCTAssertNil(failed.deliveredAt)

        let due = await outbox.pendingCount(now: iso("2026-09-21T00:00:00Z"))
        XCTAssertEqual(due, 1)
    }

    // MARK: - diagnostics-log.json (DiagnosticsLog: [DiagnosticsEntry], .iso8601)

    /// `DiagnosticsLog` deliberately doesn't use `PersistedJSON` (see that
    /// file's header): an undecodable log just reads as empty, so the
    /// non-empty assertions here are what catch a format break.
    func testDiagnosticsLogFixtureDecodesThroughTheRealStore() async throws {
        let url = try copyFixture("diagnostics-log.json")

        let log = DiagnosticsLog(fileURL: url)
        let entries = await log.all()

        try assertNotQuarantined(url)
        XCTAssertEqual(entries.count, 3)
        guard entries.count == 3 else { return }

        // `all()` is newest first.
        XCTAssertEqual(entries.map(\.level), [.error, .warning, .info])
        XCTAssertEqual(entries.map(\.category), ["GarminClient", "WeightOutbox", "Outbox"])

        let newest = entries[0]
        XCTAssertEqual(newest.id, UUID(uuidString: "9E8D7C6B-5A49-4382-9160-5F4E3D2C1B03"))
        XCTAssertEqual(newest.timestamp, iso("2026-09-20T10:30:45Z"))
        XCTAssertEqual(newest.message, "GET /nutrition-service/food/logs/2026-09-20 failed: 401")

        let oldest = entries[2]
        XCTAssertEqual(oldest.timestamp, iso("2026-09-20T08:15:01Z"))
        XCTAssertEqual(oldest.message, "drain: 1 delivered, 0 gave up, rateLimited=false, authOutcome=none")
    }

    // MARK: - Coverage of the fixture set itself

    func testEveryPersistedFileHasAFixture() throws {
        let fileManager = FileManager.default

        // 1. The fixtures on disk are exactly the ones the tests above use.
        let onDisk = try fileManager.contentsOfDirectory(atPath: Self.fixturesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertEqual(
            Set(onDisk), Set(Self.allFixtures),
            "Fixtures/Stores and StoreFixtureTests.allFixtures disagree -- add a test for a new fixture, never delete an old one"
        )

        // 2. Collect every .swift file under Sources/GarminKit.
        guard let enumerator = fileManager.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: nil) else {
            return XCTFail("couldn't enumerate \(Self.sourcesDirectory.path)")
        }
        var sourceFiles: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            sourceFiles.append(fileURL)
        }
        XCTAssertFalse(sourceFiles.isEmpty, "found no Swift sources at \(Self.sourcesDirectory.path)")

        // `"<name>.json"` -- a literal file name.
        let literalName = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]+)\\.json\"")
        // `"<prefix>\(identifier).json"` -- an interpolated per-process name.
        let interpolatedName = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]+)\\\\\\([A-Za-z0-9_]+\\)\\.json\"")

        var literalFileNames = Set<String>()
        var interpolatedPrefixes = Set<String>()
        for fileURL in sourceFiles {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in literalName.matches(in: text, range: range) {
                if let captured = Range(match.range(at: 1), in: text) {
                    literalFileNames.insert(String(text[captured]) + ".json")
                }
            }
            for match in interpolatedName.matches(in: text, range: range) {
                if let captured = Range(match.range(at: 1), in: text) {
                    interpolatedPrefixes.insert(String(text[captured]))
                }
            }
        }

        // Sanity: the scan actually sees the stores we know about, so a
        // broken path or regex can't make this test pass vacuously.
        XCTAssertTrue(literalFileNames.contains("diagnostics-log.json"), "scan found: \(literalFileNames)")
        XCTAssertEqual(interpolatedPrefixes, ["outbox-", "weight-outbox-", "hydration-outbox-"])

        // 3. Every literal store file name has a fixture (or a stated reason not to).
        let fixtures = Set(Self.allFixtures)
        for name in literalFileNames.sorted() where Self.exempt[name] == nil {
            XCTAssertTrue(fixtures.contains(name), "\(name) is persisted by Sources/GarminKit but has no fixture in Fixtures/Stores (or an entry in `exempt`)")
        }

        // 4. Every interpolated per-process store has an "app" fixture...
        for prefix in interpolatedPrefixes.sorted() {
            let name = prefix + "app.json"
            XCTAssertTrue(
                Self.dynamicStoreFixtures.contains(name),
                "\(prefix)\\(processName).json is persisted by Sources/GarminKit but \(name) is not in `dynamicStoreFixtures`"
            )
        }
        // ...and each listed one really exists and is tested.
        for name in Self.dynamicStoreFixtures {
            XCTAssertTrue(
                fileManager.fileExists(atPath: Self.fixturesDirectory.appendingPathComponent(name).path),
                "missing fixture \(name)"
            )
            XCTAssertTrue(fixtures.contains(name), "\(name) is not in `allFixtures`")
        }
    }
}

// ProjectionStoreTests.swift
//
// The last good plan survives everything (tasks 2.4; design D5), over an
// in-memory `VaultTransport` and a REAL `ConditionalFileSync` on temp
// files: a bad file keeps the last good one; a v2 file keeps it and reports
// `unsupportedMajor`; an offline cold start still has the plan; freshness
// never reads `generatedAt`.

import XCTest
import VaultKit
@testable import TrainingCore

final class ProjectionStoreTests: XCTestCase {
    private let path = VaultHub.projectionPath

    private func makeStore(directory: URL, transport: InMemoryTransport) -> (ConditionalFileSync, ProjectionStore) {
        let sync = ConditionalFileSync(transport: transport, directory: directory)
        return (sync, ProjectionStore(fetchSync: sync, path: path))
    }

    private func refresh(_ sync: ConditionalFileSync, _ store: ProjectionStore) async -> FetchReport {
        let result = await sync.refresh(path) { bytes in try ProjectionStore.validate(bytes) }
        await store.noteRefresh(result.report)
        return result.report
    }

    func testGoodFileIsCachedAndDecoded() async throws {
        let transport = InMemoryTransport()
        transport.enqueue(.fetched(bytes: try Fixtures.example(), etag: "\"e1\""))
        let (sync, store) = makeStore(directory: try makeTemporaryDirectory(), transport: transport)

        let report = await refresh(sync, store)
        guard case .updated = report else { return XCTFail("\(report)") }
        let cached = await store.loadCached()
        XCTAssertEqual(cached?.projection.asOf, D.asOf)
        let rejection = await store.rejection
        XCTAssertNil(rejection)
    }

    func testInvalidFileKeepsTheLastGoodOne() async throws {
        let transport = InMemoryTransport()
        transport.enqueue(.fetched(bytes: try Fixtures.example(), etag: "\"e1\""))
        let notAProjection = try Fixtures.mutatedExample { $0["schema"] = "something-else" }
        transport.enqueue(.fetched(bytes: notAProjection, etag: "\"e2\""))
        let (sync, store) = makeStore(directory: try makeTemporaryDirectory(), transport: transport)

        _ = await refresh(sync, store)
        let report = await refresh(sync, store)
        guard case .rejected = report else { return XCTFail("\(report)") }

        let cached = await store.loadCached()
        XCTAssertEqual(cached?.projection.plan?.id, "test-base-2030")
        let rejection = await store.rejection
        XCTAssertEqual(rejection, .invalid(reason: "not a plan projection"))
        let remembered = await store.hasRejectedCopy()
        XCTAssertTrue(remembered)
    }

    func testVersionTwoKeepsTheLastGoodOneAndSaysUpdate() async throws {
        let transport = InMemoryTransport()
        transport.enqueue(.fetched(bytes: try Fixtures.example(), etag: "\"e1\""))
        transport.enqueue(.fetched(bytes: try Fixtures.mutatedExample { $0["schemaVersion"] = 2 }, etag: "\"e2\""))
        let (sync, store) = makeStore(directory: try makeTemporaryDirectory(), transport: transport)

        _ = await refresh(sync, store)
        _ = await refresh(sync, store)
        let rejection = await store.rejection
        XCTAssertEqual(rejection, .unsupportedMajor(found: 2))
        let cached = await store.loadCached()
        XCTAssertEqual(cached?.projection.schemaVersion, 1)

        // A good file clears the rejection.
        transport.enqueue(.fetched(bytes: try Fixtures.example(), etag: "\"e3\""))
        _ = await refresh(sync, store)
        let cleared = await store.rejection
        XCTAssertNil(cleared)
    }

    func testRejectionWithoutALastGoodCopyIsUnreadable() async throws {
        let transport = InMemoryTransport()
        transport.enqueue(.fetched(bytes: try Fixtures.mutatedExample { $0["schemaVersion"] = 2 }, etag: "\"e1\""))
        let (sync, store) = makeStore(directory: try makeTemporaryDirectory(), transport: transport)
        _ = await refresh(sync, store)
        let cached = await store.loadCached()
        XCTAssertNil(cached)
        let rejection = await store.rejection
        XCTAssertEqual(
            ProjectionAvailability.evaluate(cached: cached, rejection: rejection, fileNotFound: false),
            .unreadable(.unsupportedMajor(found: 2))
        )
    }

    func testOfflineColdStartStillHasThePlan() async throws {
        let directory = try makeTemporaryDirectory()
        let online = InMemoryTransport()
        online.enqueue(.fetched(bytes: try Fixtures.example(), etag: "\"e1\""))
        let (firstSync, firstStore) = makeStore(directory: directory, transport: online)
        _ = await refresh(firstSync, firstStore)

        // A new process: fresh objects over the same directory, no network.
        let offline = InMemoryTransport()
        let (sync, store) = makeStore(directory: directory, transport: offline)
        let cached = await store.loadCached()
        XCTAssertEqual(cached?.projection.asOf, D.asOf)
        XCTAssertEqual(offline.fetchCount, 0)

        let report = await refresh(sync, store)
        guard case .failed(.offline) = report else { return XCTFail("\(report)") }
        let still = await store.loadCached()
        XCTAssertEqual(still?.projection.asOf, D.asOf)
    }

    func testAvailabilityStates() {
        XCTAssertEqual(ProjectionAvailability.evaluate(cached: nil, rejection: nil, fileNotFound: false), .waitingForFirstSync)
        XCTAssertEqual(ProjectionAvailability.evaluate(cached: nil, rejection: nil, fileNotFound: true), .notGenerated)
    }

    // MARK: Freshness (never generatedAt)

    func testOldGeneratedAtWithAFreshSyncIsNotStale() {
        let now = Date(timeIntervalSince1970: 1_950_000_000)
        let freshness = TrainingFreshness.evaluate(
            asOf: D.asOf,
            trainingToday: D.asOf,
            lastSuccessAt: now.addingTimeInterval(-3600),
            now: now
        )
        XCTAssertFalse(freshness.isBehind)
        XCTAssertNil(freshness.staleDays)
        XCTAssertEqual(FormatSupport.english.notices(freshness), [])
    }

    func testAsOfBehindTheTrainingDay() {
        let now = Date(timeIntervalSince1970: 1_950_000_000)
        let freshness = TrainingFreshness.evaluate(asOf: D.date("2030-10-20"), trainingToday: D.date("2030-10-21"), lastSuccessAt: now, now: now)
        XCTAssertTrue(freshness.isBehind)
        XCTAssertEqual(FormatSupport.english.notices(freshness).map(\.text), ["Plan as of Sun 20 Oct"])
    }

    func testStaleAfterADayWithoutASync() {
        let now = Date(timeIntervalSince1970: 1_950_000_000)
        let freshness = TrainingFreshness.evaluate(asOf: D.asOf, trainingToday: D.asOf, lastSuccessAt: now.addingTimeInterval(-2 * 86_400 - 60), now: now)
        XCTAssertEqual(freshness.staleDays, 2)
        XCTAssertEqual(FormatSupport.english.notices(freshness).map(\.text), ["Last synced 2 days ago"])
        XCTAssertEqual(FormatSupport.czech.notices(freshness).map(\.text), ["Naposledy synchronizováno před 2 dny"])
    }

    func testRejectionNotices() {
        let v2 = TrainingFreshness(asOf: D.asOf, rejection: .unsupportedMajor(found: 2))
        let lines = FormatSupport.english.notices(v2)
        XCTAssertEqual(lines.map(\.text), ["Update Jirka's Arc to read this plan", "Plan as of Wed 23 Oct"])
        XCTAssertTrue(lines[0].isLoud)

        let invalid = TrainingFreshness(asOf: D.asOf, rejection: .invalid(reason: "not a plan projection"))
        XCTAssertEqual(FormatSupport.english.notices(invalid).map(\.text), ["Couldn't read the latest plan; showing Wed 23 Oct"])
        XCTAssertFalse(FormatSupport.english.notices(invalid)[0].isLoud)
    }
}

enum FormatSupport {
    static let english = TrainingFormatting(language: .english, zones: nil)
    static let czech = TrainingFormatting(language: .czech, zones: nil)
}

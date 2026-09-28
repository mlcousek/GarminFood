// ConditionalFileSyncTests.swift
//
// add-vault-connection tasks 2.10-2.11 (design D8, D9; spec "Fetched data
// replaces the cached copy only after it validates", "Training code
// depends on a transport"): bytes and ETag are committed only after the
// validator accepts them; a rejected file keeps the last good copy, is
// logged once and is not downloaded again (its ETag goes out as
// If-None-Match); the last good copy survives a failed fetch and a cold
// launch offline; disconnect clears it. Run over the in-memory transport
// and, for the wire-level If-None-Match behaviour, over the GitHub client.

import XCTest
@testable import VaultKit

final class ConditionalFileSyncTests: XCTestCase {
    private let path = VaultHub.projectionPath
    private let good = Data(#"{"schema":"example","v":1}"#.utf8)
    private let better = Data(#"{"schema":"example","v":2}"#.utf8)
    private let broken = Data("not json".utf8)
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let validate: @Sendable (Data) throws -> Void = { try VaultValidators.jsonObject($0) }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    func testFirstFetchCommitsValidBytes() async throws {
        let transport = InMemoryVaultTransport()
        transport.put(path, good)
        let sync = ConditionalFileSync(transport: transport, directory: try makeTemporaryDirectory())

        let result = await sync.refresh(path, now: now, validate: validate)

        XCTAssertEqual(result.report, .updated(byteCount: good.count))
        let cached = await sync.cachedFile(path)
        XCTAssertEqual(cached, CachedVaultFile(bytes: good, fetchedAt: now))
        let entry = await sync.entry(for: path)
        XCTAssertEqual(entry?.etag, InMemoryVaultTransport.etag(for: good))
    }

    func testUnchangedFileIsA304AndKeepsTheCopy() async throws {
        let transport = InMemoryVaultTransport()
        transport.put(path, good)
        let sync = ConditionalFileSync(transport: transport, directory: try makeTemporaryDirectory())
        _ = await sync.refresh(path, now: now, validate: validate)

        let second = await sync.refresh(path, now: now.addingTimeInterval(60), validate: validate)

        XCTAssertEqual(second.report, .unchanged)
        let cached = await sync.cachedFile(path)
        XCTAssertEqual(cached?.bytes, good)
        XCTAssertEqual(cached?.fetchedAt, now, "fetchedAt is when the bytes arrived")
        let entry = await sync.entry(for: path)
        XCTAssertEqual(entry?.checkedAt, now.addingTimeInterval(60))
    }

    func testBrokenFileKeepsTheLastGoodCopyAndIsNotDownloadedAgain() async throws {
        let log = recordVaultLog()
        let transport = InMemoryVaultTransport()
        transport.put(path, good)
        let sync = ConditionalFileSync(transport: transport, directory: try makeTemporaryDirectory())
        _ = await sync.refresh(path, now: now, validate: validate)

        // spec "A broken file is published".
        transport.put(path, broken)
        let rejected = await sync.refresh(path, now: now.addingTimeInterval(60), validate: validate)
        guard case .rejected = rejected.report else { return XCTFail("\(rejected.report)") }
        let kept = await sync.cachedFile(path)
        XCTAssertEqual(kept?.bytes, good)
        XCTAssertEqual(log.errorLines.count, 1)

        let again = await sync.refresh(path, now: now.addingTimeInterval(120), validate: validate)
        XCTAssertEqual(again.report, .unchanged, "the rejected ETag goes out as If-None-Match")
        XCTAssertEqual(log.errorLines.count, 1, "logged once, not on every foreground")

        // A fixed file replaces it and clears the rejected ETag.
        transport.put(path, better)
        let fixed = await sync.refresh(path, now: now.addingTimeInterval(180), validate: validate)
        XCTAssertEqual(fixed.report, .updated(byteCount: better.count))
        let entry = await sync.entry(for: path)
        XCTAssertNil(entry?.rejectedETag)
        let cached = await sync.cachedFile(path)
        XCTAssertEqual(cached?.bytes, better)
    }

    func testFailedFetchAndColdLaunchOfflineKeepTheCopy() async throws {
        let directory = try makeTemporaryDirectory()
        let transport = InMemoryVaultTransport()
        transport.put(path, good)
        let sync = ConditionalFileSync(transport: transport, directory: directory)
        _ = await sync.refresh(path, now: now, validate: validate)

        transport.failNextFetch(with: .offline)
        let offline = await sync.refresh(path, now: now.addingTimeInterval(60), validate: validate)
        XCTAssertEqual(offline.report, .failed(.offline))
        XCTAssertEqual(offline.statusOutcome, .offline)

        // spec "Cold launch offline": a new process, no network.
        let relaunched = ConditionalFileSync(transport: InMemoryVaultTransport(), directory: directory)
        let cached = await relaunched.cachedFile(path)
        XCTAssertEqual(cached, CachedVaultFile(bytes: good, fetchedAt: now))
    }

    func testMismatchedCacheFileReadsAsNoCopy() async throws {
        let directory = try makeTemporaryDirectory()
        let transport = InMemoryVaultTransport()
        transport.put(path, good)
        let sync = ConditionalFileSync(transport: transport, directory: directory)
        _ = await sync.refresh(path, now: now, validate: validate)
        let binURL = directory.appendingPathComponent("cache").appendingPathComponent(ConditionalFileSync.cacheFileName(for: path))
        try Data("truncated".utf8).write(to: binURL)
        let relaunched = ConditionalFileSync(transport: transport, directory: directory)
        let cached = await relaunched.cachedFile(path)
        XCTAssertNil(cached)
    }

    func testClearForgetsEverything() async throws {
        let directory = try makeTemporaryDirectory()
        let transport = InMemoryVaultTransport()
        transport.put(path, good)
        let sync = ConditionalFileSync(transport: transport, directory: directory)
        _ = await sync.refresh(path, now: now, validate: validate)

        try await sync.clear()

        let cached = await sync.cachedFile(path)
        XCTAssertNil(cached)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cache").path))
        let relaunched = ConditionalFileSync(transport: transport, directory: directory)
        let reloaded = await relaunched.cachedFile(path)
        XCTAssertNil(reloaded)
    }

    func testRefusedPathIsAFailureForEveryTransport() async throws {
        let transport = InMemoryVaultTransport()
        let sync = ConditionalFileSync(transport: transport, directory: try makeTemporaryDirectory())
        let result = await sync.refresh(HubPath("Daily/2026-10-01.md")!, now: now, validate: validate)
        XCTAssertEqual(result.report, .failed(.refusedByPolicy))
        XCTAssertEqual(transport.fetchCount, 0)
    }

    // MARK: - Over the GitHub client

    func testOverGitHubTheStoredETagGoesOutAndA304KeepsTheCopy() async throws {
        StubURLProtocol.reset(replies: [
            .status(200, headers: ["ETag": "W/\"abc\""], body: good),
            .status(304, headers: ["ETag": "W/\"abc\""])
        ])
        let sync = ConditionalFileSync(transport: GitHubVaultTransport(api: TestSupport.makeClient()), directory: try makeTemporaryDirectory())

        let first = await sync.refresh(path, now: now, validate: validate)
        let second = await sync.refresh(path, now: now.addingTimeInterval(60), validate: validate)

        XCTAssertEqual(first.report, .updated(byteCount: good.count))
        XCTAssertEqual(second.report, .unchanged)
        XCTAssertNil(StubURLProtocol.requests.first?.header("If-None-Match"))
        XCTAssertEqual(StubURLProtocol.requests.last?.header("If-None-Match"), "W/\"abc\"")
        let cached = await sync.cachedFile(path)
        XCTAssertEqual(cached?.bytes, good)
    }

    func testOverGitHubAnErrorBodyIsNeverCached() async throws {
        StubURLProtocol.reset(replies: [.status(500, body: Data(#"{"message":"boom"}"#.utf8))])
        let sync = ConditionalFileSync(transport: GitHubVaultTransport(api: TestSupport.makeClient()), directory: try makeTemporaryDirectory())
        let result = await sync.refresh(path, now: now, validate: validate)
        XCTAssertEqual(result.report, .failed(.serverError(status: 500)))
        let cached = await sync.cachedFile(path)
        XCTAssertNil(cached)
    }

    func testMinimalValidator() {
        XCTAssertNoThrow(try VaultValidators.jsonObject(good))
        XCTAssertThrowsError(try VaultValidators.jsonObject(broken))
        XCTAssertThrowsError(try VaultValidators.jsonObject(Data("[1,2]".utf8)), "an array is not the projection")
        XCTAssertThrowsError(try VaultValidators.jsonObject(good, maxBytes: 4)) { error in
            XCTAssertEqual(error as? VaultValidators.Problem, .tooLarge(byteCount: self.good.count))
        }
    }
}

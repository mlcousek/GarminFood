// OfflineIndexStoreTests.swift
//
// add-offline-czech-food-index task 3.3 (design.md D3): the update check
// against a faked fetcher, with real files in a unique temp directory per
// test (the LogEntryCoordinatorTests convention -- stores are never
// mocked). Covers the spec's "Corrupted download" scenario (the previous
// index keeps working and the failure is recorded), the no-change case,
// the 24 h throttle, and reloading the installed index in a new process.

import XCTest
@testable import FoodLogCore

private struct IndexServerUnavailable: Error {}

/// Serves a manifest and an index file from memory, counting requests.
private actor FakeIndexServer: OfflineIndexFetching {
    private var manifest: Data
    private var indexFile: Data
    private let failsManifest: Bool
    private(set) var manifestRequests = 0
    private(set) var downloads: [URL] = []
    /// The `allowsCellular` ("any network") flag of every request, in order.
    private(set) var networkPermissions: [Bool] = []

    init(manifest: Data, indexFile: Data, failsManifest: Bool = false) {
        self.manifest = manifest
        self.indexFile = indexFile
        self.failsManifest = failsManifest
    }

    func publish(manifest: Data, indexFile: Data) {
        self.manifest = manifest
        self.indexFile = indexFile
    }

    func fetchManifest(from url: URL, allowsCellular: Bool) async throws -> Data {
        manifestRequests += 1
        networkPermissions.append(allowsCellular)
        if failsManifest { throw IndexServerUnavailable() }
        return manifest
    }

    func download(from url: URL, allowsCellular: Bool) async throws -> URL {
        downloads.append(url)
        networkPermissions.append(allowsCellular)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("offline-index-test-download-\(UUID().uuidString).gz")
        try indexFile.write(to: file)
        return file
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(interval)
        lock.unlock()
    }
}

final class OfflineIndexStoreTests: XCTestCase {
    private var directory: URL!
    private let clock = MutableClock(Date(timeIntervalSince1970: 1_790_000_000))
    private let manifestURL = URL(string: "https://example.invalid/releases/download/food-index/manifest.json")!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("offline-index-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func products(_ names: [String]) -> [OfflineIndexProduct] {
        names.enumerated().map { offset, name in
            OfflineIndexProduct(code: "85940000000\(10 + offset)", name: name, kcal: 100)
        }
    }

    private func release(_ names: [String], version: String, sha256Override: String? = nil) throws -> (manifest: Data, file: Data) {
        let file = try makeTestIndexGzip(products(names))
        let manifest = OfflineIndexManifest(
            schema: 1,
            version: version,
            count: names.count,
            file: "czech-food-index-v1.json.gz",
            sha256: sha256Override ?? OfflineIndexChecksum.sha256Hex(file),
            bytes: file.count
        )
        let manifestData = try JSONEncoder().encode(manifest)
        return (manifest: manifestData, file: file)
    }

    private func makeStore(_ server: FakeIndexServer, holder: OfflineFoodIndexHolder = OfflineFoodIndexHolder(), directory: URL? = nil) -> OfflineIndexStore {
        let clock = self.clock
        return OfflineIndexStore(holder: holder, directory: directory ?? self.directory!, fetcher: server, manifestURL: manifestURL, clock: { clock.now })
    }

    func testFirstCheckDownloadsVerifiesAndInstalls() async throws {
        let published = try release(["Tvaroh měkký", "Rohlík"], version: "v1")
        let server = FakeIndexServer(manifest: published.manifest, indexFile: published.file)
        let holder = OfflineFoodIndexHolder()
        let store = makeStore(server, holder: holder)

        let outcome = await store.checkForUpdate()

        XCTAssertEqual(outcome, .installed(count: 2))
        XCTAssertEqual(holder.index?.count, 2, "search can use it immediately")
        let downloads = await server.downloads
        XCTAssertEqual(downloads.map(\.absoluteString), ["https://example.invalid/releases/download/food-index/czech-food-index-v1.json.gz"])
        let status = await store.currentStatus()
        XCTAssertEqual(status.installedVersion, "v1")
        XCTAssertEqual(status.installedCount, 2)
        XCTAssertEqual(status.installedBytes, published.file.count)
        XCTAssertEqual(status.lastCheckAt, clock.now)
        XCTAssertNil(status.lastError)
        let installed = directory.appendingPathComponent("czech-food-index.json.gz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        let excluded = try installed.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(excluded, true, "re-downloadable, so kept out of backups")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("czech-food-index.staging.gz").path))
    }

    /// Owner report 2026-09-24: "Download now" did nothing on a hotspot /
    /// in Low Data Mode. A deliberate tap may use any network; the
    /// automatic check stays Wi-Fi only unless cellular was allowed.
    func testDownloadNowMayUseAnyNetworkButTheAutomaticCheckMayNot() async throws {
        let published = try release(["Tvaroh"], version: "v1")
        let automaticServer = FakeIndexServer(manifest: published.manifest, indexFile: published.file)
        _ = await makeStore(automaticServer).checkForUpdate()
        let automatic = await automaticServer.networkPermissions
        XCTAssertEqual(automatic, [false, false], "manifest + download, Wi-Fi only")

        let manualServer = FakeIndexServer(manifest: published.manifest, indexFile: published.file)
        let manualDirectory = directory.appendingPathComponent("manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualDirectory, withIntermediateDirectories: true)
        _ = await makeStore(manualServer, directory: manualDirectory).checkForUpdate(force: true)
        let manual = await manualServer.networkPermissions
        XCTAssertEqual(manual, [true, true], "manifest + download, any network")
    }

    func testUnchangedManifestDownloadsNothing() async throws {
        let published = try release(["Tvaroh"], version: "v1")
        let server = FakeIndexServer(manifest: published.manifest, indexFile: published.file)
        let store = makeStore(server)
        _ = await store.checkForUpdate()

        let outcome = await store.checkForUpdate(force: true)

        XCTAssertEqual(outcome, .upToDate)
        let downloads = await server.downloads
        XCTAssertEqual(downloads.count, 1, "the same SHA-256 is never downloaded twice")
    }

    /// spec "Corrupted download".
    func testChecksumMismatchKeepsThePreviousIndexAndRecordsTheFailure() async throws {
        let v1 = try release(["Tvaroh"], version: "v1")
        let server = FakeIndexServer(manifest: v1.manifest, indexFile: v1.file)
        let holder = OfflineFoodIndexHolder()
        let store = makeStore(server, holder: holder)
        _ = await store.checkForUpdate()
        let installedBefore = try Data(contentsOf: directory.appendingPathComponent("czech-food-index.json.gz"))

        let corrupted = try release(["Tvaroh", "Rohlík", "Eidam"], version: "v2", sha256Override: String(repeating: "ab", count: 32))
        await server.publish(manifest: corrupted.manifest, indexFile: corrupted.file)
        let outcome = await store.checkForUpdate(force: true)

        guard case .failed(let message) = outcome else {
            return XCTFail("expected a failure, got \(outcome)")
        }
        XCTAssertTrue(message.contains("checksum"), message)
        XCTAssertEqual(holder.index?.count, 1, "the previous index keeps working")
        let installedAfter = try Data(contentsOf: directory.appendingPathComponent("czech-food-index.json.gz"))
        XCTAssertEqual(installedAfter, installedBefore, "a bad download never replaces the good file")
        let status = await store.currentStatus()
        XCTAssertEqual(status.installedVersion, "v1")
        XCTAssertNotNil(status.lastError, "visible in Settings")
        XCTAssertEqual(status.lastErrorAt, clock.now)
    }

    func testAFileThatMatchesItsChecksumButDoesNotDecodeIsRejected() async throws {
        let garbage = try makeTestGzip(Data("not json".utf8))
        let manifest = OfflineIndexManifest(schema: 1, version: "v1", count: 0, file: "czech-food-index-v1.json.gz", sha256: OfflineIndexChecksum.sha256Hex(garbage), bytes: garbage.count)
        let manifestData = try JSONEncoder().encode(manifest)
        let server = FakeIndexServer(manifest: manifestData, indexFile: garbage)
        let holder = OfflineFoodIndexHolder()
        let store = makeStore(server, holder: holder)

        let outcome = await store.checkForUpdate()

        guard case .failed = outcome else { return XCTFail("expected a failure, got \(outcome)") }
        XCTAssertNil(holder.index)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("czech-food-index.json.gz").path))
    }

    func testChecksAtMostOnceADayUnlessForced() async throws {
        let published = try release(["Tvaroh"], version: "v1")
        let server = FakeIndexServer(manifest: published.manifest, indexFile: published.file)
        let store = makeStore(server)
        _ = await store.checkForUpdate()

        clock.advance(by: 23 * 60 * 60)
        let soon = await store.checkForUpdate()
        XCTAssertEqual(soon, .checkedRecently)
        var requests = await server.manifestRequests
        XCTAssertEqual(requests, 1)

        let forced = await store.checkForUpdate(force: true)
        XCTAssertEqual(forced, .upToDate, "Download now skips the throttle")

        clock.advance(by: 25 * 60 * 60)
        _ = await store.checkForUpdate()
        requests = await server.manifestRequests
        XCTAssertEqual(requests, 3)
    }

    func testANewVersionReplacesTheOldOne() async throws {
        let v1 = try release(["Tvaroh"], version: "v1")
        let server = FakeIndexServer(manifest: v1.manifest, indexFile: v1.file)
        let holder = OfflineFoodIndexHolder()
        let store = makeStore(server, holder: holder)
        _ = await store.checkForUpdate()

        let v2 = try release(["Tvaroh", "Rohlík"], version: "v2")
        await server.publish(manifest: v2.manifest, indexFile: v2.file)
        let outcome = await store.checkForUpdate(force: true)

        XCTAssertEqual(outcome, .installed(count: 2))
        XCTAssertEqual(holder.index?.count, 2)
        let status = await store.currentStatus()
        XCTAssertEqual(status.installedVersion, "v2")
    }

    func testManifestFailureIsRecordedAndTheThrottleIsNotStarted() async throws {
        let published = try release(["Tvaroh"], version: "v1")
        let server = FakeIndexServer(manifest: published.manifest, indexFile: published.file, failsManifest: true)
        let store = makeStore(server)

        let outcome = await store.checkForUpdate()

        guard case .failed = outcome else { return XCTFail("expected a failure, got \(outcome)") }
        let status = await store.currentStatus()
        XCTAssertNotNil(status.lastError)
        XCTAssertNil(status.lastCheckAt, "an unanswered check is retried on the next foreground")
    }

    func testAManifestPointingOutsideTheReleaseIsRejected() async throws {
        let published = try release(["Tvaroh"], version: "v1")
        let evil = OfflineIndexManifest(schema: 1, version: "v1", count: 1, file: "../../evil.gz", sha256: OfflineIndexChecksum.sha256Hex(published.file), bytes: published.file.count)
        let evilData = try JSONEncoder().encode(evil)
        let server = FakeIndexServer(manifest: evilData, indexFile: published.file)
        let store = makeStore(server)

        let outcome = await store.checkForUpdate()

        guard case .failed = outcome else { return XCTFail("expected a failure, got \(outcome)") }
        let downloads = await server.downloads
        XCTAssertEqual(downloads, [])
    }

    func testANewProcessLoadsTheInstalledIndexAndStatus() async throws {
        let published = try release(["Tvaroh", "Rohlík"], version: "v1")
        let server = FakeIndexServer(manifest: published.manifest, indexFile: published.file)
        _ = await makeStore(server).checkForUpdate()

        let relaunchedHolder = OfflineFoodIndexHolder()
        let relaunched = makeStore(server, holder: relaunchedHolder)
        XCTAssertNil(relaunchedHolder.index, "nothing is decoded until asked, so launch never waits on it")
        await relaunched.loadInstalledIndexIfNeeded()

        XCTAssertEqual(relaunchedHolder.index?.count, 2)
        let status = await relaunched.currentStatus()
        XCTAssertEqual(status.installedVersion, "v1")
    }

    func testNothingInstalledLoadsNothing() async {
        let holder = OfflineFoodIndexHolder()
        let store = makeStore(FakeIndexServer(manifest: Data(), indexFile: Data()), holder: holder)

        await store.loadInstalledIndexIfNeeded()

        XCTAssertNil(holder.index)
        let status = await store.currentStatus()
        XCTAssertFalse(status.isInstalled)
        XCTAssertNil(status.lastError, "no index yet is a normal state, not an error")
    }
}

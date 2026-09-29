// CreateOnlyFileUploaderTests.swift
//
// add-vault-connection task 2.9 (design D7, spec "Vault writes are durable,
// create-only and idempotent"): git blob SHA vectors, then the uploader
// over BOTH transports -- the GitHub client behind a URLProtocol stub and
// the in-memory transport: 201; 422 + equal SHA (a lost response) ->
// delivered without a second file; 422 + different SHA -> failed
// permanently and logged; 409 -> retry; auth/offline/rate limit -> stop the
// cycle; a path outside the install's folder -> refused, nothing sent.

import XCTest
@testable import VaultKit

final class CreateOnlyFileUploaderTests: XCTestCase {
    private let path = HubPath("events/ios-0000abcd/2026/10/20261001T101500Z-1.jsonl")!
    private let bytes = Data("{\"id\":\"e1\"}\n".utf8)

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    // MARK: - Blob SHA

    func testGitBlobVectors() {
        // `git hash-object` of: nothing, "hello\n", "test content\n".
        XCTAssertEqual(GitBlob.sha1Hex(of: Data()), "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391")
        XCTAssertEqual(GitBlob.sha1Hex(of: Data("hello\n".utf8)), "ce013625030ba8dba906f756967f9e9ca394464a")
        XCTAssertEqual(GitBlob.sha1Hex(of: Data("test content\n".utf8)), "d670460b4b4aece5915caf5c68d12f560a9fe3e4")
    }

    func testSealingFixesTheBytesAndTheirSha() throws {
        let sealed = SealedFile(path: path, bytes: bytes, commitMessage: "app: 1 event", createdAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(sealed.blobSHA, GitBlob.sha1Hex(of: bytes))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(SealedFile.self, from: encoder.encode(sealed)), sealed)
    }

    // MARK: - Over the GitHub client

    private func githubUploader() -> CreateOnlyFileUploader {
        CreateOnlyFileUploader(transport: GitHubVaultTransport(api: TestSupport.makeClient()))
    }

    private var sealed: SealedFile {
        SealedFile(path: path, bytes: bytes, commitMessage: "app: 1 event")
    }

    func testCreatedIsDelivered() async {
        StubURLProtocol.reset(replies: [.status(201)])
        let delivery = await githubUploader().deliver(sealed)
        XCTAssertEqual(delivery, .delivered)
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["PUT"])
    }

    func testLostResponseWithEqualShaIsDelivered() async {
        // spec "Lost response": the create landed earlier, the retry gets 422,
        // the existing file has our exact bytes.
        StubURLProtocol.reset(replies: [.status(422), .status(200, body: bytes)])
        let delivery = await githubUploader().deliver(sealed)
        XCTAssertEqual(delivery, .delivered)
        XCTAssertEqual(StubURLProtocol.requests.map(\.method), ["PUT", "GET"])
        XCTAssertEqual(StubURLProtocol.requests.last?.header("Accept"), "application/vnd.github.raw+json")
    }

    func testDifferentFileAtThePathFailsPermanentlyAndIsLogged() async {
        let log = recordVaultLog()
        StubURLProtocol.reset(replies: [.status(422), .status(200, body: Data("{\"id\":\"other\"}\n".utf8))])
        let delivery = await githubUploader().deliver(sealed)
        XCTAssertEqual(delivery, .failedPermanently(reason: CreateOnlyFileUploader.differentFileReason))
        XCTAssertTrue(log.errorLines.contains { $0.contains("a different file already exists") })
    }

    func testConflictAndServerErrorsRetry() async {
        StubURLProtocol.reset(replies: [.status(409), .status(503)])
        let uploader = githubUploader()
        let first = await uploader.deliver(sealed)
        let second = await uploader.deliver(sealed)
        guard case .retry = first, case .retry = second else {
            return XCTFail("409 and 5xx retry with backoff: \(first), \(second)")
        }
    }

    func testAuthOfflineAndRateLimitStopTheCycle() async {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        StubURLProtocol.reset(replies: [.status(401), .failure(.notConnectedToInternet), .status(429, headers: ["Retry-After": "60"])])
        let uploader = CreateOnlyFileUploader(transport: GitHubVaultTransport(api: TestSupport.makeClient(now: now)))
        let auth = await uploader.deliver(sealed)
        let offline = await uploader.deliver(sealed)
        let limited = await uploader.deliver(sealed)
        XCTAssertEqual(auth, .stopCycle(.auth))
        XCTAssertEqual(offline, .stopCycle(.offline))
        XCTAssertEqual(limited, .stopCycle(.rateLimited(until: now.addingTimeInterval(60))))
    }

    func testAnotherDevicesFolderIsRefusedWithNothingSent() async {
        let foreign = SealedFile(path: HubPath("events/ios-00000000/2026/10/x.jsonl")!, bytes: bytes, commitMessage: "m")
        let delivery = await githubUploader().deliver(foreign)
        XCTAssertEqual(delivery, .failedPermanently(reason: "refused by the path policy"))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - Over the in-memory transport, through the real queue

    func testQueueAndUploaderOverTheInMemoryTransport() async throws {
        let transport = InMemoryVaultTransport()
        let uploader = CreateOnlyFileUploader(transport: transport)
        let queue = DurableQueue<SealedFile>(fileURL: try makeTemporaryDirectory().appendingPathComponent("write-queue.json"))
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        // The first attempt lands but its answer is lost (reported offline).
        transport.loseNextCreateResponse = true
        let entry = try await queue.enqueue(sealed, now: now)
        let first = await queue.drain(using: uploader, now: now)
        XCTAssertEqual(first.stoppedBy, .offline)
        XCTAssertEqual(transport.file(path), bytes)

        // The retry gets "already exists", compares SHAs, and is delivered
        // without creating anything new.
        let second = await queue.drain(using: uploader, now: now.addingTimeInterval(60))
        XCTAssertEqual(second.delivered, [entry.id])
        XCTAssertEqual(transport.createCount, 2)
        XCTAssertEqual(transport.file(path), bytes)

        // A different file at the same path fails permanently.
        let clash = SealedFile(path: path, bytes: Data("different\n".utf8), commitMessage: "m")
        let clashEntry = try await queue.enqueue(clash, now: now.addingTimeInterval(120))
        let third = await queue.drain(using: uploader, now: now.addingTimeInterval(120))
        XCTAssertEqual(third.failed, [clashEntry.id])
        XCTAssertEqual(transport.file(path), bytes, "never overwritten")

        // Refusals hold for this transport too.
        let foreign = SealedFile(path: HubPath("events/ios-00000000/x.jsonl")!, bytes: bytes, commitMessage: "m")
        let refused = await uploader.deliver(foreign)
        XCTAssertEqual(refused, .failedPermanently(reason: "refused by the path policy"))
        XCTAssertEqual(transport.createCount, 3)
    }
}

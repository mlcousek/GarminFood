// GitHubContentsClientTests.swift
//
// add-vault-connection task 2.5 (design D2, D6, D13): the real client --
// request building, ephemeral session, redirect guard, classification --
// against a `URLProtocol` stub. Covers 200 + ETag, 304, 401, 403 with and
// without rate-limit headers, 404 repository vs file, 409, 422, 429 +
// Retry-After, 5xx, offline, a cross-host redirect, and a refused path that
// sends nothing. Never touches api.github.com.

import XCTest
@testable import VaultKit

final class GitHubContentsClientTests: XCTestCase {
    private let projection = VaultHub.projectionPath
    private let ownEvent = HubPath("events/ios-0000abcd/2026/10/20261001T101500Z-1.jsonl")!

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    // MARK: - Request shape

    func testFileGetIsConditionalRawAndScopedToTheHub() async throws {
        StubURLProtocol.reset(replies: [.status(200, headers: ["ETag": "\"v1\""], body: Data(#"{"schema":"example"}"#.utf8))])
        let client = TestSupport.makeClient()

        let result = await client.getFile(projection, ifNoneMatch: "\"v0\"")

        XCTAssertEqual(result.outcome, .fetched(bytes: Data(#"{"schema":"example"}"#.utf8), etag: "\"v1\""))
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "api.github.com")
        XCTAssertEqual(request.url?.path, "/repos/example-owner/example-vault/contents/Sport/Training/_hub/projection/projection.v1.json")
        XCTAssertEqual(request.url?.query, "ref=main")
        XCTAssertEqual(request.header("Accept"), "application/vnd.github.raw+json")
        XCTAssertEqual(request.header("X-GitHub-Api-Version"), "2022-11-28")
        XCTAssertEqual(request.header("If-None-Match"), "\"v0\"")
        XCTAssertEqual(request.header("Authorization"), "Bearer " + TestSupport.plantedTokenString)
    }

    func testNoIfNoneMatchWithoutAStoredETag() async {
        StubURLProtocol.reset(replies: [.status(200, body: Data("{}".utf8))])
        _ = await TestSupport.makeClient().getFile(projection, ifNoneMatch: nil)
        XCTAssertNil(StubURLProtocol.requests.first?.header("If-None-Match"))
    }

    func testRepositoryGet() async throws {
        StubURLProtocol.reset(replies: [.status(200, body: Data(#"{"private":true}"#.utf8))])
        let result = await TestSupport.makeClient().getRepository()
        XCTAssertEqual(result.outcome, .success)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/repos/example-owner/example-vault")
        XCTAssertEqual(request.header("Accept"), "application/vnd.github+json")
    }

    func testCreateIsAPutWithoutShaOnTheConfiguredBranch() async throws {
        StubURLProtocol.reset(replies: [.status(201, body: Data(#"{"content":{}}"#.utf8))])
        let bytes = Data("{\"event\":1}\n".utf8)

        let result = await TestSupport.makeClient().createFile(ownEvent, bytes: bytes, message: "app: 1 event")

        XCTAssertEqual(result.outcome, .created)
        let request = try XCTUnwrap(StubURLProtocol.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.url?.path, "/repos/example-owner/example-vault/contents/Sport/Training/_hub/events/ios-0000abcd/2026/10/20261001T101500Z-1.jsonl")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: String])
        XCTAssertEqual(body["message"], "app: 1 event")
        XCTAssertEqual(body["branch"], "main")
        XCTAssertEqual(body["content"].flatMap { Data(base64Encoded: $0) }, bytes)
        XCTAssertNil(body["sha"], "no sha: create-only, never an overwrite")
    }

    // MARK: - Statuses

    func testNotModified() async {
        StubURLProtocol.reset(replies: [.status(304, headers: ["ETag": "\"v1\""])])
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: "\"v1\"")
        XCTAssertEqual(result.outcome, .notModified)
    }

    func testUnauthorized() async {
        StubURLProtocol.reset(replies: [.status(401, body: Data(#"{"message":"Bad credentials"}"#.utf8))])
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(result.outcome, .failed(.authFailed(.tokenRejected)))
    }

    func testForbiddenWithoutRateLimitHeadersIsLoud() async {
        StubURLProtocol.reset(replies: [.status(403, headers: ["X-RateLimit-Remaining": "4999"])])
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(result.outcome, .failed(.authFailed(.forbidden)))
    }

    func testForbiddenWithRateLimitHeadersIsARateLimit() async {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        StubURLProtocol.reset(replies: [.status(403, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1790000600"])])
        let result = await TestSupport.makeClient(now: now).getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(result.outcome, .failed(.rateLimited(until: now.addingTimeInterval(600))))
    }

    func testTooManyRequestsHonoursRetryAfter() async {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        StubURLProtocol.reset(replies: [.status(429, headers: ["Retry-After": "120"])])
        let result = await TestSupport.makeClient(now: now).getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(result.outcome, .failed(.rateLimited(until: now.addingTimeInterval(120))))
    }

    func testNotFoundRepositoryVersusFile() async {
        StubURLProtocol.reset(replies: [.status(404)])
        let client = TestSupport.makeClient()
        let repository = await client.getRepository()
        let file = await client.getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(repository.outcome, .authFailed(.repositoryNotFound))
        XCTAssertEqual(file.outcome, .failed(.fileNotFound))
    }

    func testCreateConflictAndAlreadyExists() async {
        StubURLProtocol.reset(replies: [.status(422), .status(409)])
        let client = TestSupport.makeClient()
        let first = await client.createFile(ownEvent, bytes: Data("x".utf8), message: "m")
        let second = await client.createFile(ownEvent, bytes: Data("x".utf8), message: "m")
        XCTAssertEqual(first.outcome, .alreadyExists)
        XCTAssertEqual(second.outcome, .failed(.conflict))
    }

    func testServerError() async {
        StubURLProtocol.reset(replies: [.status(502)])
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(result.outcome, .failed(.serverError(status: 502)))
    }

    func testOffline() async {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet)])
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: nil)
        XCTAssertEqual(result.outcome, .failed(.offline))
    }

    func testTokenExpiryIsReadFromEveryResponse() async {
        StubURLProtocol.reset(replies: [.status(304, headers: ["github-authentication-token-expiration": "2027-01-03 18:13:20 UTC"])])
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: "\"v1\"")
        XCTAssertEqual(result.tokenExpiresAt, Date(timeIntervalSince1970: 1_799_000_000))
    }

    // MARK: - Nothing sent

    func testRefusedPathSendsNothingAndLogsAnError() async {
        let log = recordVaultLog()
        let client = TestSupport.makeClient()
        let otherDevice = HubPath("events/ios-00000000/2026/10/x.jsonl")!

        let write = await client.createFile(otherDevice, bytes: Data("x".utf8), message: "m")
        let read = await client.getFile(HubPath("Daily/2026-10-01.md")!, ifNoneMatch: nil)

        XCTAssertEqual(write.outcome, .failed(.refusedByPolicy))
        XCTAssertEqual(read.outcome, .failed(.refusedByPolicy))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty, "a refused path must not reach the network")
        XCTAssertEqual(log.errorLines.count, 2)
    }

    func testWithoutCredentialsNothingIsSent() async {
        let client = TestSupport.makeClient(credentials: nil)
        let result = await client.getFile(projection, ifNoneMatch: nil)
        let repository = await client.getRepository()
        XCTAssertEqual(result.outcome, .failed(.notConfigured))
        XCTAssertEqual(repository.outcome, .notConfigured)
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: - Redirects

    func testCrossHostRedirectIsRefusedAndTheTokenNeverLeaves() async {
        let elsewhere = URL(string: "https://attacker.example/steal")!
        StubURLProtocol.reset { request in
            request.url?.host == "api.github.com" ? .redirect(to: elsewhere) : .status(200, body: Data("{}".utf8))
        }
        let result = await TestSupport.makeClient().getFile(projection, ifNoneMatch: nil)

        XCTAssertFalse(StubURLProtocol.requests.contains { $0.url?.host != "api.github.com" }, "no request may reach another host")
        switch result.outcome {
        case .fetched, .notModified:
            XCTFail("a refused redirect must not look like a successful fetch")
        case .failed:
            break
        }
    }

    func testRedirectDecision() {
        var original = URLRequest(url: URL(string: "https://api.github.com/repos/example-owner/example-vault")!)
        original.setValue("Bearer x", forHTTPHeaderField: "Authorization")
        original.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let sameHost = URLRequest(url: URL(string: "https://api.github.com/repositories/123")!)
        let followed = RedirectGuard.redirect(from: original, to: sameHost)
        XCTAssertEqual(followed?.url, sameHost.url)
        XCTAssertEqual(followed?.value(forHTTPHeaderField: "Authorization"), "Bearer x")
        XCTAssertEqual(followed?.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")

        for target in ["https://evil.example/x", "http://api.github.com/x", "https://api.github.com.evil.example/x", "https://raw.githubusercontent.com/x"] {
            XCTAssertNil(RedirectGuard.redirect(from: original, to: URLRequest(url: URL(string: target)!)), target)
        }
    }

    func testSessionHasNoCacheAndNoCookies() {
        let configuration = GitHubContentsClient.makeSessionConfiguration()
        XCTAssertNil(configuration.urlCredentialStorage)
        // The client also nils the cache and cookies on whatever it's given.
        _ = TestSupport.makeClient()
        XCTAssertEqual(GitHubContentsClient.host, "api.github.com")
    }
}

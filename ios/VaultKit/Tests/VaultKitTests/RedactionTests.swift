// RedactionTests.swift
//
// add-vault-connection task 2.12 (design D3, spec "Token absent from logs
// after failures"): a token is planted, flows into real request headers,
// and then every failure path runs -- 401, 403 (with and without rate-limit
// headers), 404, 409, 422, 429, 5xx, offline, a timeout, a cross-host
// redirect, a refused path, a validator rejection, a durable-queue failure.
// No `vault` log line, no outcome's description, no queued entry's
// lastError and no VaultKit file on disk may contain any part of the token
// beyond the last four characters Settings shows -- nor the repository's
// owner or name (task 4.6: log lines carry hub-relative paths only).

import XCTest
@testable import VaultKit

final class RedactionTests: XCTestCase {
    /// Distinctive slices of the planted token, excluding its last four
    /// characters (which Settings shows) and its public prefix.
    private let secretSlices = ["PLANTED0", "_pat_PLANTED", "D0PLA", TestSupport.plantedTokenString]
    private let repositorySlices = [TestSupport.owner, TestSupport.repositoryName, "api.github.com/repos"]

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    private func assertClean(_ text: String, _ context: String, file: StaticString = #filePath, line: UInt = #line) {
        for slice in secretSlices {
            XCTAssertFalse(text.contains(slice), "\(context) leaks the token: \(text)", file: file, line: line)
        }
        for slice in repositorySlices {
            XCTAssertFalse(text.contains(slice), "\(context) names the repository: \(text)", file: file, line: line)
        }
    }

    func testNoFailurePathLeaksTheTokenOrTheRepository() async throws {
        let log = recordVaultLog()
        let directory = try makeTemporaryDirectory()
        let projection = VaultHub.projectionPath
        let event = HubPath("events/ios-0000abcd/2026/10/x.jsonl")!

        StubURLProtocol.reset(replies: [
            .status(401, body: Data(#"{"message":"Bad credentials"}"#.utf8)),
            .status(403, body: Data(#"{"message":"Resource not accessible by personal access token"}"#.utf8)),
            .status(403, headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1790000600"]),
            .status(404),
            .status(429, headers: ["Retry-After": "120"]),
            .status(500, body: Data("<html>error</html>".utf8)),
            .failure(.notConnectedToInternet),
            .failure(.timedOut),
            .failure(.secureConnectionFailed),
            .status(409),
            .status(422),
            .redirect(to: URL(string: "https://attacker.example/x")!),
            .status(200, headers: ["ETag": "\"bad\""], body: Data("not json".utf8))
        ])
        let client = TestSupport.makeClient()
        var outcomes: [String] = []

        for _ in 0..<9 {
            let result = await client.getFile(projection, ifNoneMatch: "\"old\"")
            outcomes.append(String(describing: result))
            outcomes.append(String(reflecting: result.outcome))
        }
        for _ in 0..<2 {
            let result = await client.createFile(event, bytes: Data("{}\n".utf8), message: "app: test")
            outcomes.append(String(describing: result))
        }
        let repository = await client.getRepository()
        outcomes.append(String(describing: repository))

        // The validator rejection path (ConditionalFileSync logs it).
        let transport = GitHubVaultTransport(api: client)
        let sync = ConditionalFileSync(transport: transport, directory: directory)
        let report = await sync.refresh(projection) { try VaultValidators.jsonObject($0) }
        outcomes.append(String(describing: report))

        // A refused path.
        let refused = await client.getFile(HubPath("Daily/x.md")!, ifNoneMatch: nil)
        outcomes.append(String(describing: refused))

        // A durable-queue failure through the real client.
        StubURLProtocol.reset(replies: [.status(401)])
        let queue = DurableQueue<SealedFile>(fileURL: directory.appendingPathComponent("write-queue.json"))
        try await queue.enqueue(SealedFile(path: event, bytes: Data("{}\n".utf8), commitMessage: "app: test"))
        _ = await queue.drain(using: CreateOnlyFileUploader(transport: transport))
        for entry in await queue.all() {
            outcomes.append(entry.lastError ?? "")
        }

        // The token really was sent -- otherwise this test proves nothing.
        XCTAssertTrue(StubURLProtocol.requests.contains { $0.header("Authorization")?.contains(TestSupport.plantedTokenString) == true })

        XCTAssertGreaterThanOrEqual(log.lines.count, 10)
        for line in log.lines {
            assertClean(line, "log line")
        }
        for text in outcomes {
            assertClean(text, "outcome")
        }
        for name in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
            let url = directory.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
            let contents = String(decoding: try Data(contentsOf: url), as: UTF8.self)
            assertClean(contents, "file \(name)")
        }
    }

    func testStatusFileHoldsNoSecret() async throws {
        let directory = try makeTemporaryDirectory()
        let store = VaultStatusStore(directory: directory)
        await store.record(.authFailed(.tokenRejected), at: Date(), tokenExpiresAt: Date())
        let contents = String(decoding: try Data(contentsOf: directory.appendingPathComponent("status.json")), as: UTF8.self)
        assertClean(contents, "status.json")
        XCTAssertFalse(contents.contains("github_pat_"))
    }
}

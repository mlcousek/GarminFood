// TestSupport.swift
//
// Shared fixtures for VaultKit's tests: synthetic repository names, a
// planted token, temp directories, an in-memory token store, an in-memory
// `VaultTransport`, and a log recorder.
//
// Nothing here is real (design D12, D13): the repository is
// `example-owner/example-vault`, the device `ios-0000abcd`. The planted
// token is assembled at run time from pieces and is shorter than a real
// fine-grained token, so no secret scanner can mistake this public
// repository's source for a leak -- while still passing `VaultToken`'s
// shape check, so it flows into real request headers.

import Foundation
import XCTest
import GarminKit
@testable import VaultKit

enum TestSupport {
    static let owner = "example-owner"
    static let repositoryName = "example-vault"
    static let deviceID = VaultDeviceID("ios-0000abcd")!
    static let otherDeviceID = VaultDeviceID("ios-00000000")!

    /// A token-shaped secret nobody issued. Built from pieces on purpose.
    static let plantedTokenString = "github" + "_pat_" + String(repeating: "PLANTED0", count: 5) + "zq9x"

    static var token: VaultToken {
        try! VaultToken(validating: plantedTokenString)
    }

    static var repository: VaultRepository {
        try! VaultRepository(owner: owner, name: repositoryName)
    }

    static var credentials: VaultCredentials {
        VaultCredentials(repository: repository, token: token)
    }

    static func makeClient(
        deviceID: VaultDeviceID? = TestSupport.deviceID,
        credentials: VaultCredentials? = TestSupport.credentials,
        now: Date = Date(timeIntervalSince1970: 1_790_000_000)
    ) -> GitHubContentsClient {
        GitHubContentsClient(
            configuration: StubURLProtocol.sessionConfiguration(),
            timeout: 5,
            credentials: { credentials },
            policy: { VaultPathPolicy(ownDeviceID: deviceID) },
            now: { now }
        )
    }
}

extension XCTestCase {
    /// A fresh, unique directory removed after the test.
    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vaultkit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    /// Records every `VaultLog` line until the test ends.
    func recordVaultLog() -> VaultLogRecorder {
        let recorder = VaultLogRecorder()
        let id = VaultLog.addObserver { level, message in
            recorder.append(level, message)
        }
        addTeardownBlock {
            VaultLog.removeObserver(id)
        }
        return recorder
    }
}

final class VaultLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(DiagnosticsLevel, String)] = []

    func append(_ level: DiagnosticsLevel, _ message: String) {
        lock.lock()
        entries.append((level, message))
        lock.unlock()
    }

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.map(\.1)
    }

    var errorLines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.0 == .error }.map(\.1)
    }
}

/// The Keychain's stand-in.
final class InMemoryTokenStore: VaultTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: VaultToken?

    init(_ token: VaultToken? = nil) {
        self.token = token
    }

    func load() throws -> VaultToken? {
        lock.lock()
        defer { lock.unlock() }
        return token
    }

    func save(_ token: VaultToken) throws {
        lock.lock()
        self.token = token
        lock.unlock()
    }

    func delete() {
        lock.lock()
        token = nil
        lock.unlock()
    }
}

/// A `VaultTransport` over an in-memory file map, enforcing the same path
/// policy as the GitHub client (spec "Training code depends on a
/// transport, not on GitHub": behaves the same, refusals included).
final class InMemoryVaultTransport: VaultTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [HubPath: Data] = [:]
    private var scriptedFetchFailures: [VaultOutcome] = []
    private var scriptedCreateFailures: [VaultOutcome] = []
    private(set) var fetchCount = 0
    private(set) var createCount = 0
    var policy: VaultPathPolicy
    var repositoryOutcome: VaultOutcome = .success
    /// Simulates "the create landed but its answer was lost".
    var loseNextCreateResponse = false

    init(policy: VaultPathPolicy = VaultPathPolicy(ownDeviceID: TestSupport.deviceID)) {
        self.policy = policy
    }

    static func etag(for bytes: Data) -> String {
        "\"" + GitBlob.sha1Hex(of: bytes) + "\""
    }

    func put(_ path: HubPath, _ bytes: Data) {
        lock.lock()
        files[path] = bytes
        lock.unlock()
    }

    func file(_ path: HubPath) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return files[path]
    }

    func failNextFetch(with outcome: VaultOutcome) {
        lock.lock()
        scriptedFetchFailures.append(outcome)
        lock.unlock()
    }

    func failNextCreate(with outcome: VaultOutcome) {
        lock.lock()
        scriptedCreateFailures.append(outcome)
        lock.unlock()
    }

    func fetch(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult {
        fetchSync(path, ifNoneMatch: ifNoneMatch)
    }

    private func fetchSync(_ path: HubPath, ifNoneMatch: String?) -> VaultFetchResult {
        lock.lock()
        defer { lock.unlock() }
        guard policy.allowsRead(path) else { return VaultFetchResult(.failed(.refusedByPolicy)) }
        fetchCount += 1
        if !scriptedFetchFailures.isEmpty {
            return VaultFetchResult(.failed(scriptedFetchFailures.removeFirst()))
        }
        guard let bytes = files[path] else { return VaultFetchResult(.failed(.fileNotFound)) }
        let etag = Self.etag(for: bytes)
        if ifNoneMatch == etag { return VaultFetchResult(.notModified) }
        return VaultFetchResult(.fetched(bytes: bytes, etag: etag))
    }

    func createOnly(_ file: SealedFile) async -> VaultWriteResult {
        createSync(file)
    }

    private func createSync(_ file: SealedFile) -> VaultWriteResult {
        lock.lock()
        defer { lock.unlock() }
        guard policy.allowsWrite(file.path) else { return VaultWriteResult(.failed(.refusedByPolicy)) }
        createCount += 1
        if !scriptedCreateFailures.isEmpty {
            return VaultWriteResult(.failed(scriptedCreateFailures.removeFirst()))
        }
        if files[file.path] != nil { return VaultWriteResult(.alreadyExists) }
        files[file.path] = file.bytes
        if loseNextCreateResponse {
            loseNextCreateResponse = false
            return VaultWriteResult(.failed(.offline))
        }
        return VaultWriteResult(.created)
    }

    func probe() async -> VaultProbeResult {
        let repository = repositoryOutcome
        guard repository == .success else {
            return VaultProbeResult(repository: repository, projection: nil, tokenExpiresAt: nil)
        }
        let file = fetchSync(VaultHub.projectionPath, ifNoneMatch: nil)
        switch file.outcome {
        case .fetched(let bytes, _):
            return VaultProbeResult(repository: .success, projection: .found(byteCount: bytes.count), tokenExpiresAt: nil)
        case .failed(.fileNotFound):
            return VaultProbeResult(repository: .success, projection: .notFound, tokenExpiresAt: nil)
        case .failed(let outcome):
            return VaultProbeResult(repository: .success, projection: .failed(outcome), tokenExpiresAt: nil)
        case .notModified:
            return VaultProbeResult(repository: .success, projection: .found(byteCount: 0), tokenExpiresAt: nil)
        }
    }
}

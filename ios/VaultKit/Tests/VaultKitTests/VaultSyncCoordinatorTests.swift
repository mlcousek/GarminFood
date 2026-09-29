// VaultSyncCoordinatorTests.swift
//
// add-vault-connection design D6/D11 and the vault-connection spec
// scenarios that don't need a device: nothing is sent while the
// connection is off, unconfigured or tokenless; two foregrounds within a
// minute send one request (pull to refresh bypasses the interval, never
// the gate); a loud outcome stops requests until the user acts; a rate
// limit stops them until its reset; a missing projection is told apart
// from a missing repository; "Test connection" is read-only and creates the
// device identity on its first success; disconnect clears cache and status
// but keeps the identity.

import XCTest
@testable import VaultKit

final class VaultSyncCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let ready = VaultSyncInputs(enabled: true, configured: true, hasToken: true)
    private let validate: @Sendable (Data) throws -> Void = { try VaultValidators.jsonObject($0) }
    private let projection = Data(#"{"schema":"example"}"#.utf8)

    private struct Harness {
        let transport: InMemoryVaultTransport
        let coordinator: VaultSyncCoordinator
        let status: VaultStatusStore
        let identity: DeviceIdentityStore
        let fetchSync: ConditionalFileSync
    }

    private func makeHarness(transport: InMemoryVaultTransport = InMemoryVaultTransport()) throws -> Harness {
        let directory = try makeTemporaryDirectory()
        let status = VaultStatusStore(directory: directory)
        let identity = DeviceIdentityStore(directory: directory)
        let fetchSync = ConditionalFileSync(transport: transport, directory: directory)
        let coordinator = VaultSyncCoordinator(transport: transport, fetchSync: fetchSync, statusStore: status, identityStore: identity)
        return Harness(transport: transport, coordinator: coordinator, status: status, identity: identity, fetchSync: fetchSync)
    }

    func testNothingIsSentUnlessEnabledConfiguredAndHoldingAToken() async throws {
        let harness = try makeHarness()
        let off = await harness.coordinator.refreshProjection(VaultSyncInputs(enabled: false, configured: true, hasToken: true), now: now, validate: validate)
        let unconfigured = await harness.coordinator.refreshProjection(VaultSyncInputs(enabled: true, configured: false, hasToken: true), now: now, validate: validate)
        let tokenless = await harness.coordinator.refreshProjection(VaultSyncInputs(enabled: true, configured: true, hasToken: false), now: now, validate: validate)
        XCTAssertEqual(off, .skipped(.gate(.disabled)))
        XCTAssertEqual(unconfigured, .skipped(.gate(.notConfigured)))
        XCTAssertEqual(tokenless, .skipped(.gate(.noToken)))
        XCTAssertEqual(harness.transport.fetchCount, 0)
    }

    func testTwoForegroundsWithinAMinuteSendOneRequest() async throws {
        let harness = try makeHarness()
        harness.transport.put(VaultHub.projectionPath, projection)

        let first = await harness.coordinator.refreshProjection(ready, now: now, validate: validate)
        let second = await harness.coordinator.refreshProjection(ready, now: now.addingTimeInterval(30), validate: validate)
        XCTAssertEqual(first, .ran(.updated(byteCount: projection.count)))
        XCTAssertEqual(second, .skipped(.tooSoon))
        XCTAssertEqual(harness.transport.fetchCount, 1)

        // Pull to refresh bypasses the interval.
        let pulled = await harness.coordinator.refreshProjection(ready, force: true, now: now.addingTimeInterval(31), validate: validate)
        XCTAssertEqual(pulled, .ran(.unchanged))
        // After a minute, a foreground goes out again.
        let later = await harness.coordinator.refreshProjection(ready, now: now.addingTimeInterval(95), validate: validate)
        XCTAssertEqual(later, .ran(.unchanged))
        XCTAssertEqual(harness.transport.fetchCount, 3)

        let status = await harness.status.current()
        XCTAssertEqual(status.lastSuccessAt, now.addingTimeInterval(95), "a 304 updates the last successful sync")
    }

    func testLoudOutcomeStopsRequestsUntilTheUserActs() async throws {
        let harness = try makeHarness()
        harness.transport.failNextFetch(with: .authFailed(.tokenRejected))

        _ = await harness.coordinator.refreshProjection(ready, now: now, validate: validate)
        let state = await harness.coordinator.connectionState(ready)
        XCTAssertEqual(state.bannerReason(now: now), .authProblem(.tokenRejected))

        // spec "Token revoked": no further request on the next foreground.
        let next = await harness.coordinator.refreshProjection(ready, force: true, now: now.addingTimeInterval(120), validate: validate)
        XCTAssertEqual(next, .skipped(.gate(.blockedByAuth(.tokenRejected))))
        XCTAssertEqual(harness.transport.fetchCount, 1)

        // Saving a new token lifts the block.
        await harness.coordinator.userActed()
        harness.transport.put(VaultHub.projectionPath, projection)
        let after = await harness.coordinator.refreshProjection(ready, now: now.addingTimeInterval(130), validate: validate)
        XCTAssertEqual(after, .ran(.updated(byteCount: projection.count)))
        let cleared = await harness.coordinator.connectionState(ready)
        XCTAssertNil(cleared.bannerReason(now: now))
    }

    func testRateLimitIsQuietAndHonoured() async throws {
        let harness = try makeHarness()
        let until = now.addingTimeInterval(120)
        harness.transport.failNextFetch(with: .rateLimited(until: until))
        _ = await harness.coordinator.refreshProjection(ready, now: now, validate: validate)

        let state = await harness.coordinator.connectionState(ready)
        XCTAssertNil(state.bannerReason(now: now), "no banner for a rate limit")
        let during = await harness.coordinator.refreshProjection(ready, force: true, now: now.addingTimeInterval(100), validate: validate)
        XCTAssertEqual(during, .skipped(.gate(.rateLimited(until: until))))
        harness.transport.put(VaultHub.projectionPath, projection)
        let after = await harness.coordinator.refreshProjection(ready, force: true, now: now.addingTimeInterval(121), validate: validate)
        XCTAssertEqual(after, .ran(.updated(byteCount: projection.count)))
    }

    func testOfflineIsQuietAndKeepsTheLastSync() async throws {
        let harness = try makeHarness()
        harness.transport.put(VaultHub.projectionPath, projection)
        _ = await harness.coordinator.refreshProjection(ready, now: now, validate: validate)
        harness.transport.failNextFetch(with: .offline)
        _ = await harness.coordinator.refreshProjection(ready, force: true, now: now.addingTimeInterval(60), validate: validate)

        let state = await harness.coordinator.connectionState(ready)
        XCTAssertNil(state.bannerReason(now: now))
        XCTAssertEqual(state.status.lastSuccessAt, now)
        XCTAssertEqual(state.status.lastProblem, .offline)
        let cached = await harness.fetchSync.cachedFile(VaultHub.projectionPath)
        XCTAssertEqual(cached?.bytes, projection)
    }

    func testMissingProjectionIsToldApartFromMissingRepository() async throws {
        let harness = try makeHarness()
        // Reachable repository, no projection yet: quiet.
        _ = await harness.coordinator.refreshProjection(ready, now: now, validate: validate)
        var state = await harness.coordinator.connectionState(ready)
        XCTAssertEqual(state.status.lastOutcome, .fileNotFound)
        XCTAssertNil(state.bannerReason(now: now))

        // A missing repository: loud.
        let other = try makeHarness()
        other.transport.repositoryOutcome = .authFailed(.repositoryNotFound)
        _ = await other.coordinator.refreshProjection(ready, now: now, validate: validate)
        state = await other.coordinator.connectionState(ready)
        XCTAssertEqual(state.bannerReason(now: now), .authProblem(.repositoryNotFound))
    }

    func testTestConnectionIsReadOnlyAndCreatesTheIdentityOnce() async throws {
        let harness = try makeHarness()
        let before = await harness.identity.current()
        XCTAssertNil(before)

        // Connected, plan not generated yet.
        let result = await harness.coordinator.testConnection(ready, now: now)
        XCTAssertEqual(result.probe?.repository, .success)
        XCTAssertEqual(result.probe?.projection, .notFound)
        XCTAssertEqual(result.gate, .allowed)
        let created = try XCTUnwrap(result.deviceID)
        XCTAssertEqual(harness.transport.createCount, 0, "Test connection never writes")

        let again = await harness.coordinator.testConnection(ready, now: now.addingTimeInterval(60))
        XCTAssertEqual(again.deviceID, created, "the identity is created once")

        let state = await harness.coordinator.connectionState(ready)
        XCTAssertNil(state.bannerReason(now: now), "no plan data yet is information, not an error")
    }

    func testTestConnectionWithAWrongRepositoryNeedsAttentionAndCreatesNoIdentity() async throws {
        let harness = try makeHarness()
        harness.transport.repositoryOutcome = .authFailed(.repositoryNotFound)
        let result = await harness.coordinator.testConnection(ready, now: now)
        XCTAssertEqual(result.probe?.repository, .authFailed(.repositoryNotFound))
        XCTAssertNil(result.deviceID)
        let state = await harness.coordinator.connectionState(ready)
        XCTAssertTrue(state.needsAttention(now: now))
    }

    func testTestConnectionLiftsALoudBlock() async throws {
        let harness = try makeHarness()
        try await harness.status.update { $0.blockedBy = .tokenRejected }
        let result = await harness.coordinator.testConnection(ready, now: now)
        XCTAssertEqual(result.gate, .allowed)
    }

    func testTestConnectionNeedsConfigurationAndAToken() async throws {
        let harness = try makeHarness()
        let unconfigured = await harness.coordinator.testConnection(VaultSyncInputs(enabled: true, configured: false, hasToken: true), now: now)
        let tokenless = await harness.coordinator.testConnection(VaultSyncInputs(enabled: true, configured: true, hasToken: false), now: now)
        XCTAssertNil(unconfigured.probe)
        XCTAssertEqual(unconfigured.gate, .notConfigured)
        XCTAssertEqual(tokenless.gate, .noToken)
        XCTAssertEqual(harness.transport.fetchCount, 0)
    }

    func testDisconnectClearsCacheAndStatusButKeepsTheIdentity() async throws {
        let harness = try makeHarness()
        harness.transport.put(VaultHub.projectionPath, projection)
        let tested = await harness.coordinator.testConnection(ready, now: now)
        _ = await harness.coordinator.refreshProjection(ready, force: true, now: now, validate: validate)

        try await harness.coordinator.disconnect()

        let cached = await harness.fetchSync.cachedFile(VaultHub.projectionPath)
        XCTAssertNil(cached)
        let status = await harness.status.current()
        XCTAssertEqual(status, VaultStatus())
        let identity = await harness.identity.currentID()
        XCTAssertEqual(identity, tested.deviceID)
        // Off after disconnect: nothing is sent.
        let off = await harness.coordinator.refreshProjection(VaultSyncInputs(enabled: false, configured: true, hasToken: false), force: true, now: now.addingTimeInterval(300), validate: validate)
        XCTAssertEqual(off, .skipped(.gate(.disabled)))
    }
}

// SetupRefreshTests.swift
//
// polish-training-today task 1.4 (design D1): the chain the app runs when
// the vault setup is finished, over an in-memory transport and REAL
// VaultKit stores on temp files -- save the repository, save the token,
// turn the switch on -> `VaultSetupRefresh` starts exactly one fetch ->
// `ProjectionStore.refresh(via:)` stores it -> what TrainingModel reloads
// (`loadCached` + `ProjectionAvailability`) is the loaded plan, not
// "Fetching your plan...".
//
// The app's VaultController only replays this sequence and launches the
// refresh unstructured; it is not testable without a Mac.

import XCTest
import VaultKit
@testable import TrainingCore

final class SetupRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testFinishingSetupFetchesOnceAndTheCachedPlanLoads() async throws {
        let directory = try makeTemporaryDirectory()
        let transport = InMemoryTransport()
        transport.enqueue(.fetched(bytes: try Fixtures.example(), etag: "\"e1\""))
        let fetchSync = ConditionalFileSync(transport: transport, directory: directory)
        let status = VaultStatusStore(directory: directory)
        let coordinator = VaultSyncCoordinator(
            transport: transport,
            fetchSync: fetchSync,
            statusStore: status,
            identityStore: DeviceIdentityStore(directory: directory)
        )
        let store = ProjectionStore(fetchSync: fetchSync)

        // Before: connection on, nothing cached -> the first-sync state.
        let before = await store.loadCached()
        XCTAssertEqual(ProjectionAvailability.evaluate(cached: before, rejection: nil, fileNotFound: false), .waitingForFirstSync)

        // Settings: the order the screen offers.
        let steps: [(VaultSetupRefresh.Trigger, VaultSyncInputs, VaultSyncInputs)] = [
            (.repositorySaved,
             VaultSyncInputs(enabled: false, configured: false, hasToken: false),
             VaultSyncInputs(enabled: false, configured: true, hasToken: false)),
            (.tokenSaved,
             VaultSyncInputs(enabled: false, configured: true, hasToken: false),
             VaultSyncInputs(enabled: false, configured: true, hasToken: true)),
            (.switchedOn,
             VaultSyncInputs(enabled: false, configured: true, hasToken: true),
             VaultSyncInputs(enabled: true, configured: true, hasToken: true)),
        ]
        var gate = VaultSetupRefresh()
        var refreshes = 0
        for (trigger, old, new) in steps {
            let synced = await status.current().lastSuccessAt != nil
            if gate.request(trigger, before: old, after: new, hasSynced: synced) {
                refreshes += 1
                let report = await store.refresh(via: coordinator, inputs: new, force: true, now: now)
                guard case .ran(.updated) = report else { return XCTFail("\(report)") }
                XCTAssertFalse(gate.finish())
            }
        }
        XCTAssertEqual(refreshes, 1)
        XCTAssertEqual(transport.fetchCount, 1)

        // A successful "Test connection" afterwards fetches nothing more.
        let synced = await status.current().lastSuccessAt != nil
        XCTAssertTrue(synced)
        let ready = VaultSyncInputs(enabled: true, configured: true, hasToken: true)
        XCTAssertFalse(gate.request(.testSucceeded, before: ready, after: ready, hasSynced: synced))

        // What TrainingModel.reload reads now: the plan.
        let cached = await store.loadCached()
        let availability = ProjectionAvailability.evaluate(cached: cached, rejection: await store.rejection, fileNotFound: false)
        guard case .loaded(let loaded) = availability else { return XCTFail("\(availability)") }
        XCTAssertEqual(loaded.projection.asOf, D.asOf)
    }

    func testTheRefreshStepRespectsTheGate() async throws {
        let directory = try makeTemporaryDirectory()
        let transport = InMemoryTransport()
        let fetchSync = ConditionalFileSync(transport: transport, directory: directory)
        let coordinator = VaultSyncCoordinator(
            transport: transport,
            fetchSync: fetchSync,
            statusStore: VaultStatusStore(directory: directory),
            identityStore: DeviceIdentityStore(directory: directory)
        )
        let store = ProjectionStore(fetchSync: fetchSync)
        let report = await store.refresh(via: coordinator, inputs: VaultSyncInputs(enabled: true, configured: true, hasToken: false), force: true, now: now)
        XCTAssertEqual(report, .skipped(.gate(.noToken)))
        XCTAssertEqual(transport.fetchCount, 0)
    }
}

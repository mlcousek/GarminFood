// VaultSetupRefreshTests.swift
//
// polish-training-today design D1: finishing the vault setup starts the
// first projection fetch exactly once. The Settings order (switch on,
// repository, token, then "Test connection") fetches once, when the token
// makes the connection usable; nothing fetches while it isn't usable; a
// credential change during a fetch is coalesced into one follow-up; a test
// after a successful sync fetches nothing.

import XCTest
@testable import VaultKit

final class VaultSetupRefreshTests: XCTestCase {
    private let off = VaultSyncInputs(enabled: false, configured: false, hasToken: false)
    private let onOnly = VaultSyncInputs(enabled: true, configured: false, hasToken: false)
    private let onConfigured = VaultSyncInputs(enabled: true, configured: true, hasToken: false)
    private let ready = VaultSyncInputs(enabled: true, configured: true, hasToken: true)
    private let readyButOff = VaultSyncInputs(enabled: false, configured: true, hasToken: true)

    func testUsableNeedsAllThree() {
        XCTAssertTrue(ready.isUsable)
        XCTAssertFalse(readyButOff.isUsable)
        XCTAssertFalse(onConfigured.isUsable)
        XCTAssertFalse(VaultSyncInputs(enabled: true, configured: false, hasToken: true).isUsable)
    }

    func testSettingsOrderFetchesExactlyOnce() {
        var gate = VaultSetupRefresh()
        var starts = 0
        if gate.request(.switchedOn, before: off, after: onOnly, hasSynced: false) { starts += 1 }
        if gate.request(.repositorySaved, before: onOnly, after: onConfigured, hasSynced: false) { starts += 1 }
        if gate.request(.tokenSaved, before: onConfigured, after: ready, hasSynced: false) { starts += 1 }
        XCTAssertEqual(starts, 1, "the token made it usable")
        XCTAssertTrue(gate.isRunning)
        // "Test connection" while the fetch runs: nothing more.
        if gate.request(.testSucceeded, before: ready, after: ready, hasSynced: false) { starts += 1 }
        XCTAssertFalse(gate.finish())
        XCTAssertFalse(gate.isRunning)
        // And after the sync succeeded, a test fetches nothing either.
        if gate.request(.testSucceeded, before: ready, after: ready, hasSynced: true) { starts += 1 }
        XCTAssertEqual(starts, 1)
    }

    func testRepositoryAndTokenFirstThenTheSwitch() {
        var gate = VaultSetupRefresh()
        XCTAssertFalse(gate.request(.repositorySaved, before: off, after: VaultSyncInputs(enabled: false, configured: true, hasToken: false), hasSynced: false))
        XCTAssertFalse(gate.request(.tokenSaved, before: off, after: readyButOff, hasSynced: false))
        XCTAssertTrue(gate.request(.switchedOn, before: readyButOff, after: ready, hasSynced: false))
    }

    func testSwitchBackOnAfterASyncStillFetches() {
        var gate = VaultSetupRefresh()
        // Off -> on is a change of usability even with an earlier sync.
        XCTAssertTrue(gate.request(.switchedOn, before: readyButOff, after: ready, hasSynced: true))
    }

    func testNewCredentialsWhileAFetchRunsGiveOneFollowUp() {
        var gate = VaultSetupRefresh()
        XCTAssertTrue(gate.request(.tokenSaved, before: onConfigured, after: ready, hasSynced: false))
        XCTAssertFalse(gate.request(.tokenSaved, before: ready, after: ready, hasSynced: false))
        XCTAssertFalse(gate.request(.repositorySaved, before: ready, after: ready, hasSynced: false))
        XCTAssertTrue(gate.finish(), "one follow-up for both changes")
        XCTAssertTrue(gate.isRunning)
        XCTAssertFalse(gate.finish())
        XCTAssertFalse(gate.isRunning)
    }

    func testTestSuccessBeforeAnySyncFetchesWhenIdle() {
        var gate = VaultSetupRefresh()
        XCTAssertTrue(gate.request(.testSucceeded, before: ready, after: ready, hasSynced: false))
        XCTAssertFalse(gate.request(.testSucceeded, before: ready, after: ready, hasSynced: false), "one at a time")
    }

    func testResetForgetsTheFollowUp() {
        var gate = VaultSetupRefresh()
        XCTAssertTrue(gate.request(.tokenSaved, before: onConfigured, after: ready, hasSynced: false))
        XCTAssertFalse(gate.request(.repositorySaved, before: ready, after: ready, hasSynced: false))
        gate.reset()
        XCTAssertFalse(gate.isRunning)
        XCTAssertFalse(gate.finish())
    }
}

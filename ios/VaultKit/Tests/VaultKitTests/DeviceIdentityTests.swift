// DeviceIdentityTests.swift
//
// add-vault-connection task 2.7 (design D5, spec "Each install has its own
// device identity that is never copied"): the id's format, persistence
// across launches, a sequence counter that never hands out a number twice
// even when the app is killed after reserving, a fresh container getting a
// fresh id, and quarantine of an unreadable file instead of a silent wipe.

import XCTest
@testable import VaultKit

final class DeviceIdentityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testNoIdentityUntilEnsured() async throws {
        let store = DeviceIdentityStore(directory: try makeTemporaryDirectory())
        let before = await store.current()
        XCTAssertNil(before)
        do {
            _ = try await store.reserveSequence(count: 1)
            XCTFail("reserving before an identity exists must fail")
        } catch {
            XCTAssertEqual(error as? DeviceIdentityError, .noIdentity)
        }
    }

    func testCreatedOnceAndPersisted() async throws {
        let directory = try makeTemporaryDirectory()
        let store = DeviceIdentityStore(directory: directory)
        let created = try await store.ensureIdentity(now: now)
        XCTAssertTrue(VaultDeviceID.isValid(created.deviceId.rawValue))
        XCTAssertEqual(created.createdAt, now)
        XCTAssertEqual(created.nextSequence, 1)

        let again = try await store.ensureIdentity(now: now.addingTimeInterval(60))
        XCTAssertEqual(again, created, "ensureIdentity never replaces an existing id")

        let relaunched = DeviceIdentityStore(directory: directory)
        let reloaded = await relaunched.current()
        XCTAssertEqual(reloaded, created)
    }

    func testSequenceIsNeverReusedAfterACrash() async throws {
        let directory = try makeTemporaryDirectory()
        let store = DeviceIdentityStore(directory: directory)
        try await store.ensureIdentity(now: now)

        // spec: three numbers reserved, then the app is killed before use.
        let reserved = try await store.reserveSequence(count: 3)
        XCTAssertEqual(reserved, 1...3)

        let relaunched = DeviceIdentityStore(directory: directory)
        let next = try await relaunched.reserveSequence(count: 1)
        XCTAssertEqual(next, 4...4, "the next reservation starts above every reserved number")
        let more = try await relaunched.reserveSequence(count: 2)
        XCTAssertEqual(more, 5...6)

        do {
            _ = try await relaunched.reserveSequence(count: 0)
            XCTFail("count 0 must be refused")
        } catch {
            XCTAssertEqual(error as? DeviceIdentityError, .invalidCount)
        }
    }

    func testAFreshContainerGetsADifferentId() async throws {
        // Restore on a new phone: the identity file is never in a backup, so
        // the new container starts without one and creates its own.
        let ids = [VaultDeviceID("ios-11111111")!, VaultDeviceID("ios-22222222")!]
        let first = DeviceIdentityStore(directory: try makeTemporaryDirectory(), makeID: { ids[0] })
        let second = DeviceIdentityStore(directory: try makeTemporaryDirectory(), makeID: { ids[1] })
        let a = try await first.ensureIdentity(now: now)
        let b = try await second.ensureIdentity(now: now)
        XCTAssertNotEqual(a.deviceId, b.deviceId)

        // And real random ids differ too.
        let randomA = try await DeviceIdentityStore(directory: try makeTemporaryDirectory()).ensureIdentity(now: now)
        let randomB = try await DeviceIdentityStore(directory: try makeTemporaryDirectory()).ensureIdentity(now: now)
        XCTAssertNotEqual(randomA.deviceId, randomB.deviceId)
    }

    func testUndecodableFileIsQuarantinedNotOverwrittenSilently() async throws {
        let directory = try makeTemporaryDirectory()
        let fileURL = directory.appendingPathComponent(DeviceIdentityStore.fileName)
        try Data(#"{"deviceId":"ios-XYZ","createdAt":"nope"}"#.utf8).write(to: fileURL)

        let store = DeviceIdentityStore(directory: directory, makeID: { VaultDeviceID("ios-0000abcd")! })
        let current = await store.current()
        XCTAssertNil(current)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("device-identity.unreadable-") }, "the bad file is moved aside, not destroyed: \(names)")

        let created = try await store.ensureIdentity(now: now)
        XCTAssertEqual(created.deviceId.rawValue, "ios-0000abcd")
    }
}

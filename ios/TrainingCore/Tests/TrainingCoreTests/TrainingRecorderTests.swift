// TrainingRecorderTests.swift
//
// The local log and its delivery (add-training-checkins design D3-D5; spec
// training-event-log): durable appends that survive a reload, a corrupt
// log quarantined rather than wiped, pruning (sealed and old only), the
// recorder refusing without a device id, sequence numbers, sealing into
// one create-only segment per drain, a lost response ("already exists"
// with the same bytes) counted as delivered, offline keeping everything
// queued, and the overlay's latest-wins fold with its delivery state.
//
// Real stores on temp files (house convention: never mocked); the only
// stand-in is the transport.

import XCTest
import VaultKit
@testable import TrainingCore

/// A transport that stores what it is asked to create.
final class RecordingTransport: VaultTransport, @unchecked Sendable {
    enum Mode { case accept, offline, alreadyExists }

    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var mode: Mode

    init(mode: Mode = .accept) {
        self.mode = mode
    }

    func setMode(_ newMode: Mode) {
        lock.lock()
        mode = newMode
        lock.unlock()
    }

    var created: [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        return files
    }

    func put(_ path: String, _ bytes: Data) {
        lock.lock()
        files[path] = bytes
        lock.unlock()
    }

    func fetch(_ path: HubPath, ifNoneMatch: String?) async -> VaultFetchResult {
        lookup(path.rawValue)
    }

    private func lookup(_ path: String) -> VaultFetchResult {
        lock.lock()
        defer { lock.unlock() }
        if let bytes = files[path] { return VaultFetchResult(.fetched(bytes: bytes, etag: nil)) }
        return VaultFetchResult(.failed(.fileNotFound))
    }

    func createOnly(_ file: SealedFile) async -> VaultWriteResult {
        create(file)
    }

    private func create(_ file: SealedFile) -> VaultWriteResult {
        lock.lock()
        defer { lock.unlock() }
        switch mode {
        case .offline:
            return VaultWriteResult(.failed(.offline))
        case .alreadyExists:
            files[file.path.rawValue] = file.bytes
            return VaultWriteResult(.alreadyExists)
        case .accept:
            if files[file.path.rawValue] != nil { return VaultWriteResult(.alreadyExists) }
            files[file.path.rawValue] = file.bytes
            return VaultWriteResult(.created)
        }
    }

    func probe() async -> VaultProbeResult {
        VaultProbeResult(repository: .success, projection: .notFound, tokenExpiresAt: nil)
    }
}

final class TrainingRecorderTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_918_951_651) // 2030-10-23T02:07:31Z
    private var prague: TimeZone { TimeZone(identifier: "Europe/Prague")! }

    private struct Setup {
        let directory: URL
        let log: TrainingEventLog
        let identity: DeviceIdentityStore
        let queue: DurableQueue<SealedFile>
        let recorder: TrainingRecorder
    }

    private func makeSetup(withIdentity: Bool = true) async throws -> Setup {
        let directory = try makeTemporaryDirectory()
        let log = TrainingEventLog.make(directory: directory)
        let identity = DeviceIdentityStore(directory: directory, makeID: { VaultDeviceID("ios-0000beef")! })
        if withIdentity {
            try await identity.ensureIdentity(now: t0)
        }
        let queue = VaultWriteQueue.make(directory: directory)
        let counter = Counter()
        let recorder = TrainingRecorder(log: log, identity: identity, queue: queue, makeID: { _ in "id-\(counter.next())" })
        return Setup(directory: directory, log: log, identity: identity, queue: queue, recorder: recorder)
    }

    private func checkIn(_ light: MorningLight, _ date: String = "2030-10-23") -> HubEventPayload {
        .morningCheckIn(MorningCheckInPayload(date: D.date(date), light: light, sessionId: "2030-w43-wed-am"))
    }

    // MARK: Recording

    func testRecordingWithoutADeviceIDIsRefused() async throws {
        let setup = try await makeSetup(withIdentity: false)
        do {
            try await setup.recorder.record(checkIn(.amberLight), now: t0, timeZone: prague)
            XCTFail("recorded without a device id")
        } catch {
            XCTAssertEqual(error as? TrainingRecorderError, .noDeviceIdentity)
        }
        let events = await setup.log.all()
        XCTAssertTrue(events.isEmpty)
        let hasIdentity = await setup.recorder.hasDeviceIdentity()
        XCTAssertFalse(hasIdentity)
    }

    func testRecordingIsDurableAndNumbered() async throws {
        let setup = try await makeSetup()
        let first = try await setup.recorder.record(checkIn(.amberLight), now: t0, timeZone: prague)
        let second = try await setup.recorder.record(.habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "holds", done: true)), now: t0.addingTimeInterval(5), timeZone: prague)
        XCTAssertEqual(first.seq, 1)
        XCTAssertEqual(second.seq, 2)
        XCTAssertEqual(first.deviceId, "ios-0000beef")
        XCTAssertEqual(first.at, "2030-10-23T04:07:31.000+02:00")
        XCTAssertEqual(first.id, "id-1")

        // A fresh log instance over the same file sees both.
        let reopened = TrainingEventLog.make(directory: setup.directory)
        let events = await reopened.all()
        XCTAssertEqual(events.map(\.event), [first, second])
        XCTAssertTrue(events.allSatisfy { !$0.isSealed })
    }

    func testInvalidPayloadIsNotRecorded() async throws {
        let setup = try await makeSetup()
        do {
            try await setup.recorder.record(.sessionRPE(SessionRPEPayload(date: D.date("2030-10-23"), sessionId: "s", rpe: 12)), now: t0)
            XCTFail("recorded an RPE of 12")
        } catch {
            XCTAssertEqual(error as? HubEventError, .invalidPayload("rpe out of range"))
        }
        let next = try await setup.identity.reserveSequence(count: 1).lowerBound
        XCTAssertEqual(next, 1, "a refused payload reserves no sequence number")
    }

    // MARK: Delivery

    func testDrainSealsOneSegmentAndDeliversIt() async throws {
        let setup = try await makeSetup()
        try await setup.recorder.record(checkIn(.amberLight), now: t0, timeZone: prague)
        try await setup.recorder.record(checkIn(.greenLight), now: t0.addingTimeInterval(30), timeZone: prague)
        try await setup.recorder.record(.habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "holds", done: true)), now: t0.addingTimeInterval(60), timeZone: prague)

        let waitingBefore = await setup.recorder.waitingCount()
        XCTAssertEqual(waitingBefore, 3)

        let transport = RecordingTransport()
        let sealedAt = Date(timeIntervalSince1970: 1_918_951_800) // 02:10:00Z
        let result = await setup.recorder.drain(transport: transport, now: sealedAt)
        XCTAssertEqual(result.delivered.count, 1)
        XCTAssertNil(result.stoppedBy)

        let created = transport.created
        XCTAssertEqual(Array(created.keys), ["events/ios-0000beef/2030/10/20301023T021000Z-1.jsonl"])
        let decoded = HubEventCodec.decode(try XCTUnwrap(created.values.first))
        XCTAssertEqual(decoded.events.map(\.seq), [1, 2, 3])
        XCTAssertEqual(decoded.invalidLines, [])

        let waitingAfter = await setup.recorder.waitingCount()
        XCTAssertEqual(waitingAfter, 0)
        let overlay = await setup.recorder.overlay()
        XCTAssertEqual(overlay.light(on: D.date("2030-10-23")), OverlayValue(value: .greenLight, delivery: .sent))

        // Nothing new: a second drain creates nothing.
        let again = await setup.recorder.drain(transport: transport, now: sealedAt.addingTimeInterval(600))
        XCTAssertEqual(again.delivered.count, 0)
        XCTAssertEqual(transport.created.count, 1)
    }

    func testOfflineKeepsEverythingQueued() async throws {
        let setup = try await makeSetup()
        try await setup.recorder.record(checkIn(.redLight), now: t0, timeZone: prague)
        let transport = RecordingTransport(mode: .offline)
        let result = await setup.recorder.drain(transport: transport, now: t0.addingTimeInterval(10))
        XCTAssertEqual(result.stoppedBy, .offline)
        XCTAssertTrue(transport.created.isEmpty)
        let waiting = await setup.recorder.waitingCount()
        XCTAssertEqual(waiting, 1)
        let overlay = await setup.recorder.overlay()
        XCTAssertEqual(overlay.light(on: D.date("2030-10-23"))?.delivery, .savedOnPhone)
        let sealed = await setup.log.unsealed()
        XCTAssertTrue(sealed.isEmpty, "sealed once, queued, and resent as the same bytes later")

        transport.setMode(.accept)
        let retry = await setup.recorder.drain(transport: transport, now: t0.addingTimeInterval(20))
        XCTAssertEqual(retry.delivered.count, 1)
        XCTAssertEqual(transport.created.count, 1)
    }

    func testALostResponseWithTheSameBytesCountsAsDelivered() async throws {
        let setup = try await makeSetup()
        try await setup.recorder.record(checkIn(.amberLight), now: t0, timeZone: prague)
        let transport = RecordingTransport(mode: .alreadyExists)
        let result = await setup.recorder.drain(transport: transport, now: t0.addingTimeInterval(10))
        XCTAssertEqual(result.delivered.count, 1)
        XCTAssertEqual(result.failed.count, 0)
    }

    // MARK: Log

    func testPruneDropsOnlyOldSealedEvents() async throws {
        let directory = try makeTemporaryDirectory()
        let log = TrainingEventLog.make(directory: directory)
        let old = t0.addingTimeInterval(-30 * 86_400)
        let a = HubEvent(id: "a", deviceId: "ios-0000beef", seq: 1, at: "t", payload: checkIn(.amberLight))
        let b = HubEvent(id: "b", deviceId: "ios-0000beef", seq: 2, at: "t", payload: checkIn(.greenLight))
        let c = HubEvent(id: "c", deviceId: "ios-0000beef", seq: 3, at: "t", payload: checkIn(.redLight))
        try await log.append(a, now: old)
        try await log.append(b, now: old)
        try await log.append(c, now: t0)
        try await log.markSealed(["a", "c"], segment: UUID())
        try await log.prune(now: t0)
        let kept = await log.all().map(\.id)
        XCTAssertEqual(kept, ["b", "c"], "old+sealed pruned; old+unsealed and recent kept")
    }

    func testCorruptLogIsQuarantinedNotWiped() async throws {
        let directory = try makeTemporaryDirectory()
        let url = directory.appendingPathComponent(TrainingEventLog.fileName)
        try Data("not json".utf8).write(to: url)
        let log = TrainingEventLog(fileURL: url)
        let events = await log.all()
        XCTAssertTrue(events.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(names.contains { $0 != TrainingEventLog.fileName && $0.hasPrefix("training-events") }, "the unreadable file was moved aside: \(names)")
        try await log.append(HubEvent(id: "a", deviceId: "ios-0000beef", seq: 1, at: "t", payload: checkIn(.amberLight)), now: t0)
        let after = await log.all()
        XCTAssertEqual(after.count, 1)
    }

    // MARK: Overlay

    func testOverlayLatestWinsWithDelivery() {
        let segment = UUID()
        let unsentSegment = UUID()
        let events = [
            LoggedEvent(event: HubEvent(id: "1", deviceId: "d", seq: 1, at: "t", payload: checkIn(.amberLight)), recordedAt: t0, segmentID: segment),
            LoggedEvent(event: HubEvent(id: "2", deviceId: "d", seq: 2, at: "t", payload: checkIn(.greenLight)), recordedAt: t0.addingTimeInterval(1), segmentID: unsentSegment),
            LoggedEvent(event: HubEvent(id: "3", deviceId: "d", seq: 3, at: "t", payload: .habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "holds", done: true))), recordedAt: t0.addingTimeInterval(2), segmentID: segment),
            LoggedEvent(event: HubEvent(id: "4", deviceId: "d", seq: 4, at: "t", payload: .habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "holds", done: false))), recordedAt: t0.addingTimeInterval(3)),
            LoggedEvent(event: HubEvent(id: "5", deviceId: "d", seq: 5, at: "t", payload: .sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "s1", rpe: 7))), recordedAt: t0.addingTimeInterval(4), segmentID: segment),
            LoggedEvent(event: HubEvent(id: "6", deviceId: "d", seq: 6, at: "t", payload: .sessionNote(SessionNotePayload(date: D.date("2030-10-22"), sessionId: "s1", text: "ok"))), recordedAt: t0.addingTimeInterval(5))
        ]
        // Out of order on purpose: recording time decides.
        let overlay = CheckInOverlay.fold(Array(events.reversed()), unsentSegments: [unsentSegment])
        XCTAssertEqual(overlay.light(on: D.date("2030-10-23")), OverlayValue(value: .greenLight, delivery: .savedOnPhone))
        XCTAssertEqual(overlay.checkInSessions[D.date("2030-10-23")], "2030-w43-wed-am")
        XCTAssertEqual(overlay.habitTick(on: D.date("2030-10-23"), habitId: "holds"), OverlayValue(value: false, delivery: .savedOnPhone))
        XCTAssertEqual(overlay.rpe(session: "s1"), OverlayValue(value: 7, delivery: .sent))
        XCTAssertEqual(overlay.note(session: "s1"), OverlayValue(value: "ok", delivery: .savedOnPhone))
        XCTAssertNil(overlay.light(on: D.date("2030-10-24")))
        XCTAssertFalse(overlay.isEmpty)
        XCTAssertTrue(CheckInOverlay.empty.isEmpty)
    }

    // MARK: Planning

    func testCheckInPlanningUsesThePlansDayAndSession() throws {
        let projection = try Fixtures.exampleProjection().projection
        // 02:05Z is 04:05 in Prague, after the 03:00 boundary: the 23rd.
        let morning = CheckInPlanning.morningCheckIn(light: .amberLight, projection: projection, now: Date(timeIntervalSince1970: 1_918_951_500), deviceTimeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(morning, MorningCheckInPayload(date: D.date("2030-10-23"), light: .amberLight, sessionId: "2030-w43-wed-am"))
        // 22:00Z on the 22nd is 00:00 in Prague, before the boundary: still the 22nd.
        let night = CheckInPlanning.morningCheckIn(light: .greenLight, projection: projection, now: Date(timeIntervalSince1970: 1_918_936_800), deviceTimeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(night.date, D.date("2030-10-22"))
        XCTAssertNil(night.sessionId, "the 22nd's easy run has no options")
        // Rest day, and no projection at all.
        XCTAssertNil(CheckInPlanning.checkInSessionID(on: D.date("2030-10-25"), plan: projection.plan))
        let bare = CheckInPlanning.morningCheckIn(light: .redLight, projection: nil, now: Date(timeIntervalSince1970: 1_918_951_500), deviceTimeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(bare.date, D.date("2030-10-23"))
        XCTAssertNil(bare.sessionId)
    }
}

/// A thread-safe counter for injected ids.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

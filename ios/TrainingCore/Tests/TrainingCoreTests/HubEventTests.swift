// HubEventTests.swift
//
// The wire format (add-training-checkins design D2, spec "The wire format
// is one versioned, deterministic envelope"): byte-exact encoding against
// the synthetic golden fixture `Fixtures/Events/events.v1.app.jsonl`,
// decoding it back, tolerance of unknown fields and types, payload bounds,
// UUIDv7 ids, the `at` clock, and segments (path, bytes, message, chunks).
//
// The vault's own event fixtures (its `add-hub-ingest` contract, mirrored
// verbatim under Fixtures/Contract/vault/) are decoded here too: the four
// types this app writes decode to their payloads, the rest to `.other`.

import XCTest
import VaultKit
@testable import TrainingCore

enum EventFixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TrainingCoreTests
        .appendingPathComponent("Fixtures/Events", isDirectory: true)

    static func appGolden() throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("events.v1.app.jsonl"))
    }

    static func vault(_ name: String) throws -> Data {
        try Fixtures.data(name)
    }

    static let device = "ios-0000beef"
    static var deviceID: VaultDeviceID { VaultDeviceID(device)! }

    /// The golden file's events, built in Swift.
    static var goldenEvents: [HubEvent] {
        [
            HubEvent(id: "01beca6e-76b8-7abc-bd11-223344556601", deviceId: device, seq: 1, at: "2030-10-23T04:07:31.000+02:00",
                     payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-23"), light: .amberLight, sessionId: "2030-w43-wed-am"))),
            HubEvent(id: "01beca6e-efd0-7abc-bd11-223344556602", deviceId: device, seq: 2, at: "2030-10-23T04:08:02.000+02:00",
                     payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-23"), light: .greenLight, sessionId: "2030-w43-wed-am"))),
            HubEvent(id: "01becde4-38a0-7abc-bd11-223344556603", deviceId: device, seq: 3, at: "2030-10-23T20:15:00.000+02:00",
                     payload: .habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "holds", done: true))),
            HubEvent(id: "01becde4-4840-7abc-bd11-223344556604", deviceId: device, seq: 4, at: "2030-10-23T20:15:04.000+02:00",
                     payload: .habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "gym", done: false))),
            HubEvent(id: "01bece0d-6b80-7abc-bd11-223344556605", deviceId: device, seq: 5, at: "2030-10-23T21:00:00.000+02:00",
                     payload: .sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 6))),
            HubEvent(id: "01bece0d-e0b0-7abc-bd11-223344556606", deviceId: device, seq: 6, at: "2030-10-23T21:00:30.000+02:00",
                     payload: .sessionNote(SessionNotePayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", text: "Lýtko ztuhlé po 8 km / \"ok\"\nzítra lehce"))),
            HubEvent(id: "01bed506-b2c0-7abc-bd11-223344556607", deviceId: device, seq: 7, at: "2030-10-25T05:30:00.000+02:00",
                     payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-25"), light: .redLight, sessionId: nil)))
        ]
    }
}

final class HubEventTests: XCTestCase {
    // MARK: Golden

    func testEncodingReproducesTheGoldenFileByteForByte() throws {
        let encoded = try HubEventCodec.jsonl(EventFixtures.goldenEvents)
        let golden = try EventFixtures.appGolden()
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), String(decoding: golden, as: UTF8.self))
        XCTAssertEqual(encoded, golden)
        XCTAssertEqual(encoded.last, 0x0A, "every line ends with a newline")
    }

    func testDecodingTheGoldenFile() throws {
        let decoded = HubEventCodec.decode(try EventFixtures.appGolden())
        XCTAssertEqual(decoded.invalidLines, [])
        XCTAssertEqual(decoded.events, EventFixtures.goldenEvents)
        XCTAssertEqual(decoded.events.map(\.type.rawValue), [
            "checkin.morning", "checkin.morning", "habit.tick", "habit.tick", "session.rpe", "session.note", "checkin.morning"
        ])
    }

    func testOptionalKeysAreWrittenAsNull() throws {
        // The contract: optional keys may be absent or null, and the app
        // should write them.
        let rest = String(decoding: try HubEventCodec.line(EventFixtures.goldenEvents[6]), as: UTF8.self)
        XCTAssertTrue(rest.contains("\"option\":null"))
        XCTAssertTrue(rest.contains("\"sessionId\":null"))
        let rpe = String(decoding: try HubEventCodec.line(EventFixtures.goldenEvents[4]), as: UTF8.self)
        XCTAssertTrue(rpe.contains("\"feel\":null"))
        // The option follows the light when the day has a session.
        XCTAssertEqual(MorningCheckInPayload(date: D.asOf, light: .amberLight, sessionId: "s").option, .a)
        XCTAssertNil(MorningCheckInPayload(date: D.asOf, light: .amberLight).option)
    }

    // MARK: The vault's contract fixtures

    func testTheVaultsExampleDecodes() throws {
        let decoded = HubEventCodec.decode(try EventFixtures.vault("events.v1.example.jsonl"))
        XCTAssertEqual(decoded.invalidLines, [])
        XCTAssertEqual(decoded.events.count, 22)
        XCTAssertEqual(decoded.events.map(\.seq), Array(1...22))
        XCTAssertTrue(decoded.events.allSatisfy { $0.deviceId == "ios-0a1b2c3d" && $0.v == 1 })

        let byType = Dictionary(grouping: decoded.events, by: { $0.type.rawValue }).mapValues(\.count)
        XCTAssertEqual(byType["checkin.morning"], 7)
        XCTAssertEqual(byType["habit.tick"], 3)
        XCTAssertEqual(byType["session.rpe"], 1)
        XCTAssertEqual(byType["session.note"], 1)
        let others = decoded.events.filter { if case .other = $0.type { return true } else { return false } }
        XCTAssertEqual(Set(others.map(\.type.rawValue)), [
            "device.hello", "plan.session.skipped", "plan.session.moved", "plan.session.swapped",
            "plan.rule.overridden", "event.retracted", "plan.session.unskipped"
        ])

        XCTAssertEqual(decoded.events[1].payload, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-14"), light: .redLight, sessionId: nil, option: nil)))
        XCTAssertEqual(decoded.events[2].payload, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-16"), light: .greenLight, sessionId: "2030-w42-wed-am", option: .g)))
        XCTAssertEqual(decoded.events[8].payload, .sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 7, feel: 3)))
        XCTAssertEqual(decoded.events[11].payload, .habitTick(HabitTickPayload(date: D.date("2030-10-22"), habitId: "holds", done: true)))
        XCTAssertNil(decoded.events[3].payload.date, "a plan command carries a week, not a date")

        // Every event this app could write re-encodes and reads back the same.
        for event in decoded.events {
            if case .other = event.payload { continue }
            XCTAssertEqual(HubEventCodec.decode(try HubEventCodec.jsonl([event])).events, [event])
        }
    }

    func testTheVaultsMinimalDecodes() throws {
        let decoded = HubEventCodec.decode(try EventFixtures.vault("events.v1.minimal.jsonl"))
        XCTAssertEqual(decoded.invalidLines, [])
        XCTAssertEqual(decoded.events.map(\.type.rawValue), ["device.hello", "checkin.morning", "habit.tick"])
        XCTAssertEqual(decoded.events[1].payload, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-23"), light: .greenLight, sessionId: nil, option: nil)))
        XCTAssertEqual(decoded.events[1].at, "2030-10-23T04:01:00+02:00", "the fraction is optional")
    }

    func testTheVaultsExampleFoldsLikeThePhonesOwnEvents() throws {
        let events = HubEventCodec.decode(try EventFixtures.vault("events.v1.example.jsonl")).events
        let base = Date(timeIntervalSince1970: 1_918_000_000)
        let logged = events.map { LoggedEvent(event: $0, recordedAt: base.addingTimeInterval(Double($0.seq)), segmentID: nil) }
        let overlay = CheckInOverlay.fold(logged, unsentSegments: [])
        XCTAssertEqual(overlay.light(on: D.date("2030-10-23"))?.value, .amberLight)
        XCTAssertEqual(overlay.habitTick(on: D.date("2030-10-22"), habitId: "holds")?.value, true, "last per habit and day wins")
        XCTAssertEqual(overlay.rpe(session: "2030-w43-tue-am")?.value, 7)
        XCTAssertEqual(overlay.note(session: "2030-w43-tue-am")?.value, "Calf tight on the last repeat, eased off.")
    }

    // MARK: Tolerance

    func testUnknownFieldsAndTypesAreTolerated() {
        let text = """
        {"at":"2030-10-23T04:07:31.000+02:00","deviceId":"ios-0000beef","extra":{"x":1},"id":"a","payload":{"date":"2030-10-23","habitId":"holds","done":true,"part":"pm"},"seq":1,"type":"habit.tick","v":1}
        {"at":"2030-10-23T04:07:32.000+02:00","deviceId":"ios-0000beef","id":"b","payload":{"name":"phone","date":"2030-10-23"},"seq":2,"type":"device.hello","v":1}

        not json
        {"at":"x","deviceId":"ios-0000beef","id":"c","payload":{"date":"2030-10-23","light":"purple"},"seq":3,"type":"checkin.morning","v":1}\r
        """
        let decoded = HubEventCodec.decode(Data(text.utf8))
        XCTAssertEqual(decoded.events.count, 2)
        XCTAssertEqual(decoded.events[0].payload, .habitTick(HabitTickPayload(date: D.date("2030-10-23"), habitId: "holds", done: true)))
        XCTAssertEqual(decoded.events[1].type, .other("device.hello"))
        XCTAssertEqual(decoded.events[1].payload.date, D.date("2030-10-23"))
        XCTAssertEqual(decoded.invalidLines, [4, 5], "a bad line and an unknown light are reported, not fatal")
    }

    func testUnknownTypesAreNeverWritten() {
        let event = HubEvent(id: "x", deviceId: EventFixtures.device, seq: 1, at: "t", payload: .other(type: "device.hello", date: nil))
        XCTAssertThrowsError(try HubEventCodec.line(event))
        XCTAssertThrowsError(try event.payload.validate())
    }

    // MARK: Bounds

    func testPayloadBounds() {
        let date = D.date("2030-10-23")
        XCTAssertNoThrow(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "s", rpe: 1)).validate())
        XCTAssertNoThrow(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "s", rpe: 10)).validate())
        XCTAssertThrowsError(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "s", rpe: 0)).validate())
        XCTAssertThrowsError(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "s", rpe: 11)).validate())
        XCTAssertThrowsError(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "", rpe: 5)).validate())
        XCTAssertThrowsError(try HubEventPayload.habitTick(HabitTickPayload(date: date, habitId: "", done: true)).validate())
        let long = String(repeating: "a", count: SessionNotePayload.maxLength + 1)
        XCTAssertThrowsError(try HubEventPayload.sessionNote(SessionNotePayload(date: date, sessionId: "s", text: long)).validate())
        XCTAssertNoThrow(try HubEventPayload.sessionNote(SessionNotePayload(date: date, sessionId: "s", text: String(long.dropFirst()))).validate())
        XCTAssertThrowsError(try HubEventPayload.sessionNote(SessionNotePayload(date: date, sessionId: "s", text: "")).validate())
        XCTAssertThrowsError(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "s", rpe: 5, feel: 6)).validate())
        XCTAssertNoThrow(try HubEventPayload.sessionRPE(SessionRPEPayload(date: date, sessionId: "s", rpe: 5, feel: 3)).validate())
    }

    // MARK: Ids and clock

    func testUUIDv7Layout() {
        let date = Date(timeIntervalSince1970: 1_918_951_651.25)
        let uuid = UUIDv7.make(at: date) { bytes in
            for index in bytes.indices { bytes[index] = 0xFF }
        }
        let u = uuid.uuid
        XCTAssertEqual(u.6 >> 4, 0x7, "version 7")
        XCTAssertEqual(u.8 >> 6, 0b10, "RFC 9562 variant")
        XCTAssertEqual(UUIDv7.milliseconds(of: uuid), 1_918_951_651_250)
        XCTAssertEqual(uuid.uuidString.lowercased().prefix(13), "01beca6e-77b2")
    }

    func testUUIDv7StringsSortByTime() {
        let earlier = UUIDv7.string(at: Date(timeIntervalSince1970: 1_918_951_651))
        let later = UUIDv7.string(at: Date(timeIntervalSince1970: 1_918_951_652))
        XCTAssertLessThan(earlier, later)
        XCTAssertEqual(earlier, earlier.lowercased())
        XCTAssertNotEqual(UUIDv7.string(at: Date(timeIntervalSince1970: 1)), UUIDv7.string(at: Date(timeIntervalSince1970: 1)))
    }

    func testClockKeepsTheLocalOffset() throws {
        let date = Date(timeIntervalSince1970: 1_918_951_651) // 2030-10-23T02:07:31Z
        let prague = try XCTUnwrap(TimeZone(identifier: "Europe/Prague"))
        XCTAssertEqual(HubEventClock.string(date, timeZone: prague), "2030-10-23T04:07:31.000+02:00")
        XCTAssertEqual(HubEventClock.string(date, timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))), "2030-10-23T02:07:31.000Z")
    }

    // MARK: Segments

    func testSegmentPathIsInTheOwnFolder() throws {
        let sealedAt = Date(timeIntervalSince1970: 1_918_951_800) // 2030-10-23T02:10:00Z
        let path = try XCTUnwrap(EventSegment.path(deviceID: EventFixtures.deviceID, sealedAt: sealedAt, firstSeq: 1))
        XCTAssertEqual(path.rawValue, "events/ios-0000beef/2030/10/20301023T021000Z-1.jsonl")
        XCTAssertTrue(VaultPathPolicy(ownDeviceID: EventFixtures.deviceID).allowsWrite(path))
        XCTAssertFalse(VaultPathPolicy(ownDeviceID: VaultDeviceID("ios-00000001")!).allowsWrite(path))
    }

    func testSealedSegmentCarriesTheJSONL() throws {
        let sealedAt = Date(timeIntervalSince1970: 1_918_951_800)
        let file = try EventSegment.seal(EventFixtures.goldenEvents, deviceID: EventFixtures.deviceID, sealedAt: sealedAt)
        XCTAssertEqual(file.bytes, try EventFixtures.appGolden())
        XCTAssertEqual(file.blobSHA, GitBlob.sha1Hex(of: try EventFixtures.appGolden()))
        XCTAssertEqual(file.commitMessage, "hub: ios-0000beef seq 1-7 (7)")
        XCTAssertThrowsError(try EventSegment.seal([], deviceID: EventFixtures.deviceID, sealedAt: sealedAt))
    }

    func testChunksOfAtMostFiveHundred() {
        let one = EventFixtures.goldenEvents[0]
        let events = (1...1001).map { HubEvent(id: "\($0)", deviceId: one.deviceId, seq: $0, at: one.at, payload: one.payload) }
        let chunks = EventSegment.chunks(events)
        XCTAssertEqual(chunks.map(\.count), [500, 500, 1])
        XCTAssertEqual(chunks[1].first?.seq, 501)
        XCTAssertEqual(EventSegment.chunks([]).count, 0)
    }
}

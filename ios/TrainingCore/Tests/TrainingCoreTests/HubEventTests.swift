// HubEventTests.swift
//
// The wire format (add-training-checkins design D2, spec "The wire format
// is one versioned, deterministic envelope"): byte-exact encoding against
// the synthetic golden fixture `Fixtures/Events/events.v1.app.jsonl`,
// decoding it back, tolerance of unknown fields and types, payload bounds,
// UUIDv7 ids, the `at` clock, and segments (path, bytes, message, chunks).
//
// The vault's own event fixtures (its `add-hub-ingest` contract, mirrored
// verbatim under Fixtures/Contract/vault/) are decoded here too: every
// type this app writes decodes to its payload, `device.hello` to
// `.other`. add-plan-editing adds the plan commands and the retraction: a
// byte-exact golden file of its own (`plan-commands.v1.app.jsonl`) and a
// line-by-line comparison with the vault's example commands.
// add-checkin-pain-score adds `pains` to the check-in: every check-in line
// of the first golden file carries `"pains":null`, and a third golden file
// (`checkin-pains.v1.app.jsonl`, accepted by the vault's `validateEvent`
// on 2026-09-30) pins a list, an empty list and a note that needs escaping.

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

    static func planGolden() throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("plan-commands.v1.app.jsonl"))
    }

    static func painGolden() throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("checkin-pains.v1.app.jsonl"))
    }

    /// The pain golden file's events, built in Swift (add-checkin-pain-score D1).
    static var painGoldenEvents: [HubEvent] {
        [
            HubEvent(id: "01beca7b-6c00-7abc-bd11-223344556615", deviceId: device, seq: 15, at: "2030-10-23T04:20:00.000+02:00",
                     payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-23"), light: .amberLight, sessionId: "2030-w43-wed-am", pains: [
                        PainEntry(site: .achillesLeft, score: 5.5, note: "Stiff for the first steps"),
                        PainEntry(site: .kneeRight, score: 1)
                     ]))),
            HubEvent(id: "01becf9f-f8e0-7abc-bd11-223344556616", deviceId: device, seq: 16, at: "2030-10-24T04:05:00.000+02:00",
                     payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-24"), light: .greenLight, sessionId: nil, pains: []))),
            HubEvent(id: "01bed507-9d20-7abc-bd11-223344556617", deviceId: device, seq: 17, at: "2030-10-25T05:31:00.000+02:00",
                     payload: .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-25"), light: .redLight, sessionId: nil, pains: [
                        PainEntry(site: .achillesLeft, score: 0),
                        PainEntry(site: .achillesRight, score: 0),
                        PainEntry(site: .other, score: 2, note: "Lower back / \"desk day\"")
                     ])))
        ]
    }

    /// The plan-command golden file's events, built in Swift
    /// (add-plan-editing D2).
    static var planGoldenEvents: [HubEvent] {
        let w43 = D.week("2030-W43")
        let w44 = D.week("2030-W44")
        return [
            HubEvent(id: "01becdb6-a200-7abc-bd11-223344556608", deviceId: device, seq: 8, at: "2030-10-23T20:00:00.000+02:00",
                     payload: .sessionMoved(SessionMovedPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-tue-am", from: D.date("2030-10-31"), to: D.date("2030-11-01")))),
            HubEvent(id: "01becdb7-8c60-7abc-bd11-223344556609", deviceId: device, seq: 9, at: "2030-10-23T20:01:00.000+02:00",
                     payload: .sessionsSwapped(SessionsSwappedPayload(week: w44, baseRevision: 1, a: "2030-w44-fri-am", aDate: D.date("2030-10-29"), b: "2030-w44-wed-am", bDate: D.date("2030-10-30")))),
            HubEvent(id: "01becdb8-76c0-7abc-bd11-22334455660a", deviceId: device, seq: 10, at: "2030-10-23T20:02:00.000+02:00",
                     payload: .sessionSkipped(SessionSkippedPayload(week: w43, baseRevision: 1, sessionId: "2030-w43-sat-am", reason: "Travel day / rest"))),
            HubEvent(id: "01becdb9-6120-7abc-bd11-22334455660b", deviceId: device, seq: 11, at: "2030-10-23T20:03:00.000+02:00",
                     payload: .sessionSkipped(SessionSkippedPayload(week: w43, baseRevision: 1, sessionId: "2030-w43-thu-pm", reason: nil))),
            HubEvent(id: "01becdba-4b80-7abc-bd11-22334455660c", deviceId: device, seq: 12, at: "2030-10-23T20:04:00.000+02:00",
                     payload: .sessionUnskipped(SessionUnskippedPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-mon-pm"))),
            HubEvent(id: "01becdbb-35e0-7abc-bd11-22334455660d", deviceId: device, seq: 13, at: "2030-10-23T20:05:00.000+02:00",
                     payload: .ruleOverridden(RuleOverriddenPayload(week: w44, baseRevision: 1, sessionId: "2030-w44-wed-am", rule: "two-ambers"))),
            HubEvent(id: "01becdbc-2040-7abc-bd11-22334455660e", deviceId: device, seq: 14, at: "2030-10-23T20:06:00.000+02:00",
                     payload: .eventRetracted(EventRetractedPayload(target: "01becdb9-6120-7abc-bd11-22334455660b")))
        ]
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
        XCTAssertTrue(rest.contains("\"pains\":null"), "pain not asked (add-checkin-pain-score)")
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
        XCTAssertEqual(decoded.events.count, 31)
        XCTAssertEqual(decoded.events.map(\.seq), Array(1...31))
        XCTAssertTrue(decoded.events.allSatisfy { $0.deviceId == "ios-0a1b2c3d" && $0.v == 1 })

        let byType = Dictionary(grouping: decoded.events, by: { $0.type.rawValue }).mapValues(\.count)
        XCTAssertEqual(byType["checkin.morning"], 8)
        XCTAssertEqual(byType["habit.tick"], 6)
        XCTAssertEqual(byType["session.rpe"], 2)
        XCTAssertEqual(byType["session.note"], 1)
        XCTAssertEqual(byType["plan.session.moved"], 4)
        XCTAssertEqual(byType["plan.session.swapped"], 1)
        XCTAssertEqual(byType["plan.session.skipped"], 2)
        XCTAssertEqual(byType["plan.session.unskipped"], 1)
        XCTAssertEqual(byType["plan.rule.overridden"], 1)
        XCTAssertEqual(byType["event.retracted"], 1)
        let others = decoded.events.filter { if case .other = $0.type { return true } else { return false } }
        // The vault's 2026-10-01 contract added `test.gate` (seq 25) and
        // `session.done` (seq 26, 27): this build doesn't write them, so
        // they read as `.other` -- never an invalid line.
        XCTAssertEqual(Set(others.map(\.type.rawValue)), ["device.hello", "test.gate", "session.done"])
        XCTAssertEqual(others.map(\.seq), [1, 25, 26, 27])
        XCTAssertEqual(decoded.events[24].payload, .other(type: "test.gate", date: D.date("2030-10-23")))
        XCTAssertEqual(decoded.events[25].payload, .other(type: "session.done", date: D.date("2030-10-21")))

        XCTAssertEqual(decoded.events[1].payload, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-14"), light: .redLight, sessionId: nil, option: nil)))
        XCTAssertEqual(decoded.events[2].payload, .morningCheckIn(MorningCheckInPayload(date: D.date("2030-10-16"), light: .greenLight, sessionId: "2030-w42-wed-am", option: .g)))
        XCTAssertEqual(decoded.events[8].payload, .sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 7, feel: 3)))
        XCTAssertEqual(decoded.events[11].payload, .habitTick(HabitTickPayload(date: D.date("2030-10-22"), habitId: "holds", done: true)))
        XCTAssertNil(decoded.events[3].payload.date, "a plan command carries a week, not a date")
        XCTAssertEqual(decoded.events[3].payload, .sessionSkipped(SessionSkippedPayload(week: D.week("2030-W42"), baseRevision: 2, sessionId: "2030-w42-thu-pm", reason: "Calf tight, skip the shake-out")))
        XCTAssertEqual(decoded.events[14].payload, .sessionsSwapped(SessionsSwappedPayload(week: D.week("2030-W44"), baseRevision: 1, a: "2030-w44-tue-am", aDate: D.date("2030-10-29"), b: "2030-w44-fri-am", bDate: D.date("2030-10-31"))))
        XCTAssertEqual(decoded.events[19].payload, .eventRetracted(EventRetractedPayload(target: "01beca6a-5420-7113-a113-5eed00000013", reason: "Changed my mind, ride it")))
        // seq 24 (2026-09-30, the vault's A57): a second check-in of the day
        // with pains; a missing note reads as none.
        XCTAssertEqual(decoded.events[23].payload, .morningCheckIn(MorningCheckInPayload(
            date: D.date("2030-10-23"), light: .amberLight, sessionId: "2030-w43-wed-am", option: .a,
            pains: [PainEntry(site: .achillesLeft, score: 5.5, note: "Stiff first steps, eases after 10 min"), PainEntry(site: .kneeRight, score: 1)]
        )))
        let otherPains = decoded.events.filter { $0.seq != 24 }.compactMap { event -> [PainEntry]? in
            if case .morningCheckIn(let payload) = event.payload { return payload.pains }
            return nil
        }
        XCTAssertEqual(otherPains, [], "no other check-in carries pains")
        // seq 28 (2026-10-01): an RPE with `pains` during/after the session.
        // The key is not read yet (unknown keys are ignored): the RPE is.
        XCTAssertEqual(decoded.events[27].payload, .sessionRPE(SessionRPEPayload(date: D.date("2030-10-22"), sessionId: "2030-w43-tue-am", rpe: 7, feel: 3)))
        // seq 29-31: a back-filled tick, and two the vault refuses (too old,
        // in the future) -- all three are ordinary ticks on the wire.
        XCTAssertEqual(decoded.events[28...30].map(\.payload.date), [D.date("2030-10-21"), D.date("2030-10-01"), D.date("2030-10-25")])
        XCTAssertEqual(decoded.events[28].payload, .habitTick(HabitTickPayload(date: D.date("2030-10-21"), habitId: "holds", done: true)))

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
        XCTAssertEqual(overlay.pains(on: D.date("2030-10-23"))?.value.map(\.site), [.achillesLeft, .kneeRight])
        XCTAssertNil(overlay.pains(on: D.date("2030-10-22")), "not asked")
    }

    // MARK: Pain (add-checkin-pain-score)

    func testPainCheckInsReproduceTheirGoldenFileByteForByte() throws {
        let encoded = try HubEventCodec.jsonl(EventFixtures.painGoldenEvents)
        let golden = try EventFixtures.painGolden()
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), String(decoding: golden, as: UTF8.self))
        XCTAssertEqual(encoded, golden)

        let decoded = HubEventCodec.decode(golden)
        XCTAssertEqual(decoded.invalidLines, [])
        XCTAssertEqual(decoded.events, EventFixtures.painGoldenEvents)
        for event in decoded.events {
            XCTAssertNoThrow(try event.payload.validate())
        }
        let text = String(decoding: golden, as: UTF8.self)
        XCTAssertTrue(text.contains("\"score\":1,"), "a whole score has no fraction")
        XCTAssertTrue(text.contains("\"score\":5.5,"))
        XCTAssertTrue(text.contains("\"pains\":[]"), "asked, nothing hurts")
    }

    func testPainBounds() {
        func checkIn(_ pains: [PainEntry]) -> HubEventPayload {
            .morningCheckIn(MorningCheckInPayload(date: D.asOf, light: .amberLight, sessionId: nil, pains: pains))
        }
        XCTAssertNoThrow(try checkIn([]).validate())
        XCTAssertNoThrow(try checkIn([PainEntry(site: .achillesLeft, score: 0)]).validate())
        XCTAssertNoThrow(try checkIn([PainEntry(site: .achillesLeft, score: 10)]).validate())
        XCTAssertNoThrow(try checkIn([PainEntry(site: .kneeLeft, score: 4.5)]).validate())
        for score in [4.3, -0.5, 10.5, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try checkIn([PainEntry(site: .achillesLeft, score: score)]).validate(), "\(score)")
        }
        XCTAssertThrowsError(try checkIn([PainEntry(site: .other, score: 1, note: "   ")]).validate(), "a blank note")
        XCTAssertThrowsError(try checkIn([PainEntry(site: .other, score: 1, note: "")]).validate())
        XCTAssertNoThrow(try checkIn([PainEntry(site: .other, score: 1, note: String(repeating: "a", count: 200))]).validate())
        XCTAssertThrowsError(try checkIn([PainEntry(site: .other, score: 1, note: String(repeating: "a", count: 201))]).validate())
        // The vault counts UTF-16 units: 100 emoji are 200 units, 101 too many.
        XCTAssertNoThrow(try checkIn([PainEntry(site: .other, score: 1, note: String(repeating: "\u{1F9B5}", count: 100))]).validate())
        XCTAssertThrowsError(try checkIn([PainEntry(site: .other, score: 1, note: String(repeating: "\u{1F9B5}", count: 101))]).validate())
    }

    func testUnknownPainSiteReadsAsOther() {
        let line = #"{"v":1,"id":"01beca76-3b00-7118-a118-5eed00000099","deviceId":"ios-0a1b2c3d","seq":30,"at":"2030-10-23T04:16:00.000+02:00","type":"checkin.morning","payload":{"date":"2030-10-23","light":"green","pains":[{"site":"hip-left","score":2},{"site":"achilles-right","score":0.5,"note":null}]}}"#
        let decoded = HubEventCodec.decode(Data(line.utf8))
        XCTAssertEqual(decoded.invalidLines, [])
        XCTAssertEqual(decoded.events.first?.payload, .morningCheckIn(MorningCheckInPayload(
            date: D.date("2030-10-23"), light: .greenLight, sessionId: nil, option: nil,
            pains: [PainEntry(site: .other, score: 2), PainEntry(site: .achillesRight, score: 0.5)]
        )))
        let nullPains = #"{"v":1,"id":"01beca76-3b00-7118-a118-5eed0000009a","deviceId":"ios-0a1b2c3d","seq":31,"at":"2030-10-23T04:17:00.000+02:00","type":"checkin.morning","payload":{"date":"2030-10-23","light":"green","pains":null}}"#
        guard case .morningCheckIn(let payload)? = HubEventCodec.decode(Data(nullPains.utf8)).events.first?.payload else {
            return XCTFail("not a check-in")
        }
        XCTAssertNil(payload.pains, "null = not asked")
    }

    // MARK: Plan commands (add-plan-editing)

    func testPlanCommandsReproduceTheirGoldenFileByteForByte() throws {
        let encoded = try HubEventCodec.jsonl(EventFixtures.planGoldenEvents)
        let golden = try EventFixtures.planGolden()
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), String(decoding: golden, as: UTF8.self))
        XCTAssertEqual(encoded, golden)

        let decoded = HubEventCodec.decode(golden)
        XCTAssertEqual(decoded.invalidLines, [])
        XCTAssertEqual(decoded.events, EventFixtures.planGoldenEvents)
        XCTAssertEqual(decoded.events.map(\.type.rawValue), [
            "plan.session.moved", "plan.session.swapped", "plan.session.skipped", "plan.session.skipped",
            "plan.session.unskipped", "plan.rule.overridden", "event.retracted"
        ])
        for event in decoded.events {
            XCTAssertNoThrow(try event.payload.validate(), event.type.rawValue)
        }
    }

    func testTheVaultsExampleCommandsReencodeToTheSameObjects() throws {
        // The vault's lines are not key-sorted, so compare JSON objects.
        let data = try EventFixtures.vault("events.v1.example.jsonl")
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        var compared = 0
        for line in lines {
            let event = try XCTUnwrap(HubEventCodec.decode(Data(line.utf8)).events.first)
            guard event.payload.isPlanCommand || event.type == .eventRetracted else { continue }
            let ours = try XCTUnwrap(JSONSerialization.jsonObject(with: try HubEventCodec.line(event)) as? NSDictionary)
            let theirs = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? NSDictionary)
            XCTAssertEqual(ours, theirs, "seq \(event.seq)")
            compared += 1
        }
        XCTAssertEqual(compared, 10, "nine commands and one retraction")
    }

    func testOptionalReasonIsWrittenAsNull() throws {
        let skip = String(decoding: try HubEventCodec.line(EventFixtures.planGoldenEvents[3]), as: UTF8.self)
        XCTAssertTrue(skip.contains("\"reason\":null"))
        let retraction = String(decoding: try HubEventCodec.line(EventFixtures.planGoldenEvents[6]), as: UTF8.self)
        XCTAssertTrue(retraction.contains("\"reason\":null"))
        XCTAssertNil(EventFixtures.planGoldenEvents[0].payload.date)
        XCTAssertEqual(EventFixtures.planGoldenEvents[1].payload.commandSessionIDs, ["2030-w44-fri-am", "2030-w44-wed-am"])
        XCTAssertEqual(EventFixtures.planGoldenEvents[1].payload.commandWeek, D.week("2030-W44"))
        XCTAssertFalse(EventFixtures.planGoldenEvents[6].payload.isPlanCommand)
    }

    func testPlanCommandBounds() {
        let week = D.week("2030-W43")
        func move(_ from: String, _ to: String, revision: Int = 1, id: String = "s") -> HubEventPayload {
            .sessionMoved(SessionMovedPayload(week: week, baseRevision: revision, sessionId: id, from: D.date(from), to: D.date(to)))
        }
        XCTAssertNoThrow(try move("2030-10-24", "2030-10-27").validate())
        XCTAssertThrowsError(try move("2030-10-24", "2030-10-28").validate(), "another week")
        XCTAssertThrowsError(try move("2030-10-24", "2030-10-24").validate(), "the same day")
        XCTAssertThrowsError(try move("2030-10-24", "2030-10-25", revision: 0).validate(), "no revision")
        XCTAssertThrowsError(try move("2030-10-24", "2030-10-25", id: "").validate(), "no session")

        let swapSame = HubEventPayload.sessionsSwapped(SessionsSwappedPayload(week: week, baseRevision: 1, a: "x", aDate: D.date("2030-10-24"), b: "x", bDate: D.date("2030-10-25")))
        XCTAssertThrowsError(try swapSame.validate())
        let swapDay = HubEventPayload.sessionsSwapped(SessionsSwappedPayload(week: week, baseRevision: 1, a: "x", aDate: D.date("2030-10-24"), b: "y", bDate: D.date("2030-10-24")))
        XCTAssertThrowsError(try swapDay.validate())

        XCTAssertThrowsError(try HubEventPayload.sessionSkipped(SessionSkippedPayload(week: week, baseRevision: 1, sessionId: "s", reason: "")).validate(), "an empty reason is written as null, never as \"\"")
        let long = String(repeating: "a", count: SessionNotePayload.maxLength + 1)
        XCTAssertThrowsError(try HubEventPayload.sessionSkipped(SessionSkippedPayload(week: week, baseRevision: 1, sessionId: "s", reason: long)).validate())
        XCTAssertThrowsError(try HubEventPayload.ruleOverridden(RuleOverriddenPayload(week: week, baseRevision: 1, sessionId: "s", rule: "")).validate())
        XCTAssertThrowsError(try HubEventPayload.eventRetracted(EventRetractedPayload(target: "")).validate())
        XCTAssertNoThrow(try HubEventPayload.eventRetracted(EventRetractedPayload(target: "x", reason: "why")).validate())
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

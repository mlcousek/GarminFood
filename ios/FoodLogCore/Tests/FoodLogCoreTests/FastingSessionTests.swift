// FastingSessionTests.swift
//
// The retired manual-fasting model is now only read, once, to seed the
// daily schedule (redesign-fasting-schedule 1.3). These tests pin down
// that: the legacy `fasting-sessions.json` shape still decodes through the
// read-only `FastingSessionStore` (hand-written fixture JSON in the exact
// shape older builds wrote -- no store writes anything any more), reading
// it leaves the file untouched, and `FastingScheduleMigration.seed` turns
// the last session into the right daily window. Real files at unique temp
// paths, never mocked; explicit Europe/Prague calendar.

import XCTest
@testable import FoodLogCore

final class FastingSessionTests: XCTestCase {
    private var prague: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        prague.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-fasting-legacy-\(UUID().uuidString).json")
    }

    // MARK: - Protocol

    func testNamedProtocolsCarryTheirOwnHourPairs() {
        XCTAssertEqual(FastingProtocol.sixteenEight.fastingHours, 16)
        XCTAssertEqual(FastingProtocol.eighteenSix.fastingHours, 18)
        XCTAssertEqual(FastingProtocol.twentyFour.fastingHours, 20)
        XCTAssertEqual(FastingProtocol.omad.fastingHours, 23)
        XCTAssertEqual(FastingProtocol.custom(fastingHours: 14, eatingHours: 10).fastingHours, 14)
    }

    func testProtocolWireShapeRoundTrips() throws {
        for kind: FastingProtocol in [.sixteenEight, .eighteenSix, .twentyFour, .omad, .custom(fastingHours: 14.5, eatingHours: 9.5)] {
            let data = try JSONEncoder().encode(kind)
            XCTAssertEqual(try JSONDecoder().decode(FastingProtocol.self, from: data), kind)
        }
    }

    // MARK: - Legacy store (read-only)

    func testLegacyFileDecodesAndIsLeftUntouched() async throws {
        let url = tempURL()
        let json = """
        {
          "active": null,
          "history": [
            {
              "id": "6F1C2D3E-0000-4000-8000-000000000001",
              "protocolKind": { "kind": "sixteenEight" },
              "startedAt": "2026-09-20T18:00:00Z",
              "fastingEndedAt": "2026-09-21T10:00:00Z",
              "eatingEndedAt": "2026-09-21T18:00:00Z"
            },
            {
              "id": "6F1C2D3E-0000-4000-8000-000000000002",
              "protocolKind": { "kind": "custom", "fastingHours": 14, "eatingHours": 10 },
              "startedAt": "2026-09-21T19:00:00Z",
              "fastingEndedAt": "2026-09-22T09:30:00Z",
              "eatingEndedAt": "2026-09-22T19:00:00Z"
            }
          ]
        }
        """
        let original = Data(json.utf8)
        try original.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let store = FastingSessionStore(fileURL: url)
        let active = await store.active()
        let history = await store.history()

        XCTAssertNil(active)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.first?.protocolKind, .custom(fastingHours: 14, eatingHours: 10), "newest first")
        XCTAssertEqual(history.last?.protocolKind, .sixteenEight)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the legacy file is never deleted")
        XCTAssertEqual(try Data(contentsOf: url), original, "reading never rewrites it")
    }

    func testMissingLegacyFileReadsAsEmpty() async {
        let store = FastingSessionStore(fileURL: tempURL())
        let active = await store.active()
        let history = await store.history()
        XCTAssertNil(active)
        XCTAssertTrue(history.isEmpty)
    }

    // MARK: - Migration seed

    func testNoLegacySessionsSeedsTheStandardWindowSwitchedOff() {
        let seed = FastingScheduleMigration.seed(active: nil, history: [], calendar: prague)
        XCTAssertEqual(seed, FastingScheduleMigration.Seed(schedule: .standard, isEnabled: false))
    }

    func testSixteenEightLastBrokenAtNoonSeedsTwentyToTwelve() {
        let last = FastingSession(
            protocolKind: .sixteenEight,
            startedAt: local(2026, 9, 21, 20, 13),
            fastingEndedAt: local(2026, 9, 22, 12, 0),
            eatingEndedAt: local(2026, 9, 22, 20, 0)
        )

        let seed = FastingScheduleMigration.seed(active: nil, history: [last], calendar: prague)

        XCTAssertTrue(seed.isEnabled, "they were already fasting, so it stays on")
        XCTAssertEqual(seed.schedule.startMinute, 20 * 60)
        XCTAssertEqual(seed.schedule.endMinute, 12 * 60)
    }

    func testTheMostRecentlyStartedSessionWins() {
        let older = FastingSession(protocolKind: .eighteenSix, startedAt: local(2026, 9, 19, 18), fastingEndedAt: local(2026, 9, 20, 12))
        let newer = FastingSession(protocolKind: .sixteenEight, startedAt: local(2026, 9, 21, 19), fastingEndedAt: local(2026, 9, 22, 11, 30))

        let seed = FastingScheduleMigration.seed(active: nil, history: [newer, older], calendar: prague)

        XCTAssertEqual(seed.schedule.startMinute, 19 * 60 + 30)
        XCTAssertEqual(seed.schedule.endMinute, 11 * 60 + 30)
    }

    func testAnActiveUnbrokenFastUsesItsScheduledEnd() {
        let finished = FastingSession(protocolKind: .sixteenEight, startedAt: local(2026, 9, 21, 20), fastingEndedAt: local(2026, 9, 22, 12))
        let running = FastingSession(protocolKind: .eighteenSix, startedAt: local(2026, 9, 22, 19))

        let seed = FastingScheduleMigration.seed(active: running, history: [finished], calendar: prague)

        XCTAssertEqual(seed.schedule.startMinute, 19 * 60)
        XCTAssertEqual(seed.schedule.endMinute, 13 * 60, "19:00 + 18 h")
        XCTAssertEqual(seed.schedule.fastingMinutes, 18 * 60)
    }

    func testOMADSeedsATwentyThreeHourWindow() {
        let last = FastingSession(protocolKind: .omad, startedAt: local(2026, 9, 21, 19), fastingEndedAt: local(2026, 9, 22, 18))

        let seed = FastingScheduleMigration.seed(active: nil, history: [last], calendar: prague)

        XCTAssertEqual(seed.schedule.endMinute, 18 * 60)
        XCTAssertEqual(seed.schedule.startMinute, 19 * 60)
        XCTAssertEqual(seed.schedule.fastingMinutes, 23 * 60)
    }

    func testANonsensicalCustomProtocolFallsBackToTheStandardWindowButStaysOn() {
        let last = FastingSession(protocolKind: .custom(fastingHours: 30, eatingHours: 2), startedAt: local(2026, 9, 21, 19))

        let seed = FastingScheduleMigration.seed(active: nil, history: [last], calendar: prague)

        XCTAssertEqual(seed, FastingScheduleMigration.Seed(schedule: .standard, isEnabled: true))
    }
}

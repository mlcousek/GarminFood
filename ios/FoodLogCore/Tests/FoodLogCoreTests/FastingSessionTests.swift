// FastingSessionTests.swift
//
// Pure logic (protocol hour math, phase derivation, completion, streak) and
// store tests for FastingSession.swift -- same conventions as
// MealPresetTests.swift: real `FastingSessionStore` instances at unique
// temp files (never mocked), explicit `now:`/`at:` parameters rather than
// reading the system clock.

import XCTest
@testable import FoodLogCore

final class FastingSessionTests: XCTestCase {
    private let hour: TimeInterval = 3600

    // MARK: - Protocol

    func testNamedProtocolsCarryTheirOwnHourPairs() {
        XCTAssertEqual(FastingProtocol.sixteenEight.fastingHours, 16)
        XCTAssertEqual(FastingProtocol.sixteenEight.eatingHours, 8)
        XCTAssertEqual(FastingProtocol.eighteenSix.fastingHours, 18)
        XCTAssertEqual(FastingProtocol.eighteenSix.eatingHours, 6)
        XCTAssertEqual(FastingProtocol.twentyFour.fastingHours, 20)
        XCTAssertEqual(FastingProtocol.twentyFour.eatingHours, 4)
        XCTAssertEqual(FastingProtocol.omad.fastingHours, 23)
        XCTAssertEqual(FastingProtocol.omad.eatingHours, 1)
    }

    func testCustomProtocolCarriesItsOwnHours() {
        let custom = FastingProtocol.custom(fastingHours: 14, eatingHours: 10)
        XCTAssertEqual(custom.fastingHours, 14)
        XCTAssertEqual(custom.eatingHours, 10)
    }

    // MARK: - Phase

    func testCurrentPhaseIsFastingBeforeTheScheduledBoundary() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start)

        let phase = session.currentPhase(at: start.addingTimeInterval(4 * hour))

        XCTAssertEqual(phase.kind, .fasting)
        XCTAssertEqual(phase.scheduledEndAt, start.addingTimeInterval(16 * hour))
        XCTAssertEqual(phase.remaining(at: start.addingTimeInterval(4 * hour)), 12 * hour, accuracy: 0.01)
        XCTAssertEqual(phase.elapsed(at: start.addingTimeInterval(4 * hour)), 4 * hour, accuracy: 0.01)
    }

    func testCurrentPhaseStaysFastingPastTheScheduledBoundaryUntilExplicitlyEnded() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start)

        let now = start.addingTimeInterval(20 * hour)
        let phase = session.currentPhase(at: now)

        XCTAssertEqual(phase.kind, .fasting, "not ended by the user yet, so still fasting even though the 16h target passed")
        XCTAssertTrue(phase.isOverdue(at: now))
    }

    func testCurrentPhaseMovesToEatingOnceFastingEndedAtIsSet() {
        let start = Date(timeIntervalSince1970: 0)
        let brokeFastAt = start.addingTimeInterval(16 * hour)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start, fastingEndedAt: brokeFastAt)

        let now = brokeFastAt.addingTimeInterval(2 * hour)
        let phase = session.currentPhase(at: now)

        XCTAssertEqual(phase.kind, .eating)
        XCTAssertEqual(phase.startedAt, brokeFastAt)
        XCTAssertEqual(phase.scheduledEndAt, brokeFastAt.addingTimeInterval(8 * hour))
    }

    func testCurrentPhaseUsesTheActualEatingEndWhenSet() {
        let start = Date(timeIntervalSince1970: 0)
        let brokeFastAt = start.addingTimeInterval(16 * hour)
        let endedEatingAt = brokeFastAt.addingTimeInterval(3 * hour)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start, fastingEndedAt: brokeFastAt, eatingEndedAt: endedEatingAt)

        let phase = session.currentPhase(at: endedEatingAt.addingTimeInterval(hour))

        XCTAssertEqual(phase.scheduledEndAt, endedEatingAt, "the actual recorded end wins over the protocol's own 8h schedule")
    }

    func testFractionIsClampedBetweenZeroAndOne() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start)

        XCTAssertEqual(session.currentPhase(at: start).fraction(at: start), 0)
        XCTAssertEqual(session.currentPhase(at: start.addingTimeInterval(8 * hour)).fraction(at: start.addingTimeInterval(8 * hour)), 0.5, accuracy: 0.001)
        XCTAssertEqual(session.currentPhase(at: start.addingTimeInterval(40 * hour)).fraction(at: start.addingTimeInterval(40 * hour)), 1)
    }

    // MARK: - Completion

    func testMetFastingTargetIsFalseWhileStillActive() {
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: Date())
        XCTAssertFalse(session.metFastingTarget)
    }

    func testMetFastingTargetIsTrueWhenTheFastRanAtLeastAsLongAsTheProtocol() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start, fastingEndedAt: start.addingTimeInterval(16 * hour))
        XCTAssertTrue(session.metFastingTarget)
    }

    func testMetFastingTargetIsFalseWhenTheFastBrokeEarly() {
        let start = Date(timeIntervalSince1970: 0)
        let session = FastingSession(protocolKind: .sixteenEight, startedAt: start, fastingEndedAt: start.addingTimeInterval(10 * hour))
        XCTAssertFalse(session.metFastingTarget)
    }

    // MARK: - Stats

    func testCurrentRunCountsConsecutiveCompletedFastsFromMostRecent() {
        let start = Date(timeIntervalSince1970: 0)
        let completed = { (daysAgo: Double) in
            FastingSession(
                protocolKind: .sixteenEight,
                startedAt: start.addingTimeInterval(-daysAgo * 86400),
                fastingEndedAt: start.addingTimeInterval(-daysAgo * 86400 + 16 * self.hour)
            )
        }
        let brokeEarly = { (daysAgo: Double) in
            FastingSession(
                protocolKind: .sixteenEight,
                startedAt: start.addingTimeInterval(-daysAgo * 86400),
                fastingEndedAt: start.addingTimeInterval(-daysAgo * 86400 + 5 * self.hour)
            )
        }

        let history = [completed(1), completed(2), brokeEarly(3), completed(4)]

        XCTAssertEqual(FastingStats.currentRun(history: history), 2, "the day-3 early break stops the run before day 4 is counted")
    }

    func testCurrentRunIgnoresTheInProgressSession() {
        let start = Date(timeIntervalSince1970: 0)
        let inProgress = FastingSession(protocolKind: .sixteenEight, startedAt: start)
        let completedYesterday = FastingSession(
            protocolKind: .sixteenEight,
            startedAt: start.addingTimeInterval(-86400),
            fastingEndedAt: start.addingTimeInterval(-86400 + 16 * hour)
        )

        let run = FastingStats.currentRun(history: [inProgress, completedYesterday])

        XCTAssertEqual(run, 1)
    }

    func testCurrentRunIsZeroWithNoCompletedFasts() {
        XCTAssertEqual(FastingStats.currentRun(history: []), 0)
    }

    // MARK: - Store

    private func makeStore() -> FastingSessionStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-fasting-test-\(UUID().uuidString).json")
        return FastingSessionStore(fileURL: url)
    }

    func testStartThenActiveReturnsTheSession() async throws {
        let store = makeStore()
        let session = FastingSession(protocolKind: .sixteenEight)

        try await store.start(session)

        let active = await store.active()
        XCTAssertEqual(active?.id, session.id)
    }

    func testStartingASecondFastWhileOneIsActiveThrows() async throws {
        let store = makeStore()
        try await store.start(FastingSession(protocolKind: .sixteenEight))

        do {
            try await store.start(FastingSession(protocolKind: .omad))
            XCTFail("expected sessionAlreadyActive")
        } catch FastingSessionStore.StoreError.sessionAlreadyActive {
            // expected
        }
    }

    func testEndFastingPhaseMovesTheActiveSessionToEatingWithoutArchivingIt() async throws {
        let store = makeStore()
        try await store.start(FastingSession(protocolKind: .sixteenEight, startedAt: Date(timeIntervalSince1970: 0)))

        try await store.endFastingPhase(at: Date(timeIntervalSince1970: 16 * hour))

        let active = await store.active()
        XCTAssertEqual(active?.fastingEndedAt, Date(timeIntervalSince1970: 16 * hour))
        let history = await store.history()
        XCTAssertTrue(history.isEmpty, "still active, not archived yet")
    }

    func testEndFastingPhaseWithNoActiveSessionThrows() async throws {
        let store = makeStore()
        do {
            try await store.endFastingPhase(at: Date())
            XCTFail("expected noActiveSession")
        } catch FastingSessionStore.StoreError.noActiveSession {
            // expected
        }
    }

    func testEndActiveSessionArchivesItAndClearsActive() async throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 0)
        try await store.start(FastingSession(protocolKind: .sixteenEight, startedAt: start))
        try await store.endFastingPhase(at: start.addingTimeInterval(16 * hour))

        let ended = try await store.endActiveSession(at: start.addingTimeInterval(24 * hour))

        XCTAssertEqual(ended.eatingEndedAt, start.addingTimeInterval(24 * hour))
        let active = await store.active()
        XCTAssertNil(active)
        let history = await store.history()
        XCTAssertEqual(history.map(\.id), [ended.id])
    }

    func testEndActiveSessionThatNeverBrokeFastStillSetsFastingEndedAt() async throws {
        let store = makeStore()
        let start = Date(timeIntervalSince1970: 0)
        try await store.start(FastingSession(protocolKind: .sixteenEight, startedAt: start))

        let ended = try await store.endActiveSession(at: start.addingTimeInterval(5 * hour))

        XCTAssertEqual(ended.fastingEndedAt, start.addingTimeInterval(5 * hour))
        XCTAssertEqual(ended.eatingEndedAt, start.addingTimeInterval(5 * hour))
    }

    func testCancelActiveSessionDiscardsItWithoutArchiving() async throws {
        let store = makeStore()
        try await store.start(FastingSession(protocolKind: .sixteenEight))

        try await store.cancelActiveSession()

        let active = await store.active()
        XCTAssertNil(active)
        let history = await store.history()
        XCTAssertTrue(history.isEmpty, "a cancelled fast never counts towards history/streak")
    }

    func testCancelActiveSessionWithNoActiveSessionThrows() async throws {
        let store = makeStore()
        do {
            try await store.cancelActiveSession()
            XCTFail("expected noActiveSession")
        } catch FastingSessionStore.StoreError.noActiveSession {
            // expected
        }
    }

    func testDeleteFromHistoryRemovesIt() async throws {
        let store = makeStore()
        try await store.start(FastingSession(protocolKind: .sixteenEight))
        let ended = try await store.endActiveSession(at: Date())

        try await store.deleteFromHistory(id: ended.id)

        let history = await store.history()
        XCTAssertTrue(history.isEmpty)
    }

    func testStateSurvivesAFreshStoreInstanceAtTheSameFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-fasting-persist-\(UUID().uuidString).json")
        let store1 = FastingSessionStore(fileURL: url)
        try await store1.start(FastingSession(protocolKind: .omad, startedAt: Date(timeIntervalSince1970: 0)))
        _ = try await store1.endActiveSession(at: Date(timeIntervalSince1970: 23 * hour))

        let store2 = FastingSessionStore(fileURL: url)
        let active = await store2.active()
        let history = await store2.history()

        XCTAssertNil(active)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.protocolKind, .omad)
    }
}

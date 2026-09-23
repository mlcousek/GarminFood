// WeightHistoryMergeTests.swift
//
// design.md D1 (sync-weight-hydration-with-garmin): Garmin's weigh-ins and
// the app's own must merge into ONE history with no duplicates, Garmin's
// copy winning once a local entry is delivered. Covers the four cases the
// task list names -- delivered duplicate, pending, Garmin-only, near-miss --
// plus the delete-hiding rules (D3) and the "Garmin not re-read since the
// delivery" grace. Outbox entries are built with `WeightOutboxEntry`'s
// public initializer (the same values a real drain writes), since
// `WeightHistoryMerge` is a pure function over them.

import XCTest
@testable import FoodLogCore
import GarminKit

final class WeightHistoryMergeTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        return calendar
    }

    /// 2026-09-23 08:21:31 CEST -- the owner's real 83.9 kg weigh-in.
    private let morning = Date(timeIntervalSince1970: 1_790_149_291.732)

    private func garmin(_ pk: Int, kg: Double, at date: Date, day: String = "2026-09-23") -> GarminWeighIn {
        GarminWeighIn(samplePk: pk, calendarDate: day, weightGrams: (kg * 1000).rounded(), timestampGMT: date.timeIntervalSince1970 * 1000)
    }

    private func local(kg: Double, at date: Date, outboxId: UUID?, note: String? = nil) -> WeightEntry {
        WeightEntry(weightKg: kg, loggedAt: date, note: note, createdAt: date, outboxEntryId: outboxId)
    }

    private func outbox(_ id: UUID, state: OutboxEntryState, kg: Double, at date: Date, deliveredAt: Date? = nil) -> WeightOutboxEntry {
        WeightOutboxEntry(id: id, weightKg: kg, loggedAt: date, state: state, operation: .add, deliveredAt: deliveredAt)
    }

    // MARK: - Delivered duplicate

    func testADeliveredEntryAppearsOnceAsGarminsCopyKeepingItsNote() {
        let outboxId = UUID()
        let mine = local(kg: 83.9, at: morning, outboxId: outboxId, note: "after run")
        let theirs = garmin(1, kg: 83.9, at: morning.addingTimeInterval(1.5))

        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [theirs],
            garminDayFetchedAt: ["2026-09-23": morning.addingTimeInterval(600)],
            localEntries: [mine],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning, deliveredAt: morning.addingTimeInterval(5))],
            calendar: calendar
        )

        XCTAssertEqual(rows.count, 1, "exactly one 83.9 kg entry at that time")
        XCTAssertTrue(rows[0].isFromGarmin, "Garmin's copy wins -- it carries the samplePk a delete needs")
        XCTAssertEqual(rows[0].syncState, .synced)
        XCTAssertEqual(rows[0].note, "after run", "the local note survives the merge")
        XCTAssertEqual(rows[0].source, .garmin(theirs, matchedLocalEntry: mine))
    }

    func testAnEntryFromAnOlderBuildWithoutDeliveredAtStillDeduplicates() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [garmin(1, kg: 82.8, at: morning)],
            garminDayFetchedAt: ["2026-09-23": morning],
            localEntries: [local(kg: 82.8, at: morning.addingTimeInterval(-30), outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 82.8, at: morning)],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isFromGarmin)
    }

    func testTwoIdenticalWeighInsMatchOneToOne() {
        let firstId = UUID(), secondId = UUID()
        let later = morning.addingTimeInterval(60)
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [garmin(1, kg: 80, at: morning), garmin(2, kg: 80, at: later)],
            garminDayFetchedAt: ["2026-09-23": later.addingTimeInterval(600)],
            localEntries: [local(kg: 80, at: morning, outboxId: firstId), local(kg: 80, at: later, outboxId: secondId)],
            outboxEntries: [outbox(firstId, state: .sent, kg: 80, at: morning), outbox(secondId, state: .sent, kg: 80, at: later)],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy(\.isFromGarmin), "each local entry claims its own sample, never the same one twice")
    }

    // MARK: - Pending / failed

    func testAPendingEntryIsShownAndNeverDeduplicated() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [],
            garminDayFetchedAt: ["2026-09-23": morning.addingTimeInterval(600)],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .pending, kg: 83.9, at: morning)],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].syncState, .pending)
        XCTAssertEqual(rows[0].outboxEntryId, outboxId)
        XCTAssertFalse(rows[0].isFromGarmin)
    }

    func testAFailedEntryIsShownAsFailedWithItsOutboxIdForRetry() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [],
            garminDayFetchedAt: [:],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .failed, kg: 83.9, at: morning)],
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.syncState), [.failed])
        XCTAssertEqual(rows.first?.outboxEntryId, outboxId)
    }

    // MARK: - Garmin-only

    func testAScaleOrConnectWeighInAppears() {
        let scale = garmin(9, kg: 82.8, at: morning)
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [scale],
            garminDayFetchedAt: ["2026-09-23": morning],
            localEntries: [],
            outboxEntries: [],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].weightKg, 82.8, accuracy: 0.0001)
        XCTAssertEqual(rows[0].loggedAt, scale.timestamp)
        XCTAssertEqual(rows[0].syncState, .synced)
        XCTAssertNil(rows[0].note)
    }

    // MARK: - Near misses

    func testATimeNearMissOutsideTwoMinutesIsNotMerged() {
        let outboxId = UUID()
        let delivered = morning.addingTimeInterval(10)
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [garmin(1, kg: 83.9, at: morning.addingTimeInterval(121))],
            // Garmin last read BEFORE the delivery, so the unmatched local
            // entry is kept (Garmin can't know about it yet).
            garminDayFetchedAt: ["2026-09-23": morning],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning, deliveredAt: delivered)],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 2, "121 s apart is two different weigh-ins")
    }

    func testAWeightNearMissOverFiftyGramsIsNotMerged() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [garmin(1, kg: 84.0, at: morning)],
            garminDayFetchedAt: ["2026-09-23": morning],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning, deliveredAt: morning.addingTimeInterval(5))],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 2)
    }

    func testTheToleranceEdgesStillMatch() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            // 119 s, not exactly 120: epoch-ms <-> seconds round trips can
            // add a sub-microsecond, which must not decide the test.
            garminWeighIns: [garmin(1, kg: 83.95, at: morning.addingTimeInterval(119))],
            garminDayFetchedAt: ["2026-09-23": morning.addingTimeInterval(600)],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning, deliveredAt: morning.addingTimeInterval(5))],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1, "just under 2 min and 50 g apart is still the same weigh-in")
    }

    // MARK: - Delivered but not (or no longer) in Garmin

    func testADeliveredEntryDeletedInConnectDisappearsOnceGarminIsReRead() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [],
            garminDayFetchedAt: ["2026-09-23": morning.addingTimeInterval(3_600)],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning, deliveredAt: morning.addingTimeInterval(5))],
            calendar: calendar
        )
        XCTAssertTrue(rows.isEmpty, "Garmin is the truth once it has been read after the delivery")
    }

    func testAJustDeliveredEntryStaysVisibleUntilGarminIsReRead() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [],
            garminDayFetchedAt: ["2026-09-23": morning.addingTimeInterval(-60)],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning, deliveredAt: morning.addingTimeInterval(5))],
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.syncState), [.synced], "no blink-out between delivery and the next Garmin read")
    }

    func testOfflineWithNoGarminReadEverShowsLocalEntries() {
        let outboxId = UUID()
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [],
            garminDayFetchedAt: [:],
            localEntries: [local(kg: 83.9, at: morning, outboxId: outboxId)],
            outboxEntries: [outbox(outboxId, state: .sent, kg: 83.9, at: morning)],
            calendar: calendar
        )
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - Deletes (D3)

    func testASampleWithAQueuedDeleteIsHiddenAtOnce() {
        let sample = garmin(5, kg: 82.8, at: morning)
        let delete = WeightOutboxEntry(weightKg: 82.8, loggedAt: morning, state: .pending, operation: .delete, samplePk: 5, calendarDate: "2026-09-23")
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [sample],
            garminDayFetchedAt: ["2026-09-23": morning],
            localEntries: [],
            outboxEntries: [delete],
            calendar: calendar
        )
        XCTAssertTrue(rows.isEmpty)
    }

    func testASampleWhoseDeleteFailedReappearsFlaggedWithTheDeleteToRetry() {
        let sample = garmin(5, kg: 82.8, at: morning)
        let delete = WeightOutboxEntry(weightKg: 82.8, loggedAt: morning, state: .failed, operation: .delete, samplePk: 5, calendarDate: "2026-09-23")
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [sample],
            garminDayFetchedAt: ["2026-09-23": morning],
            localEntries: [],
            outboxEntries: [delete],
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.syncState), [.deleteFailed])
        XCTAssertEqual(rows.first?.outboxEntryId, delete.id)
    }

    // MARK: - Ordering

    func testRowsAreNewestFirstAcrossSources() {
        let pendingId = UUID()
        let yesterday = morning.addingTimeInterval(-86_400)
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [garmin(1, kg: 83.0, at: yesterday, day: "2026-09-22")],
            garminDayFetchedAt: ["2026-09-22": morning, "2026-09-23": morning],
            localEntries: [local(kg: 83.9, at: morning, outboxId: pendingId)],
            outboxEntries: [outbox(pendingId, state: .pending, kg: 83.9, at: morning)],
            calendar: calendar
        )
        XCTAssertEqual(rows.map(\.weightKg), [83.9, 83.0])
    }

    func testDeltaBetweenMergedRows() throws {
        let rows = WeightHistoryMerge.merge(
            garminWeighIns: [garmin(1, kg: 83.9, at: morning), garmin(2, kg: 82.8, at: morning.addingTimeInterval(-3_600))],
            garminDayFetchedAt: [:],
            localEntries: [],
            outboxEntries: [],
            calendar: calendar
        )
        let delta = try XCTUnwrap(WeightHistory.delta(latest: rows[0], previous: rows[1]))
        XCTAssertEqual(delta, 1.1, accuracy: 0.0001)
    }
}

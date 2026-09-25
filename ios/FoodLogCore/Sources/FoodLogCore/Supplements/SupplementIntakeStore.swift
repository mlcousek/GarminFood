// SupplementIntakeStore.swift
//
// The intake log -- every tick and extra dose (add-supplements D2, task
// 2.1). The local system of record for supplements; Garmin plays no part.
//
// Shape decisions:
//   - One JSON file per calendar month (`SupplementIntake/2026-09.json`),
//     like `LocalFoodLogStore`: a tick rewrites one small file, and a
//     backfill a year back (D14) touches only that month.
//   - Planned ticks are IDEMPOTENT, keyed by (day, product, slot): ticking
//     twice, "Take all" after a single tick, or the reminder's "Taken"
//     action delivered twice (D5 spec "Double tap") leaves exactly one
//     record per item. Extras are separate records by design.
//   - Every write checks `PastDayLogging.editability` against `today`:
//     only today and the last 365 days, never the future (D14). Each record
//     stores `recordedOn` (the day it was written) for the late-entry XP
//     rule.
//   - The store contract of this package (SupplementStoreSupport.swift):
//     quarantine on undecodable months, unreadable months refuse reads and
//     writes, every mutation loads its month first.
//
// Local-first: every call is a local file write, no network, so the
// checklist shows a tick immediately (spec "Airplane mode").
//
// Depended on by: AppServices, the supplements screen and Today card
// (wave 3), the notification "Taken" action (wave 4).
// Tests: SupplementStoresTests.

import Foundation
import GarminKit

public actor SupplementIntakeStore {
    private let directoryURL: URL
    private var shards: [String: [IntakeRecord]] = [:]
    private var loadedMonths: Set<String> = []

    public init(directoryURL: URL = SupplementIntakeStore.defaultDirectoryURL()) {
        self.directoryURL = directoryURL
    }

    public static func defaultDirectoryURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("SupplementIntake", isDirectory: true)
    }

    // MARK: Reads

    /// The day's records in write order. Throws when its month's file exists
    /// but can't be read yet.
    public func records(forDay day: String) throws -> [IntakeRecord] {
        let month = try Self.month(ofDay: day)
        return try readableShard(month).filter { $0.day == day }
    }

    /// Every record on days `startDay...endDay` (inclusive), oldest day
    /// first, write order within a day.
    public func records(fromDay startDay: String, toDay endDay: String) throws -> [IntakeRecord] {
        let first = try Self.month(ofDay: startDay)
        let last = try Self.month(ofDay: endDay)
        guard first <= last else { return [] }
        var result: [IntakeRecord] = []
        for month in LocalFoodLogStore.months(from: first, to: last) {
            result.append(contentsOf: try readableShard(month).filter { $0.day >= startDay && $0.day <= endDay })
        }
        return result.enumerated()
            .sorted { lhs, rhs in
                lhs.element.day != rhs.element.day ? lhs.element.day < rhs.element.day : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: Writes

    /// Ticks `items` as taken on `day` ("Take all", a single tick, or the
    /// reminder's "Taken" action). Idempotent per (day, product, slot): an
    /// item already ticked keeps its record. Returns the records now stored
    /// for `items`, in their order. One write at most.
    @discardableResult
    public func recordPlanned(_ items: [DueItem], on day: String, takenAt: Date, today: String) throws -> [IntakeRecord] {
        try requireEditable(day, today: today)
        let month = try Self.month(ofDay: day)
        var records = try loadedShardForWrite(month)
        var byKey: [PlannedIntakeKey: IntakeRecord] = [:]
        for record in records {
            if let key = record.plannedKey, byKey[key] == nil { byKey[key] = record }
        }
        var result: [IntakeRecord] = []
        var changed = false
        for item in items {
            let key = item.key(on: day)
            if let existing = byKey[key] {
                result.append(existing)
                continue
            }
            let record = IntakeRecord(
                day: day,
                productId: item.productId,
                slot: item.slot,
                servings: item.servings,
                takenAt: takenAt,
                kind: .planned,
                recordedOn: today
            )
            byKey[key] = record
            records.append(record)
            result.append(record)
            changed = true
        }
        if changed { try write(records, month: month) }
        return result
    }

    /// Unticks a planned item (every planned record under its key). No-op
    /// when it wasn't ticked.
    public func removePlanned(productId: UUID, slot: TimeSlot, on day: String, today: String) throws {
        try requireEditable(day, today: today)
        let month = try Self.month(ofDay: day)
        let records = try loadedShardForWrite(month)
        let key = PlannedIntakeKey(day: day, productId: productId, slotKey: slot.key)
        let kept = records.filter { $0.plannedKey != key }
        guard kept.count != records.count else { return }
        try write(kept, month: month)
    }

    /// Logs a one-off extra dose (never replaces a planned item).
    @discardableResult
    public func addExtra(productId: UUID, servings: Double, on day: String, takenAt: Date, today: String) throws -> IntakeRecord {
        try requireEditable(day, today: today)
        let month = try Self.month(ofDay: day)
        let records = try loadedShardForWrite(month)
        let record = IntakeRecord(day: day, productId: productId, slot: nil, servings: servings, takenAt: takenAt, kind: .extra, recordedOn: today)
        try write(records + [record], month: month)
        return record
    }

    /// Deletes one record (an extra logged by mistake). No-op when absent.
    public func remove(id: UUID, on day: String, today: String) throws {
        try requireEditable(day, today: today)
        let month = try Self.month(ofDay: day)
        let records = try loadedShardForWrite(month)
        let kept = records.filter { $0.id != id }
        guard kept.count != records.count else { return }
        try write(kept, month: month)
    }

    // MARK: Files

    func fileURL(month: String) -> URL {
        directoryURL.appendingPathComponent("\(month).json")
    }

    private func requireEditable(_ day: String, today: String) throws {
        guard PastDayLogging.editability(of: day, today: today) == .editable else {
            throw SupplementStoreError.dayNotEditable(day)
        }
    }

    private func loadIfNeeded(_ month: String) {
        guard !loadedMonths.contains(month) else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON(
            [IntakeRecord].self,
            from: fileURL(month: month),
            decoder: JSONDecoder(),
            category: "SupplementIntakeStore"
        )
        shards[month] = result.value ?? []
        // Unreadable (e.g. before first unlock): retry on next access.
        if !result.isUnreadable { loadedMonths.insert(month) }
    }

    private func readableShard(_ month: String) throws -> [IntakeRecord] {
        loadIfNeeded(month)
        guard loadedMonths.contains(month) else {
            throw PersistedJSONUnreadFileError(fileName: fileURL(month: month).lastPathComponent)
        }
        return shards[month] ?? []
    }

    private func loadedShardForWrite(_ month: String) throws -> [IntakeRecord] {
        loadIfNeeded(month)
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loadedMonths.contains(month), fileURL: fileURL(month: month), category: "SupplementIntakeStore")
        return shards[month] ?? []
    }

    private func write(_ records: [IntakeRecord], month: String) throws {
        try SupplementStoreIO.write(records, to: fileURL(month: month), category: "SupplementIntakeStore")
        shards[month] = records
    }

    /// `yyyy-MM` of a valid `yyyy-MM-dd` day.
    static func month(ofDay day: String) throws -> String {
        guard SupplementDate.ordinal(day) != nil else { throw SupplementStoreError.dayNotEditable(day) }
        return String(day.prefix(7))
    }
}

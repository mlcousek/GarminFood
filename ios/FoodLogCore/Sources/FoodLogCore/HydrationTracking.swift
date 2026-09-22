// HydrationTracking.swift
//
// The hydration domain layer -- the water-tracking equivalent of
// WeightTracking.swift. Same reason a local `HydrationEntry` exists
// separately from GarminKit's `HydrationOutboxEntry`: GarminKit has no UI
// layer and no concept of "today's running total" or "this drink's own
// identity independent of whichever outbox entry is currently trying to
// deliver it". `HydrationEntry` is that identity -- durable, JSON-file-
// backed (`HydrationStore`, the exact same pattern as `WeightStore`), and
// the source of truth the Hydration screen actually reads. `outboxEntryId`
// is the only link back to GarminKit's delivery queue, kept purely so a
// later delete can also cancel an undelivered outbox entry -- see
// `HydrationLogCoordinator.deleteHydration`.

import Foundation

public struct HydrationEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var valueInML: Double
    /// What the user says the drink happened -- may be backdated. This is
    /// what's shown in the day's total/history AND what's sent to Garmin,
    /// via the linked outbox entry.
    public var loggedAt: Date
    /// When this record was actually created on this device -- distinct
    /// from `loggedAt` only when backdated. Same reasoning as
    /// `WeightEntry.createdAt`.
    public let createdAt: Date
    /// The `HydrationOutboxEntry.id` (GarminKit) this drink was enqueued
    /// as. Used only to let a later local delete also cancel an
    /// undelivered outbox entry; `nil` is allowed only so a manually
    /// constructed/migrated value doesn't have to fake one.
    public var outboxEntryId: UUID?

    public init(
        id: UUID = UUID(),
        valueInML: Double,
        loggedAt: Date = Date(),
        createdAt: Date = Date(),
        outboxEntryId: UUID? = nil
    ) {
        self.id = id
        self.valueInML = valueInML
        self.loggedAt = loggedAt
        self.createdAt = createdAt
        self.outboxEntryId = outboxEntryId
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `WeightStore`.
public actor HydrationStore {
    private let fileURL: URL
    private var entriesById: [UUID: HydrationEntry] = [:]
    private var loaded = false

    public init(fileURL: URL = HydrationStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("hydration-entries.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([HydrationEntry].self, from: data)) ?? []
        entriesById = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(entriesById.values))
        try data.write(to: fileURL, options: .atomic)
    }

    /// Newest first -- same reasoning as `WeightStore.all()`.
    public func all() -> [HydrationEntry] {
        loadIfNeeded()
        return Array(entriesById.values).sorted { $0.loggedAt > $1.loggedAt }
    }

    @discardableResult
    public func upsert(_ entry: HydrationEntry) throws -> HydrationEntry {
        loadIfNeeded()
        entriesById[entry.id] = entry
        try persist()
        return entry
    }

    public func delete(id: UUID) throws {
        loadIfNeeded()
        entriesById.removeValue(forKey: id)
        try persist()
    }
}

/// Pure day-total helpers, kept separate from `HydrationEntry` itself so
/// they stay trivially unit-testable and are reusable between the quick-add
/// card and the full Hydration screen -- both show "how much today".
public enum HydrationHistory {
    /// Sum of every entry whose `loggedAt` falls on `date`'s own calendar
    /// day, in `calendar`'s time zone -- matches how a person actually
    /// thinks about "today's water", not a rolling 24h window.
    public static func total(for entries: [HydrationEntry], on date: Date, calendar: Calendar = .current) -> Double {
        entries
            .filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
            .reduce(0) { $0 + $1.valueInML }
    }

    /// Every entry logged on `date`'s own calendar day, newest first --
    /// `entries` is assumed already sorted that way (matching
    /// `HydrationStore.all()`'s own contract), so this just filters.
    public static func entries(for entries: [HydrationEntry], on date: Date, calendar: Calendar = .current) -> [HydrationEntry] {
        entries.filter { calendar.isDate($0.loggedAt, inSameDayAs: date) }
    }
}

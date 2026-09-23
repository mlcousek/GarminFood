// WeightTracking.swift
//
// The weight domain layer. WHY a local entry exists separately from
// GarminKit's `WeightOutboxEntry`: exactly the same reason `OutboxEntry`
// isn't shown directly as "the food log" (LogEntryCoordinator.swift's own
// header explains this for food) -- GarminKit has no UI layer and no
// concept of a user-facing history list, an optional note, or "this
// weigh-in's own identity independent of whichever outbox entry is
// currently trying to deliver it". `WeightEntry` is that identity --
// durable, JSON-file-backed (`WeightStore`, the exact same pattern as
// `MealPresetStore` in MealPreset.swift), and the source of truth the
// History screen actually reads. `outboxEntryId` is the only link back to
// GarminKit's delivery queue, kept purely so a later delete can also cancel
// an undelivered outbox entry -- see `WeightLogCoordinator.deleteWeight`.
//
// This app has no imperial/metric setting anywhere today (checked before
// building this feature), so `weightKg` is the only unit stored -- always
// kilograms, matching what `GarminClient.addWeighIn` always sends.

import Foundation

public struct WeightEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var weightKg: Double
    /// What the user says the weigh-in happened -- may be backdated (the Add
    /// Weight screen allows picking a past date/time for a missed entry).
    /// This is what's shown in the history list/chart AND what's sent to
    /// Garmin, via the linked outbox entry.
    public var loggedAt: Date
    public var note: String?
    /// When this record was actually created on this device -- distinct
    /// from `loggedAt` only when backdated. Not shown anywhere today; kept
    /// for the same reason `MealPreset.createdAt` is: a durable record
    /// should carry its own real history, not just the user-editable
    /// business date.
    public let createdAt: Date
    /// The `WeightOutboxEntry.id` (GarminKit) this weigh-in was enqueued as,
    /// at the moment it was logged -- always set in practice
    /// (`WeightLogCoordinator.logWeight` enqueues before it creates this
    /// record). Used only to let a later local delete also cancel an
    /// undelivered outbox entry; `nil` is allowed only so a manually
    /// constructed/migrated value doesn't have to fake one.
    public var outboxEntryId: UUID?

    public init(
        id: UUID = UUID(),
        weightKg: Double,
        loggedAt: Date = Date(),
        note: String? = nil,
        createdAt: Date = Date(),
        outboxEntryId: UUID? = nil
    ) {
        self.id = id
        self.weightKg = weightKg
        self.loggedAt = loggedAt
        self.note = note
        self.createdAt = createdAt
        self.outboxEntryId = outboxEntryId
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `MealPresetStore`.
public actor WeightStore {
    private let fileURL: URL
    private var entriesById: [UUID: WeightEntry] = [:]
    private var loaded = false

    public init(fileURL: URL = WeightStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("weight-entries.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = FoodLogCoreStorage.loadPersistedJSON([WeightEntry].self, from: fileURL, decoder: decoder, category: "WeightStore") ?? []
        entriesById = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(entriesById.values))
        try data.write(to: fileURL, options: .atomic)
    }

    /// Newest first -- every screen that reads this wants "most recent
    /// weigh-in" at index 0 (the hero card, the Progress tab summary, the
    /// history list/chart); nothing in this app wants oldest-first.
    public func all() -> [WeightEntry] {
        loadIfNeeded()
        return Array(entriesById.values).sorted { $0.loggedAt > $1.loggedAt }
    }

    @discardableResult
    public func upsert(_ entry: WeightEntry) throws -> WeightEntry {
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

/// Pure trend helpers, kept separate from `WeightEntry` itself so they stay
/// trivially unit-testable and are reusable between the Progress tab's
/// summary card and the full History screen's hero -- both show the same
/// "vs last time" delta.
public enum WeightHistory {
    /// The change from `previous` to `latest`, or `nil` when there's no
    /// earlier entry to compare against. Positive means `latest` is heavier.
    public static func delta(latest: WeightEntry, previous: WeightEntry?) -> Double? {
        guard let previous else { return nil }
        return latest.weightKg - previous.weightKg
    }
}

// RecordsStore.swift
//
// add-journeys-and-records design D6/D8: the personal records' persisted
// state at `<features>/records/records.json` -- per record the current best
// `(value, day)`, the previous best, a `DailyLedger` whose sealed days
// count toward `qualifyingDays` exactly once (the 7-day warm-up), and how
// many PRs it has announced; plus the last 10 announced PRs (history list),
// the water-goal streak carried over from the newest sealed day (the
// 42-day snapshot can't see further back) and the first-run day (the
// silent baseline).
//
// Every persisted field is Optional so the format can grow, and the file
// follows the package's unreadable-file contract through
// `FeatureStateFile` (JourneysStore.swift): an undecodable file is
// quarantined by the loader, and one that exists but can't be read (before
// first unlock) is never overwritten.
//
// Depends on: DailyLedger, FeatureStateFile, GamificationStorage.
// Depended on by: RecordsEvaluator, PersonalRecordsFeature.

import Foundation

/// A record value and the `yyyy-MM-dd` day it was set.
public struct RecordMark: Codable, Sendable, Equatable {
    public var value: Double?
    public var day: String?

    public init(value: Double?, day: String?) {
        self.value = value
        self.day = day
    }
}

public struct PersonalRecordState: Codable, Sendable, Equatable {
    public var current: RecordMark?
    public var previous: RecordMark?
    public var ledger: DailyLedger<Double>?
    /// Qualifying days already sealed (each counted once).
    public var sealedQualifyingDays: Int?
    /// PRs announced for this record (moments + XP).
    public var prCount: Int?

    public init(
        current: RecordMark? = nil,
        previous: RecordMark? = nil,
        ledger: DailyLedger<Double>? = nil,
        sealedQualifyingDays: Int? = nil,
        prCount: Int? = nil
    ) {
        self.current = current
        self.previous = previous
        self.ledger = ledger
        self.sealedQualifyingDays = sealedQualifyingDays
        self.prCount = prCount
    }

    /// Sealed qualifying days + the still-open days that qualify.
    public var qualifyingDays: Int {
        (sealedQualifyingDays ?? 0) + (ledger?.openDays?.count ?? 0)
    }
}

/// One announced PR (the history list).
public struct PersonalRecordEvent: Codable, Sendable, Equatable, Identifiable {
    public var recordId: String?
    public var day: String?
    public var value: Double?
    public var previousValue: Double?

    public init(recordId: String?, day: String?, value: Double?, previousValue: Double?) {
        self.recordId = recordId
        self.day = day
        self.value = value
        self.previousValue = previousValue
    }

    public var id: String { "\(recordId ?? "")|\(day ?? "")" }
}

/// The water-goal streak length as of a sealed day.
public struct WaterStreakCarry: Codable, Sendable, Equatable {
    public var day: String?
    public var length: Int?

    public init(day: String?, length: Int?) {
        self.day = day
        self.length = length
    }
}

public struct RecordsState: Codable, Sendable, Equatable {
    /// Keyed by `PersonalRecordId.rawValue`.
    public var records: [String: PersonalRecordState]?
    /// Newest last, at most `PersonalRecordCatalog.historyLimit`.
    public var history: [PersonalRecordEvent]?
    public var waterStreakCarry: WaterStreakCarry?
    /// `yyyy-MM-dd` of the first (silent baseline) run.
    public var startedOn: String?

    public init(
        records: [String: PersonalRecordState]? = nil,
        history: [PersonalRecordEvent]? = nil,
        waterStreakCarry: WaterStreakCarry? = nil,
        startedOn: String? = nil
    ) {
        self.records = records
        self.history = history
        self.waterStreakCarry = waterStreakCarry
        self.startedOn = startedOn
    }

    public var isFirstRun: Bool { startedOn == nil }

    public func record(_ id: PersonalRecordId) -> PersonalRecordState {
        records?[id.rawValue] ?? PersonalRecordState()
    }

    /// PRs announced over all records.
    public var totalPRs: Int {
        (records ?? [:]).values.reduce(0) { $0 + ($1.prCount ?? 0) }
    }
}

/// Loads and saves `RecordsState`. One instance per `PersonalRecordsFeature`.
public actor RecordsStore {
    public static let fileName = "records.json"

    private var file: FeatureStateFile<RecordsState>
    private var cached: RecordsState?

    public init(directory: URL) {
        file = FeatureStateFile(
            fileURL: directory.appendingPathComponent(Self.fileName),
            category: "RecordsStore"
        )
    }

    /// The stored state; an empty state (= first run) when none exists yet.
    /// `isReadable` is false while the file exists but can't be read -- the
    /// feature then skips the run instead of re-baselining over it.
    public func load() -> (state: RecordsState, isReadable: Bool) {
        if let cached, file.loaded { return (cached, true) }
        let value = file.load()
        if file.loaded {
            cached = value ?? RecordsState()
            return (cached ?? RecordsState(), true)
        }
        return (RecordsState(), false)
    }

    public func save(_ state: RecordsState) throws {
        try file.save(state)
        cached = state
    }
}

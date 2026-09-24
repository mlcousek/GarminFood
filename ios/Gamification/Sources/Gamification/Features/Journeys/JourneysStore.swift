// JourneysStore.swift
//
// add-journeys-and-records design D8: the journeys' persisted state --
// per cumulative journey a `DailyLedger` (open days + seal mark), the sum
// of every sealed day, and the milestone ids already reached (so each
// milestone is celebrated once); the road trip also keeps the weight known
// as of its last sealed day; the passport keeps the set of food ids seen
// (ids only). Stored at `<features>/journeys/journeys.json`.
//
// Every persisted field is Optional so the format can grow, and the file
// follows the package's unreadable-file contract
// (`GamificationStorage.loadPersistedJSON` / `ensureSafeToWrite`): an
// undecodable file is quarantined by the loader, and a file that exists but
// can't be read (before first unlock) is never overwritten.
//
// `FeatureStateFile` is the small shared JSON-file helper for this change's
// two stores (journeys and records).
//
// Depends on: DailyLedger, GamificationStorage.
// Depended on by: JourneysEvaluator, JourneysFeature.

import Foundation

public struct CumulativeJourneyState: Codable, Sendable, Equatable {
    public var ledger: DailyLedger<Double>?
    /// Sum of every sealed day's value, in the journey's unit.
    public var sealedTotal: Double?
    public var reachedMilestones: [String]?
    /// Road trip only: the latest weigh-in on or before `ledger.sealedThrough`.
    public var lastKnownWeightKg: Double?

    public init(
        ledger: DailyLedger<Double>? = nil,
        sealedTotal: Double? = nil,
        reachedMilestones: [String]? = nil,
        lastKnownWeightKg: Double? = nil
    ) {
        self.ledger = ledger
        self.sealedTotal = sealedTotal
        self.reachedMilestones = reachedMilestones
        self.lastKnownWeightKg = lastKnownWeightKg
    }

    /// Sealed days plus the still-open days' current values.
    public var total: Double {
        (sealedTotal ?? 0) + (ledger?.openValues ?? []).reduce(0, +)
    }
}

public struct PassportJourneyState: Codable, Sendable, Equatable {
    public var foodIds: [String]?
    public var reachedMilestones: [String]?

    public init(foodIds: [String]? = nil, reachedMilestones: [String]? = nil) {
        self.foodIds = foodIds
        self.reachedMilestones = reachedMilestones
    }
}

public struct JourneysState: Codable, Sendable, Equatable {
    public var protein: CumulativeJourneyState?
    public var water: CumulativeJourneyState?
    public var road: CumulativeJourneyState?
    public var passport: PassportJourneyState?
    /// `yyyy-MM-dd` of the first run (the 42-day back-fill).
    public var startedOn: String?

    public init(
        protein: CumulativeJourneyState? = nil,
        water: CumulativeJourneyState? = nil,
        road: CumulativeJourneyState? = nil,
        passport: PassportJourneyState? = nil,
        startedOn: String? = nil
    ) {
        self.protein = protein
        self.water = water
        self.road = road
        self.passport = passport
        self.startedOn = startedOn
    }

    public var isFirstRun: Bool { startedOn == nil }

    /// The cumulative total of `kind`, in its unit.
    public func total(_ kind: JourneyKind) -> Double {
        switch kind {
        case .protein: return protein?.total ?? 0
        case .water: return water?.total ?? 0
        case .road: return road?.total ?? 0
        case .passport: return Double(passport?.foodIds?.count ?? 0)
        }
    }

    public func reachedMilestones(_ kind: JourneyKind) -> Set<String> {
        switch kind {
        case .protein: return Set(protein?.reachedMilestones ?? [])
        case .water: return Set(water?.reachedMilestones ?? [])
        case .road: return Set(road?.reachedMilestones ?? [])
        case .passport: return Set(passport?.reachedMilestones ?? [])
        }
    }
}

/// A JSON file holding one Codable state value, with the package's
/// unreadable-file contract. Not thread-safe on its own: owned by an actor.
struct FeatureStateFile<State: Codable> {
    let fileURL: URL
    let category: String
    private(set) var loaded = false

    init(fileURL: URL, category: String) {
        self.fileURL = fileURL
        self.category = category
    }

    /// `nil` when the file doesn't exist yet (or was quarantined as
    /// undecodable). An unreadable file leaves `loaded` false, so `save`
    /// refuses to overwrite it and a later `load` retries.
    mutating func load() -> State? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = GamificationStorage.loadPersistedJSON(State.self, from: fileURL, decoder: decoder, category: category)
        loaded = !result.isUnreadable
        return result.value
    }

    func save(_ state: State) throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: category)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }
}

/// Loads and saves `JourneysState`. One instance per `JourneysFeature`.
public actor JourneysStore {
    public static let fileName = "journeys.json"

    private var file: FeatureStateFile<JourneysState>
    private var cached: JourneysState?

    public init(directory: URL) {
        file = FeatureStateFile(
            fileURL: directory.appendingPathComponent(Self.fileName),
            category: "JourneysStore"
        )
    }

    /// The stored state; an empty state (= first run) when none exists yet.
    /// `isReadable` is false while the file exists but can't be read -- the
    /// feature then skips the run instead of back-filling over it.
    public func load() -> (state: JourneysState, isReadable: Bool) {
        if let cached, file.loaded { return (cached, true) }
        let value = file.load()
        if file.loaded {
            cached = value ?? JourneysState()
            return (cached ?? JourneysState(), true)
        }
        return (JourneysState(), false)
    }

    public func save(_ state: JourneysState) throws {
        try file.save(state)
        cached = state
    }
}

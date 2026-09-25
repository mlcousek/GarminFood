// BossStore.swift
//
// add-weekly-boss-and-streak-freezes design D3: the weekly boss's persisted
// state -- per ISO week the boss chosen for it (so it is never re-rolled),
// its target and the adherence that chose it, the hit days so far and the
// outcome -- plus the lifetime counters the badges need (defeat count,
// archetypes ever defeated, whether a 7-day target was ever beaten), which
// must survive the 26-week pruning of `weeks`. Stored at
// `<features>/boss/boss.json`.
//
// Every persisted field except a week's `bossId` is Optional so the format
// can grow; `outcome` is a plain string (an unknown future value must not
// make the whole file undecodable). The file follows the package's
// unreadable-file contract through `FeatureStateFile` (quarantine on
// undecodable, never overwrite a file that exists but can't be read), and
// `save` loads first when nothing was loaded yet (the lesson from
// `JourneysStore.save`).
//
// Depends on: FeatureStateFile (JourneysStore.swift), GamificationStorage.
// Depended on by: WeeklyBossFeature.

import Foundation

/// How a boss week ended (or that it is still running).
public enum BossOutcome: String, Sendable, Equatable, Codable {
    case active, defeated, escaped
}

public struct BossWeekRecord: Codable, Sendable, Equatable {
    public let bossId: String
    public var target: Int?
    /// 0...1, over the 28-day analysis window.
    public var adherence: Double?
    public var goodDays: Int?
    public var consideredDays: Int?
    /// `yyyy-MM-dd` days that scored a hit.
    public var hits: [String]?
    /// `BossOutcome.rawValue`; nil = active.
    public var outcome: String?
    /// `yyyy-MM-dd` nutrition day the defeat was recorded on.
    public var defeatedOn: String?

    public init(
        bossId: String,
        target: Int? = nil,
        adherence: Double? = nil,
        goodDays: Int? = nil,
        consideredDays: Int? = nil,
        hits: [String]? = nil,
        outcome: String? = nil,
        defeatedOn: String? = nil
    ) {
        self.bossId = bossId
        self.target = target
        self.adherence = adherence
        self.goodDays = goodDays
        self.consideredDays = consideredDays
        self.hits = hits
        self.outcome = outcome
        self.defeatedOn = defeatedOn
    }

    public var kind: BossKind? { BossKind(rawValue: bossId) }
    public var resolvedOutcome: BossOutcome { outcome.flatMap(BossOutcome.init(rawValue:)) ?? .active }
    public var hitCount: Int { hits?.count ?? 0 }
    /// At least 3, per the target formula (a malformed record can't be
    /// defeated by zero hits).
    public var resolvedTarget: Int { min(max(target ?? 3, 3), 7) }
}

public struct BossState: Codable, Sendable, Equatable {
    /// Keyed by `WeekKey.rawValue` ("2026-W39").
    public var weeks: [String: BossWeekRecord]?
    public var defeatCount: Int?
    /// `BossKind.rawValue`s ever defeated (for the bestiary).
    public var defeatedIds: [String]?
    /// A boss with a 7-day target was defeated at least once.
    public var perfectDefeat: Bool?

    public init(
        weeks: [String: BossWeekRecord]? = nil,
        defeatCount: Int? = nil,
        defeatedIds: [String]? = nil,
        perfectDefeat: Bool? = nil
    ) {
        self.weeks = weeks
        self.defeatCount = defeatCount
        self.defeatedIds = defeatedIds
        self.perfectDefeat = perfectDefeat
    }

    public static let keptWeeks = 26

    /// Drops all but the `keptWeeks` most recent weeks.
    public mutating func prune() {
        guard let weeks, weeks.count > Self.keptWeeks else { return }
        let keep = Set(weeks.keys.sorted().suffix(Self.keptWeeks))
        self.weeks = weeks.filter { keep.contains($0.key) }
    }
}

/// Loads and saves `BossState`. One instance per `WeeklyBossFeature`.
public actor BossStore {
    public static let fileName = "boss.json"

    private var file: FeatureStateFile<BossState>
    private var cached: BossState?

    public init(directory: URL) {
        file = FeatureStateFile(
            fileURL: directory.appendingPathComponent(Self.fileName),
            category: "BossStore"
        )
    }

    /// The stored state (empty when none exists yet). `isReadable` is false
    /// while the file exists but can't be read -- the feature then skips
    /// the run instead of picking and announcing a boss over it.
    public func load() -> (state: BossState, isReadable: Bool) {
        if let cached, file.loaded { return (cached, true) }
        let value = file.load()
        if file.loaded {
            cached = value ?? BossState()
            return (cached ?? BossState(), true)
        }
        return (BossState(), false)
    }

    public func save(_ state: BossState) throws {
        // Load first so an existing-but-unreadable file is detected (and
        // refused) rather than failing as merely "never loaded".
        if !file.loaded { _ = load() }
        try file.save(state)
        cached = state
    }
}

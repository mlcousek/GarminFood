// SupplementsStore.swift
//
// add-supplements D9/D10: the supplements feature's own persisted state,
// at `<features>/supplements/supplements.json`. The digest itself is
// rebuilt from the supplement stores on every run, so this keeps only what
// the digest can't say:
//
//   - pauses (D10 "the streak is frozen in place" while the feature is
//     off or has no product): `inactiveSince` while inactive, and the
//     closed `pausedRanges` once it is active again. Paused days read as
//     neutral (`SupplementPause.apply`), so they neither extend nor break
//     the supplement streak, and the freeze planner never spends a freeze
//     on them;
//   - the archive (6.3): the digest only covers 365 days, so days about to
//     leave it are folded into running totals (creatine grams and days) for
//     the lifetime badges and the creatine journey;
//   - the vitamin-alphabet collection (ingredient id -> first day taken;
//     it only grows), the journey milestones already reached (each
//     announced once) and the longest supplement streak seen.
//
// Every field is Optional so the format can grow; the file follows the
// package's unreadable-file contract through `FeatureStateFile`
// (quarantine on decode failure, never overwrite a file that can't be read
// yet). Fixture: Tests/GamificationTests/Fixtures/Stores/supplements.json.
//
// Depends on: FeatureStateFile (JourneysStore.swift), GamificationStorage.
// Depended on by: SupplementsFeature, SupplementPause, SupplementsEvaluator.

import Foundation

/// Days (inclusive) the supplements feature was inactive.
public struct SupplementPausedRange: Codable, Sendable, Equatable {
    public var from: String?
    public var through: String?

    public init(from: String?, through: String?) {
        self.from = from
        self.through = through
    }

    public func contains(_ day: String) -> Bool {
        guard let from, let through else { return false }
        return day >= from && day <= through
    }
}

public struct SupplementsState: Codable, Sendable, Equatable {
    /// `yyyy-MM-dd` of the first run that found the feature inactive (off
    /// or no product), while it still is.
    public var inactiveSince: String?
    /// Closed pauses, oldest first.
    public var pausedRanges: [SupplementPausedRange]?
    /// Days on or before this one are folded into the archive totals.
    public var archivedThrough: String?
    /// Creatine grams taken on archived days.
    public var archivedCreatineGrams: Double?
    /// Archived days with creatine taken.
    public var archivedCreatineDays: Int?
    /// Vitamin alphabet: ingredient id -> first day it was taken.
    public var collected: [String: String]?
    /// Creatine-journey milestone ids already reached.
    public var reachedMilestones: [String]?
    /// The longest supplement streak ever seen.
    public var longestStreak: Int?

    public init(
        inactiveSince: String? = nil,
        pausedRanges: [SupplementPausedRange]? = nil,
        archivedThrough: String? = nil,
        archivedCreatineGrams: Double? = nil,
        archivedCreatineDays: Int? = nil,
        collected: [String: String]? = nil,
        reachedMilestones: [String]? = nil,
        longestStreak: Int? = nil
    ) {
        self.inactiveSince = inactiveSince
        self.pausedRanges = pausedRanges
        self.archivedThrough = archivedThrough
        self.archivedCreatineGrams = archivedCreatineGrams
        self.archivedCreatineDays = archivedCreatineDays
        self.collected = collected
        self.reachedMilestones = reachedMilestones
        self.longestStreak = longestStreak
    }
}

/// Loads and saves `SupplementsState`. One instance per `SupplementsFeature`.
public actor SupplementsStore {
    public static let fileName = "supplements.json"

    private var file: FeatureStateFile<SupplementsState>
    private var cached: SupplementsState?

    public init(directory: URL) {
        file = FeatureStateFile(
            fileURL: directory.appendingPathComponent(Self.fileName),
            category: "SupplementsStore"
        )
    }

    /// The stored state (empty when none exists yet). `isReadable` is false
    /// while the file exists but can't be read -- the feature then skips
    /// the run instead of evaluating (and announcing) over it.
    public func load() -> (state: SupplementsState, isReadable: Bool) {
        if let cached, file.loaded { return (cached, true) }
        let value = file.load()
        if file.loaded {
            cached = value ?? SupplementsState()
            return (cached ?? SupplementsState(), true)
        }
        return (SupplementsState(), false)
    }

    public func save(_ state: SupplementsState) throws {
        // Load first so an existing-but-unreadable file is detected (and
        // refused) rather than failing as merely "never loaded".
        if !file.loaded { _ = load() }
        try file.save(state)
        cached = state
    }
}

import Foundation

// XPStore.swift
//
// Levels spec's "Logging awards XP, with larger awards for consistency than
// volume" requirement (design.md D3, task 24.1).
//
// WHY THIS IS A PERSISTED COUNTER, NOT A FULLY-DERIVED PURE FUNCTION (worth
// recording, since design.md's Goals explicitly want "a pure function of
// local log data" and this is the one place that is not literally true):
// total XP could, in principle, be recomputed on every call purely from
// `UsageEvent` history plus `GoalStatusStore`, with no counter persisted at
// all. That was the first design tried here. It does not actually work,
// because `UsageHistoryStore` caps itself at 500 events and silently trims
// the oldest ones (UsageHistory.swift's own doc comment) -- so a "total XP"
// recomputed from the current snapshot of usage history would PLATEAU
// permanently once a user passes ~500 lifetime logs (roughly 4-6 months at
// a few logs/day), since events keep aging out of the very data the total
// is derived from. A level that can never increase again well within a
// year of normal use defeats the entire point of levels. So XP is instead
// a small persisted running total -- genuinely a ledger, in the accounting
// sense: each log appends an award, the balance accumulates, and the
// balance survives independently of how much raw log history
// `UsageHistoryStore` still happens to be holding onto. Everything else in
// this package (streaks, level-from-XP, challenge progress) stays a pure
// function; this is the one deliberate, documented exception.
//
// Same JSON-file-actor pattern as `FoodLogCore.UsageHistoryStore` /
// `GoalStatusStore` above.
public enum XPAward {
    /// Awarded for every logged entry, no matter how many happen on the
    /// same day (levels spec's "each entry awards the flat per-log XP
    /// amount, without an escalating bonus for logging multiple entries at
    /// once"). Small on purpose -- see design.md D3: "enough to feel
    /// earned, not so much that logging ten items in one sitting
    /// meaningfully outpaces logging steadily across days."
    public static let flatPerLog = 10

    /// Awarded once per nutrition-day, to whichever log entry is the FIRST
    /// one that day (the one that actually extends the streak -- see
    /// `StreakEngine`). Meaningfully larger than the flat award, per D3:
    /// "meaningfully larger XP comes from things that require actual
    /// consistency."
    public static let streakExtensionBonus = 20

    /// Awarded once per nutrition-day, the first time that day's goal
    /// status (from `GoalStatusStore`, populated by the app layer) is
    /// observed to have been met.
    public static let goalHitBonus = 25

    /// Awarded once per challenge completion (challenges spec's "SHALL
    /// award XP on challenge completion") -- deliberately the single
    /// largest award in the system, since a challenge requires sustained
    /// behaviour over several days, not a single lucky day.
    public static let challengeCompletionBonus = 50

    /// Awarded once per completed daily challenge (daily-challenges spec's
    /// "distinct from the long-running-challenge completion bonus"
    /// requirement, expand-gamification-depth design.md D3). Deliberately
    /// smaller than `challengeCompletionBonus`: daily challenges are meant
    /// to be frequent and easy, two of them a day, not a multi-day effort.
    public static let dailyChallengeBonus = 15

    /// Awarded once per achievement unlock (achievements spec).
    public static let achievementBonus = 30
}

public struct XPAwardResult: Equatable, Sendable {
    public let totalXPBefore: Int
    public let totalXPAfter: Int
    public let xpAwarded: Int
    public let streakBonusAwarded: Bool
    public let goalBonusAwarded: Bool
    /// add-gamification-signals D10: the highest level ever reached,
    /// before and after this award (`nil` only for results built without a
    /// store, e.g. in tests).
    public let peakLevelBefore: Int?
    public let peakLevelAfter: Int?

    public init(
        totalXPBefore: Int,
        totalXPAfter: Int,
        xpAwarded: Int,
        streakBonusAwarded: Bool,
        goalBonusAwarded: Bool,
        peakLevelBefore: Int? = nil,
        peakLevelAfter: Int? = nil
    ) {
        self.totalXPBefore = totalXPBefore
        self.totalXPAfter = totalXPAfter
        self.xpAwarded = xpAwarded
        self.streakBonusAwarded = streakBonusAwarded
        self.goalBonusAwarded = goalBonusAwarded
        self.peakLevelBefore = peakLevelBefore
        self.peakLevelAfter = peakLevelAfter
    }

    /// The displayed levels: never below the peak (design D10).
    public var levelBefore: LevelCurve.Progress { LevelCurve.level(forTotalXP: totalXPBefore, peakLevel: peakLevelBefore) }
    public var levelAfter: LevelCurve.Progress { LevelCurve.level(forTotalXP: totalXPAfter, peakLevel: peakLevelAfter) }
    /// Fires only when the curve level rises ABOVE the previous peak, so a
    /// level that was already reached is never celebrated twice.
    public var didLevelUp: Bool { levelAfter.level > levelBefore.level }
}

public actor XPStore {
    private struct Snapshot: Codable {
        var totalXP: Int
        var lastStreakBonusDay: String?
        var lastGoalBonusDay: String?
        /// add-gamification-signals D10: the highest level ever displayed.
        /// Optional so pre-change files decode; seeded on load (see
        /// `loadIfNeeded`) from the larger of the old-curve and new-curve
        /// level, so the 1.045 -> 1.0505 retune never lowers anyone.
        var peakLevel: Int?
    }

    private let fileURL: URL
    private var snapshot = Snapshot(totalXP: 0, lastStreakBonusDay: nil, lastGoalBonusDay: nil)
    private var loaded = false

    public init(fileURL: URL = XPStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("xp-ledger.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        // Unreadable (e.g. before first unlock): don't latch, retry on next
        // access; `persist()` refuses to overwrite it meanwhile.
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: "XPStore")
        loaded = !result.isUnreadable
        snapshot = result.value ?? snapshot
        if snapshot.peakLevel == nil {
            let legacy = LevelCurve.level(forTotalXP: snapshot.totalXP, growthFactor: LevelCurve.pastGrowthFactors[0]).level
            let current = LevelCurve.level(forTotalXP: snapshot.totalXP).level
            snapshot.peakLevel = max(legacy, current)
        }
    }

    /// Adds `xp` and raises the peak if the curve level passed it.
    /// Returns the peak before the change.
    private func add(_ xp: Int) -> (peakBefore: Int, peakAfter: Int) {
        let peakBefore = snapshot.peakLevel ?? 1
        snapshot.totalXP += xp
        let curveLevel = LevelCurve.level(forTotalXP: snapshot.totalXP).level
        let peakAfter = max(peakBefore, curveLevel)
        snapshot.peakLevel = peakAfter
        return (peakBefore, peakAfter)
    }

    /// The highest level ever reached (never lowered by a curve change).
    public func peakLevel() -> Int {
        loadIfNeeded()
        return snapshot.peakLevel ?? 1
    }

    /// The level to display: `max(curve level, peakLevel)` with progress
    /// toward the next level on the current curve.
    public func currentProgress() -> LevelCurve.Progress {
        loadIfNeeded()
        return LevelCurve.level(forTotalXP: snapshot.totalXP, peakLevel: snapshot.peakLevel)
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "XPStore")
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func currentTotal() -> Int {
        loadIfNeeded()
        return snapshot.totalXP
    }

    /// Records the XP for one confirmed log entry. `nutritionDay` is the
    /// `yyyy-MM-dd` this entry counts toward (`NutritionDayBoundary.dayString`),
    /// used purely to make the streak/goal bonuses idempotent per day --
    /// calling this twice for two entries on the SAME day still only pays
    /// the streak/goal bonus once, even if the caller (mistakenly or not)
    /// passes `streakExtendedToday`/`goalMetToday` as `true` both times.
    @discardableResult
    public func recordLog(
        nutritionDay: String,
        streakExtendedToday: Bool,
        goalMetToday: Bool
    ) throws -> XPAwardResult {
        loadIfNeeded()
        let before = snapshot.totalXP

        var awarded = XPAward.flatPerLog
        var streakBonusAwarded = false
        var goalBonusAwarded = false

        if streakExtendedToday, snapshot.lastStreakBonusDay != nutritionDay {
            awarded += XPAward.streakExtensionBonus
            snapshot.lastStreakBonusDay = nutritionDay
            streakBonusAwarded = true
        }
        if goalMetToday, snapshot.lastGoalBonusDay != nutritionDay {
            awarded += XPAward.goalHitBonus
            snapshot.lastGoalBonusDay = nutritionDay
            goalBonusAwarded = true
        }

        let peaks = add(awarded)
        try persist()

        return XPAwardResult(
            totalXPBefore: before,
            totalXPAfter: snapshot.totalXP,
            xpAwarded: awarded,
            streakBonusAwarded: streakBonusAwarded,
            goalBonusAwarded: goalBonusAwarded,
            peakLevelBefore: peaks.peakBefore,
            peakLevelAfter: peaks.peakAfter
        )
    }

    /// Records a challenge completion's flat bonus (challenges spec).
    @discardableResult
    public func recordChallengeCompletion(xp: Int = XPAward.challengeCompletionBonus) throws -> XPAwardResult {
        loadIfNeeded()
        let before = snapshot.totalXP
        let peaks = add(xp)
        try persist()
        return XPAwardResult(
            totalXPBefore: before,
            totalXPAfter: snapshot.totalXP,
            xpAwarded: xp,
            streakBonusAwarded: false,
            goalBonusAwarded: false,
            peakLevelBefore: peaks.peakBefore,
            peakLevelAfter: peaks.peakAfter
        )
    }
}

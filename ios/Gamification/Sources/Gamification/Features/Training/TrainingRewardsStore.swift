// TrainingRewardsStore.swift
//
// add-winter-arc-nutrition-and-rewards (D1): the training feature's own
// JSON file (`<features dir>/training/training.json`). The projection only
// carries a few weeks around today, but the badge ladders count check-ins,
// honest calls, habit ticks, gym weeks and kept weeks over the whole
// winter -- so each counted day/week id is remembered here and counts
// accumulate beyond the window. Habit ticks are a day -> count map (the
// latest count for a day replaces the earlier one: an un-ticked habit
// lowers it again while the day is still in the window).
//
// add-training-gamification-and-150-levels (D8): three more Optional
// fields, so the format only grows (the schema version stays, the first
// fixture still decodes, `training.v2.json` is today's shape):
//   - `sets`: the counted ids behind every new ladder, by `TrainingSetKey`
//     (sessions done within the light, kept days, easy weeks, rated
//     sessions, gate-test weeks, tests, approved weeks, ladder steps,
//     phases, applied plan edits, race preps / carb-load days / finishes /
//     reports / goals / PRs / wise calls, seasons). Ids are only ever
//     added: a reward once counted is never taken back. The field is
//     written by the first recording that carries any fact, even when no
//     set got an id: a file without it is what "first recording" means
//     (no moments for the whole window at once), also on a device that
//     already filled the five original lists;
//   - `habitDayStates`: per day whether the habits met the ladder's gate
//     share (`TrainingXPRules.habitDay…`), replaced while the day is in the
//     window, for the habit streak -- the vault's own streaks stop at its
//     84-day history, the milestones go to 365;
//   - `seasonEnds`: season id -> the last day of its period, so a season
//     that ends after the plan has moved on to the next one is still
//     completed.
// XP itself is NOT here: every grant is a `RewardLedger` key.
//
// Same `GamificationStorage` contract as every store in this package
// (SportBodyStore is the model): every field Optional, lists capped at
// 2,000 newest, an undecodable file quarantined, an unreadable one (device
// locked) never overwritten. Unlock state is NOT here (AchievementStore).
//
// Depends on: GamificationStorage, TrainingXPRules (Facts, the streaks).
// Depended on by: TrainingRewardsFeature.

import Foundation

public actor TrainingRewardsStore {
    struct Snapshot: Codable, Equatable {
        var checkInDays: [String]?
        var honestDays: [String]?
        var habitTicksByDay: [String: Int]?
        var gymWeeks: [String]?
        var keptWeeks: [String]?
        // add-training-gamification-and-150-levels D8 (all Optional).
        var sets: [String: [String]]?
        var habitDayStates: [String: Int]?
        var seasonEnds: [String: String]?
    }

    public static let cap = 2_000
    static let category = "TrainingRewardsStore"

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false
    private var dirty = false

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("training.json")
    }

    /// A store on any file (the frozen fixtures are read under their own
    /// names).
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Whether the file could be read (a locked device reads as `false`,
    /// and the feature then sits the run out).
    public func isReadable() -> Bool {
        loadIfNeeded()
        return loaded
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: Self.category)
        loaded = !result.isUnreadable
        if let value = result.value {
            snapshot = value
        }
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: Self.category)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    // MARK: - Reads

    public func counts() -> TrainingRewardCounts {
        loadIfNeeded()
        return TrainingRewardCounts(
            checkInDays: snapshot.checkInDays?.count ?? 0,
            honestCalls: snapshot.honestDays?.count ?? 0,
            habitTicks: (snapshot.habitTicksByDay ?? [:]).values.reduce(0) { $0 + max(0, $1) },
            gymWeeks: snapshot.gymWeeks?.count ?? 0,
            keptWeeks: snapshot.keptWeeks?.count ?? 0
        )
    }

    /// The counts and streaks behind the ladders of
    /// `TrainingProgressCatalog` and the Progress tab's training section.
    /// - Parameters:
    ///   - today: the plan's today (`yyyy-MM-dd`), for the current streaks.
    ///   - currentWeek: the plan's current week (`YYYY-Www`).
    public func progress(today: String, currentWeek: String?) -> TrainingProgress {
        loadIfNeeded()
        var setCounts: [String: Int] = [:]
        for (name, ids) in snapshot.sets ?? [:] {
            setCounts[name] = ids.count
        }
        return TrainingProgress(
            setCounts: setCounts,
            habitStreak: TrainingXPRules.habitStreak(states: snapshot.habitDayStates ?? [:], today: today),
            checkInStreak: TrainingXPRules.dayStreak(snapshot.checkInDays ?? [], today: today),
            keptWeekStreak: TrainingXPRules.weekStreak(snapshot.keptWeeks ?? [], currentWeek: currentWeek)
        )
    }

    /// The seasons seen so far: id -> the last day of its period.
    public func seasonEnds() -> [String: String] {
        loadIfNeeded()
        return snapshot.seasonEnds ?? [:]
    }

    /// The ids recorded under `key`, oldest first.
    public func ids(_ key: TrainingSetKey) -> [String] {
        loadIfNeeded()
        return snapshot.sets?[key.rawValue] ?? []
    }

    // MARK: - Writes (in memory; `save()` persists)

    /// The facts of the original five ladders. `includeJudgements: false`
    /// leaves honest calls and kept weeks to `record(_ facts:)`, whose rules
    /// (TrainingXPRules) then decide them for the ladders and the XP alike.
    public func record(_ signals: TrainingSignals, gymSessionsPerWeek: Int, includeJudgements: Bool = true) {
        loadIfNeeded()
        for day in signals.days {
            if day.checkedIn { insert(day.day, into: \.checkInDays) }
            if includeJudgements, day.honestLightFollowed { insert(day.day, into: \.honestDays) }
            setHabitTicks(day.habitTicks, on: day.day)
        }
        for week in signals.weeks {
            if week.strengthSessionsDone >= gymSessionsPerWeek { insert(week.week, into: \.gymWeeks) }
            if includeJudgements, week.keptWithinPlan { insert(week.week, into: \.keptWeeks) }
        }
    }

    /// One evaluation's facts (add-training-gamification-and-150-levels).
    /// Returns what was new, so the feature can celebrate a kept week, a
    /// closed phase or a finished race exactly once.
    @discardableResult
    public func record(_ facts: TrainingXPRules.Facts) -> TrainingRecordedFacts {
        loadIfNeeded()
        var recorded = TrainingRecordedFacts()
        // "First" = the first recording of the plan's facts: a device that
        // upgrades already has the five original lists, but no `sets`.
        recorded.wasFirstRecording = snapshot.sets == nil
        for day in facts.checkInDays { insert(day, into: \.checkInDays) }
        for day in facts.honestDays { insert(day, into: \.honestDays) }
        for week in facts.gymWeeks { insert(week, into: \.gymWeeks) }
        for week in facts.keptWeeks where insert(week, into: \.keptWeeks) {
            recorded.newKeptWeeks.append(week)
        }
        for day in facts.habitTicksByDay.keys.sorted() {
            setHabitTicks(facts.habitTicksByDay[day] ?? 0, on: day)
        }

        var states = snapshot.habitDayStates ?? [:]
        var statesChanged = false
        for (day, state) in facts.habitDayStates where states[day] != state {
            states[day] = state
            statesChanged = true
        }
        if statesChanged {
            if states.count > Self.cap {
                for key in states.keys.sorted().prefix(states.count - Self.cap) {
                    states[key] = nil
                }
            }
            snapshot.habitDayStates = states
            dirty = true
        }

        var sets = snapshot.sets ?? [:]
        var setsChanged = false
        for name in facts.sets.keys.sorted() {
            var list = sets[name] ?? []
            var known = Set(list)
            var added: [String] = []
            for id in facts.sets[name] ?? [] where known.insert(id).inserted {
                list.append(id)
                added.append(id)
            }
            guard !added.isEmpty else { continue }
            recorded.newSetIds[name] = added
            if list.count > Self.cap {
                list.removeFirst(list.count - Self.cap)
            }
            sets[name] = list
            setsChanged = true
        }
        // Written by the first recording that carries anything, even when
        // no set got an id: its presence is what tells the next run that it
        // is not the first. A run without any fact (no plan in the file
        // yet) leaves it alone, so the plan's arrival is still "first".
        if setsChanged || (snapshot.sets == nil && facts != TrainingXPRules.Facts()) {
            snapshot.sets = sets
            dirty = true
        }

        var ends = snapshot.seasonEnds ?? [:]
        var endsChanged = false
        for (id, end) in facts.seasonEnds where ends[id] != end {
            ends[id] = end
            endsChanged = true
        }
        if endsChanged {
            snapshot.seasonEnds = ends
            dirty = true
        }
        return recorded
    }

    public func save() throws {
        loadIfNeeded()
        guard dirty else { return }
        try persist()
        dirty = false
    }

    /// The latest count for a day replaces the earlier one; a day never
    /// recorded is not created for a zero.
    private func setHabitTicks(_ count: Int, on day: String) {
        var ticks = snapshot.habitTicksByDay ?? [:]
        guard ticks[day] != count, count > 0 || ticks[day] != nil else { return }
        ticks[day] = count
        if ticks.count > Self.cap {
            for key in ticks.keys.sorted().prefix(ticks.count - Self.cap) {
                ticks[key] = nil
            }
        }
        snapshot.habitTicksByDay = ticks
        dirty = true
    }

    /// `true` when `value` was not in the list yet.
    @discardableResult
    private func insert(_ value: String, into keyPath: WritableKeyPath<Snapshot, [String]?>) -> Bool {
        var list = snapshot[keyPath: keyPath] ?? []
        guard !list.contains(value) else { return false }
        list.append(value)
        list.sort()
        if list.count > Self.cap {
            list.removeFirst(list.count - Self.cap)
        }
        snapshot[keyPath: keyPath] = list
        dirty = true
        return true
    }
}

/// What one `record(_ facts:)` added that was not there before.
public struct TrainingRecordedFacts: Sendable, Equatable {
    public var newKeptWeeks: [String] = []
    /// `TrainingSetKey.rawValue` -> the ids added.
    public var newSetIds: [String: [String]] = [:]
    /// The plan's facts were never recorded before: the first run takes in
    /// the whole plan window at once, which is not a moment to celebrate
    /// item by item.
    public var wasFirstRecording = false

    public init() {}

    public func new(_ key: TrainingSetKey) -> [String] {
        newSetIds[key.rawValue] ?? []
    }
}

/// Lifetime counts behind the training badge ladders.
public struct TrainingRewardCounts: Sendable, Equatable {
    public let checkInDays: Int
    public let honestCalls: Int
    public let habitTicks: Int
    public let gymWeeks: Int
    public let keptWeeks: Int

    public init(checkInDays: Int, honestCalls: Int, habitTicks: Int, gymWeeks: Int, keptWeeks: Int) {
        self.checkInDays = checkInDays
        self.honestCalls = honestCalls
        self.habitTicks = habitTicks
        self.gymWeeks = gymWeeks
        self.keptWeeks = keptWeeks
    }

    public static let zero = TrainingRewardCounts(checkInDays: 0, honestCalls: 0, habitTicks: 0, gymWeeks: 0, keptWeeks: 0)
}

/// add-training-gamification-and-150-levels D8: the counts behind the new
/// ladders (by `TrainingSetKey`) and the current streaks.
public struct TrainingProgress: Sendable, Equatable {
    /// `TrainingSetKey.rawValue` -> how many ids were counted.
    public let setCounts: [String: Int]
    public let habitStreak: TrainingHabitStreak
    /// Days in a row with a morning check-in, ending today or yesterday.
    public let checkInStreak: Int
    /// Weeks in a row kept within plan, ending with the latest closed week.
    public let keptWeekStreak: Int

    public init(
        setCounts: [String: Int] = [:],
        habitStreak: TrainingHabitStreak = .none,
        checkInStreak: Int = 0,
        keptWeekStreak: Int = 0
    ) {
        self.setCounts = setCounts
        self.habitStreak = habitStreak
        self.checkInStreak = checkInStreak
        self.keptWeekStreak = keptWeekStreak
    }

    public static let zero = TrainingProgress()

    public func count(_ key: TrainingSetKey) -> Int {
        setCounts[key.rawValue] ?? 0
    }
}

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
// Same `GamificationStorage` contract as every store in this package
// (SportBodyStore is the model): every field Optional, lists capped at
// 2,000 newest, an undecodable file quarantined, an unreadable one (device
// locked) never overwritten. Unlock state is NOT here (AchievementStore).
//
// Depends on: GamificationStorage. Depended on by: TrainingRewardsFeature.

import Foundation

public actor TrainingRewardsStore {
    struct Snapshot: Codable, Equatable {
        var checkInDays: [String]?
        var honestDays: [String]?
        var habitTicksByDay: [String: Int]?
        var gymWeeks: [String]?
        var keptWeeks: [String]?
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

    // MARK: - Writes (in memory; `save()` persists)

    public func record(_ signals: TrainingSignals, gymSessionsPerWeek: Int) {
        loadIfNeeded()
        for day in signals.days {
            if day.checkedIn { insert(day.day, into: \.checkInDays) }
            if day.honestLightFollowed { insert(day.day, into: \.honestDays) }
            var ticks = snapshot.habitTicksByDay ?? [:]
            if ticks[day.day] != day.habitTicks, day.habitTicks > 0 || ticks[day.day] != nil {
                ticks[day.day] = day.habitTicks
                if ticks.count > Self.cap {
                    for key in ticks.keys.sorted().prefix(ticks.count - Self.cap) {
                        ticks[key] = nil
                    }
                }
                snapshot.habitTicksByDay = ticks
                dirty = true
            }
        }
        for week in signals.weeks {
            if week.strengthSessionsDone >= gymSessionsPerWeek { insert(week.week, into: \.gymWeeks) }
            if week.keptWithinPlan { insert(week.week, into: \.keptWeeks) }
        }
    }

    public func save() throws {
        loadIfNeeded()
        guard dirty else { return }
        try persist()
        dirty = false
    }

    private func insert(_ value: String, into keyPath: WritableKeyPath<Snapshot, [String]?>) {
        var list = snapshot[keyPath: keyPath] ?? []
        guard !list.contains(value) else { return }
        list.append(value)
        list.sort()
        if list.count > Self.cap {
            list.removeFirst(list.count - Self.cap)
        }
        snapshot[keyPath: keyPath] = list
        dirty = true
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

// StreakFreezeStore.swift
//
// add-weekly-boss-and-streak-freezes design D4/D6: the one persisted input
// that turns a streak-breaking miss into a `.frozen` day -- the list of
// consumed freezes ({frozenDay, consumedOn, protectedLength}). The frozen
// days `StreakEngine` walks are DERIVED from it, so the streak stays a pure
// function of (logged days, this list). Freeze GRANTS are not stored here:
// they live in `RewardLedger` (`*.freeze.*` keys, `.streakFreeze` kind) and
// `FreezeBalance` replays both into the available count.
//
// A consumption is never removed (no refund on a later backfill, D5) --
// the list only grows, by at most a couple of entries a month.
//
// One instance per process, owned by `WeeklyBossFeature` (which declares
// the freeze badges and reads this list to unlock them); the app's
// `GamificationEngine` reaches it through `WeeklyBossFeature.streakFreezes`
// and is the only writer (via `StreakFreezePlanner`). File:
// `<features dir>/boss/streak-freezes.json`.
//
// Same JSON-file actor + unreadable-file contract as every store in this
// package (`GamificationStorage.loadPersistedJSON`/`ensureSafeToWrite`):
// an undecodable file is quarantined, an unreadable one (device locked) is
// never overwritten. Every persisted field except `frozenDay` is Optional.
//
// Depends on: GamificationStorage.
// Depended on by: WeeklyBossFeature, StreakFreezePlanner, FreezeBalance,
// the app's GamificationEngine.

import Foundation

public actor StreakFreezeStore {
    public struct Consumption: Codable, Sendable, Equatable, Hashable {
        /// `yyyy-MM-dd` nutrition day the freeze covers.
        public let frozenDay: String
        /// `yyyy-MM-dd` nutrition day the planner consumed it on.
        public var consumedOn: String?
        /// The streak length the freeze kept alive (for `freeze.saved-100`).
        public var protectedLength: Int?

        public init(frozenDay: String, consumedOn: String?, protectedLength: Int?) {
            self.frozenDay = frozenDay
            self.consumedOn = consumedOn
            self.protectedLength = protectedLength
        }
    }

    struct Snapshot: Codable, Equatable {
        var consumptions: [Consumption]?
    }

    static let category = "StreakFreezeStore"

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("streak-freezes.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: Self.category)
        // Unreadable: don't latch; `persist()` refuses to overwrite meanwhile.
        loaded = !result.isUnreadable
        snapshot = result.value ?? snapshot
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

    /// Every consumption, in the order recorded, and whether the file could
    /// be read. While `isReadable` is false (file exists but is locked) the
    /// caller must not plan new freezes -- it can't know which were spent.
    public func load() -> (consumptions: [Consumption], isReadable: Bool) {
        loadIfNeeded()
        return (snapshot.consumptions ?? [], loaded)
    }

    /// Every consumption, in the order recorded.
    public func consumptions() -> [Consumption] {
        loadIfNeeded()
        return snapshot.consumptions ?? []
    }

    /// The `yyyy-MM-dd` days covered by a freeze.
    public func frozenDayKeys() -> Set<String> {
        Set(consumptions().map(\.frozenDay))
    }

    /// Appends new consumptions (a day already frozen is ignored) and
    /// persists. Throws -- leaving memory unchanged -- when the file could
    /// not be written, so the next run re-plans the same freeze.
    public func record(_ new: [Consumption]) throws {
        loadIfNeeded()
        var all = snapshot.consumptions ?? []
        var known = Set(all.map(\.frozenDay))
        var changed = false
        for consumption in new where !known.contains(consumption.frozenDay) {
            known.insert(consumption.frozenDay)
            all.append(consumption)
            changed = true
        }
        guard changed else { return }
        let previous = snapshot
        snapshot.consumptions = all
        do {
            try persist()
        } catch {
            snapshot = previous
            throw error
        }
    }
}

/// `yyyy-MM-dd` <-> nutrition-day midnight, in a given calendar, for the
/// freeze bookkeeping (the ledger and store speak day keys, `StreakEngine`
/// speaks midnight `Date`s).
public enum FreezeDayKey {
    public static func key(for day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: day)
    }

    /// Midnight of the day, or `nil` for a malformed key.
    public static func date(for key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        components.hour = 12
        guard let noon = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: noon)
    }
}

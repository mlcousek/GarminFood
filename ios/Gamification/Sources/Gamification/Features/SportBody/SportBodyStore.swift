// SportBodyStore.swift
//
// add-sport-and-body-achievements design D4: the sport & body feature's own
// JSON file (`<features dir>/sportBody/sport.json`). The tiered badges count
// fuelled / recovered activities, Earned-It days and race days over the
// owner's whole history, but the signals window is only 42 days (and the
// activity cache 120) -- so every counted activity id / day is remembered
// here and the counts accumulate beyond the window.
//
// `activityDays` (activity id -> its `yyyy-MM-dd` day) is an addition to the
// design's four lists, so "this month: 6 fuelled" can be answered from the
// store alone. Each list is capped at 2,000 newest items (years of
// training; far past the 50/100 badge tiers), every field is Optional so an
// older or newer file still decodes, an undecodable file is quarantined and
// an unreadable one (device locked) is never overwritten -- the same
// `GamificationStorage` contract as every store in this package. Unlock
// state is NOT here; it lives in `AchievementStore`.
//
// `save()` loads first when nothing has been read yet, so a save before any
// read never trips `ensureSafeToWrite` on a file that was merely unread.
//
// Depends on: GamificationStorage. Depended on by: SportAndBodyFeature.

import Foundation

public actor SportBodyStore {
    struct Snapshot: Codable, Equatable {
        var fuelledActivityIds: [String]?
        var recoveredActivityIds: [String]?
        var earnedDays: [String]?
        var raceDays: [String]?
        /// Activity id -> `yyyy-MM-dd` (for per-month counts).
        var activityDays: [String: String]?
    }

    public static let cap = 2_000
    static let category = "SportBodyStore"

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false
    private var dirty = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("sport.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: Self.category)
        // Unreadable: don't latch; `persist()` refuses to overwrite meanwhile.
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

    public func fuelledActivityIds() -> [String] {
        loadIfNeeded()
        return snapshot.fuelledActivityIds ?? []
    }

    public func recoveredActivityIds() -> [String] {
        loadIfNeeded()
        return snapshot.recoveredActivityIds ?? []
    }

    public func earnedDays() -> [String] {
        loadIfNeeded()
        return snapshot.earnedDays ?? []
    }

    public func raceDays() -> [String] {
        loadIfNeeded()
        return snapshot.raceDays ?? []
    }

    public func activityDay(for activityId: String) -> String? {
        loadIfNeeded()
        return snapshot.activityDays?[activityId]
    }

    /// Fuelled and recovered activities whose day starts with `monthPrefix`
    /// ("2026-09").
    public func counts(monthPrefix: String) -> (fuelled: Int, recovered: Int) {
        loadIfNeeded()
        let days = snapshot.activityDays ?? [:]
        func inMonth(_ id: String) -> Bool { days[id]?.hasPrefix(monthPrefix) ?? false }
        return (
            (snapshot.fuelledActivityIds ?? []).filter(inMonth).count,
            (snapshot.recoveredActivityIds ?? []).filter(inMonth).count
        )
    }

    // MARK: - Writes (in memory; `save()` persists)

    /// `true` when `activityId` was new.
    @discardableResult
    public func addFuelled(activityId: String, day: String) -> Bool {
        loadIfNeeded()
        guard insert(activityId, into: \.fuelledActivityIds) else { return false }
        remember(activityId: activityId, day: day)
        return true
    }

    @discardableResult
    public func addRecovered(activityId: String, day: String) -> Bool {
        loadIfNeeded()
        guard insert(activityId, into: \.recoveredActivityIds) else { return false }
        remember(activityId: activityId, day: day)
        return true
    }

    @discardableResult
    public func addEarnedDay(_ day: String) -> Bool {
        loadIfNeeded()
        return insert(day, into: \.earnedDays, sorted: true)
    }

    @discardableResult
    public func addRaceDay(_ day: String) -> Bool {
        loadIfNeeded()
        return insert(day, into: \.raceDays, sorted: true)
    }

    /// Persists when anything changed since the last save.
    public func save() throws {
        loadIfNeeded()
        guard dirty else { return }
        try persist()
        dirty = false
    }

    // MARK: - Helpers

    private func insert(_ value: String, into keyPath: WritableKeyPath<Snapshot, [String]?>, sorted: Bool = false) -> Bool {
        var list = snapshot[keyPath: keyPath] ?? []
        guard !list.contains(value) else { return false }
        let outOfOrder = sorted && (list.last.map { value < $0 } ?? false)
        list.append(value)
        if outOfOrder { list.sort() }
        if list.count > Self.cap {
            list.removeFirst(list.count - Self.cap)
        }
        snapshot[keyPath: keyPath] = list
        dirty = true
        pruneActivityDays()
        return true
    }

    private func remember(activityId: String, day: String) {
        var days = snapshot.activityDays ?? [:]
        days[activityId] = day
        snapshot.activityDays = days
        dirty = true
    }

    /// Drops day entries for ids no longer in either list (after a cap).
    private func pruneActivityDays() {
        guard var days = snapshot.activityDays else { return }
        let kept = Set(snapshot.fuelledActivityIds ?? []).union(snapshot.recoveredActivityIds ?? [])
        guard days.count > kept.count else { return }
        for id in days.keys where !kept.contains(id) {
            days[id] = nil
        }
        snapshot.activityDays = days
    }
}

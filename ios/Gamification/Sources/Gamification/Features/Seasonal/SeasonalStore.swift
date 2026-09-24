// SeasonalStore.swift
//
// add-seasonal-events design D6: the seasonal feature's own JSON file
// (`<features dir>/seasonal/seasonal.json`). Two things must outlive the
// 42-day signals window: which years each event was completed in (badge
// detail "Earned 2026, 2027", collector badges, moment de-duplication) and
// sticky quest progress -- a grill season is 72 days long, so days counted
// in June must still count in August, like a bingo square.
//
// Progress is stored as "marks" per quest (a day key for day-counting
// quests, "g<i>" for tag-group quests; see `SeasonalEvaluator`), for the
// current and previous year only. Every field is Optional so an older or
// newer file still decodes; an undecodable file is quarantined, and an
// unreadable one (device locked) is never overwritten -- the same
// `GamificationStorage` contract as every other store in this package.
// Ids only, never display text.
//
// Depends on: GamificationStorage. Depended on by: SeasonalEventsFeature.

import Foundation

public actor SeasonalStore {
    struct Snapshot: Codable, Equatable {
        /// Event id -> years completed, ascending.
        var completedYears: [String: [Int]]?
        /// "<eventId>.<year>" -> quest id -> marks.
        var questMarks: [String: [String: [String]]]?
        /// The last known owner first name (for the name-day event before
        /// the first signals sync of a launch).
        var ownerFirstName: String?
    }

    static let category = "SeasonalStore"

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("seasonal.json")
    }

    public static func instanceKey(eventId: String, year: Int) -> String {
        "\(eventId).\(year)"
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: Self.category)
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

    // MARK: - Reads

    public func completedYears() -> [String: [Int]] {
        loadIfNeeded()
        return snapshot.completedYears ?? [:]
    }

    public func completedYears(eventId: String) -> [Int] {
        loadIfNeeded()
        return snapshot.completedYears?[eventId] ?? []
    }

    /// Quest id -> marks for one event instance.
    public func marks(eventId: String, year: Int) -> [String: Set<String>] {
        loadIfNeeded()
        let stored = snapshot.questMarks?[Self.instanceKey(eventId: eventId, year: year)] ?? [:]
        return stored.mapValues { Set($0) }
    }

    public func ownerFirstName() -> String? {
        loadIfNeeded()
        return snapshot.ownerFirstName
    }

    // MARK: - Writes (in memory; `save()` persists)

    public func setMarks(_ marks: [String: Set<String>], eventId: String, year: Int) {
        loadIfNeeded()
        var all = snapshot.questMarks ?? [:]
        let nonEmpty = marks.filter { !$0.value.isEmpty }.mapValues { $0.sorted() }
        all[Self.instanceKey(eventId: eventId, year: year)] = nonEmpty.isEmpty ? nil : nonEmpty
        snapshot.questMarks = all
    }

    /// Records a completion; `true` when `year` was new for `eventId`.
    @discardableResult
    public func recordCompletion(eventId: String, year: Int) -> Bool {
        loadIfNeeded()
        var all = snapshot.completedYears ?? [:]
        var years = all[eventId] ?? []
        guard !years.contains(year) else { return false }
        years.append(year)
        years.sort()
        all[eventId] = years
        snapshot.completedYears = all
        return true
    }

    public func setOwnerFirstName(_ name: String?) {
        loadIfNeeded()
        snapshot.ownerFirstName = name
    }

    /// Drops quest progress older than `oldestYear` (completed years are
    /// kept forever -- they are the badge history).
    public func pruneMarks(keepingFrom oldestYear: Int) {
        loadIfNeeded()
        guard var all = snapshot.questMarks else { return }
        for key in all.keys {
            guard let yearText = key.split(separator: ".").last, let year = Int(yearText) else {
                all[key] = nil
                continue
            }
            if year < oldestYear { all[key] = nil }
        }
        snapshot.questMarks = all
    }

    public func save() throws {
        loadIfNeeded()
        try persist()
    }
}

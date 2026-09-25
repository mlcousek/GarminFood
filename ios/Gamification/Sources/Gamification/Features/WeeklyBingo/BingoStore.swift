// BingoStore.swift
//
// add-weekly-bingo design D7: the bingo feature's own JSON file
// (`<features dir>/bingo/bingo.json`). A card must be persisted -- not
// regenerated -- because it must never change during its week even when the
// catalog or the owner's data does (D1), and completions are sticky (D4):
// the 42-day signals window and later edits cannot be trusted to reproduce
// them.
//
// Keeps the last 12 weeks of cards (the detail screen's history pager) and
// two lifetime counters for the badges (`totalLines`, `fullCards`), which
// are bumped only when a line / full card is recorded for the first time on
// a card, so re-running the feature never double counts. Every field is
// Optional so an older or newer file still decodes; an undecodable file is
// quarantined, and an unreadable one (device locked) is never overwritten
// -- the same `GamificationStorage` contract as every other store in this
// package. Ids only, never display text.
//
// Depends on: GamificationStorage, WeekKey. Depended on by:
// WeeklyBingoFeature, WeeklyBingoStoreTests.

import Foundation

/// One week's card as stored.
public struct BingoCardRecord: Codable, Equatable, Sendable {
    /// Nine task ids, "free" at index 4.
    public var taskIds: [String]
    /// Square index (a string -- JSON object keys) -> `yyyy-MM-dd` it completed.
    public var completed: [String: String]?
    /// Line ids ("row0", "diag1") already celebrated/rewarded.
    public var linesDone: [String]?
    public var full: Bool?

    public init(taskIds: [String], completed: [String: String]? = nil, linesDone: [String]? = nil, full: Bool? = nil) {
        self.taskIds = taskIds
        self.completed = completed
        self.linesDone = linesDone
        self.full = full
    }

    private enum CodingKeys: String, CodingKey {
        case taskIds, completed, linesDone, full
    }

    /// Lenient like every other field: one card without `taskIds` decodes
    /// as an empty card (which `WeeklyBingoFeature` regenerates / skips)
    /// instead of failing -- and quarantining -- the whole file with all
    /// 12 weeks of cards and the lifetime counters.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        taskIds = try container.decodeIfPresent([String].self, forKey: .taskIds) ?? []
        completed = try container.decodeIfPresent([String: String].self, forKey: .completed)
        linesDone = try container.decodeIfPresent([String].self, forKey: .linesDone)
        full = try container.decodeIfPresent(Bool.self, forKey: .full)
    }

    /// `completed` with integer keys (unparsable keys are dropped).
    public var completedByIndex: [Int: String] {
        var result: [Int: String] = [:]
        for (key, day) in completed ?? [:] {
            if let index = Int(key) { result[index] = day }
        }
        return result
    }

    public mutating func setCompleted(_ byIndex: [Int: String]) {
        var stored: [String: String] = [:]
        for (index, day) in byIndex { stored[String(index)] = day }
        completed = stored.isEmpty ? nil : stored
    }

    public var isFull: Bool { full ?? false }
}

public actor BingoStore {
    struct Snapshot: Codable, Equatable {
        /// "2026-W39" -> card.
        var cards: [String: BingoCardRecord]?
        var totalLines: Int?
        var fullCards: Int?
    }

    static let category = "BingoStore"
    /// Weeks of cards kept (design D7).
    public static let maxCards = 12

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("bingo.json")
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

    public func card(week: WeekKey) -> BingoCardRecord? {
        loadIfNeeded()
        return snapshot.cards?[week.rawValue]
    }

    /// Every stored card, newest week first (unparsable keys skipped).
    public func allCards() -> [(week: WeekKey, card: BingoCardRecord)] {
        loadIfNeeded()
        var result: [(week: WeekKey, card: BingoCardRecord)] = []
        for (key, card) in snapshot.cards ?? [:] {
            if let week = WeekKey(rawValue: key) { result.append((week: week, card: card)) }
        }
        return result.sorted { $0.week > $1.week }
    }

    public func totalLines() -> Int {
        loadIfNeeded()
        return snapshot.totalLines ?? 0
    }

    public func fullCards() -> Int {
        loadIfNeeded()
        return snapshot.fullCards ?? 0
    }

    // MARK: - Writes (in memory; `save()` persists)

    public func setCard(_ card: BingoCardRecord, week: WeekKey) {
        loadIfNeeded()
        var cards = snapshot.cards ?? [:]
        cards[week.rawValue] = card
        snapshot.cards = cards
    }

    public func addLines(_ count: Int) {
        loadIfNeeded()
        guard count > 0 else { return }
        snapshot.totalLines = (snapshot.totalLines ?? 0) + count
    }

    public func addFullCard() {
        loadIfNeeded()
        snapshot.fullCards = (snapshot.fullCards ?? 0) + 1
    }

    /// Keeps only the newest `maxCards` weeks.
    public func prune() {
        loadIfNeeded()
        guard let cards = snapshot.cards, cards.count > Self.maxCards else { return }
        let keep = Set(allCards().prefix(Self.maxCards).map { $0.week.rawValue })
        snapshot.cards = cards.filter { keep.contains($0.key) }
    }

    public func save() throws {
        loadIfNeeded()
        try persist()
    }
}

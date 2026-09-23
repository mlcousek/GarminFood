// DayNote.swift
//
// A free-text note plus quick tags for one day (add-day-notes). The owner
// wants to look back at a day in Trends and see WHY it looked the way it
// did -- a race, a party, a sick day. LOCAL ONLY: Garmin has no notes
// route at all (there is nothing in docs/garmin-routes.json to sync to), so
// unlike food/weight/water there is no outbox and nothing waits on the
// network. This is the whole feature's source of truth.
//
// Keyed by the same `yyyy-MM-dd` string the rest of the app uses for "the
// day shown on Today" -- `NutritionDate.string(from:)`, which is exactly
// what `DayLogLoader.dateString` produces for its `selectedDate`. One
// record per day; there is no separate note id because a note has no
// identity independent of its day (same reasoning as `FavoriteFood` keyed
// by `food.id`).
//
// An empty note (blank text after trimming, no tags) is DELETED rather
// than stored, so "clearing a note" (spec scenario) leaves no trace and
// Trends never shows a marker for a day the user emptied out.
//
// Actor-isolated, JSON-file-backed, loaded through
// `FoodLogCoreStorage.loadPersistedJSON` (the quarantining loader) -- same
// shape as `FavoriteFoodStore` (FavoriteFood.swift) and `WeightStore`
// (WeightTracking.swift). Used by the app's `DayNoteCard` (Today screen,
// writes) and `TrendsView` (reads, for chart markers), both through the one
// instance held by `AppServices`.

import Foundation

/// A fixed set of quick tags (add-day-notes: custom user tags are a
/// non-goal). The raw value is what's persisted -- never rename a case's
/// raw value; add new cases instead. `DayNote`'s decoder drops unknown raw
/// values rather than failing, so removing a case later can't make the
/// whole notes file undecodable (and quarantined).
public enum DayNoteTag: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case race
    case training
    case celebration
    case sick
    case travel
    case party
    case restDay

    public var id: String { rawValue }

    public var emoji: String {
        switch self {
        case .race: return "🏃"
        case .training: return "🏋️"
        case .celebration: return "🎉"
        case .sick: return "🤒"
        case .travel: return "✈️"
        case .party: return "🍺"
        case .restDay: return "😴"
        }
    }

    public var title: String {
        switch self {
        case .race: return "Race"
        case .training: return "Training"
        case .celebration: return "Celebration"
        case .sick: return "Sick"
        case .travel: return "Travel"
        case .party: return "Party"
        case .restDay: return "Rest day"
        }
    }

    /// `tags` de-duplicated and put in `allCases` order, so the same set of
    /// tags always persists and displays identically regardless of the
    /// order the user tapped them in.
    public static func canonical<S: Sequence>(_ tags: S) -> [DayNoteTag] where S.Element == DayNoteTag {
        let set = Set(tags)
        return allCases.filter { set.contains($0) }
    }
}

public struct DayNote: Codable, Sendable, Equatable, Identifiable {
    /// `yyyy-MM-dd`, as produced by `NutritionDate.string(from:)`.
    public let day: String
    /// Stored exactly as typed (not trimmed), so reopening the day shows
    /// what the user wrote; only the emptiness check trims.
    public var text: String
    /// Always canonical (`DayNoteTag.canonical`) -- see `init`.
    public var tags: [DayNoteTag]
    public var updatedAt: Date

    public var id: String { day }

    public init(day: String, text: String, tags: [DayNoteTag], updatedAt: Date = Date()) {
        self.day = day
        self.text = text
        self.tags = DayNoteTag.canonical(tags)
        self.updatedAt = updatedAt
    }

    /// Blank text (after trimming whitespace/newlines) and no tags -- such a
    /// note is never stored.
    public var isEmpty: Bool {
        DayNote.isEmpty(text: text, tags: tags)
    }

    public static func isEmpty(text: String, tags: [DayNoteTag]) -> Bool {
        tags.isEmpty && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case day, text, tags, updatedAt
    }

    /// Lenient on `tags`: an unknown raw value is dropped instead of
    /// failing the whole file (see `DayNoteTag`'s doc comment).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let day = try container.decode(String.self, forKey: .day)
        let text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        let rawTags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date(timeIntervalSince1970: 0)
        self.init(day: day, text: text, tags: rawTags.compactMap(DayNoteTag.init(rawValue:)), updatedAt: updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(day, forKey: .day)
        try container.encode(text, forKey: .text)
        try container.encode(tags.map(\.rawValue), forKey: .tags)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `FavoriteFoodStore`.
public actor DayNoteStore {
    private let fileURL: URL
    private var notesByDay: [String: DayNote] = [:]
    private var loaded = false

    public init(fileURL: URL = DayNoteStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("day-notes.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([DayNote].self, from: fileURL, decoder: decoder, category: "DayNoteStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        let decoded = result.value ?? []
        // An empty record can only exist here if the file was edited by
        // hand or written by a future version -- drop it so it never shows
        // a Trends marker for an empty day.
        notesByDay = Dictionary(decoded.filter { !$0.isEmpty }.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "DayNoteStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(notesByDay.values).sorted { $0.day < $1.day })
        try data.write(to: fileURL, options: .atomic)
    }

    public func note(for day: String) -> DayNote? {
        loadIfNeeded()
        return notesByDay[day]
    }

    /// Every stored note, oldest day first (`yyyy-MM-dd` sorts
    /// chronologically as a plain string).
    public func all() -> [DayNote] {
        loadIfNeeded()
        return notesByDay.values.sorted { $0.day < $1.day }
    }

    /// Notes for days in `from...to` (inclusive, `yyyy-MM-dd`), oldest
    /// first -- what a Trends chart over a date range needs.
    public func notes(from startDay: String, to endDay: String) -> [DayNote] {
        loadIfNeeded()
        return notesByDay.values
            .filter { $0.day >= startDay && $0.day <= endDay }
            .sorted { $0.day < $1.day }
    }

    /// Writes the day's note, or deletes it when `text`/`tags` are empty
    /// (`DayNote.isEmpty`). Returns what is now stored for the day (`nil`
    /// after a delete).
    ///
    /// Idempotent: saving exactly what's already stored (or saving empty
    /// for a day with nothing stored) touches neither `updatedAt` nor the
    /// file. The Today card relies on this -- it flushes on disappear and
    /// on backgrounding regardless of whether anything actually changed.
    @discardableResult
    public func save(day: String, text: String, tags: [DayNoteTag], now: Date = Date()) throws -> DayNote? {
        loadIfNeeded()
        let canonicalTags = DayNoteTag.canonical(tags)

        if DayNote.isEmpty(text: text, tags: canonicalTags) {
            guard notesByDay.removeValue(forKey: day) != nil else { return nil }
            try persist()
            return nil
        }

        if let existing = notesByDay[day], existing.text == text, existing.tags == canonicalTags {
            return existing
        }

        let note = DayNote(day: day, text: text, tags: canonicalTags, updatedAt: now)
        notesByDay[day] = note
        try persist()
        return note
    }

    public func delete(day: String) throws {
        loadIfNeeded()
        guard notesByDay.removeValue(forKey: day) != nil else { return }
        try persist()
    }
}

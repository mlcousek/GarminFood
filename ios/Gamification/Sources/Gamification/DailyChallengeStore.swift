import Foundation

// DailyChallengeStore.swift
//
// Persists which two daily-challenge templates were assigned to each
// recent nutrition-day, and which of those have already had their
// completion XP awarded -- daily-challenges spec's "the same two daily
// challenges already assigned for that day are shown" (same-day
// stability) and "does not repeat within 30 days" requirements. Same
// JSON-file-actor pattern as every other store in this package.
//
// Deliberately a SEPARATE store from `ChallengeStore`, not an extension of
// it: `ChallengeStore` is architecturally single-slot (design.md D3 of
// this change) and its rotation model (replace on completion or window
// elapse) does not fit "exactly two, exactly one nutrition-day each,
// reselected every day" at all.
public actor DailyChallengeStore {
    private struct DayRecord: Codable {
        var templateIds: [String]
        var completedTemplateIds: [String] = []
    }

    private struct Snapshot: Codable {
        var byDay: [String: DayRecord] = [:]
        /// Day keys (`yyyy-MM-dd`), oldest first, for pruning.
        var order: [String] = []
        /// A true lifetime total, independent of `maxStoredDays` pruning --
        /// same reasoning as `LifetimeStatsStore`: the achievements spec's
        /// "completed N daily challenges total" tiers go well past what
        /// the bounded `byDay` window could ever answer on its own.
        var totalCompletedEver: Int = 0
    }

    /// Bounds the file size and doubles as the window `recentlyShown`
    /// scans -- generous relative to `noRepeatDays` (30) so the no-repeat
    /// rule always has enough history to check against.
    public static let maxStoredDays = 60
    public static let noRepeatDays = 30
    public static let dailyChallengesPerDay = 2

    private let fileURL: URL
    private var snapshot = Snapshot()
    private var loaded = false

    public init(fileURL: URL = DailyChallengeStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        GamificationStorage.directory().appendingPathComponent("daily-challenges.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        // Unreadable (e.g. before first unlock): don't latch, retry on next
        // access; `persist()` refuses to overwrite it meanwhile.
        let result = GamificationStorage.loadPersistedJSON(Snapshot.self, from: fileURL, decoder: JSONDecoder(), category: "DailyChallengeStore")
        loaded = !result.isUnreadable
        snapshot = result.value ?? snapshot
    }

    private func persist() throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "DailyChallengeStore")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    /// Returns `day`'s two daily challenges, assigning them (deterministically,
    /// seeded by `day`) the first time this is called for that day; every
    /// later call the same day returns the same two, unchanged.
    @discardableResult
    public func templatesForDay(
        _ day: String,
        catalog: [DailyChallengeTemplate],
        calendar: Calendar = .current
    ) throws -> [DailyChallengeTemplate] {
        loadIfNeeded()
        if let existing = snapshot.byDay[day] {
            return existing.templateIds.compactMap { id in catalog.first { $0.id == id } }
        }
        guard let today = NutritionDayBoundary.date(fromDayString: day, calendar: calendar) else { return [] }

        let picked = DailyChallengeSelection.pick(
            from: catalog,
            lastShown: lastShownMap(calendar: calendar),
            seed: day,
            today: today,
            noRepeatDays: Self.noRepeatDays,
            calendar: calendar,
            count: Self.dailyChallengesPerDay
        )
        snapshot.byDay[day] = DayRecord(templateIds: picked.map(\.id))
        snapshot.order.append(day)
        prune()
        try persist()
        return picked
    }

    /// Records that `templateId`'s daily challenge on `day` is complete.
    /// Returns `true` only the FIRST time this is recorded for that
    /// (day, templateId) pair -- callers use this to award XP exactly
    /// once, the same idempotency shape as `XPStore`'s day-keyed bonuses.
    @discardableResult
    public func markCompleted(templateId: String, day: String) throws -> Bool {
        loadIfNeeded()
        guard var record = snapshot.byDay[day], record.templateIds.contains(templateId) else { return false }
        guard !record.completedTemplateIds.contains(templateId) else { return false }
        record.completedTemplateIds.append(templateId)
        snapshot.byDay[day] = record
        snapshot.totalCompletedEver += 1
        try persist()
        return true
    }

    public func completedTemplateIds(day: String) -> Set<String> {
        loadIfNeeded()
        return Set(snapshot.byDay[day]?.completedTemplateIds ?? [])
    }

    /// achievements spec's "completed N daily challenges total" -- see
    /// `Snapshot.totalCompletedEver`'s doc comment.
    public func totalCompletedEver() -> Int {
        loadIfNeeded()
        return snapshot.totalCompletedEver
    }

    /// Every template id's most recent assignment date, derived from the
    /// bounded retained history -- the basis for the 30-day no-repeat rule.
    private func lastShownMap(calendar: Calendar) -> [String: Date] {
        var result: [String: Date] = [:]
        for (dayKey, record) in snapshot.byDay {
            guard let date = NutritionDayBoundary.date(fromDayString: dayKey, calendar: calendar) else { continue }
            for id in record.templateIds {
                if let existing = result[id] {
                    result[id] = max(existing, date)
                } else {
                    result[id] = date
                }
            }
        }
        return result
    }

    private func prune() {
        guard snapshot.order.count > Self.maxStoredDays else { return }
        let overflow = snapshot.order.count - Self.maxStoredDays
        for day in snapshot.order.prefix(overflow) { snapshot.byDay.removeValue(forKey: day) }
        snapshot.order.removeFirst(overflow)
    }
}

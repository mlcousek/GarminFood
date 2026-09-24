// ActivityCache.swift
//
// Per-day cache of the two Garmin "movement" facts gamification reads
// (design D4): the day's active kcal (from the daily user summary the Today
// screen's `DayLogLoader` ALREADY fetches -- no new request) and the day's
// Garmin activities (from the READ-ONLY activities list route,
// docs/garmin-routes.json `activitiesSearch`, read by the app's
// `GamificationSignalsSync` on refresh, never on a confirm path).
//
// Cached so signals work offline and so a feature never waits on the
// network: `DaySignalsBuilder` reads only this file's values.
//
// Day assignment: an activity belongs to the LOCAL calendar date of its
// `startTimeLocal` (the watch's clock where it happened), while its instant
// (`ActivitySummary.start`) is parsed from `startTimeGMT` as UTC -- so
// travelling across time zones can neither move a run to another day nor
// shift a "protein within 60 min after an activity" window.
//
// `activities == nil` means "never read for this day" (unknown);
// `[]` means "read, none happened". Only the latter lets a rule say "no
// activity today".
//
// Capped at `maxDays` (120) newest days; unreadable-file contract as every
// store here (fix-silent-store-wipe).
//
// Depended on by: DaySignalsBuilder (via SignalsInput), the app's
// DayLogLoader (active kcal writer), GamificationSignalsSync (activities
// writer), FeatureHost (reader).

import Foundation
import GarminKit

/// One day's cached movement facts. Every field but `day` is Optional so
/// files written by older/newer versions always decode.
public struct DayActivity: Codable, Sendable, Equatable {
    public let day: String
    public var activeKcal: Double?
    public var activities: [ActivitySummary]?
    public var fetchedAt: Date?

    public init(day: String, activeKcal: Double? = nil, activities: [ActivitySummary]? = nil, fetchedAt: Date? = nil) {
        self.day = day
        self.activeKcal = activeKcal
        self.activities = activities
        self.fetchedAt = fetchedAt
    }
}

extension ActivitySummary {
    /// Adapter from the wire DTO. `nil` when the activity has no id, no
    /// parseable start or no local start date -- without those it can be
    /// neither de-duplicated nor placed on a day.
    public init?(garmin activity: GarminActivity) {
        guard let rawId = activity.activityId,
              let gmt = activity.startTimeGMT.flatMap(ActivityCacheStore.parseGMT),
              let day = activity.startTimeLocal.flatMap(ActivityCacheStore.localDay)
        else { return nil }
        self.init(
            id: String(rawId),
            typeKey: activity.typeKey ?? "unknown",
            day: day,
            start: gmt,
            durationS: max(0, activity.duration ?? 0),
            calories: activity.calories,
            distanceM: activity.distance
        )
    }
}

public actor ActivityCacheStore {
    public static let maxDays = 120

    private let fileURL: URL
    private var days: [String: DayActivity] = [:]
    private var loaded = false

    public init(fileURL: URL = ActivityCacheStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("activity-cache.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([DayActivity].self, from: fileURL, decoder: decoder, category: "ActivityCacheStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        days = Dictionary((result.value ?? []).map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "ActivityCacheStore")
        if days.count > Self.maxDays {
            let keep = Set(days.keys.sorted(by: >).prefix(Self.maxDays))
            days = days.filter { keep.contains($0.key) }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(days.values.sorted { $0.day < $1.day })
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    /// Records the day's active kcal (the daily user summary's
    /// `activeKilocalories`). A `nil` value leaves a known one in place.
    public func recordActiveKcal(_ kcal: Double?, day: String, now: Date = Date()) throws {
        loadIfNeeded()
        guard let kcal else { return }
        var entry = days[day] ?? DayActivity(day: day)
        guard entry.activeKcal != kcal else { return }
        entry.activeKcal = kcal
        entry.fetchedAt = now
        days[day] = entry
        try persist()
    }

    /// Records one activities read covering `days` (every `yyyy-MM-dd` the
    /// request's date range spanned): each covered day gets exactly the
    /// activities whose local start date is that day -- `[]` when none --
    /// replacing what was cached. Activities dated outside `days` are
    /// ignored (the range did not fully cover their day).
    public func recordActivities(_ activities: [ActivitySummary], coveringDays covered: [String], now: Date = Date()) throws {
        loadIfNeeded()
        let coveredSet = Set(covered)
        guard !coveredSet.isEmpty else { return }
        var byDay: [String: [ActivitySummary]] = [:]
        var seenIds = Set<String>()
        for activity in activities.sorted(by: { $0.start < $1.start }) where coveredSet.contains(activity.day) {
            guard seenIds.insert(activity.id).inserted else { continue }
            byDay[activity.day, default: []].append(activity)
        }
        for day in coveredSet {
            var entry = days[day] ?? DayActivity(day: day)
            entry.activities = byDay[day] ?? []
            entry.fetchedAt = now
            days[day] = entry
        }
        try persist()
    }

    /// Convenience over the wire DTOs: converts (dropping unplaceable ones)
    /// and records.
    public func recordActivities(fromGarmin activities: [GarminActivity], coveringDays covered: [String], now: Date = Date()) throws {
        try recordActivities(activities.compactMap(ActivitySummary.init(garmin:)), coveringDays: covered, now: now)
    }

    public func day(_ day: String) -> DayActivity? {
        loadIfNeeded()
        return days[day]
    }

    /// Every cached day, oldest first.
    public func all() -> [DayActivity] {
        loadIfNeeded()
        return days.values.sorted { $0.day < $1.day }
    }

    // MARK: - Parsing ("2026-09-23 19:22:08", no zone designator)

    /// `startTimeGMT` as a UTC instant. Accepts an optional fractional part
    /// and a `T` separator defensively.
    public static func parseGMT(_ raw: String) -> Date? {
        let normalized = raw.replacingOccurrences(of: "T", with: " ")
        let trimmed = normalized.split(separator: ".").first.map(String.init) ?? normalized
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: trimmed)
    }

    /// The `yyyy-MM-dd` date part of `startTimeLocal`, validated.
    public static func localDay(_ raw: String) -> String? {
        let datePart = String(raw.prefix(10))
        let pieces = datePart.split(separator: "-")
        guard datePart.count == 10, pieces.count == 3,
              pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              pieces.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return datePart
    }
}

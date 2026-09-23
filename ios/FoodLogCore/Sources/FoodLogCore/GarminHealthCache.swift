// GarminHealthCache.swift
//
// The last good Garmin reads for weight and water (sync-weight-hydration-
// with-garmin, task 2.4 / design.md D2 + "Fallback when routes break"). WHY
// it exists: Garmin is now the source of truth for weigh-ins and the daily
// water total, but the app must still render instantly and offline -- a
// card that waits on connectapi.garmin.com, or goes blank without a
// network, would break this project's local-first rule. So every
// successful read is written here, the cards render from this file first,
// and a failed refresh just leaves the last good values in place (with a
// quiet "couldn't refresh" caption in the UI).
//
// Keyed per DAY (`yyyy-MM-dd`, Garmin's own `calendarDate`) with a
// `fetchedAt` per day, because FoodLogCore's merge logic needs to know,
// for each day, whether Garmin's copy is newer than a local delivery
// (`WeightHistoryMerge`, `HydrationDayTotal`). `GarminHealthRefreshPlan`
// decides what to re-read: the long 90-day weight history at most once a
// day, just today+yesterday otherwise (D2).
//
// Depends on GarminKit only for the wire models it stores as-is
// (`GarminWeighIn`, `HydrationDaily`, `NutritionSettings`); loads through
// `FoodLogCoreStorage.loadPersistedJSON` (quarantine instead of silent
// wipe, fix-silent-store-wipe). Losing this file is harmless -- it is a
// cache, refilled on the next refresh -- but it follows the same loader
// convention as every other store. Used by the app's `WeightLoader`/
// `HydrationLoader` (GarminFood/Weight, GarminFood/Hydration).

import Foundation
import GarminKit

/// One day's weigh-ins as Garmin returned them. An EMPTY `weighIns` is
/// meaningful: Garmin was asked about this day and had nothing (the range
/// route omits such days, so the refresh records them explicitly).
public struct CachedWeighInDay: Codable, Sendable, Equatable {
    public var weighIns: [GarminWeighIn]
    public var fetchedAt: Date

    public init(weighIns: [GarminWeighIn], fetchedAt: Date) {
        self.weighIns = weighIns
        self.fetchedAt = fetchedAt
    }
}

/// One day's Garmin water total + goal, as last read.
public struct CachedHydrationDay: Codable, Sendable, Equatable {
    public var daily: HydrationDaily
    public var fetchedAt: Date

    public init(daily: HydrationDaily, fetchedAt: Date) {
        self.daily = daily
        self.fetchedAt = fetchedAt
    }
}

/// The weight-goal half of Garmin's nutrition settings
/// (`GET /nutrition-service/settings/{date}`, live-verified 2026-09-23:
/// startingWeight 80400, targetWeightGoal 76000 -- GRAMS -- weightChangeType
/// LOSS, weightChangeRate 250, presumed g/week).
public struct CachedWeightGoal: Codable, Sendable, Equatable {
    public var startingWeightGrams: Double?
    public var targetWeightGrams: Double?
    public var weightChangeRateGramsPerWeek: Double?
    /// "LOSS" observed; presumably also "GAIN"/"MAINTAIN".
    public var weightChangeType: String?
    public var fetchedAt: Date

    public init(
        startingWeightGrams: Double?,
        targetWeightGrams: Double?,
        weightChangeRateGramsPerWeek: Double?,
        weightChangeType: String?,
        fetchedAt: Date
    ) {
        self.startingWeightGrams = startingWeightGrams
        self.targetWeightGrams = targetWeightGrams
        self.weightChangeRateGramsPerWeek = weightChangeRateGramsPerWeek
        self.weightChangeType = weightChangeType
        self.fetchedAt = fetchedAt
    }

    public init(settings: NutritionSettings, fetchedAt: Date) {
        self.init(
            startingWeightGrams: settings.startingWeight,
            targetWeightGrams: settings.targetWeightGoal,
            weightChangeRateGramsPerWeek: settings.weightChangeRate,
            weightChangeType: settings.weightChangeType,
            fetchedAt: fetchedAt
        )
    }
}

/// Everything cached, as one value -- what `GarminHealthCacheStore.current()`
/// hands the loaders.
public struct GarminHealthSnapshot: Codable, Sendable, Equatable {
    public var weighInDays: [String: CachedWeighInDay]
    public var hydrationDays: [String: CachedHydrationDay]
    public var weightGoal: CachedWeightGoal?
    /// When the long (90-day) weigh-in range was last read successfully --
    /// `GarminHealthRefreshPlan` re-reads it at most once a day.
    public var lastFullWeightRangeFetchAt: Date?

    public init(
        weighInDays: [String: CachedWeighInDay] = [:],
        hydrationDays: [String: CachedHydrationDay] = [:],
        weightGoal: CachedWeightGoal? = nil,
        lastFullWeightRangeFetchAt: Date? = nil
    ) {
        self.weighInDays = weighInDays
        self.hydrationDays = hydrationDays
        self.weightGoal = weightGoal
        self.lastFullWeightRangeFetchAt = lastFullWeightRangeFetchAt
    }

    enum CodingKeys: String, CodingKey {
        case weighInDays, hydrationDays, weightGoal, lastFullWeightRangeFetchAt
    }

    /// Every key optional on decode, so a later build that adds a field
    /// (or drops one) never makes an existing cache file undecodable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weighInDays = try container.decodeIfPresent([String: CachedWeighInDay].self, forKey: .weighInDays) ?? [:]
        hydrationDays = try container.decodeIfPresent([String: CachedHydrationDay].self, forKey: .hydrationDays) ?? [:]
        weightGoal = try container.decodeIfPresent(CachedWeightGoal.self, forKey: .weightGoal)
        lastFullWeightRangeFetchAt = try container.decodeIfPresent(Date.self, forKey: .lastFullWeightRangeFetchAt)
    }

    /// Every cached Garmin weigh-in, de-duplicated by `samplePk`, newest
    /// first.
    public var allWeighIns: [GarminWeighIn] {
        var seen = Set<Int>()
        return weighInDays.values
            .flatMap(\.weighIns)
            .filter { seen.insert($0.samplePk).inserted }
            .sorted { $0.timestampGMT > $1.timestampGMT }
    }

    /// `calendarDate` -> when Garmin was last asked about that day.
    public var weighInDayFetchTimes: [String: Date] {
        weighInDays.mapValues(\.fetchedAt)
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `WeightStore`.
public actor GarminHealthCacheStore {
    /// How many days of weigh-ins / water totals the file keeps. Bounded so
    /// the file can't grow forever; comfortably above the 90-day history the
    /// Weight screen shows.
    public static let weighInDaysKept = 120
    public static let hydrationDaysKept = 14

    private let fileURL: URL
    private var state = GarminHealthSnapshot()
    private var loaded = false

    public init(fileURL: URL = GarminHealthCacheStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("garmin-health-cache.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        state = FoodLogCoreStorage.loadPersistedJSON(GarminHealthSnapshot.self, from: fileURL, decoder: decoder, category: "GarminHealthCacheStore") ?? GarminHealthSnapshot()
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    public func current() -> GarminHealthSnapshot {
        loadIfNeeded()
        return state
    }

    /// Records a weigh-in read covering `days` (every `yyyy-MM-dd` in the
    /// requested range, INCLUDING days Garmin returned nothing for -- see
    /// `CachedWeighInDay`). Each covered day is REPLACED, so a weigh-in
    /// deleted in Garmin Connect disappears here on the next read.
    /// `isFullRange` marks the long history read (`GarminHealthRefreshPlan`).
    public func storeWeighIns(_ weighIns: [GarminWeighIn], coveringDays days: [String], fetchedAt: Date, isFullRange: Bool) throws {
        loadIfNeeded()
        let byDay = Dictionary(grouping: weighIns, by: \.calendarDate)
        for day in days {
            state.weighInDays[day] = CachedWeighInDay(weighIns: byDay[day] ?? [], fetchedAt: fetchedAt)
        }
        // A sample dated outside `days` (shouldn't happen, but Garmin's
        // calendarDate is its own) is still kept rather than dropped.
        for (day, samples) in byDay where !days.contains(day) {
            state.weighInDays[day] = CachedWeighInDay(weighIns: samples, fetchedAt: fetchedAt)
        }
        if isFullRange {
            state.lastFullWeightRangeFetchAt = fetchedAt
        }
        state.weighInDays = Self.keepingNewest(state.weighInDays, count: Self.weighInDaysKept)
        try persist()
    }

    public func storeHydration(_ daily: HydrationDaily, for day: String, fetchedAt: Date) throws {
        loadIfNeeded()
        state.hydrationDays[day] = CachedHydrationDay(daily: daily, fetchedAt: fetchedAt)
        state.hydrationDays = Self.keepingNewest(state.hydrationDays, count: Self.hydrationDaysKept)
        try persist()
    }

    public func storeWeightGoal(_ goal: CachedWeightGoal) throws {
        loadIfNeeded()
        state.weightGoal = goal
        try persist()
    }

    /// `yyyy-MM-dd` keys sort chronologically as strings.
    static func keepingNewest<Value>(_ days: [String: Value], count: Int) -> [String: Value] {
        guard days.count > count else { return days }
        let kept = Set(days.keys.sorted(by: >).prefix(count))
        return days.filter { kept.contains($0.key) }
    }
}

/// What to re-read from Garmin on a refresh -- pure, so the "long history
/// at most once a day" rule (design.md D2) is unit-testable.
public enum GarminHealthRefreshPlan {
    /// The Weight screen's history window.
    public static let historyDays = 90
    /// How old the long history may get before it is re-read in full.
    public static let fullRangeMaxAge: TimeInterval = 24 * 60 * 60

    public struct WeighInWindow: Sendable, Equatable {
        public let startDate: String
        public let endDate: String
        /// Every day in `startDate...endDate`, oldest first.
        public let days: [String]
        public let isFullRange: Bool
    }

    /// The full `historyDays` window when forced (pull-to-refresh), when it
    /// has never been read, or when the last full read is older than
    /// `fullRangeMaxAge`; otherwise just yesterday + today -- the only days
    /// a weigh-in from a scale or Connect realistically lands on between
    /// daily full reads.
    public static func weighInWindow(
        lastFullRangeFetchAt: Date?,
        now: Date,
        force: Bool,
        calendar: Calendar = .current
    ) -> WeighInWindow {
        let needsFull = force
            || lastFullRangeFetchAt.map { now.timeIntervalSince($0) > fullRangeMaxAge || $0 > now } ?? true
        let span = needsFull ? historyDays : 2
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(span - 1), to: today) ?? today
        let days = dayStrings(from: start, through: today, calendar: calendar)
        return WeighInWindow(
            startDate: days.first ?? NutritionDate.string(from: today, calendar: calendar),
            endDate: days.last ?? NutritionDate.string(from: today, calendar: calendar),
            days: days,
            isFullRange: needsFull
        )
    }

    /// `yyyy-MM-dd` for every calendar day from `start` through `end`,
    /// inclusive, oldest first.
    public static func dayStrings(from start: Date, through end: Date, calendar: Calendar = .current) -> [String] {
        var result: [String] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            result.append(NutritionDate.string(from: day, calendar: calendar))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

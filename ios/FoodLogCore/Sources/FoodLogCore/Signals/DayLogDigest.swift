// DayLogDigest.swift
//
// A small, persisted digest of one Garmin day log (design D4), so the
// gamification signals (`DaySignalsBuilder`) know what Garmin actually
// recorded for a day -- names, brands, per-entry macros incl. fibre/sugar,
// the day's goals -- WITHOUT a new request: the app writes a digest wherever
// it already fetched `GET /nutrition-service/food/logs/{date}` (the Today
// screen's `DayLogLoader`, `GamificationEngine.refreshGoalStatus`).
//
// Why a digest and not the raw `DailyFoodLog`: GarminKit's wire types are
// Decodable-only and Gamification must never name a GarminKit type, so the
// digest is plain FoodLogCore values (strings, numbers, dates). The adapter
// `DayLogDigest(log:day:fetchedAt:)` is the one place that reads the wire
// shape.
//
// `DayLogDigestStore` keeps the last `maxDays` (120) days and follows the
// unreadable-file contract every store here follows (fix-silent-store-wipe:
// quarantine an undecodable file, never latch `loaded` while unreadable,
// `ensureSafeToWrite` first in `persist`).
//
// Depended on by: DaySignalsBuilder (via SignalsInput), the app's
// DayLogLoader / GamificationEngine (writers), FeatureHost (reader).

import Foundation
import GarminKit

public struct DayLogDigest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public let foodId: String
        public let name: String?
        public let brand: String?
        /// When Garmin says the entry was logged (`logTimestamp`), UTC.
        public let timestamp: Date?
        /// `GarminKit.MealType` raw value ("BREAKFAST", "LUNCH", "SNACKS",
        /// "DINNER") as a plain string, or `nil` when the entry's meal
        /// could not be determined.
        public let mealType: String?
        public let calories: Double?
        public let protein: Double?
        public let carbs: Double?
        public let fat: Double?
        public let fiber: Double?
        public let sugar: Double?
        /// Written by THIS app (`logSource` "GCW"). Optional for forward
        /// compatibility with digests written before the field existed.
        public let fromThisApp: Bool?

        public init(
            foodId: String,
            name: String? = nil,
            brand: String? = nil,
            timestamp: Date? = nil,
            mealType: String? = nil,
            calories: Double? = nil,
            protein: Double? = nil,
            carbs: Double? = nil,
            fat: Double? = nil,
            fiber: Double? = nil,
            sugar: Double? = nil,
            fromThisApp: Bool? = nil
        ) {
            self.foodId = foodId
            self.name = name
            self.brand = brand
            self.timestamp = timestamp
            self.mealType = mealType
            self.calories = calories
            self.protein = protein
            self.carbs = carbs
            self.fat = fat
            self.fiber = fiber
            self.sugar = sugar
            self.fromThisApp = fromThisApp
        }
    }

    /// `yyyy-MM-dd`.
    public let day: String
    /// When the underlying day log was fetched. Local entries newer than
    /// this are appended by the builder (they were logged after the fetch).
    public let fetchedAt: Date
    public let totals: MacroTotals
    public let goals: MacroGoals?
    public let entries: [Entry]

    public init(day: String, fetchedAt: Date, totals: MacroTotals, goals: MacroGoals?, entries: [Entry]) {
        self.day = day
        self.fetchedAt = fetchedAt
        self.totals = totals
        self.goals = goals
        self.entries = entries
    }
}

extension DayLogDigest {
    /// Adapter from Garmin's wire shape. Entries are read from each meal's
    /// `loggedFoods` (which carries the meal name) and then from
    /// `loggedFoodsWithServingSizes`; the same entry appearing in both is
    /// kept once (by `logId`, else by food id + timestamp). A loose entry's
    /// meal is resolved through the meal instance id (`mealId`), which is
    /// different for every date, so only this day's `mealDetails` can map it.
    public init(log: DailyFoodLog, day: String, fetchedAt: Date) {
        var mealNameById: [Int: String] = [:]
        for detail in log.mealDetails ?? [] {
            if let id = detail.meal?.mealId, let name = detail.meal?.mealName {
                mealNameById[id] = name
            }
        }

        var seen = Set<String>()
        var entries: [Entry] = []

        func append(_ food: LoggedFood, mealName: String?) {
            guard let foodId = food.foodMetaData?.foodId, !foodId.isEmpty else { return }
            let key = food.logId ?? "\(foodId)|\(food.logTimestamp ?? "")"
            guard seen.insert(key).inserted else { return }
            let resolvedMeal = mealName ?? food.mealId.flatMap { mealNameById[$0] }
            let content = food.nutritionContent
            entries.append(Entry(
                foodId: foodId,
                name: food.foodMetaData?.foodName,
                brand: food.foodMetaData?.brandName,
                timestamp: food.logTimestamp.flatMap(FastingLogMoments.parseTimestamp),
                mealType: resolvedMeal.flatMap { MealType(rawValue: $0) }?.rawValue,
                calories: content?.calories,
                protein: content?.protein,
                carbs: content?.carbs,
                fat: content?.fat,
                fiber: content?.fiber,
                sugar: content?.sugar,
                fromThisApp: food.isFromThisApp
            ))
        }

        for detail in log.mealDetails ?? [] {
            for food in detail.loggedFoods ?? [] {
                append(food, mealName: detail.meal?.mealName)
            }
        }
        for food in log.loggedFoodsWithServingSizes ?? [] {
            append(food, mealName: nil)
        }

        let content = log.dailyNutritionContent
        let totals = MacroTotals(
            calories: content?.calories ?? 0,
            protein: content?.protein ?? 0,
            carbs: content?.carbs ?? 0,
            fat: content?.fat ?? 0,
            // Fibre/sugar are only reported when some logged food carried
            // them; absent means "unknown", not zero, unless nothing at all
            // was logged.
            fiber: content?.fiber ?? (entries.isEmpty ? 0 : nil),
            sugar: content?.sugar ?? (entries.isEmpty ? 0 : nil)
        )

        var goals: MacroGoals?
        if let g = log.dailyNutritionGoals {
            goals = MacroGoals(
                calories: g.calories ?? g.adjustedCalories,
                protein: g.protein ?? g.adjustedProtein,
                carbs: g.carbs ?? g.adjustedCarbs,
                fat: g.fat ?? g.adjustedFat
            )
        }

        self.init(day: day, fetchedAt: fetchedAt, totals: totals, goals: goals, entries: entries)
    }
}

/// JSON-file-backed, actor-isolated, capped at `maxDays` most recent days.
public actor DayLogDigestStore {
    public static let maxDays = 120

    private let fileURL: URL
    private var digests: [String: DayLogDigest] = [:]
    private var loaded = false

    public init(fileURL: URL = DayLogDigestStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("day-log-digests.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([DayLogDigest].self, from: fileURL, decoder: decoder, category: "DayLogDigestStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        digests = Dictionary((result.value ?? []).map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "DayLogDigestStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(digests.values.sorted { $0.day < $1.day })
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    /// Stores (or replaces) the digest for its day and trims to the newest
    /// `maxDays` days. A digest identical to the stored one skips the write.
    public func save(_ digest: DayLogDigest) throws {
        loadIfNeeded()
        if digests[digest.day] == digest { return }
        digests[digest.day] = digest
        if digests.count > Self.maxDays {
            let keep = Set(digests.keys.sorted(by: >).prefix(Self.maxDays))
            digests = digests.filter { keep.contains($0.key) }
        }
        try persist()
    }

    public func digest(for day: String) -> DayLogDigest? {
        loadIfNeeded()
        return digests[day]
    }

    /// Every stored digest, oldest day first.
    public func all() -> [DayLogDigest] {
        loadIfNeeded()
        return digests.values.sorted { $0.day < $1.day }
    }
}

// UsageHistory.swift
//
// The local usage log (design.md D1, tasks 13.1-13.2): one `UsageEvent` per
// successful log, independent of Garmin's own `isFavorite`/`isRecent`
// flags, ranked by a blend of recency and frequency into the "quick pick"
// shelf (food-catalog spec's "A quick-pick shelf is ranked from local
// usage, not from a fresh search" requirement).
//
// STORAGE FORMAT -- documented deliberately plainly here because
// `add-gamification` (a parallel, separate effort) is expected to read this
// same file read-only for streak/XP calculations, per this phase's brief:
//
//   Path:   <Application Support>/FoodLogCore/usage-history.json
//   Shape:  a JSON ARRAY of objects, oldest first, each:
//             { "foodId": "<string>", "servingId": "<string>",
//               "numberOfUnits": <number>, "timestamp": "<ISO 8601 string>",
//               "nutritionDay": "<yyyy-MM-dd>", "mealType": "<MEAL>" }
//   `nutritionDay` (added 2026-09-16) is the date the entry was logged FOR,
//   the same date sent to Garmin, which the user can edit. Files written
//   before it existed lack the key; readers must treat it as optional and
//   fall back to `timestamp`.
//   `mealType` (added 2026-09-23, improve-log-food-shelves) is the meal the
//   entry was logged under, as `GarminKit.MealType`'s raw value
//   ("BREAKFAST" / "LUNCH" / "SNACKS" / "DINNER"). Optional for the same
//   reason: files written before it existed lack the key, and it is omitted
//   (not written as null) when unknown. Events without it simply don't
//   count toward any meal's "Usual for <meal>" shelf (MealUsualRanker).
//   Nothing else is in this file -- no wrapper object, no metadata header.
//   Encoded with `JSONEncoder.dateEncodingStrategy = .iso8601` specifically
//   so a non-Swift reader (or a Swift reader that doesn't want to import
//   this package) can parse it with any standard JSON + ISO 8601 library,
//   not just `Codable` with this exact type. Do not change this shape
//   without updating this comment and coordinating with `add-gamification`.
//   The file is capped at `UsageHistoryStore.maxStoredEvents` entries
//   (oldest trimmed first) so it cannot grow unbounded over the app's
//   lifetime.

import Foundation
import GarminKit

public struct UsageEvent: Codable, Sendable, Equatable {
    public let foodId: String
    public let servingId: String
    public let numberOfUnits: Double
    public let timestamp: Date
    /// `yyyy-MM-dd`: the day this entry was logged for, which is what
    /// streaks and challenges should count, rather than when the button
    /// happened to be pressed. `nil` for events recorded before the field
    /// existed.
    public let nutritionDay: String?
    /// The meal this entry was logged under. `nil` for events recorded
    /// before the field existed (2026-09-23) -- those never count toward a
    /// per-meal ranking, rather than being guessed from the clock.
    public let mealType: MealType?

    public init(
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        timestamp: Date,
        nutritionDay: String? = nil,
        mealType: MealType? = nil
    ) {
        self.foodId = foodId
        self.servingId = servingId
        self.numberOfUnits = numberOfUnits
        self.timestamp = timestamp
        self.nutritionDay = nutritionDay
        self.mealType = mealType
    }
}

/// JSON-file-backed, actor-isolated store -- same pattern as GarminKit's
/// `OutboxStore` (own file, own Application Support subdirectory, atomic
/// writes, `.completeUntilFirstUserAuthentication` protection so a
/// foreground drain right after unlock can still touch it).
public actor UsageHistoryStore {
    public static let maxStoredEvents = 500

    private let fileURL: URL
    private var events: [UsageEvent] = []
    private var loaded = false

    public init(fileURL: URL = UsageHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("usage-history.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = FoodLogCoreStorage.loadPersistedJSON([UsageEvent].self, from: fileURL, decoder: decoder, category: "UsageHistoryStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        events = result.value ?? []
    }

    private func persist() throws {
        try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "UsageHistoryStore")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(events)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    public func all() -> [UsageEvent] {
        loadIfNeeded()
        return events
    }

    /// Appends one event and trims to `maxStoredEvents`, oldest first.
    /// Called once per confirmed log entry (food-log-entry spec's "A
    /// confirmed entry updates local usage ranking" requirement).
    public func record(
        foodId: String,
        servingId: String,
        numberOfUnits: Double,
        timestamp: Date = Date(),
        nutritionDay: String? = nil,
        mealType: MealType? = nil
    ) throws {
        loadIfNeeded()
        events.append(UsageEvent(
            foodId: foodId,
            servingId: servingId,
            numberOfUnits: numberOfUnits,
            timestamp: timestamp,
            nutritionDay: nutritionDay,
            mealType: mealType
        ))
        if events.count > Self.maxStoredEvents {
            events.removeFirst(events.count - Self.maxStoredEvents)
        }
        try persist()
    }

    /// Fills in the meal of events recorded before `mealType` existed, from
    /// Garmin's own day logs (`UsageMealBackfill`). Runs over the CURRENT
    /// events inside the actor, so a log recorded while the day logs were
    /// being fetched is never lost. Returns how many were filled; writes
    /// only when that is more than zero.
    @discardableResult
    public func applyMealBackfill(_ logs: [String: DailyFoodLog]) throws -> Int {
        loadIfNeeded()
        let result = UsageMealBackfill.apply(to: events, logs: logs)
        guard result.filled > 0 else { return 0 }
        events = result.events
        try persist()
        return result.filled
    }
}

/// Pure ranking logic (task 13.2), extracted from the store so it is
/// testable with hand-built event arrays and no file I/O at all.
public enum QuickPick {
    public struct Entry: Sendable, Equatable {
        public let foodId: String
        public let servingId: String
        /// The quantity from the MOST RECENT event for this (food, serving)
        /// pair -- what a one-tap re-log should default to.
        public let numberOfUnits: Double
        public let score: Double
        public let lastUsedAt: Date
        public let useCount: Int
    }

    /// Ranks `(foodId, servingId)` pairs by a recency-weighted frequency
    /// score: each past event contributes `0.5 ^ (ageInDays / halfLifeDays)`
    /// to its pair's total, so logging the same thing often keeps it near
    /// the top, and logging something once a long time ago fades out --
    /// exactly the "combination of recency and frequency" the food-catalog
    /// spec calls for, as a single blended number rather than two signals
    /// the caller has to reconcile itself.
    ///
    /// Returns an empty array for empty input -- the spec's "no usage
    /// history exists yet -> quick-pick list is empty rather than populated
    /// with unranked guesses" scenario holds trivially.
    public static func rank(
        events: [UsageEvent],
        now: Date = Date(),
        halfLifeDays: Double = 7,
        limit: Int = 10
    ) -> [Entry] {
        guard !events.isEmpty else { return [] }

        struct Accumulator {
            var score: Double = 0
            var lastUsedAt: Date = .distantPast
            var lastNumberOfUnits: Double = 0
            var useCount: Int = 0
        }

        var byPair: [PairKey: Accumulator] = [:]
        for event in events {
            let key = PairKey(foodId: event.foodId, servingId: event.servingId)
            let ageInDays = max(0, now.timeIntervalSince(event.timestamp) / 86_400)
            let weight = pow(0.5, ageInDays / max(halfLifeDays, 0.0001))

            var accumulator = byPair[key] ?? Accumulator()
            accumulator.score += weight
            accumulator.useCount += 1
            if event.timestamp >= accumulator.lastUsedAt {
                accumulator.lastUsedAt = event.timestamp
                accumulator.lastNumberOfUnits = event.numberOfUnits
            }
            byPair[key] = accumulator
        }

        return byPair
            .map { key, accumulator in
                Entry(
                    foodId: key.foodId,
                    servingId: key.servingId,
                    numberOfUnits: accumulator.lastNumberOfUnits,
                    score: accumulator.score,
                    lastUsedAt: accumulator.lastUsedAt,
                    useCount: accumulator.useCount
                )
            }
            // Deterministic tie-break (equal score) by identifiers, so tests
            // and UI ordering never depend on `Dictionary`'s unordered
            // iteration.
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.foodId != $1.foodId { return $0.foodId < $1.foodId }
                return $0.servingId < $1.servingId
            }
            .prefix(limit)
            .map { $0 }
    }

    private struct PairKey: Hashable {
        let foodId: String
        let servingId: String
    }
}

/// Shared Application Support subdirectory for every JSON-file store in this
/// package (`UsageHistoryStore`, `ServingDefaultStore`, `CustomFoodStore`,
/// `FoodCacheStore`) -- one directory, one place to find them all by hand,
/// matching GarminKit's own "trivially inspectable" rationale for its
/// outbox file (there is no interactive debugger for this project -- see
/// openspec/config.yaml D9-style constraints referenced throughout GarminKit).
///
/// Public only so Gamification can reach `loadPersistedJSON` (see
/// PersistedStoreLoading.swift); `directory()` itself stays internal.
public enum FoodLogCoreStorage {
    static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("FoodLogCore", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

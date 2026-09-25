// FoodCache.swift
//
// A durable, local cache of every `Food` this process has ever seen (from a
// search result or a custom food), keyed by id. This exists to solve a gap
// the quick-pick shelf would otherwise have: `UsageHistoryStore` only
// records `(foodId, servingId, numberOfUnits, timestamp)` -- enough to rank,
// not enough to DISPLAY a name or macros. Re-fetching each quick-pick item
// from Garmin would reintroduce the network dependency the whole feature
// exists to avoid (food-catalog spec: "without typing or waiting on a
// search"). So every food a search or custom-food creation ever surfaces is
// also written here, and the quick-pick shelf reads names/macros from this
// cache instead.
//
// A cache miss (e.g. the app was reinstalled, or this food was logged from
// a different process before this cache existed) simply drops that entry
// from the rendered quick-pick list rather than showing a blank row --
// acceptable per design.md's own risk framing: this is a convenience shelf,
// not a synced state, and it recovers the next time that food is searched
// again.

import Foundation

public actor FoodCacheStore {
    private let fileURL: URL
    private var foodsById: [String: Food] = [:]
    private var loaded = false

    public init(fileURL: URL = FoodCacheStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("food-cache.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON([Food].self, from: fileURL, decoder: JSONDecoder(), category: "FoodCacheStore")
        // Unreadable (e.g. before first unlock): retry on next access.
        loaded = !result.isUnreadable
        let decoded = result.value ?? []
        foodsById = Dictionary(decoded.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    /// Best-effort, like every write here -- but it still must not replace
    /// a cache file this process never managed to read.
    private func persist() {
        do {
            try FoodLogCoreStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "FoodCacheStore")
        } catch {
            return
        }
        guard let data = try? JSONEncoder().encode(Array(foodsById.values)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func food(forId id: String) -> Food? {
        loadIfNeeded()
        return foodsById[id]
    }

    public func all() -> [String: Food] {
        loadIfNeeded()
        return foodsById
    }

    /// Merges in freshly-seen foods (from a search response or a newly
    /// created custom food). Best-effort: a write failure here must never
    /// surface as a user-facing error, since this cache is a display
    /// convenience, not the durable record of anything (the outbox and
    /// usage history are).
    public func upsert(_ foods: [Food]) {
        loadIfNeeded()
        for food in foods { foodsById[food.id] = food }
        persist()
    }

    /// The food-cache side effect of an edit, duplicate or copy, shared by
    /// `LogEntryCoordinator` and `LocalLogEntryCoordinator` so both modes
    /// behave the same (add-standalone-mode D4). Never overwrites a food
    /// already cached (e.g. from a search) -- at most adds the missing
    /// serving to it; otherwise caches the food as the entry describes it.
    func cacheForDisplay(
        foodId: String,
        name: String,
        brandName: String?,
        source: FoodSource,
        serving: Serving?,
        regionCode: String?,
        languageCode: String?
    ) {
        guard let serving else { return }
        if let existing = food(forId: foodId) {
            guard !existing.servings.contains(where: { $0.id == serving.id }) else { return }
            upsert([Food(
                id: existing.id,
                name: existing.name,
                brandName: existing.brandName,
                source: existing.source,
                servings: existing.servings + [serving],
                imageURL: existing.imageURL,
                garminIsFavorite: existing.garminIsFavorite,
                garminIsRecent: existing.garminIsRecent,
                regionCode: existing.regionCode,
                languageCode: existing.languageCode
            )])
        } else {
            upsert([Food(
                id: foodId,
                name: name,
                brandName: brandName,
                source: source,
                servings: [serving],
                regionCode: regionCode,
                languageCode: languageCode
            )])
        }
    }
}

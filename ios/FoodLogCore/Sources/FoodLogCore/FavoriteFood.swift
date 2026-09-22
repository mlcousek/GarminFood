// FavoriteFood.swift
//
// A user-marked "favorite" food (add-favorite-foods) -- LOCAL ONLY, unlike
// most of this package's other Garmin-synced concepts. Two things forced
// that choice, both established by this change's own research task, not
// assumed going in:
//
//   1. `docs/garmin-routes.json`'s `favoriteFoods` entry already tried GET
//      /nutrition-service/favorite/food and got a 405 (wrong method, route
//      genuinely exists). This change followed up as that entry's own notes
//      instructed -- checked every OSS Garmin Connect client this project
//      already trusts for an unconfirmed write contract (cyberjunky/
//      python-garminconnect, Taxuspt/garmin_mcp, tamcore/garmin-mcp) plus a
//      broad GitHub code search for the route path -- and found ZERO
//      field-level evidence for this route's request/response shape
//      anywhere. That is a materially weaker position than `addWeighIn`/
//      `addHydration` (GarminClient.swift), which DID find a real client's
//      exact contract before being implemented. Per this project's own rule
//      (openspec/config.yaml: never write to the Garmin account before the
//      write contract is documented, never guess at an undocumented path/
//      body shape), that route is NOT implemented here. See
//      docs/garmin-routes.json's `favoriteFoods` entry (2026-09-22 update)
//      for the full evidence trail.
//
//   2. Independent of (1), this app's "local-first, zero-network-wait"
//      principle (CLAUDE.md) means a star tap should never itself wait on
//      Garmin anyway -- exactly like `CustomFoodDraft`/`MealPreset` before
//      it, a purely local JSON-file store is both the honest fallback AND
//      the architecturally correct choice for an instant toggle.
//
// Stores a full `Food` SNAPSHOT (not just an id) -- deliberately, so a
// favorite is self-contained and displays/logs correctly even if
// `FoodCacheStore` (FoodCache.swift) never held that food or has since
// evicted it (its own header already documents itself as a best-effort
// display cache, not a durable source of truth). The tradeoff: if the
// underlying Garmin food's macros change server-side, a favorited snapshot
// goes stale until un-favorited and re-favorited -- accepted for the same
// reason `CustomFoodDraft` accepts a similar staleness risk elsewhere in
// this package (there is no live "refresh a favorite" concept, matching
// this project's existing "convenience, not a synced state" stance for
// local-only concepts).
//
// Actor-isolated, JSON-file-backed -- same shape as `CustomFoodStore`
// (CustomFood.swift), which this file deliberately mirrors closely.

import Foundation

/// One favorited food, keyed by the underlying `Food.id` -- a food can only
/// be favorited once; toggling again un-favorites it. There is no separate
/// "favorite entry id" to manage, unlike `CustomFoodDraft`'s own `UUID`,
/// because a favorite has no identity independent of the food it favorites.
public struct FavoriteFood: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { food.id }
    public let food: Food
    /// When the user favorited this food -- drives `all()`'s newest-first
    /// ordering, matching `CustomFoodStore.all()`'s own convention.
    public let favoritedAt: Date

    public init(food: Food, favoritedAt: Date = Date()) {
        self.food = food
        self.favoritedAt = favoritedAt
    }
}

/// JSON-file-backed, actor-isolated -- same pattern as `CustomFoodStore`.
public actor FavoriteFoodStore {
    private let fileURL: URL
    private var favoritesById: [String: FavoriteFood] = [:]
    private var loaded = false

    public init(fileURL: URL = FavoriteFoodStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("favorite-foods.json")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([FavoriteFood].self, from: data)) ?? []
        favoritesById = Dictionary(uniqueKeysWithValues: decoded.map { ($0.id, $0) })
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Array(favoritesById.values))
        try data.write(to: fileURL, options: .atomic)
    }

    /// Newest-favorited first.
    public func all() -> [FavoriteFood] {
        loadIfNeeded()
        return Array(favoritesById.values).sorted { $0.favoritedAt > $1.favoritedAt }
    }

    public func isFavorite(foodId: String) -> Bool {
        loadIfNeeded()
        return favoritesById[foodId] != nil
    }

    /// Flips the given food's favorite state and returns the NEW state, so
    /// a caller (the star button's action) can update without a second
    /// read. Adding an already-favorited food is a no-op returning `true`
    /// only via the toggle-off branch below -- callers that want "set to
    /// favorited" unconditionally should check `isFavorite(foodId:)` first,
    /// same as `CustomFoodStore.upsert` callers check for an existing draft
    /// when that distinction matters.
    @discardableResult
    public func toggle(_ food: Food) throws -> Bool {
        loadIfNeeded()
        if favoritesById[food.id] != nil {
            favoritesById.removeValue(forKey: food.id)
            try persist()
            return false
        } else {
            favoritesById[food.id] = FavoriteFood(food: food)
            try persist()
            return true
        }
    }

    public func remove(foodId: String) throws {
        loadIfNeeded()
        favoritesById.removeValue(forKey: foodId)
        try persist()
    }
}

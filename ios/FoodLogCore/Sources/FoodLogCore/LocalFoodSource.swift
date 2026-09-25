// LocalFoodSource.swift
//
// The user's own foods as a search source (rebuild-food-search task 3.1).
// Before this change typing anything HID custom foods, favorites and
// recents (FoodCatalogView only showed them for an empty query), so the
// food you eat every day was the one thing search couldn't find, and none
// of it worked offline.
//
// The library is: every custom food (authoritative drafts), every
// favorite, and every food that appears in usage history and is still in
// `FoodCacheStore` (which remembers display data for foods once seen).
// Deliberately NOT every food ever seen in a search result: the cache holds
// hundreds of unrelated remote hits, which would crowd the local tier; a
// recently seen remote food comes back through the engine's term cache
// instead. A `.custom` food whose draft was deleted is skipped (its id
// means nothing to Garmin), and Open Food Facts foods are never local
// (they aren't loggable without the Garmin match step).
//
// add-standalone-mode D5: standalone mode's engine
// (`FoodSearchEngine.standard(garmin: nil)`) builds this with
// `includesOpenFoodFactsFoods: true` -- there an OFF / offline-index product
// is logged as itself, so one she has logged or starred is "hers" like any
// other. Garmin mode keeps the default (`false`), unchanged.
//
// It returns the whole library unscored -- a few hundred foods at most --
// and lets `SearchRanker` filter, which is instant and needs no network.
// Also derives the personal-boost context from the same stores.
//
// Depends on CustomFoodStore, FavoriteFoodStore, FoodCacheStore and
// UsageHistoryStore; used by FoodSearchEngine. Tested by LocalFoodSourceTests.

import Foundation

public struct LocalFoodSource: FoodSearchSource {
    private let customFoods: CustomFoodStore
    private let favorites: FavoriteFoodStore
    private let foodCache: FoodCacheStore
    private let usageHistory: UsageHistoryStore
    private let includesOpenFoodFactsFoods: Bool

    public init(
        customFoods: CustomFoodStore,
        favorites: FavoriteFoodStore,
        foodCache: FoodCacheStore,
        usageHistory: UsageHistoryStore,
        includesOpenFoodFactsFoods: Bool = false
    ) {
        self.customFoods = customFoods
        self.favorites = favorites
        self.foodCache = foodCache
        self.usageHistory = usageHistory
        self.includesOpenFoodFactsFoods = includesOpenFoodFactsFoods
    }

    public var origin: SearchOrigin { .local }
    public var isRemote: Bool { false }

    public func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage {
        guard page == 0 else { return SourcePage() }
        let drafts = await customFoods.all()
        let favoriteFoods = await favorites.all()
        let cached = await foodCache.all()
        let events = await usageHistory.all()
        return SourcePage(candidates: Self.candidates(
            customFoods: drafts,
            favorites: favoriteFoods,
            cachedFoods: cached,
            usage: events,
            includesOpenFoodFactsFoods: includesOpenFoodFactsFoods
        ))
    }

    /// Usage-frequency and favorite signals for `SearchRanker`.
    public func personalContext(now: Date = Date()) async -> SearchPersonalContext {
        let events = await usageHistory.all()
        let favoriteFoods = await favorites.all()
        return SearchPersonalContext.build(events: events, favoriteFoodIds: Set(favoriteFoods.map(\.id)), now: now)
    }

    /// The local library, pure. Custom foods first, then favorites, then
    /// logged foods most-recent first; each food once. Open Food Facts
    /// products only when `includesOpenFoodFactsFoods` (standalone mode).
    public static func candidates(
        customFoods: [CustomFoodDraft],
        favorites: [FavoriteFood],
        cachedFoods: [String: Food],
        usage: [UsageEvent],
        includesOpenFoodFactsFoods: Bool = false
    ) -> [SearchCandidate] {
        let draftsById = Dictionary(customFoods.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var library: [SearchCandidate] = []

        func add(_ food: Food) {
            guard !seen.contains(food.id) else { return }
            switch food.source {
            case .custom:
                guard let draft = draftsById[food.id] else { return }
                seen.insert(food.id)
                library.append(SearchCandidate(food: draft.asFood(), origin: .local, customDraft: draft))
            case .openFoodFacts:
                guard includesOpenFoodFactsFoods else { return }
                seen.insert(food.id)
                library.append(SearchCandidate(food: food, origin: .local))
            case .garmin, .fatSecret:
                seen.insert(food.id)
                library.append(SearchCandidate(food: food, origin: .local))
            }
        }

        for draft in customFoods { add(draft.asFood()) }
        for favorite in favorites { add(favorite.food) }
        var loggedIds = Set<String>()
        for event in usage.reversed() where loggedIds.insert(event.foodId).inserted {
            if let food = cachedFoods[event.foodId] { add(food) }
        }
        return library
    }
}

// FoodCatalogSearch.swift
//
// `FoodCatalog.search(term:)` (task 12.1): calls `GarminClient.searchFood`
// through the `FoodSearching` seam (so this is unit-testable with a fake,
// no network access), adapts each result into this package's `Food` domain
// model, keeps a short in-memory cache keyed by search term (task 12.1),
// and durably remembers every food it has ever seen via `FoodCacheStore` so
// the quick-pick shelf can display them later without another network call.

import Foundation
import GarminKit

/// The subset of `GarminClient` this type needs -- exists so tests never
/// touch the network, same rationale as GarminKit's own `FoodLogDelivering`
/// / `FoodLogReconciling` seams.
public protocol FoodSearching: Sendable {
    func searchFood(term: String) async throws -> FoodSearchResponse
}

extension GarminClient: FoodSearching {}

public actor FoodCatalogSearch {
    private let searcher: any FoodSearching
    private let foodCache: FoodCacheStore?
    /// Session-scoped only -- deliberately not persisted to disk. Garmin's
    /// own data can change between launches, and a stale disk cache
    /// surviving a relaunch isn't worth the risk for a search-as-you-type
    /// UI; `FoodCacheStore` (durable) is the one that back-fills quick-pick
    /// display data across launches instead.
    private var termCache: [String: [Food]] = [:]
    private let maxCacheEntries = 50

    public init(searcher: any FoodSearching, foodCache: FoodCacheStore? = nil) {
        self.searcher = searcher
        self.foodCache = foodCache
    }

    /// Confirmed live 2026-09-14 against `GET
    /// /nutrition-service/food/search?searchExpression=<term>` (via
    /// `GarminClient.searchFood`), including Czech terms.
    public func search(term: String) async throws -> [Food] {
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return [] }
        if let cached = termCache[key] { return cached }

        let response = try await searcher.searchFood(term: key)
        let foods = response.results.compactMap(Food.init(searchResult:))

        if termCache.count >= maxCacheEntries { termCache.removeAll() }
        termCache[key] = foods
        await foodCache?.upsert(foods)
        return foods
    }

    public func clearSessionCache() {
        termCache.removeAll()
    }
}

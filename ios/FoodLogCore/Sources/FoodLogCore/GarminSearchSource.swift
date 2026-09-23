// GarminSearchSource.swift
//
// Garmin's food database as a `FoodSearchSource` (rebuild-food-search task
// 3.2), replacing `FoodCatalogSearch`, which used only Garmin's first page
// in Garmin's raw order and searched the default (US) region.
//
// Route: GET /nutrition-service/food/search, probed read-only 2026-09-23
// (docs/garmin-routes.json `foodSearch`):
//   - `start` + `limit` page the results (Spring's 400 names them:
//     "FoodSearchParams(searchExpression, regionCode=US, languageCode=en,
//     start, limit)"); `limit` max 50, `start` must be divisible by
//     `limit`; `moreDataAvailable` flips true when another page exists.
//     `pageNumber`/`pageSize` are silently ignored.
//   - `regionCode=CZ` is accepted and switches FatSecret to its Czech
//     catalogue ("tvaroh": 5 unrelated US hits -> 20+ real Czech tvarohy
//     with more pages; "kure" -> Kuřecí šunka etc.). Results carry
//     regionCode "CZ", the tuple later sent with the log write -- the
//     owner's own Garmin diary already holds FATSECRET foods with
//     regionCode CZ, so the tuple is a real one. `languageCode=cs` is
//     rejected (400 "Language code is not supported").
//   - The search is diacritic-sensitive ("rohlík" 0 hits vs "rohlik" 13;
//     "bílý jogurt" and "bily jogurt" return different Czech products), so
//     both spellings from `SearchQuery.remoteVariants` are sent in parallel
//     and merged.
// Fallback when this route breaks: the engine shows local + OFF results
// with a "Garmin unavailable" footnote; a signed-out session stays loud.
//
// Depends on GarminKit's `GarminClient` through `GarminFoodSearching` (so
// tests use a fake). Tested by GarminSearchSourceTests.

import Foundation
import GarminKit

/// The slice of `GarminClient` this source needs.
public protocol GarminFoodSearching: Sendable {
    func searchFood(term: String, start: Int, limit: Int, regionCode: String?) async throws -> FoodSearchResponse
}

extension GarminClient: GarminFoodSearching {}

public struct GarminSearchSource: FoodSearchSource {
    /// Garmin's maximum page size for FatSecret search (probed 2026-09-23).
    public static let pageSize = 50
    /// Czech FatSecret catalogue -- see this file's header.
    public static let defaultRegionCode = "CZ"

    private let searcher: any GarminFoodSearching
    private let regionCode: String?

    public init(searcher: any GarminFoodSearching, regionCode: String? = GarminSearchSource.defaultRegionCode) {
        self.searcher = searcher
        self.regionCode = regionCode
    }

    public var origin: SearchOrigin { .garmin }
    public var isRemote: Bool { true }

    public func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage {
        let variants = query.remoteVariants
        guard !variants.isEmpty, page >= 0 else { return SourcePage() }
        let searcher = self.searcher
        let regionCode = self.regionCode
        let start = page * Self.pageSize
        let limit = Self.pageSize

        let outcomes = await withTaskGroup(
            of: (Int, Result<FoodSearchResponse, Error>).self,
            returning: [(Int, Result<FoodSearchResponse, Error>)].self
        ) { group in
            for (index, term) in variants.enumerated() {
                group.addTask {
                    do {
                        let response = try await searcher.searchFood(term: term, start: start, limit: limit, regionCode: regionCode)
                        return (index, .success(response))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<FoodSearchResponse, Error>)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }
        }

        let responses = try VariantResults.successes(outcomes.map { $0.1 })
        let foodLists = responses.map { $0.results.compactMap(Food.init(searchResult:)) }
        let foods = VariantResults.interleave(foodLists) { $0.id }
        return SourcePage(
            candidates: foods.map { SearchCandidate(food: $0, origin: .garmin) },
            hasMore: responses.contains { $0.moreDataAvailable == true }
        )
    }
}

/// Merging the answers to several spellings of one query.
enum VariantResults {
    /// The successful lists; throws the first error only when EVERY
    /// variant failed (one spelling failing shouldn't hide the other's hits).
    static func successes<Element>(_ outcomes: [Result<Element, Error>]) throws -> [Element] {
        var values: [Element] = []
        var firstError: Error?
        for outcome in outcomes {
            switch outcome {
            case .success(let value): values.append(value)
            case .failure(let error): if firstError == nil { firstError = error }
            }
        }
        if values.isEmpty, let firstError { throw firstError }
        return values
    }

    /// Round-robin merge that keeps each list's own order and drops repeats,
    /// so the top hit of every spelling stays near the top.
    static func interleave<Element>(_ lists: [[Element]], id: (Element) -> String) -> [Element] {
        var seen = Set<String>()
        var merged: [Element] = []
        let longest = lists.map(\.count).max() ?? 0
        for position in 0..<longest {
            for list in lists where position < list.count {
                let element = list[position]
                if seen.insert(id(element)).inserted { merged.append(element) }
            }
        }
        return merged
    }
}

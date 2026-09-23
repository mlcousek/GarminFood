// OpenFoodFactsSource.swift
//
// Open Food Facts as a `FoodSearchSource` (rebuild-food-search task 3.3).
// Everything OFF-specific that isn't wire format lives here:
//   - both spellings from `SearchQuery.remoteVariants` are searched in
//     parallel (OFF is diacritic-sensitive: "mléko" 45 Czech hits vs
//     "mleko" 9, probed 2026-09-23) and merged round-robin;
//   - the catalog's "Czech only" toggle is honoured, and when the
//     Czech-tagged search finds nothing it retries worldwide once, with a
//     note -- OFF's country tagging is too thin to treat "no Czech-tagged
//     hit" as "not in the database" (behaviour kept from 2026-09-21).
// No "Show more": 50 hits per spelling already exceeds what OFF's Czech
// subset returns for almost every food word sampled (design.md).
//
// Depends on `OpenFoodFactsSearching` (the client, faked in tests); used by
// FoodSearchEngine. Tested by OpenFoodFactsSourceTests.

import Foundation

public struct OpenFoodFactsSource: FoodSearchSource {
    public static let worldwideFallbackNote = "No Czech-tagged matches in Open Food Facts, so these are worldwide results."

    private let client: any OpenFoodFactsSearching

    public init(client: any OpenFoodFactsSearching = OpenFoodFactsClient()) {
        self.client = client
    }

    public var origin: SearchOrigin { .openFoodFacts }
    public var isRemote: Bool { true }

    public func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage {
        let variants = query.remoteVariants
        guard page == 0, !variants.isEmpty else { return SourcePage() }

        let scoped = try await fetch(variants, czechOnly: options.czechOnly)
        if options.czechOnly, scoped.isEmpty {
            try Task.checkCancellation()
            let worldwide = try await fetch(variants, czechOnly: false)
            if !worldwide.isEmpty {
                return SourcePage(candidates: worldwide, note: Self.worldwideFallbackNote)
            }
        }
        return SourcePage(candidates: scoped)
    }

    private func fetch(_ variants: [String], czechOnly: Bool) async throws -> [SearchCandidate] {
        let client = self.client
        let outcomes = await withTaskGroup(
            of: (Int, Result<[OFFSearchHit], Error>).self,
            returning: [(Int, Result<[OFFSearchHit], Error>)].self
        ) { group in
            for (index, term) in variants.enumerated() {
                group.addTask {
                    do {
                        let hits = try await client.search(term: term, czechOnly: czechOnly)
                        return (index, .success(hits))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var collected: [(Int, Result<[OFFSearchHit], Error>)] = []
            for await outcome in group { collected.append(outcome) }
            return collected.sorted { $0.0 < $1.0 }
        }
        let lists = try VariantResults.successes(outcomes.map { $0.1 })
        return VariantResults.interleave(lists) { $0.food.id }.map { hit in
            SearchCandidate(food: hit.food, origin: .openFoodFacts, alternateNames: hit.alternateNames)
        }
    }
}

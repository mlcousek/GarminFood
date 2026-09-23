// SearchRankerTests.swift
//
// rebuild-food-search tasks 2.4-2.5 (design.md D3-D5): each match tier,
// the garbage threshold, bonuses, personal boost, priors, cross-source
// dedup, the "rows don't jump" merge, and the voice-command confidence
// rule. The golden suite (SearchRelevanceTests) covers the combined
// behaviour on realistic data; these pin each rule on its own.

import XCTest
@testable import FoodLogCore

private func food(
    _ id: String,
    _ name: String,
    brand: String? = nil,
    source: FoodSource = .fatSecret,
    kcal: Double? = 100,
    garminIsRecent: Bool? = nil
) -> Food {
    Food(
        id: id,
        name: name,
        brandName: brand,
        source: source,
        servings: [Serving(id: "s", unit: "g", numberOfUnits: 100, calories: kcal)],
        garminIsRecent: garminIsRecent
    )
}

private func candidate(_ food: Food, _ origin: SearchOrigin = .garmin, rank: Int = 0, of count: Int = 0, aliases: [String] = []) -> SearchCandidate {
    SearchCandidate(food: food, origin: origin, alternateNames: aliases, sourceRank: rank, sourceCount: count)
}

private func tier(_ query: String, _ name: String) -> Double {
    SearchRanker.textMatch(SearchQuery(query), name: name).text
}

final class SearchRankerTests: XCTestCase {
    private let weights = SearchWeights.standard

    // MARK: - Tiers

    func testExactMatchIgnoresCaseAndDiacritics() {
        XCTAssertEqual(tier("rohlik", "ROHLÍK"), weights.exact)
    }

    func testStemMatchCoversCzechInflection() {
        XCTAssertEqual(tier("rohliky", "Rohlík"), weights.stem)
    }

    func testPrefixMatchesOnlyTheWordBeingTyped() {
        XCTAssertEqual(tier("rohl", "Rohlík"), weights.prefix)
        // "tv" is not the last word here, so it isn't a prefix match.
        XCTAssertEqual(SearchRanker.textMatch(SearchQuery("tv mleko"), name: "Tvaroh").text, 0)
    }

    func testSingleLetterQueryStillMatchesByPrefix() {
        XCTAssertEqual(tier("r", "Rohlík"), weights.prefix)
    }

    func testStemPrefixLinksDerivedWords() {
        // prsa (breast) -> prsní (breast, adjective)
        XCTAssertEqual(tier("prsa", "Prsní"), weights.stemPrefix)
    }

    func testFuzzyToleratesOneTypoWithTheSameFirstLetter() {
        XCTAssertEqual(tier("bnan", "Banán"), weights.fuzzy)
        XCTAssertEqual(tier("tvaroch", "Tvaroh"), weights.fuzzy)
    }

    func testFuzzyAllowsTwoEditsFromEightLetters() {
        XCTAssertEqual(tier("celozrnay", "celozrnny"), weights.fuzzy)
        XCTAssertEqual(tier("clozrnay", "celozrnny"), weights.fuzzy)
    }

    func testShortWordsGetNoTypoTolerance() {
        XCTAssertEqual(tier("syx", "sýr"), 0)
    }

    func testFirstLetterTypoOnlyForLongerWordsAndAtALowerWeight() {
        // Garmin answers "jogurt" with its English "Yogurt" (probed 2026-09-23).
        XCTAssertEqual(tier("jogurt", "Yogurt"), weights.fuzzyFirstLetter)
        XCTAssertEqual(tier("kure", "pure"), 0)
    }

    func testWordOrderDoesNotMatter() {
        XCTAssertEqual(tier("tvaroh mekky", "Měkký tvaroh"), 1)
    }

    func testBrandMatchesCountHalf() {
        let match = SearchRanker.textMatch(SearchQuery("madeta"), name: "Tvaroh", brand: "Madeta")
        XCTAssertEqual(match.text, weights.exact * weights.brandFactor)
        XCTAssertTrue(match.allWordsMatched)
        XCTAssertFalse(match.startMatched)
    }

    func testQuantityTokensWeighLittle() {
        let match = SearchRanker.textMatch(SearchQuery("eidam 45"), name: "Eidam 30%")
        // eidam exact (1.0 x 1) + "45" unmatched (0 x 0.2), over a total weight of 1.2
        XCTAssertEqual(match.text, 1 / 1.2, accuracy: 1e-9)
        XCTAssertTrue(match.allWordsMatched, "only WORDS need to match for coverage")
    }

    // MARK: - Threshold, bonuses, length

    func testUnrelatedCandidatesAreDropped() {
        // Garmin's own fuzzy search returned this for "rohlik" (probed 2026-09-23).
        XCTAssertNil(SearchRanker.evaluate(SearchQuery("rohlik"), candidate(food("1", "Prepared Squid", brand: "Rolin"))))
        XCTAssertNil(SearchRanker.evaluate(SearchQuery("tvaroh"), candidate(food("2", "Cheese", brand: "Dvaro"))))
    }

    func testAHalfMatchOfATwoWordQueryIsKept() {
        XCTAssertNotNil(SearchRanker.evaluate(SearchQuery("tvaroh mekky"), candidate(food("1", "Tvaroh"))))
    }

    func testCoverageAndStartBonusesAndShorterNamesWin() {
        let query = SearchQuery("tvaroh")
        let short = SearchRanker.evaluate(query, candidate(food("1", "Tvaroh")))
        let long = SearchRanker.evaluate(query, candidate(food("2", "Tvaroh jemný polotučný")))
        let notFirst = SearchRanker.evaluate(query, candidate(food("3", "Domácí tvaroh")))
        XCTAssertEqual(short?.score ?? 0, 1.25 + weights.loggableSourcePrior, accuracy: 1e-9)
        XCTAssertGreaterThan(short?.score ?? 0, long?.score ?? 0)
        XCTAssertGreaterThan(short?.score ?? 0, notFirst?.score ?? 0)
    }

    func testAliasesMatchAtAReducedWeight() {
        let query = SearchQuery("kefir")
        let viaAlias = SearchRanker.evaluate(query, candidate(food("1", "Mléčný nápoj"), .openFoodFacts, aliases: ["Kefir"]))
        let direct = SearchRanker.evaluate(query, candidate(food("2", "Kefir"), .openFoodFacts))
        XCTAssertNotNil(viaAlias)
        XCTAssertEqual(viaAlias?.score ?? 0, (direct?.score ?? 0) * weights.aliasFactor, accuracy: 1e-9)
    }

    // MARK: - Personal boost and priors

    func testUsageFavoriteCustomAndGarminFlagsBoost() {
        let query = SearchQuery("jogurt")
        let plain = SearchRanker.evaluate(query, candidate(food("plain", "Jogurt")))?.score ?? 0
        let logged = SearchRanker.evaluate(query, candidate(food("logged", "Jogurt")), personal: SearchPersonalContext(decayedUseCounts: ["logged": 3]))?.score ?? 0
        let favorite = SearchRanker.evaluate(query, candidate(food("fav", "Jogurt")), personal: SearchPersonalContext(favoriteFoodIds: ["fav"]))?.score ?? 0
        let custom = SearchRanker.evaluate(query, candidate(food("c", "Jogurt", source: .custom), .local))?.score ?? 0
        let recent = SearchRanker.evaluate(query, candidate(food("r", "Jogurt", garminIsRecent: true)))?.score ?? 0

        XCTAssertEqual(logged - plain, weights.usageBoost * log1p(3), accuracy: 1e-9)
        XCTAssertEqual(favorite - plain, weights.favoriteBoost, accuracy: 1e-9)
        XCTAssertEqual(custom - plain, weights.customBoost, accuracy: 1e-9)
        XCTAssertEqual(recent - plain, weights.garminFlagBoost, accuracy: 1e-9)
    }

    func testPersonalContextDecaysOldLogs() {
        let now = Date()
        let events = [
            UsageEvent(foodId: "a", servingId: "s", numberOfUnits: 1, timestamp: now),
            UsageEvent(foodId: "b", servingId: "s", numberOfUnits: 1, timestamp: now.addingTimeInterval(-30 * 86_400))
        ]
        let context = SearchPersonalContext.build(events: events, favoriteFoodIds: ["b"], now: now)
        XCTAssertEqual(context.decayedUseCounts["a"] ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(context.decayedUseCounts["b"] ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(context.favoriteFoodIds, ["b"])
    }

    func testLoggableSourcesAndSourceOrderAreSmallTieBreakers() {
        let query = SearchQuery("tvaroh")
        let garmin = SearchRanker.evaluate(query, candidate(food("g", "Tvaroh"), .garmin))?.score ?? 0
        let off = SearchRanker.evaluate(query, candidate(food("o", "Tvaroh"), .openFoodFacts))?.score ?? 0
        XCTAssertEqual(garmin - off, weights.loggableSourcePrior, accuracy: 1e-9)

        let first = SearchRanker.evaluate(query, candidate(food("1", "Tvaroh"), rank: 0, of: 10))?.score ?? 0
        let last = SearchRanker.evaluate(query, candidate(food("2", "Tvaroh"), rank: 9, of: 10))?.score ?? 0
        XCTAssertEqual(first - last, weights.remoteRankPrior * 0.9, accuracy: 1e-9)
    }

    func testBrandOnlyMatchesRankBelowNameMatches() {
        // The owner's 2026-09-22 complaint: OFF let the grocery brand "Rohlík"
        // swamp real bread rolls.
        let results = SearchRanker.rank(SearchQuery("rohlik"), candidates: [
            candidate(food("ham", "Turkey Ham", brand: "Rohlik"), .openFoodFacts),
            candidate(food("roll", "Rohlík tukový", brand: "Penam"), .openFoodFacts)
        ])
        XCTAssertEqual(results.map(\.food.id), ["roll", "ham"])
    }

    func testRankIsDeterministicOnTies() {
        let candidates = [
            candidate(food("b", "Tvaroh", brand: "Pilos")),
            candidate(food("a", "Tvaroh", brand: "Madeta"))
        ]
        let once = SearchRanker.rank(SearchQuery("tvaroh"), candidates: candidates).map(\.food.id)
        let again = SearchRanker.rank(SearchQuery("tvaroh"), candidates: candidates.reversed()).map(\.food.id)
        XCTAssertEqual(once, ["a", "b"])
        XCTAssertEqual(once, again)
    }

    func testEmptyQueryRanksNothing() {
        XCTAssertTrue(SearchRanker.rank(SearchQuery("  "), candidates: [candidate(food("1", "Tvaroh"))]).isEmpty)
    }
}

final class SearchDedupTests: XCTestCase {
    private func result(_ food: Food, _ origin: SearchOrigin, score: Double = 1) -> SearchResult {
        SearchResult(food: food, origin: origin, score: score, textScore: 1, coversQuery: true)
    }

    /// food-catalog spec "Same product from two sources".
    func testSameProductFromGarminAndOpenFoodFactsAppearsOnceAsTheGarminItem() {
        let merged = SearchDedup.merge([
            result(food("8594001234567", "Madeta Jihočeský tvaroh 250 g", brand: "Madeta", source: .openFoodFacts, kcal: 118), .openFoodFacts, score: 1.3),
            result(food("123", "Jihočeský Tvaroh", brand: "Madeta", kcal: 116), .garmin, score: 1.1)
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.food.id, "123")
        XCTAssertEqual(merged.first?.origin, .garmin)
        XCTAssertEqual(merged.first?.alsoIn, [.openFoodFacts])
        XCTAssertEqual(merged.first?.score ?? 0, 1.3, accuracy: 1e-9, "keeps the higher score")
    }

    func testCaloriesMoreThanFivePercentApartStayTwoProducts() {
        let merged = SearchDedup.merge([
            result(food("o", "Tvaroh", brand: "Madeta", source: .openFoodFacts, kcal: 130), .openFoodFacts),
            result(food("g", "Tvaroh", brand: "Madeta", kcal: 116), .garmin)
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testUnknownCaloriesNeverMerge() {
        let merged = SearchDedup.merge([
            result(food("o", "Tvaroh", brand: "Madeta", source: .openFoodFacts, kcal: nil), .openFoodFacts),
            result(food("g", "Tvaroh", brand: "Madeta", kcal: 116), .garmin)
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testTheSameGarminFoodFromTheLocalLibraryAndGarminMergesToTheLocalCopy() {
        let merged = SearchDedup.merge([
            result(food("42", "Rohlík", kcal: nil), .garmin, score: 1.2),
            result(food("42", "Rohlík", kcal: nil), .local, score: 1.3)
        ])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.origin, .local)
        XCTAssertEqual(merged.first?.alsoIn, [.garmin])
    }

    func testTwoDifferentGarminFoodsWithTheSameNameAreNotMerged() {
        let merged = SearchDedup.merge([
            result(food("1", "Tvaroh", brand: "Madeta", kcal: 63), .garmin),
            result(food("2", "Tvaroh", brand: "Madeta", kcal: 63), .garmin)
        ])
        XCTAssertEqual(merged.count, 2)
    }

    func testNameKeyIgnoresWordOrderPackSizeAndBrandWords() {
        XCTAssertEqual(
            SearchDedup.nameKey(for: food("a", "Madeta Jihočeský tvaroh 250 g", brand: "Madeta")),
            SearchDedup.nameKey(for: food("b", "Tvaroh jihočeský", brand: "Madeta, Jihočeské mlékárny"))
        )
    }

    func testKcalPer100ReadsGarminStyleServings() {
        let perHundred = Food(id: "1", name: "x", source: .garmin, servings: [Serving(id: "a", unit: "100g", numberOfUnits: 1, calories: 250)])
        let perGram = Food(id: "2", name: "x", source: .garmin, servings: [Serving(id: "b", unit: "g", numberOfUnits: 50, calories: 125)])
        let perPiece = Food(id: "3", name: "x", source: .garmin, servings: [Serving(id: "c", unit: "piece", numberOfUnits: 1, calories: 90)])
        XCTAssertEqual(SearchDedup.kcalPer100(perHundred) ?? 0, 250, accuracy: 1e-9)
        XCTAssertEqual(SearchDedup.kcalPer100(perGram) ?? 0, 250, accuracy: 1e-9)
        XCTAssertNil(SearchDedup.kcalPer100(perPiece))
    }
}

final class SearchResultPolicyTests: XCTestCase {
    private func row(_ id: String, _ score: Double, text: Double = 1, covers: Bool = true) -> SearchResult {
        SearchResult(food: food(id, id), origin: .garmin, score: score, textScore: text, coversQuery: covers)
    }

    func testRowsAlreadyShownKeepTheirOrderAndNewRowsSlotInByScore() {
        let previous = [row("a", 1.0), row("b", 0.9)]
        // "b" now outscores "a", "c" is new and best, "d" new and worst.
        let incoming = [row("c", 1.5), row("b", 1.2), row("a", 1.0), row("d", 0.2)]

        let merged = SearchResultOrdering.stableMerge(previous: previous, incoming: incoming)

        XCTAssertEqual(merged.map(\.food.id), ["c", "a", "b", "d"])
        XCTAssertEqual(merged.first { $0.food.id == "b" }?.score, 1.2, "kept rows carry fresh content")
    }

    func testRowsGoneFromTheSnapshotLeave() {
        let merged = SearchResultOrdering.stableMerge(previous: [row("a", 1), row("b", 1)], incoming: [row("b", 1)])
        XCTAssertEqual(merged.map(\.food.id), ["b"])
    }

    func testConfidentOnlyWithAStrongMatchAndAClearLead() {
        XCTAssertEqual(SearchConfidence.decide([row("a", 1.3), row("b", 1.0)]), .confident(row("a", 1.3)))
        XCTAssertEqual(
            SearchConfidence.decide([row("a", 1.3), row("b", 1.29), row("c", 1.2), row("d", 1.1)]),
            .ambiguous([row("a", 1.3), row("b", 1.29), row("c", 1.2)])
        )
        XCTAssertEqual(SearchConfidence.decide([row("a", 0.9, text: 0.6)]), .ambiguous([row("a", 0.9, text: 0.6)]))
        XCTAssertEqual(SearchConfidence.decide([row("a", 1.2, covers: false)]), .ambiguous([row("a", 1.2, covers: false)]))
        XCTAssertEqual(SearchConfidence.decide([]), .noMatch)
    }
}

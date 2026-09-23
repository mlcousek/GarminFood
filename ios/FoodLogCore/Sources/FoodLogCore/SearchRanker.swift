// SearchRanker.swift
//
// The single relevance function for every food search source
// (rebuild-food-search design.md D3). The owner's words: "one thing that is
// really really important for me is to find in the databases". Before this,
// Garmin results came back in Garmin's raw order and OFF results got a
// two-bucket "name contains the whole term" sort -- no word order, no
// inflection, no typos, no personal signal.
//
// How a candidate is scored:
//   1. Every query token finds its best match among the name's tokens, by
//      tier: exact > same stem > prefix (the word being typed) > stem
//      prefix (kuře -> kuřecí, prsa -> prsní) > fuzzy (bounded
//      Damerau-Levenshtein). Brand tokens match on the same tiers at half
//      weight, so "madeta" finds Madeta products but a real name match
//      still wins. Quantity tokens ("250g") weigh 0.2.
//   2. text = weighted mean of those best matches. Below
//      `textThreshold` the candidate is dropped -- that is what keeps
//      Garmin's own fuzzy garbage ("Prepared Squid [Rolin]" for "rohlik",
//      observed live 2026-09-23) off the screen.
//   3. relevance = (text + coverage bonus + start bonus) x length norm.
//   4. score = relevance + personal boost x text + source prior + remote
//      rank prior. The personal boost is scaled by `text` so a food you eat
//      daily can win among comparable matches, but can't drag a half-match
//      above a perfect one.
// Every weight lives in `SearchWeights`; SearchRelevanceTests (the golden
// suite) is the acceptance test for changing any of them.
//
// Pure; used by FoodSearchEngine. Tested by SearchRankerTests and
// SearchRelevanceTests.

import Foundation

/// Every tunable ranking constant, in one place (task 2.4).
public struct SearchWeights: Sendable, Equatable {
    // Token match tiers.
    public var exact = 1.0
    public var stem = 0.9
    public var prefix = 0.8
    public var stemPrefix = 0.7
    public var fuzzy = 0.6
    /// A one-edit typo in the FIRST letter ("jogurt" vs Garmin's
    /// "Yogurt"), only for query words of 5+ letters.
    public var fuzzyFirstLetter = 0.5
    /// Longest a name word's stem may be beyond the query's stem for a stem
    /// prefix match ("prs" -> "prsn" yes, "syr" -> "syrovatk" no).
    public var stemPrefixMaxExtraLength = 3

    // Token weighting.
    public var brandFactor = 0.5
    public var aliasFactor = 0.9
    public var quantityTokenWeight = 0.2

    // Relevance.
    public var coverageBonus = 0.15
    public var startBonus = 0.10
    public var lengthPenaltyPerExtraWord = 0.05
    public var textThreshold = 0.45

    // Personal boost.
    public var usageBoost = 0.25
    public var favoriteBoost = 0.15
    public var customBoost = 0.10
    public var garminFlagBoost = 0.05

    // Priors (tie-breakers, never dominant).
    public var loggableSourcePrior = 0.05
    public var remoteRankPrior = 0.05

    public init() {}

    public static let standard = SearchWeights()
}

/// How well one name matched one query, before bonuses.
public struct TextMatch: Sendable, Equatable {
    /// Weighted mean of each query token's best tier weight, 0...1.
    public let text: Double
    /// Every query word matched at some tier (name or brand).
    public let allWordsMatched: Bool
    /// The query's first word matched the name's first word.
    public let startMatched: Bool
    public let nameWordCount: Int
    public let queryWordCount: Int
}

public enum SearchRanker {
    /// Scores, filters, dedups and sorts `candidates` for `query`.
    public static func rank(
        _ query: SearchQuery,
        candidates: [SearchCandidate],
        personal: SearchPersonalContext = .empty,
        weights: SearchWeights = .standard
    ) -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let scored = candidates.compactMap { evaluate(query, $0, personal: personal, weights: weights) }
        return SearchDedup.merge(scored).sorted(by: isRankedBefore)
    }

    /// One candidate's result row, or `nil` when it falls under the text threshold.
    public static func evaluate(
        _ query: SearchQuery,
        _ candidate: SearchCandidate,
        personal: SearchPersonalContext = .empty,
        weights: SearchWeights = .standard
    ) -> SearchResult? {
        let food = candidate.food
        let brandTokens = SearchText.tokenize(food.brandName ?? "").filter { !$0.isQuantity }

        var bestMatch: TextMatch?
        var bestRelevance = 0.0
        let primary = textMatch(queryTokens: query.tokens, nameTokens: SearchText.tokenize(food.name), brandTokens: brandTokens, weights: weights)
        if primary.text >= weights.textThreshold {
            bestMatch = primary
            bestRelevance = relevance(primary, weights: weights)
        }
        for alias in candidate.alternateNames {
            let match = textMatch(queryTokens: query.tokens, nameTokens: SearchText.tokenize(alias), brandTokens: brandTokens, weights: weights)
            guard match.text >= weights.textThreshold else { continue }
            let aliasRelevance = relevance(match, weights: weights) * weights.aliasFactor
            if bestMatch == nil || aliasRelevance > bestRelevance {
                bestMatch = match
                bestRelevance = aliasRelevance
            }
        }
        guard let match = bestMatch else { return nil }

        let score = bestRelevance
            + personalBoost(for: food, personal: personal, weights: weights) * match.text
            + (candidate.origin.isDirectlyLoggable ? weights.loggableSourcePrior : 0)
            + rankPrior(candidate, weights: weights)

        return SearchResult(
            food: food,
            origin: candidate.origin,
            score: score,
            textScore: match.text,
            coversQuery: match.allWordsMatched,
            customDraft: candidate.customDraft
        )
    }

    /// Convenience for tests and one-off checks.
    public static func textMatch(_ query: SearchQuery, name: String, brand: String? = nil, weights: SearchWeights = .standard) -> TextMatch {
        textMatch(
            queryTokens: query.tokens,
            nameTokens: SearchText.tokenize(name),
            brandTokens: SearchText.tokenize(brand ?? "").filter { !$0.isQuantity },
            weights: weights
        )
    }

    static func textMatch(queryTokens: [SearchToken], nameTokens: [SearchToken], brandTokens: [SearchToken], weights: SearchWeights) -> TextMatch {
        let nameWordCount = nameTokens.filter { !$0.isQuantity }.count
        let queryWordCount = queryTokens.filter { !$0.isQuantity }.count
        guard !queryTokens.isEmpty else {
            return TextMatch(text: 0, allWordsMatched: false, startMatched: false, nameWordCount: nameWordCount, queryWordCount: 0)
        }

        let firstNameWordIndex = nameTokens.firstIndex { !$0.isQuantity }
        let allowsShortPrefix = queryTokens.count == 1
        var weightedSum = 0.0
        var totalWeight = 0.0
        var allWordsMatched = true
        var allTokensMatched = true
        var startMatched = false
        var sawFirstQueryWord = false

        for (queryIndex, queryToken) in queryTokens.enumerated() {
            let isLast = queryIndex == queryTokens.count - 1
            var best = 0.0
            var bestIsFirstNameWord = false
            for (nameIndex, nameToken) in nameTokens.enumerated() {
                let weight = tierWeight(queryToken, nameToken, isLastQueryToken: isLast, allowsShortPrefix: allowsShortPrefix, weights: weights)
                if weight > best {
                    best = weight
                    bestIsFirstNameWord = nameIndex == firstNameWordIndex
                }
            }
            for brandToken in brandTokens {
                let weight = tierWeight(queryToken, brandToken, isLastQueryToken: isLast, allowsShortPrefix: allowsShortPrefix, weights: weights) * weights.brandFactor
                if weight > best {
                    best = weight
                    bestIsFirstNameWord = false
                }
            }

            let tokenWeight = queryToken.isQuantity ? weights.quantityTokenWeight : 1.0
            weightedSum += tokenWeight * best
            totalWeight += tokenWeight
            if best <= 0 { allTokensMatched = false }
            if !queryToken.isQuantity {
                if best <= 0 { allWordsMatched = false }
                if !sawFirstQueryWord {
                    sawFirstQueryWord = true
                    startMatched = bestIsFirstNameWord && best > 0
                }
            }
        }

        return TextMatch(
            text: totalWeight > 0 ? weightedSum / totalWeight : 0,
            // A query of only quantities ("250g") is "covered" when all of them matched.
            allWordsMatched: queryWordCount > 0 ? allWordsMatched : allTokensMatched,
            startMatched: startMatched,
            nameWordCount: nameWordCount,
            queryWordCount: queryWordCount
        )
    }

    /// The tier weight of `queryToken` against one name (or brand) token.
    static func tierWeight(_ queryToken: SearchToken, _ nameToken: SearchToken, isLastQueryToken: Bool, allowsShortPrefix: Bool, weights: SearchWeights) -> Double {
        if queryToken.text == nameToken.text { return weights.exact }
        if queryToken.isQuantity || nameToken.isQuantity {
            // Quantities only match exactly, or by prefix while being typed ("25" -> "250g").
            if queryToken.isQuantity, nameToken.isQuantity, isLastQueryToken, nameToken.text.hasPrefix(queryToken.text) {
                return weights.prefix
            }
            return 0
        }
        if queryToken.stem == nameToken.stem { return weights.stem }
        let minimumPrefixLength = allowsShortPrefix ? 1 : 2
        if isLastQueryToken, queryToken.text.count >= minimumPrefixLength, nameToken.text.hasPrefix(queryToken.text) {
            return weights.prefix
        }
        if queryToken.stem.count >= 3,
           nameToken.stem.hasPrefix(queryToken.stem),
           nameToken.stem.count - queryToken.stem.count <= weights.stemPrefixMaxExtraLength {
            return weights.stemPrefix
        }
        return fuzzyWeight(queryToken.text, nameToken.text, weights: weights)
    }

    /// Up to 1 edit for words of 4+ letters, 2 for 8+; the first letter
    /// must match, except that 5+ letter words may have one edit there at
    /// the lower `fuzzyFirstLetter` weight.
    static func fuzzyWeight(_ query: String, _ name: String, weights: SearchWeights) -> Double {
        let length = query.count
        let maxEdits = length >= 8 ? 2 : (length >= 4 ? 1 : 0)
        guard maxEdits > 0, let queryFirst = query.first, let nameFirst = name.first else { return 0 }
        if queryFirst == nameFirst {
            return EditDistance.damerauLevenshtein(query, name, maxDistance: maxEdits) != nil ? weights.fuzzy : 0
        }
        guard length >= 5 else { return 0 }
        return EditDistance.damerauLevenshtein(query, name, maxDistance: 1) != nil ? weights.fuzzyFirstLetter : 0
    }

    /// (text + bonuses) x length normalization -- shorter, more specific
    /// names win ties.
    public static func relevance(_ match: TextMatch, weights: SearchWeights = .standard) -> Double {
        let extraWords = max(0, match.nameWordCount - match.queryWordCount)
        let lengthFactor = 1 / (1 + weights.lengthPenaltyPerExtraWord * Double(extraWords))
        var value = match.text
        if match.allWordsMatched { value += weights.coverageBonus }
        if match.startMatched { value += weights.startBonus }
        return value * lengthFactor
    }

    static func personalBoost(for food: Food, personal: SearchPersonalContext, weights: SearchWeights) -> Double {
        var boost = weights.usageBoost * log1p(personal.decayedUseCounts[food.id] ?? 0)
        if personal.favoriteFoodIds.contains(food.id) { boost += weights.favoriteBoost }
        if food.source == .custom { boost += weights.customBoost }
        if food.garminIsFavorite == true || food.garminIsRecent == true { boost += weights.garminFlagBoost }
        return boost
    }

    static func rankPrior(_ candidate: SearchCandidate, weights: SearchWeights) -> Double {
        guard candidate.sourceCount > 0 else { return 0 }
        let position = Double(min(candidate.sourceRank, candidate.sourceCount)) / Double(candidate.sourceCount)
        return weights.remoteRankPrior * (1 - position)
    }

    /// Score, then origin precedence, then name, then id -- deterministic.
    public static func isRankedBefore(_ lhs: SearchResult, _ rhs: SearchResult) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.origin.precedence != rhs.origin.precedence { return lhs.origin.precedence < rhs.origin.precedence }
        let lhsName = SearchText.fold(lhs.food.name)
        let rhsName = SearchText.fold(rhs.food.name)
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.food.id < rhs.food.id
    }
}

// FoodTagRule.swift
//
// The keyword-rule vocabulary `FoodTagger` evaluates (design D2). A rule
// says "if any of these phrases appears in the food's name, and none of
// these exclusion phrases does, the food gets these tags". Rules are
// grouped into named `FoodTagRuleSet`s so each wave-2 change owns its own
// set file (`FoodTagRules+Seasonal.swift`, ...) instead of editing one
// shared dictionary.
//
// Phrases are matched against the SAME normalisation food search uses
// (`SearchText.tokenize`: NFKD fold, lowercase, split, `CzechLightStemmer`)
// so there is one definition of "the same word" in the app. Matching is on
// whole-token boundaries, consecutive tokens for multi-word phrases. Each
// word of a phrase is written already folded and takes one of three forms:
//
//   "ryba"    -- STEM match: the token's light stem equals the stem of
//                "ryba" ("ryba", "ryby", "rybou" all stem to "ryb"; "rybíz"
//                does not). The default; handles Czech inflection.
//   "jahod*"  -- PREFIX match on the folded token text ("jahoda",
//                "jahody", "jahodový"). For derived adjectives the light
//                stemmer does not reduce.
//   "=porek"  -- EXACT match on the folded token text. For the rare case
//                where two unrelated words share a stem ("pórek" (leek) and
//                English "pork" both stem to "pork").
//
// The three-mode syntax is an extension of the design's "folded+stemmed
// phrase match": the golden suite (FoodTaggerTests) showed plain stem
// equality alone cannot express adjective derivations like "jahodový".
//
// Depends on: SearchText, CzechLightStemmer. Depended on by: FoodTagger,
// every FoodTagRules+*.swift, CzechBrands.

import Foundation

/// One compiled word pattern of a `FoodTagPhrase`.
public enum FoodTagWordPattern: Sendable, Equatable {
    case stem(String)
    case prefix(String)
    case exact(String)

    public init(_ raw: String) {
        if raw.hasPrefix("=") {
            self = .exact(SearchText.fold(String(raw.dropFirst())))
        } else if raw.hasSuffix("*") {
            self = .prefix(SearchText.fold(String(raw.dropLast())))
        } else {
            self = .stem(CzechLightStemmer.stem(SearchText.fold(raw)))
        }
    }

    public func matches(_ token: SearchToken) -> Bool {
        switch self {
        case .stem(let stem):
            return token.stem == stem
        case .prefix(let prefix):
            return token.text.hasPrefix(prefix)
        case .exact(let text):
            return token.text == text
        }
    }
}

/// A compiled, possibly multi-word phrase ("kysan* zeli").
public struct FoodTagPhrase: Sendable, Equatable {
    public let source: String
    public let words: [FoodTagWordPattern]

    public init(_ source: String) {
        self.source = source
        self.words = source
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { FoodTagWordPattern(String($0)) }
    }

    /// Whether the phrase appears as consecutive tokens anywhere in `tokens`.
    public func matches(_ tokens: [SearchToken]) -> Bool {
        guard !words.isEmpty, words.count <= tokens.count else { return false }
        for start in 0...(tokens.count - words.count) {
            var allMatch = true
            for (offset, word) in words.enumerated() where !word.matches(tokens[start + offset]) {
                allMatch = false
                break
            }
            if allMatch { return true }
        }
        return false
    }
}

public struct FoodTagRule: Sendable {
    public let tags: Set<FoodTag>
    /// Matched against the food's NAME tokens.
    public let anyPhrases: [FoodTagPhrase]
    /// Matched against the food's BRAND tokens only.
    public let anyBrands: [FoodTagPhrase]
    /// Matched against the NAME tokens; any match vetoes the whole rule
    /// (exclusions win over inclusions -- "rybíz" must never be fish).
    public let excludePhrases: [FoodTagPhrase]

    public init(
        tags: Set<FoodTag>,
        anyPhrases: [String] = [],
        anyBrands: [String] = [],
        excludePhrases: [String] = []
    ) {
        self.tags = tags
        self.anyPhrases = anyPhrases.map(FoodTagPhrase.init)
        self.anyBrands = anyBrands.map(FoodTagPhrase.init)
        self.excludePhrases = excludePhrases.map(FoodTagPhrase.init)
    }

    /// The tags this rule contributes for a food whose name and brand have
    /// already been tokenized (word tokens only), or an empty set.
    public func evaluate(nameTokens: [SearchToken], brandTokens: [SearchToken]) -> Set<FoodTag> {
        if excludePhrases.contains(where: { $0.matches(nameTokens) }) { return [] }
        if anyPhrases.contains(where: { $0.matches(nameTokens) }) { return tags }
        if anyBrands.contains(where: { $0.matches(brandTokens) }) { return tags }
        return []
    }
}

public struct FoodTagRuleSet: Sendable {
    public let id: String
    public let rules: [FoodTagRule]

    public init(id: String, rules: [FoodTagRule]) {
        self.id = id
        self.rules = rules
    }
}

// SearchText.swift
//
// The one normalization pipeline every search path shares (rebuild-food-
// search design.md D1): queries, food names, brands, the remote term-cache
// key, and the OFF -> Garmin match query all go through here, so "rohlík",
// "ROHLIK" and "Rohlík 43g" can never be compared under two different sets
// of rules. Before this existed, three call sites each did their own
// ad-hoc `folding(...)`/`lowercased()` + substring test, which is why word
// order, inflection and pack sizes all broke matching (proposal.md's audit).
//
// Pipeline: NFKD -> drop combining marks -> lowercase -> split on anything
// that isn't a letter or digit (keeping "1,5" and "3,7%" together) -> glue
// a number to a following unit ("250 g" -> "250g") -> classify each token
// as a word or a quantity -> stem words with `CzechLightStemmer`.
// Czech "ch" is one letter in the alphabet but is deliberately treated as
// plain c+h here: search only needs equality/prefix/edit distance, never
// collation order.
//
// Pure and synchronous; no Foundation locale state, so results never depend
// on the device's language setting. Used by `SearchRanker`, `SearchDedup`,
// the Garmin/OFF sources (remote query variants) and `GarminFoodMatching`.
// Tested by SearchTextTests.

import Foundation

/// One normalized token of a query, food name or brand.
public struct SearchToken: Sendable, Equatable, Hashable {
    /// Folded form: diacritics stripped, lowercased ("rohliky", "250g", "1,5l").
    public let text: String
    /// `CzechLightStemmer.stem(text)` for a word; the same as `text` for a quantity.
    public let stem: String
    /// Pack sizes and percentages ("250g", "1,5l", "30%", "43") -- they
    /// count only a little towards a match (`SearchWeights.quantityTokenWeight`)
    /// and never towards a name's word count.
    public let isQuantity: Bool

    public init(text: String, stem: String, isQuantity: Bool) {
        self.text = text
        self.stem = stem
        self.isQuantity = isQuantity
    }

    /// Builds a token from already-folded text, classifying and stemming it.
    public init(folded text: String) {
        let quantity = SearchText.isQuantity(text)
        self.init(text: text, stem: quantity ? text : CzechLightStemmer.stem(text), isQuantity: quantity)
    }
}

public enum SearchText {
    /// Units that turn a bare number into a quantity token when they follow
    /// it ("250 g") or are glued to it ("250g").
    static let quantityUnits: Set<String> = ["g", "kg", "mg", "ml", "l", "dl", "cl", "ks", "x", "%"]

    /// NFKD, combining marks removed, lowercased. "Kuřecí ŘÍZEK" -> "kureci rizek".
    public static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.decomposedStringWithCompatibilityMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars).lowercased()
    }

    /// Whether `text` carries any diacritic (a combining mark after NFKD).
    /// Garmin's and Search-a-licious's own search are both diacritic-
    /// sensitive (probed 2026-09-23, see design.md), so this decides which
    /// spelling variants get sent to them.
    public static func hasDiacritics(_ text: String) -> Bool {
        text.decomposedStringWithCompatibilityMapping.unicodeScalars.contains { scalar in
            scalar.properties.generalCategory == .nonspacingMark
        }
    }

    /// The full D1 pipeline: fold, split, glue units, classify, stem.
    public static func tokenize(_ text: String) -> [SearchToken] {
        mergeUnits(rawTokens(fold(text))).map { SearchToken(folded: $0) }
    }

    /// The folded, non-quantity words of `text`.
    public static func words(_ text: String) -> [String] {
        tokenize(text).filter { !$0.isQuantity }.map(\.text)
    }

    /// Folded tokens joined by single spaces: "Rohlík, 43 g" -> "rohlik 43g".
    public static func foldedPhrase(_ text: String) -> String {
        tokenize(text).map(\.text).joined(separator: " ")
    }

    /// Lowercased and whitespace-collapsed, diacritics KEPT -- what a
    /// diacritic-sensitive remote API should see, and the remote term-cache
    /// key ("Rohlík  " -> "rohlík").
    public static func typedPhrase(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The spellings to send to a diacritic-sensitive remote search, at most
    /// two: what was typed, plus either its diacritic-free form (when the
    /// user typed diacritics) or its restored-diacritics form (when they
    /// didn't and `CzechDiacritics` knows the words). Probed 2026-09-23:
    /// Garmin returned 0 hits for "rohlík" but 13 for "rohlik", and 45
    /// Czech Search-a-licious hits for "mléko" but 9 for "mleko" -- neither
    /// spelling alone is reliably better, so both are asked and merged.
    public static func remoteQueryVariants(_ text: String) -> [String] {
        let typed = typedPhrase(text)
        guard !typed.isEmpty else { return [] }
        if hasDiacritics(typed) {
            let folded = typedPhrase(fold(typed))
            return folded.isEmpty || folded == typed ? [typed] : [typed, folded]
        }
        if let restored = CzechDiacritics.restore(typed), restored != typed {
            return [typed, restored]
        }
        return [typed]
    }

    /// The query used to look a product up in another database (OFF ->
    /// Garmin match, task 4.2): the name's own words with the brand's words
    /// and every pack size removed, diacritics kept (Garmin's search is
    /// diacritic-sensitive). "Rohlíky Krehké 250G Bonavita" / "Bonavita" ->
    /// "rohlíky krehké". Falls back to the whole name when stripping the
    /// brand would leave nothing (a product named just "Madeta").
    public static func matchQuery(name: String, brand: String?) -> String {
        let brandWords = Set(words(brand ?? ""))
        let pieces = mergeUnits(rawTokens(name.lowercased())).filter { !isQuantity(fold($0)) }
        let withoutBrand = pieces.filter { !brandWords.contains(fold($0)) }
        return (withoutBrand.isEmpty ? pieces : withoutBrand).joined(separator: " ")
    }

    /// True for "250", "250g", "1,5l", "3,7%" -- a number, optionally
    /// followed by one of `quantityUnits`.
    public static func isQuantity(_ token: String) -> Bool {
        let numeric = token.prefix { $0.isNumber || $0 == "," }
        guard let first = numeric.first, first.isNumber, let last = numeric.last, last.isNumber else {
            return false
        }
        let suffix = String(token.dropFirst(numeric.count))
        return suffix.isEmpty || quantityUnits.contains(suffix)
    }

    // MARK: - Tokenizer internals

    /// Splits on every character that isn't a letter or digit, except that
    /// a "," or "." between two digits stays (normalized to ",") and a "%"
    /// straight after a digit is kept on that number.
    static func rawTokens(_ text: String) -> [String] {
        let characters = Array(text)
        var tokens: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        for index in characters.indices {
            let character = characters[index]
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if character == "," || character == ".",
                      let previous = current.last, previous.isNumber,
                      index + 1 < characters.count, characters[index + 1].isNumber {
                current.append(",")
            } else if character == "%", let previous = current.last, previous.isNumber {
                current.append("%")
                flush()
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    /// Glues a bare number to the unit token right after it: ["250", "g"] -> ["250g"].
    static func mergeUnits(_ tokens: [String]) -> [String] {
        var merged: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if index + 1 < tokens.count, isBareNumber(token), quantityUnits.contains(tokens[index + 1]) {
                merged.append(token + tokens[index + 1])
                index += 2
            } else {
                merged.append(token)
                index += 1
            }
        }
        return merged
    }

    private static func isBareNumber(_ token: String) -> Bool {
        guard let first = token.first, first.isNumber, let last = token.last, last.isNumber else { return false }
        return token.allSatisfy { $0.isNumber || $0 == "," }
    }
}

/// A search query, tokenized once and reused for every candidate.
public struct SearchQuery: Sendable, Equatable {
    public let raw: String
    public let tokens: [SearchToken]
    /// `SearchText.typedPhrase(raw)` -- the remote term-cache key.
    public let remoteKey: String
    /// `SearchText.remoteQueryVariants(raw)` -- what remote sources send.
    public let remoteVariants: [String]

    public init(_ raw: String) {
        self.raw = raw
        self.tokens = SearchText.tokenize(raw)
        self.remoteKey = SearchText.typedPhrase(raw)
        self.remoteVariants = SearchText.remoteQueryVariants(raw)
    }

    /// Nothing searchable (blank, or only punctuation).
    public var isEmpty: Bool { tokens.isEmpty }

    public var wordTokens: [SearchToken] { tokens.filter { !$0.isQuantity } }
}

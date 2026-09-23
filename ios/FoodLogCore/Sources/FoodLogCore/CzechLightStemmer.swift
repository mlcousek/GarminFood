// CzechLightStemmer.swift
//
// Czech is heavily inflected: the same bread roll is "rohlík", "rohlíky",
// "rohlíku", "rohlíkem". Without stemming, the owner's search for
// "rohlíky" missed every food named "Rohlík" (rebuild-food-search
// proposal.md). This is a conservative port of the Dolamic & Savoy (2009)
// "light" Czech stemmer -- the same algorithm Lucene ships as
// `CzechStemmer` -- adapted to run on FOLDED text (diacritics already
// stripped by `SearchText.fold`), because both the query and every food
// name are folded before they get here (design.md D2).
//
// Steps: strip one case ending, then one possessive ending, then normalize
// a few consonant alternations (c->k, z->h) or drop a "mobile e"
// (chleb/chleba -> chlb, mleko/mleka -> mlk). Aggressive derivational
// stripping is deliberately left out: it over-conflates food names.
// Adaptations for folded input, each because the rule can no longer tell
// the original letters apart:
//   - Lucene's "čt -> ck" and "št -> sk" rules are dropped (folded "st"
//     would also hit ordinary words like "pasta");
//   - its "ů -> o" rule is dropped (folded "u" is ambiguous);
//   - mobile-e removal requires more than 3 letters, so no stem is ever
//     shorter than 3 characters ("med" stays "med");
//   - the case endings "-at", "-ám", "-os", "-us" and "-aty" are not
//     stripped: on folded text they mostly hit the NOMINATIVE of common
//     food nouns, which both conflated different foods (salát/salám ->
//     "sal") and split one food's own forms apart (losos -> "los" but
//     lososa -> "losos"; eidam -> "eid" but eidamu -> "eidam").
// A small exception table covers kuře/kuřecí, whose regular stems diverge
// ("kur" vs "kurek") although every Czech shopper treats them as one word.
//
// Pure function, no state. Used by `SearchToken`; tested by
// CzechLightStemmerTests.

import Foundation

public enum CzechLightStemmer {
    /// Whole-word overrides, keyed by folded word.
    static let exceptions: [String: String] = {
        let chicken = [
            "kure", "kurete", "kureti", "kuretem", "kurata", "kuratum", "kuratech", "kuratka", "kuratko",
            "kureci", "kureciho", "kurecimu", "kurecim", "kurecich", "kurecimi"
        ]
        return Dictionary(uniqueKeysWithValues: chicken.map { ($0, "kur") })
    }()

    private static let caseSuffixes5 = ["atech"]
    private static let caseSuffixes4 = ["etem", "atum"]
    private static let caseSuffixes3 = [
        "ech", "ich", "eho", "emi", "emu", "ete", "eti", "iho", "imi", "imu",
        "ach", "ata", "ych", "ama", "ami", "ove", "ovi", "ymi"
    ]
    private static let caseSuffixes2 = ["em", "es", "im", "um", "ym", "mi", "ou"]
    private static let caseVowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    private static let possessiveSuffixes = ["ov", "in", "uv"]

    /// The light stem of one folded word. Words shorter than 4 letters keep
    /// all their letters (only the c->k / z->h normalization can touch them).
    public static func stem(_ word: String) -> String {
        if let exception = exceptions[word] { return exception }
        var characters = Array(word)
        characters = removeCase(characters)
        characters = removePossessive(characters)
        characters = normalize(characters)
        return String(characters)
    }

    static func removeCase(_ word: [Character]) -> [Character] {
        let length = word.count
        if length > 7, endsWithAny(word, caseSuffixes5) { return Array(word.dropLast(5)) }
        if length > 6, endsWithAny(word, caseSuffixes4) { return Array(word.dropLast(4)) }
        if length > 5, endsWithAny(word, caseSuffixes3) { return Array(word.dropLast(3)) }
        if length > 4, endsWithAny(word, caseSuffixes2) { return Array(word.dropLast(2)) }
        if length > 3, let last = word.last, caseVowels.contains(last) { return Array(word.dropLast()) }
        return word
    }

    static func removePossessive(_ word: [Character]) -> [Character] {
        if word.count > 5, endsWithAny(word, possessiveSuffixes) { return Array(word.dropLast(2)) }
        return word
    }

    static func normalize(_ word: [Character]) -> [Character] {
        guard let last = word.last else { return word }
        var result = word
        if last == "c" {
            result[result.count - 1] = "k"
            return result
        }
        if last == "z" {
            result[result.count - 1] = "h"
            return result
        }
        if result.count > 3, result[result.count - 2] == "e" {
            result.remove(at: result.count - 2)
            return result
        }
        return result
    }

    private static func endsWithAny(_ word: [Character], _ suffixes: [String]) -> Bool {
        suffixes.contains { suffix in
            let tail = Array(suffix)
            return word.count >= tail.count && word.suffix(tail.count).elementsEqual(tail)
        }
    }
}

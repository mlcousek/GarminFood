// SearchTextTests.swift
//
// rebuild-food-search task 2.1 (design.md D1): the shared normalization
// pipeline -- folding, tokenizing, quantity tokens, remote spelling
// variants, the OFF -> Garmin match query, and the diacritics vocabulary.

import XCTest
@testable import FoodLogCore

final class SearchTextTests: XCTestCase {
    func testFoldingStripsCzechDiacriticsAndCase() {
        XCTAssertEqual(SearchText.fold("Kuřecí ŘÍZEK"), "kureci rizek")
        XCTAssertEqual(SearchText.fold("Žluťoučký kůň úpěl ďábelské ódy"), "zlutoucky kun upel dabelske ody")
        XCTAssertEqual(SearchText.fold("Müsli"), "musli")
    }

    func testHasDiacritics() {
        XCTAssertTrue(SearchText.hasDiacritics("rohlík"))
        XCTAssertFalse(SearchText.hasDiacritics("rohlik 250g"))
    }

    func testTokenizeSplitsOnPunctuationAndKeepsWordOrder() {
        XCTAssertEqual(SearchText.tokenize("Tvaroh, měkký (Pilos)").map(\.text), ["tvaroh", "mekky", "pilos"])
    }

    func testChIsTreatedAsTwoPlainLetters() {
        XCTAssertEqual(SearchText.tokenize("Chléb").map(\.text), ["chleb"])
    }

    func testPackSizesBecomeQuantityTokens() {
        let tokens = SearchText.tokenize("Rohlíky 250 g, Mléko 1,5 l, Eidam 30% 100g")
        XCTAssertEqual(tokens.map(\.text), ["rohliky", "250g", "mleko", "1,5l", "eidam", "30%", "100g"])
        XCTAssertEqual(tokens.filter(\.isQuantity).map(\.text), ["250g", "1,5l", "30%", "100g"])
    }

    func testDecimalPointAndCommaNormalizeToTheSameToken() {
        XCTAssertEqual(SearchText.tokenize("1.5l").map(\.text), SearchText.tokenize("1,5 l").map(\.text))
    }

    func testIsQuantity() {
        XCTAssertTrue(SearchText.isQuantity("43"))
        XCTAssertTrue(SearchText.isQuantity("3,7%"))
        XCTAssertTrue(SearchText.isQuantity("500ml"))
        XCTAssertFalse(SearchText.isQuantity("b12"))
        XCTAssertFalse(SearchText.isQuantity("7days"))
        XCTAssertFalse(SearchText.isQuantity("rohlik"))
    }

    func testWordsAreStemmed() {
        let token = SearchText.tokenize("rohlíky")[0]
        XCTAssertEqual(token.text, "rohliky")
        XCTAssertEqual(token.stem, "rohlik")
        XCTAssertFalse(token.isQuantity)
    }

    func testBlankOrPunctuationOnlyQueryIsEmpty() {
        XCTAssertTrue(SearchQuery("   ").isEmpty)
        XCTAssertTrue(SearchQuery("--!").isEmpty)
        XCTAssertFalse(SearchQuery("a").isEmpty)
    }

    func testTypedPhraseKeepsDiacriticsButCollapsesSpaceAndCase() {
        XCTAssertEqual(SearchText.typedPhrase("  Rohlík   TUKOVÝ "), "rohlík tukový")
    }

    // MARK: - Remote spelling variants (task 1.3 decision)

    func testTypedDiacriticsAlsoSendTheFoldedSpelling() {
        XCTAssertEqual(SearchText.remoteQueryVariants("Bílý jogurt"), ["bílý jogurt", "bily jogurt"])
    }

    func testPlainSpellingOfKnownWordsAlsoSendsTheAccentedSpelling() {
        XCTAssertEqual(SearchText.remoteQueryVariants("mleko"), ["mleko", "mléko"])
        XCTAssertEqual(SearchText.remoteQueryVariants("bily jogurt"), ["bily jogurt", "bílý jogurt"])
    }

    func testUnknownPlainWordsAreSentOnce() {
        XCTAssertEqual(SearchText.remoteQueryVariants("tvaroh"), ["tvaroh"])
        XCTAssertEqual(SearchText.remoteQueryVariants("   "), [])
    }

    func testEveryVocabularyEntryFoldsToItsKey() {
        for (key, accented) in CzechDiacritics.vocabulary {
            XCTAssertEqual(SearchText.fold(accented), key)
            XCTAssertTrue(SearchText.hasDiacritics(accented), "\(accented) needs no restoring")
        }
        XCTAssertNil(CzechDiacritics.restore("tvaroh"))
        XCTAssertEqual(CzechDiacritics.restore("kure sunka"), "kuře šunka")
    }

    // MARK: - OFF -> Garmin match query (task 4.2)

    func testMatchQueryDropsBrandAndPackSizeButKeepsDiacritics() {
        XCTAssertEqual(
            SearchText.matchQuery(name: "Rohlíky Krehké Celozrné 250G Active Bonavita", brand: "Bonavita"),
            "rohlíky krehké celozrné active"
        )
        XCTAssertEqual(SearchText.matchQuery(name: "Madeta Jihočeský tvaroh 250 g", brand: "Madeta"), "jihočeský tvaroh")
    }

    func testMatchQueryKeepsTheNameWhenItIsOnlyTheBrand() {
        XCTAssertEqual(SearchText.matchQuery(name: "Lipánek", brand: "Lipánek"), "lipánek")
    }
}

final class CzechLightStemmerTests: XCTestCase {
    /// design.md D2's table: each group collapses to one stem.
    func testInflectedFormsCollapseToOneStem() {
        let groups: [[String]] = [
            ["rohlik", "rohliky", "rohliku", "rohlikem", "rohlikum"],
            ["chleb", "chleba", "chlebem"],
            ["jogurt", "jogurty", "jogurtu", "jogurtem", "jogurtovy"],
            ["mleko", "mleka", "mlekem"],
            ["syr", "syry", "syru", "syrem"],
            ["banan", "banany", "bananu"],
            ["sunka", "sunky", "sunkou"],
            ["kefir", "kefirove"],
            ["kure", "kureci", "kureciho", "kuretem"],
            ["salat", "salaty", "salatu"],
            ["losos", "lososa"],
            ["eidam", "eidamu"]
        ]
        for group in groups {
            let stems = Set(group.map(CzechLightStemmer.stem))
            XCTAssertEqual(stems.count, 1, "\(group) stemmed to \(stems)")
        }
    }

    func testTvarohIsNotOverStemmed() {
        XCTAssertEqual(CzechLightStemmer.stem("tvaroh"), "tvaroh")
        XCTAssertEqual(CzechLightStemmer.stem("tvarohu"), "tvaroh")
    }

    func testDifferentFoodsStayApart() {
        XCTAssertNotEqual(CzechLightStemmer.stem("salam"), CzechLightStemmer.stem("salat"))
        XCTAssertNotEqual(CzechLightStemmer.stem("syr"), CzechLightStemmer.stem("sunka"))
    }

    func testTypoOfAMobileEWordSharesItsStem() {
        // "chlba" is what a hurried thumb types for "chleba".
        XCTAssertEqual(CzechLightStemmer.stem("chlba"), CzechLightStemmer.stem("chleb"))
    }

    func testNoStemIsShorterThanThreeLetters() {
        for word in ["med", "syr", "caj", "mleko", "vejce", "maso", "ryze", "kure", "pivo"] {
            XCTAssertGreaterThanOrEqual(CzechLightStemmer.stem(word).count, 3, word)
        }
    }
}

final class EditDistanceTests: XCTestCase {
    func testDistances() {
        XCTAssertEqual(EditDistance.damerauLevenshtein("banan", "banan", maxDistance: 1), 0)
        XCTAssertEqual(EditDistance.damerauLevenshtein("bnan", "banan", maxDistance: 1), 1)
        XCTAssertEqual(EditDistance.damerauLevenshtein("tvoroh", "tvaroh", maxDistance: 1), 1)
        XCTAssertEqual(EditDistance.damerauLevenshtein("", "ab", maxDistance: 2), 2)
    }

    func testAdjacentTranspositionCostsOne() {
        XCTAssertEqual(EditDistance.damerauLevenshtein("jgourt", "jogurt", maxDistance: 1), 1)
    }

    func testReturnsNilBeyondTheBound() {
        XCTAssertNil(EditDistance.damerauLevenshtein("rohlik", "rolin", maxDistance: 1))
        XCTAssertNil(EditDistance.damerauLevenshtein("a", "abcd", maxDistance: 2))
        XCTAssertEqual(EditDistance.damerauLevenshtein("rohlik", "rolin", maxDistance: 2), 2)
    }

    /// Task 2.3's budget is 10k comparisons < 50 ms in a RELEASE build; CI
    /// runs `swift test` in debug (several times slower), so this asserts a
    /// generous debug-mode ceiling that still catches an accidental
    /// unbounded O(n*m) regression on long strings.
    func testTenThousandBoundedComparisonsAreFast() {
        let words = ["rohliky", "tvaroh", "jogurt", "mleko", "chleba", "banany", "kureci", "sunka", "eidam", "ovesne"]
        let names = ["rohlik", "tvoroh", "yogurt", "mliko", "chleb", "bananas", "kuracie", "sunkova", "edam", "ovsene"]
        let start = Date()
        var matches = 0
        for index in 0..<10_000 {
            if EditDistance.damerauLevenshtein(words[index % 10], names[(index / 10) % 10], maxDistance: 1) != nil {
                matches += 1
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertGreaterThan(matches, 0)
        XCTAssertLessThan(elapsed, 2.0, "10k bounded comparisons took \(elapsed)s")
    }
}

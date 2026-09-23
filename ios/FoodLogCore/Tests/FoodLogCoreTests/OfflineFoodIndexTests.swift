// OfflineFoodIndexTests.swift
//
// add-offline-czech-food-index tasks 3.1, 3.2 and 3.6: decoding the file
// the Node builder publishes (a real gzip made by Node's zlib, so gzip
// interop is proven rather than assumed), the inverted index's candidate
// gathering against SearchRanker, the search source inside the real
// FoodSearchEngine (dedup against live OFF), and the barcode fallback.
// No network. The fixture is ~200 products built in code.

import XCTest
@testable import FoodLogCore
import GarminKit

// MARK: - Fixtures

/// `{"schema":1,"products":[tvaroh (Madeta, alt "Soft quark"), rohlík (Penam)]}`
/// gzipped by tools/build-czech-food-index's own zlib settings (Node 22).
private let nodeGzipBase64 = "H4sIAAAAAAACCj2OPY7CMBSEr2JN/YRsB8PmHWElJAQlojDBbFbeYIgdGpQjcALOwBGowsFWCT/TzRTzfWfEonSVBSvCoQ7bpkgRvDqjAOPL5GMplc7GZjIFYQ/G928ZHhcXfXcX6WTrUIrqcfW+u4PgwFiGXRLHxtYehA0YM7t1yYJwBEMbKX5A8GAlNaHYgLORIRzAakrYgWVf42uOth9USx8j+Yp6Gy1C+dfdvEiND6dBo6fO3d5WT5DOh8seZZ6kfABlI92u23+1WmvYAwEAAA=="
/// Its SHA-256 as Node's crypto computed it.
private let nodeGzipSHA256 = "4020266374a2d79527e04fecc81d925c2f8e6faabe36783e97b03fa960a248f5"

private func offlineFixtureProducts() -> [OfflineIndexProduct] {
    var products: [OfflineIndexProduct] = [
        OfflineIndexProduct(code: "8594001234567", name: "Jihočeský tvaroh měkký", alternateName: "Soft quark", brand: "Madeta", quantity: "250 g", kcal: 102, carbs: 3.5, protein: 17, fat: 0.5, salt: 0.1),
        OfflineIndexProduct(code: "8594001234574", name: "Tvaroh polotučný", brand: "Pilos", kcal: 118, protein: 16),
        OfflineIndexProduct(code: "8590000000017", name: "Rohlík tukový", brand: "Penam", kcal: 290.5, carbs: 55, protein: 9, fat: 3.2),
        OfflineIndexProduct(code: "8595000000024", name: "Kuřecí prsní řízek", brand: "Vodňanské kuře", kcal: 110, protein: 23),
        OfflineIndexProduct(code: "8595000000031", name: "Mléko polotučné 1,5 %", brand: "Kunín", quantity: "1 l", kcal: 46),
        OfflineIndexProduct(code: "8595000000048", name: "Eidam 30 %", brand: "Madeta", kcal: 263),
        OfflineIndexProduct(code: "8595000000055", name: "Chléb Šumava", brand: "Penam", kcal: 240),
        OfflineIndexProduct(code: "012345678905", name: "Arašídové máslo", alternateName: "Peanut butter", kcal: 600)
    ]
    for number in 1...192 {
        products.append(OfflineIndexProduct(code: String(format: "859999%07ld", number), name: "Jogurt bílý \(number)", brand: "Filler", kcal: 60))
    }
    return products
}

/// A gzip file around `data`, built with Foundation's raw DEFLATE -- lets
/// tests make arbitrary index files without Node.
func makeTestGzip(_ data: Data) throws -> Data {
    let deflated = try (data as NSData).compressed(using: .zlib) as Data
    var gzip = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0xff])
    gzip.append(deflated)
    for value in [GzipCRC32.checksum(data), UInt32(truncatingIfNeeded: data.count)] {
        gzip.append(contentsOf: [UInt8(value & 0xff), UInt8((value >> 8) & 0xff), UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)])
    }
    return gzip
}

func makeTestIndexGzip(_ products: [OfflineIndexProduct], schema: Int = 1) throws -> Data {
    try makeTestGzip(JSONEncoder().encode(OfflineIndexFile(schema: schema, products: products)))
}

// MARK: - File format and gzip

final class OfflineFoodIndexDecodingTests: XCTestCase {
    func testDecodesTheGzipTheNodeBuilderProduces() throws {
        let data = try XCTUnwrap(Data(base64Encoded: nodeGzipBase64))

        let index = try OfflineFoodIndex.decode(gzipData: data)

        XCTAssertEqual(index.count, 2)
        let tvaroh = try XCTUnwrap(index.product(code: "8594001234567"))
        XCTAssertEqual(tvaroh.name, "Jihočeský tvaroh měkký", "Czech diacritics must survive the round trip")
        XCTAssertEqual(tvaroh.alternateName, "Soft quark")
        XCTAssertEqual(tvaroh.brand, "Madeta")
        XCTAssertEqual(tvaroh.kcal, 102)
        XCTAssertEqual(tvaroh.salt, 0.1)
        XCTAssertNil(tvaroh.fiber, "a key the builder omitted decodes as unknown")
        XCTAssertEqual(index.product(code: "8590000000017")?.kcal, 290.5)
    }

    func testChecksumMatchesNodesSHA256() throws {
        let data = try XCTUnwrap(Data(base64Encoded: nodeGzipBase64))
        XCTAssertEqual(OfflineIndexChecksum.sha256Hex(data), nodeGzipSHA256)
    }

    func testCorruptedGzipIsRejected() throws {
        var data = try XCTUnwrap(Data(base64Encoded: nodeGzipBase64))
        let middle = data.startIndex + data.count / 2
        data[middle] ^= 0xFF

        XCTAssertThrowsError(try OfflineFoodIndex.decode(gzipData: data))
    }

    func testTruncatedGzipIsRejected() throws {
        let data = try XCTUnwrap(Data(base64Encoded: nodeGzipBase64))
        XCTAssertThrowsError(try OfflineFoodIndex.decode(gzipData: data.prefix(data.count - 20)))
    }

    func testPlainJSONIsNotMistakenForGzip() {
        XCTAssertThrowsError(try OfflineFoodIndex.decode(gzipData: Data(#"{"schema":1,"products":[]}"#.utf8))) { error in
            XCTAssertEqual(error as? OfflineIndexError, .notGzip)
        }
    }

    func testANewerSchemaIsIgnoredUntilTheAppIsUpdated() throws {
        let data = try makeTestGzip(Data(#"{"schema":2,"items":{}}"#.utf8))
        XCTAssertThrowsError(try OfflineFoodIndex.decode(gzipData: data)) { error in
            XCTAssertEqual(error as? OfflineIndexError, .unsupportedSchema(2))
        }
    }

    func testProductBecomesAnOpenFoodFactsShapedFood() {
        let food = offlineFixtureProducts()[0].food
        XCTAssertEqual(food.id, "8594001234567", "the EAN is the id, exactly like a live OFF hit, so the two dedup")
        XCTAssertEqual(food.source, .openFoodFacts, "so a tap routes through the Garmin-match flow")
        XCTAssertEqual(food.brandName, "Madeta")
        XCTAssertEqual(food.servings.count, 1)
        XCTAssertEqual(food.servings[0].numberOfUnits, 100)
        XCTAssertEqual(food.servings[0].unit, "g")
        XCTAssertEqual(food.servings[0].calories, 102)
        XCTAssertEqual(food.servings[0].sodium ?? 0, 40, accuracy: 0.0001, "0.1 g salt = 40 mg sodium")
    }
}

// MARK: - Search

final class OfflineFoodIndexSearchTests: XCTestCase {
    private let index = OfflineFoodIndex(products: offlineFixtureProducts())

    private func ids(_ query: String) -> [String] {
        index.candidates(for: SearchQuery(query)).map(\.food.id)
    }

    /// spec "Airplane mode": typing "tvaroh" lists the Czech quark products.
    func testFindsCzechProductsByName() {
        XCTAssertEqual(Set(ids("tvaroh")), ["8594001234567", "8594001234574"])
    }

    func testFoldsDiacriticsAndInflection() {
        XCTAssertEqual(ids("rohliky"), ["8590000000017"], "rohlíky (plural, no diacritics) finds Rohlík")
        XCTAssertTrue(ids("kureci").contains("8595000000024"))
        XCTAssertTrue(ids("mleko").contains("8595000000031"))
        XCTAssertTrue(ids("chleba").contains("8595000000055"), "mobile-e stemming: chleba ~ chléb")
    }

    func testFindsTheWordBeingTyped() {
        XCTAssertTrue(ids("tvar").contains("8594001234567"))
        XCTAssertTrue(ids("jihocesky tv").contains("8594001234567"))
    }

    func testToleratesATypo() {
        XCTAssertTrue(ids("tvarh").contains("8594001234567"))
    }

    func testMatchesAlternateNamesAndBrands() {
        XCTAssertEqual(ids("soft quark").first, "8594001234567")
        XCTAssertEqual(Set(ids("madeta")), ["8594001234567", "8595000000048"])
    }

    func testUnrelatedQueryFindsNothing() {
        XCTAssertEqual(ids("banán"), [])
        XCTAssertEqual(ids("250g"), [], "a query of only pack sizes gathers no candidates")
    }

    /// Design D2: at most 50 pre-scored candidates reach the engine.
    func testCandidatesAreCappedAtFiftyAndTaggedAsTheOfflineIndex() {
        let candidates = index.candidates(for: SearchQuery("jogurt"))
        XCTAssertEqual(candidates.count, OfflineFoodIndex.maximumCandidates)
        XCTAssertTrue(candidates.allSatisfy { $0.origin == .offlineIndex })
    }

    /// Pre-scoring must not change the answer: ranking only the index's
    /// top 50 gives the same top results as ranking the whole index.
    func testPreScoringKeepsTheSameTopResultsAsRankingEverything() {
        let everything = index.products.map { SearchCandidate(food: $0.food, origin: .offlineIndex, alternateNames: $0.alternateNames) }
        for query in ["tvaroh", "rohlik", "kureci rizek", "madeta", "jogurt bily 7", "soft quark", "mleko 1,5", "tv", "jo", "tvaroh m", "jogurt b", "a tvaroh"] {
            let parsed = SearchQuery(query)
            let full = SearchRanker.rank(parsed, candidates: everything).prefix(10).map(\.food.id)
            let fromIndex = SearchRanker.rank(parsed, candidates: index.candidates(for: parsed)).prefix(10).map(\.food.id)
            XCTAssertEqual(fromIndex, full, "query: \(query)")
        }
    }

    /// Per-keystroke cost: a single letter prefixes a large share of the
    /// real ~8k-product index, and 50 arbitrary rows out of thousands are
    /// noise, so the index answers nothing until a word has 2 letters.
    func testASingleLetterGetsNothingFromTheIndex() {
        XCTAssertEqual(ids("j"), [])
        XCTAssertEqual(ids("t"), [])
        XCTAssertEqual(ids("a b"), [], "no word of two letters or more")
        XCTAssertTrue(ids("tv").contains("8594001234567"), "two letters already search")
    }

    /// A one-letter word next to a real one looks up only its exact
    /// posting (the ranker can't prefix-match it in a multi-word query),
    /// and the other word still finds the product.
    func testAOneLetterWordBesideAnotherStillFinds() {
        XCTAssertEqual(Set(ids("tvaroh m")), ["8594001234567", "8594001234574"])
    }

    /// The next keystroke cancels this search; the loops stop instead of
    /// scoring rows nobody will see.
    func testACancelledSearchStopsEarlyWithNothing() async {
        let index = self.index
        let candidates = await Task { () -> [SearchCandidate] in
            _ = withUnsafeCurrentTask { $0?.cancel() }
            return index.candidates(for: SearchQuery("jogurt"))
        }.value
        XCTAssertEqual(candidates, [])
        XCTAssertEqual(index.candidates(for: SearchQuery("jogurt")).count, OfflineFoodIndex.maximumCandidates, "the same query uncancelled has results")
    }

    func testBarcodeLookupHandlesUPCVariants() {
        XCTAssertEqual(index.product(code: "8594001234567")?.name, "Jihočeský tvaroh měkký")
        XCTAssertEqual(index.product(code: " 8594001234567\n")?.name, "Jihočeský tvaroh měkký")
        XCTAssertEqual(index.product(code: "012345678905")?.name, "Arašídové máslo")
        XCTAssertEqual(index.product(code: "0012345678905")?.name, "Arašídové máslo", "a zero-padded UPC-A scan")
        XCTAssertNil(index.product(code: "4006381333931"))
    }
}

// MARK: - Source and engine

private struct CannedLiveOFFSource: FoodSearchSource {
    let foods: [Food]
    var origin: SearchOrigin { .openFoodFacts }
    var isRemote: Bool { true }

    func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage {
        SourcePage(candidates: foods.map { SearchCandidate(food: $0, origin: .openFoodFacts) })
    }
}

final class OfflineCzechIndexSourceTests: XCTestCase {
    /// spec "No index yet": search behaves as without it.
    func testAnswersEmptyUntilAnIndexIsLoaded() async throws {
        let holder = OfflineFoodIndexHolder()
        let source = OfflineCzechIndexSource(holder: holder)
        XCTAssertFalse(source.isRemote, "answers from memory on every keystroke")

        let before = try await source.search(SearchQuery("tvaroh"), page: 0, options: SearchOptions())
        XCTAssertEqual(before.candidates, [])

        holder.replace(with: OfflineFoodIndex(products: offlineFixtureProducts()))
        let after = try await source.search(SearchQuery("tvaroh"), page: 0, options: SearchOptions())
        XCTAssertEqual(after.candidates.count, 2)
        let second = try await source.search(SearchQuery("tvaroh"), page: 1, options: SearchOptions())
        XCTAssertEqual(second.candidates, [])
    }

    /// A cancelled search is reported as a cancellation, not as "no matches".
    func testACancelledSearchThrowsCancellation() async {
        let source = OfflineCzechIndexSource(holder: OfflineFoodIndexHolder(index: OfflineFoodIndex(products: offlineFixtureProducts())))
        let outcome = await Task { () -> Result<SourcePage, Error> in
            _ = withUnsafeCurrentTask { $0?.cancel() }
            do {
                return .success(try await source.search(SearchQuery("tvaroh"), page: 0, options: SearchOptions()))
            } catch {
                return .failure(error)
            }
        }.value
        switch outcome {
        case .success(let page):
            XCTFail("expected CancellationError, got \(page.candidates.count) candidates")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testEngineListsOfflineHitsAndMergesTheLiveCopyOfTheSameProduct() async {
        let holder = OfflineFoodIndexHolder(index: OfflineFoodIndex(products: offlineFixtureProducts()))
        let liveCopy = offlineFixtureProducts()[0].food
        let engine = FoodSearchEngine(
            sources: [OfflineCzechIndexSource(holder: holder), CannedLiveOFFSource(foods: [liveCopy])],
            debounceNanoseconds: 0
        )

        let snapshot = await engine.search("tvaroh")

        let tvaroh = snapshot.results.filter { $0.food.id == "8594001234567" }
        XCTAssertEqual(tvaroh.count, 1, "same EAN from the index and live OFF is one row")
        XCTAssertEqual(tvaroh.first?.origin, .offlineIndex)
        XCTAssertEqual(tvaroh.first?.alsoIn, [.openFoodFacts])
        XCTAssertEqual(Set(snapshot.results.map(\.food.id)), ["8594001234567", "8594001234574"])
        XCTAssertEqual(snapshot.statuses[.offlineIndex], .finished(hasMore: false))
    }

    func testEngineWithAnEmptyHolderStillReturnsLiveResults() async {
        let engine = FoodSearchEngine(
            sources: [OfflineCzechIndexSource(holder: OfflineFoodIndexHolder()), CannedLiveOFFSource(foods: [offlineFixtureProducts()[1].food])],
            debounceNanoseconds: 0
        )

        let snapshot = await engine.search("tvaroh")

        XCTAssertEqual(snapshot.results.map(\.food.id), ["8594001234574"])
        XCTAssertEqual(snapshot.results.first?.origin, .openFoodFacts)
    }
}

// MARK: - Barcode fallback (design.md D4, task 3.6)

private struct GarminBarcodeUnavailable: Error {}

private actor ScriptedGarminBarcodeLookup: BarcodeFoodLookup {
    private let result: FoodSearchResult?
    private let fails: Bool
    private(set) var calls = 0

    init(result: FoodSearchResult? = nil, fails: Bool = false) {
        self.result = result
        self.fails = fails
    }

    func searchFoodByBarcode(ean: String) async throws -> FoodSearchResult? {
        calls += 1
        if fails { throw GarminBarcodeUnavailable() }
        return result
    }
}

final class OfflineBarcodeFallbackTests: XCTestCase {
    private let holder = OfflineFoodIndexHolder(index: OfflineFoodIndex(products: offlineFixtureProducts()))

    /// spec "Czech product barcode": Garmin doesn't know it, the index does.
    func testGarminMissFallsBackToTheOfflineIndex() async throws {
        let garmin = ScriptedGarminBarcodeLookup()

        let food = try await BarcodeResolution.resolve(scannedCode: "8594001234567", using: garmin, offlineIndex: holder)

        XCTAssertEqual(food?.name, "Jihočeský tvaroh měkký", "shown by its Czech name")
        XCTAssertEqual(food?.source, .openFoodFacts, "so the caller routes it through the Garmin-match flow")
        let calls = await garmin.calls
        XCTAssertEqual(calls, 1, "Garmin is still asked first")
    }

    func testGarminHitWinsOverTheOfflineIndex() async throws {
        let result = try JSONDecoder().decode(FoodSearchResult.self, from: Data("""
        { "foodMetaData": { "foodId": "g-1", "foodName": "Tvaroh (Garmin)" }, "nutritionContents": [ { "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100 } ] }
        """.utf8))
        let garmin = ScriptedGarminBarcodeLookup(result: result)

        let food = try await BarcodeResolution.resolve(scannedCode: "8594001234567", using: garmin, offlineIndex: holder)

        XCTAssertEqual(food?.id, "g-1")
    }

    func testMissEverywhereIsStillUnresolved() async throws {
        let food = try await BarcodeResolution.resolve(scannedCode: "4006381333931", using: ScriptedGarminBarcodeLookup(), offlineIndex: holder)
        XCTAssertNil(food)
    }

    func testGarminFailureIsCoveredByAnOfflineHit() async throws {
        let food = try await BarcodeResolution.resolve(scannedCode: "8594001234567", using: ScriptedGarminBarcodeLookup(fails: true), offlineIndex: holder)
        XCTAssertEqual(food?.id, "8594001234567", "the offline index needs no network")
    }

    func testGarminFailureWithNoOfflineHitStillThrows() async {
        do {
            _ = try await BarcodeResolution.resolve(scannedCode: "4006381333931", using: ScriptedGarminBarcodeLookup(fails: true), offlineIndex: holder)
            XCTFail("a transient failure must not look like 'no product'")
        } catch {
            XCTAssertTrue(error is GarminBarcodeUnavailable)
        }
    }

    func testNoOfflineIndexKeepsTheOldBehaviour() async throws {
        let food = try await BarcodeResolution.resolve(scannedCode: "8594001234567", using: ScriptedGarminBarcodeLookup())
        XCTAssertNil(food)
    }
}

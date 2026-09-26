// SupplementBarcodeLookupTests.swift
//
// add-supplements task 5.3: the barcode prefill chain on fixture JSON (the
// shapes recorded in docs/supplement-data-sources.md, 2026-09-26) -- no
// live network. Open Food Facts first, DSLD only for US/Canada UPC-A codes
// in the spaced form, nothing (manual entry) when both miss or fail, and a
// successful result cached by barcode in a real store on a temp file.

import XCTest
@testable import FoodLogCore

final class SupplementBarcodeLookupTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("SupplementBarcodeLookupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    private func makeCache() -> SupplementBarcodeCache {
        SupplementBarcodeCache(fileURL: tempDirectory.appendingPathComponent("supplement-barcode-cache.json"))
    }

    /// Records requested URLs; answers by the first matching fragment.
    private final class FakeNetwork: @unchecked Sendable {
        var responses: [(fragment: String, body: String, status: Int)] = []
        var requested: [URL] = []
        var fails = false

        var fetch: SupplementBarcodeLookup.Fetch {
            { [self] url in
                requested.append(url)
                if fails { throw URLError(.notConnectedToInternet) }
                for response in responses where url.absoluteString.contains(response.fragment) {
                    return (Data(response.body.utf8), response.status)
                }
                return (Data(#"{"status":0}"#.utf8), 404)
            }
        }
    }

    private let offFound = #"""
    {"code":"4058172309250","status":1,"status_verbose":"product found",
     "product":{"product_name":"Magnesium","brands":"Mivolis, dm","quantity":"82 g","serving_size":"4.1 g"}}
    """#

    private let offOtherType = #"{"code":"0733739020307","status":0,"status_verbose":"product found with a different product type: beauty"}"#

    private let dsldSearch = #"{"hits":[{"_id":"205180","_source":{"fullName":"Creatine Monohydrate","brandName":"NOW Sports"}}],"stats":{"count":1}}"#

    private let dsldLabel = #"""
    {"id":205180,"fullName":"Creatine Monohydrate","brandName":"NOW Sports","upcSku":"7 33739 02030 7",
     "servingSizes":[{"order":1,"minQuantity":1.5,"maxQuantity":1.5,"unit":"tsp"}],
     "ingredientRows":[
       {"order":1,"name":"Creatine Monohydrate","ingredientGroup":"Creatine",
        "quantity":[{"servingSizeOrder":1,"quantity":5,"unit":"Gram(s)"}]},
       {"order":2,"name":"Mystery Blend","ingredientGroup":"Blend",
        "quantity":[{"servingSizeOrder":1,"quantity":1,"unit":"Gram(s)"}]}
     ]}
    """#

    // MARK: - Spaced UPC-A

    func testSpacedUPCAFromUPCAndLeadingZeroEAN() {
        XCTAssertEqual(SupplementBarcodeLookup.spacedUPCA("733739020307"), "7 33739 02030 7")
        XCTAssertEqual(SupplementBarcodeLookup.spacedUPCA("0733739020307"), "7 33739 02030 7")
        XCTAssertNil(SupplementBarcodeLookup.spacedUPCA("4058172309250"), "a European EAN-13 is not a US code")
        XCTAssertNil(SupplementBarcodeLookup.spacedUPCA("12345"))
    }

    // MARK: - Chain

    func testOpenFoodFactsNameAndBrandPrefill() async {
        let network = FakeNetwork()
        network.responses = [("openfoodfacts.org/api/v2/product/4058172309250", offFound, 200)]
        let lookup = SupplementBarcodeLookup(cache: makeCache(), fetch: network.fetch)

        let result = await lookup.lookup("4058172309250")

        XCTAssertEqual(result?.provider, .openFoodFacts)
        XCTAssertEqual(result?.name, "Magnesium")
        XCTAssertEqual(result?.brand, "Mivolis")
        XCTAssertEqual(result?.servingDescription, "4.1 g")
        XCTAssertEqual(result?.ingredients, [], "OFF amounts are never taken over (per 100 g, often missing)")
        XCTAssertFalse(network.requested.contains { $0.host == "api.ods.od.nih.gov" }, "no DSLD call for a European code")
    }

    func testUSCodeFallsBackToDSLDWithTheSpacedUPC() async {
        let network = FakeNetwork()
        network.responses = [
            ("openfoodfacts.org", offOtherType, 404),
            ("dsld/v9/search-filter", dsldSearch, 200),
            ("dsld/v9/label/205180", dsldLabel, 200),
        ]
        let lookup = SupplementBarcodeLookup(cache: makeCache(), fetch: network.fetch)

        let result = await lookup.lookup("0733739020307")

        XCTAssertEqual(result?.provider, .dsld)
        XCTAssertEqual(result?.name, "Creatine Monohydrate")
        XCTAssertEqual(result?.brand, "NOW Sports")
        XCTAssertEqual(result?.servingDescription, "1.5 tsp")
        XCTAssertEqual(result?.ingredients, [IngredientAmount(ingredient: .creatine, amount: 5, unit: .g)], "unknown ingredients are left for the user")
        let search = network.requested.first { $0.path.hasSuffix("search-filter") }
        XCTAssertEqual(URLComponents(url: search!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value, "\"7 33739 02030 7\"")
    }

    func testDSLDLabelWithAnotherUPCIsRejected() async {
        let network = FakeNetwork()
        network.responses = [
            ("openfoodfacts.org", offOtherType, 404),
            ("dsld/v9/search-filter", dsldSearch, 200),
            ("dsld/v9/label/205180", dsldLabel, 200),
        ]
        let lookup = SupplementBarcodeLookup(cache: makeCache(), fetch: network.fetch)

        // A different US code whose text search happened to hit the same label.
        let result = await lookup.lookup("012345678905")

        XCTAssertNil(result)
    }

    func testNothingFoundMeansManualEntry() async {
        let network = FakeNetwork()
        let lookup = SupplementBarcodeLookup(cache: makeCache(), fetch: network.fetch)

        let result = await lookup.lookup("8595011107548")

        XCTAssertNil(result)
    }

    func testNetworkFailureMeansManualEntryNotAnError() async {
        let network = FakeNetwork()
        network.fails = true
        let lookup = SupplementBarcodeLookup(cache: makeCache(), fetch: network.fetch)

        let result = await lookup.lookup("0733739020307")

        XCTAssertNil(result)
    }

    func testOpenFoodFactsWithoutANameIsNotAResult() {
        let body = #"{"status":1,"product":{"product_name":"","brands":"Vitar"}}"#
        XCTAssertNil(SupplementBarcodeLookup.parseOpenFoodFacts(Data(body.utf8), barcode: "8595011107548"))
    }

    // MARK: - Cache

    func testSuccessfulLookupIsCachedAndServedOffline() async {
        let cache = makeCache()
        let online = FakeNetwork()
        online.responses = [("openfoodfacts.org/api/v2/product/4058172309250", offFound, 200)]
        _ = await SupplementBarcodeLookup(cache: cache, fetch: online.fetch).lookup("4058172309250")

        // A fresh cache instance on the same file, and no network at all.
        let offline = FakeNetwork()
        offline.fails = true
        let reloaded = SupplementBarcodeCache(fileURL: tempDirectory.appendingPathComponent("supplement-barcode-cache.json"))
        let result = await SupplementBarcodeLookup(cache: reloaded, fetch: offline.fetch).lookup("4058172309250")

        XCTAssertEqual(result?.name, "Magnesium")
        XCTAssertTrue(offline.requested.isEmpty)
    }

    func testIngredientAndUnitMapping() {
        XCTAssertEqual(SupplementBarcodeLookup.ingredientID(group: "Vitamin D", name: "Vitamin D3"), .vitaminD)
        XCTAssertEqual(SupplementBarcodeLookup.ingredientID(group: "Fish Oil", name: "EPA (Eicosapentaenoic Acid)"), .omega3EPA_DHA)
        XCTAssertNil(SupplementBarcodeLookup.ingredientID(group: "Blend", name: "Mystery Blend"))
        XCTAssertNil(SupplementBarcodeLookup.ingredientID(group: "Botanical", name: "Ashwagandha"), "\"dha\" inside a word is not DHA")
        XCTAssertEqual(SupplementBarcodeLookup.doseUnit("Gram(s)"), .g)
        XCTAssertEqual(SupplementBarcodeLookup.doseUnit("mcg"), .ug)
        XCTAssertEqual(SupplementBarcodeLookup.doseUnit("IU"), .iu)
        XCTAssertNil(SupplementBarcodeLookup.doseUnit("capsule(s)"))
    }
}

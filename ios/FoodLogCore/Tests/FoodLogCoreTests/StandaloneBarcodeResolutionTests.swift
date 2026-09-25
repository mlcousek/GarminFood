// StandaloneBarcodeResolutionTests.swift
//
// add-standalone-mode 3.5 (design D5, standalone-food-catalog spec "Barcodes
// resolve without Garmin"): decoding the Open Food Facts product-by-barcode
// route from fixtures trimmed from the 2026-09-25 probe
// (docs/openfoodfacts-product-route.md), and the standalone chain -- own
// custom foods, then the offline index, then OFF, else nil (the custom-food
// editor). No live network: the OFF route is a recording fake, the custom
// foods live in a real store on a temp file, the index is a real holder.

import XCTest
@testable import FoodLogCore

final class StandaloneBarcodeResolutionTests: XCTestCase {
    // MARK: Fixtures (probed 2026-09-25)

    /// `GET /api/v2/product/8594003963391.json?fields=...` -> 200, trimmed.
    private let foundJSON = """
    {"code":"8594003963391","product":{"brands":"Billa, Polabské Mlékárny","code":"8594003963391","generic_name":"","nutriments":{"carbohydrates_100g":4,"carbohydrates_serving":10,"energy-kcal":67,"energy-kcal_100g":67,"energy-kcal_serving":168,"energy_100g":280,"fat_100g":0.5,"fat_serving":1.25,"proteins_100g":12,"proteins_serving":30,"saturated-fat_100g":0.200000002980232,"sugars_100g":4},"product_name":"Tvaroh odtučněný","product_name_cs":"Tvaroh odtučněný","quantity":"250 g","serving_quantity":250,"serving_size":"250.0g"},"status":1,"status_verbose":"product found"}
    """

    /// `8594003849149` -> 404 with this body.
    private let notFoundJSON = """
    {"code":"8594003849149","status":0,"status_verbose":"product not found"}
    """

    /// `0000000000000` -> 200 with this body.
    private let invalidCodeJSON = """
    {"code":"00000000","status":0,"status_verbose":"no code or invalid code"}
    """

    // MARK: Decoding

    func testDecodesAFoundProductAsTheSameFoodSearchWouldGive() throws {
        let food = try XCTUnwrap(OpenFoodFactsClient.decodeProduct(Data(foundJSON.utf8)))

        XCTAssertEqual(food.id, "8594003963391")
        XCTAssertEqual(food.name, "Tvaroh odtučněný")
        XCTAssertEqual(food.brandName, "Billa, Polabské Mlékárny")
        XCTAssertEqual(food.source, .openFoodFacts)
        let serving = try XCTUnwrap(food.servings.first)
        XCTAssertEqual(food.servings.count, 1)
        XCTAssertEqual(serving.id, "100g")
        XCTAssertEqual(serving.numberOfUnits, 100)
        XCTAssertEqual(serving.calories, 67, "per 100 g, never the per-serving 168")
        XCTAssertEqual(serving.carbs, 4)
        XCTAssertEqual(serving.protein, 12)
        XCTAssertEqual(serving.fat, 0.5)
    }

    func testNotFoundAndInvalidBodiesMeanNoProduct() throws {
        XCTAssertNil(try OpenFoodFactsClient.decodeProduct(Data(notFoundJSON.utf8)))
        XCTAssertNil(try OpenFoodFactsClient.decodeProduct(Data(invalidCodeJSON.utf8)))
    }

    func testTheTopLevelCodeFillsInAProductWithoutOne() throws {
        let json = #"{"code":"8594003963391","status":1,"product":{"product_name":"Tvaroh","lang":"cs","nutriments":{"energy-kcal_100g":67}}}"#
        let food = try XCTUnwrap(OpenFoodFactsClient.decodeProduct(Data(json.utf8)))
        XCTAssertEqual(food.id, "8594003963391")
    }

    func testAnUndecodableBodyThrowsRatherThanMeaningNoProduct() {
        XCTAssertThrowsError(try OpenFoodFactsClient.decodeProduct(Data("<html>503</html>".utf8)))
    }

    func testAnImplausibleCodeReturnsNilWithoutARequest() async throws {
        let client = OpenFoodFactsClient(legacyBaseURL: "http://127.0.0.1:1")
        let empty = try await client.product(barcode: "  ")
        let tooShort = try await client.product(barcode: "123")
        let letters = try await client.product(barcode: "85940039ABCDE")
        XCTAssertNil(empty)
        XCTAssertNil(tooShort)
        XCTAssertNil(letters)
    }

    // MARK: Chain

    private actor FakeProductLookup: OpenFoodFactsProductLookup {
        private let foodsByCode: [String: Food]
        private let failure: OpenFoodFactsError?
        private(set) var queried: [String] = []

        init(foodsByCode: [String: Food] = [:], failure: OpenFoodFactsError? = nil) {
            self.foodsByCode = foodsByCode
            self.failure = failure
        }

        func product(barcode: String) async throws -> Food? {
            queried.append(barcode)
            if let failure { throw failure }
            return foodsByCode[barcode]
        }
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("standalone-barcode-\(name)-\(UUID().uuidString).json")
    }

    private let offlineHolder = OfflineFoodIndexHolder(index: OfflineFoodIndex(products: [
        OfflineIndexProduct(code: "8594001234567", name: "Jihočeský tvaroh měkký", brand: "Madeta", kcal: 102, carbs: 3.5, protein: 17, fat: 0.5),
        OfflineIndexProduct(code: "012345678905", name: "Arašídové máslo", kcal: 600),
    ]))

    private func liveTvaroh() throws -> Food {
        try XCTUnwrap(OpenFoodFactsClient.decodeProduct(Data(foundJSON.utf8)))
    }

    /// Spec "Czech product in the offline index": no network request.
    func testTheOfflineIndexAnswersWithoutTheNetwork() async throws {
        let lookup = FakeProductLookup()

        let match = try await StandaloneBarcodeResolution.resolve(scannedCode: "8594001234567", customFoods: [], offlineIndex: offlineHolder, productLookup: lookup)

        guard case .product(let food)? = match else { return XCTFail("expected the offline product, got \(String(describing: match))") }
        XCTAssertEqual(food.name, "Jihočeský tvaroh měkký")
        let queried = await lookup.queried
        XCTAssertTrue(queried.isEmpty)
    }

    func testAZeroPaddedUPCAFindsTheOfflineProduct() async throws {
        let match = try await StandaloneBarcodeResolution.resolve(scannedCode: "0012345678905", customFoods: [], offlineIndex: offlineHolder, productLookup: nil)
        guard case .product(let food)? = match else { return XCTFail("expected a product") }
        XCTAssertEqual(food.id, "012345678905")
    }

    func testOpenFoodFactsIsAskedWhenTheIndexMisses() async throws {
        let tvaroh = try liveTvaroh()
        let lookup = FakeProductLookup(foodsByCode: ["8594003963391": tvaroh])

        let match = try await StandaloneBarcodeResolution.resolve(scannedCode: "8594003963391", customFoods: [], offlineIndex: offlineHolder, productLookup: lookup)

        XCTAssertEqual(match, .product(tvaroh))
    }

    /// "Scanning this barcode later finds this food": her own custom food
    /// wins over every other source.
    func testHerOwnCustomFoodWithTheBarcodeComesFirst() async throws {
        let store = CustomFoodStore(fileURL: tempURL("custom"))
        let buchty = CustomFoodDraft(name: "Babiččiny buchty", servingUnit: "kus", numberOfUnits: 1, calories: 280, barcode: "8594003963391")
        _ = try await store.upsert(buchty)
        _ = try await store.upsert(CustomFoodDraft(name: "Bez kódu", servingUnit: "kus", numberOfUnits: 1, calories: 100))
        let tvaroh = try liveTvaroh()
        let lookup = FakeProductLookup(foodsByCode: ["8594003963391": tvaroh])
        let customFoods = await store.all()

        let match = try await StandaloneBarcodeResolution.resolve(scannedCode: " 8594003963391 ", customFoods: customFoods, offlineIndex: offlineHolder, productLookup: lookup)

        XCTAssertEqual(match, .customFood(buchty))
        let queried = await lookup.queried
        XCTAssertTrue(queried.isEmpty)
    }

    /// Spec "Unknown barcode": nil, so the custom-food editor opens.
    func testFoundNowhereIsNil() async throws {
        let lookup = FakeProductLookup()

        let match = try await StandaloneBarcodeResolution.resolve(scannedCode: "8594003849149", customFoods: [], offlineIndex: offlineHolder, productLookup: lookup)

        XCTAssertNil(match)
        let queried = await lookup.queried
        XCTAssertEqual(queried, ["8594003849149"])
    }

    /// A network failure is not "no product".
    func testAnOpenFoodFactsFailureThrows() async {
        let lookup = FakeProductLookup(failure: OpenFoodFactsError.httpError(statusCode: 503, body: nil))
        do {
            _ = try await StandaloneBarcodeResolution.resolve(scannedCode: "8594003849149", customFoods: [], offlineIndex: offlineHolder, productLookup: lookup)
            XCTFail("expected the failure to propagate")
        } catch {
            XCTAssertEqual(error as? OpenFoodFactsError, .httpError(statusCode: 503, body: nil))
        }
    }
}

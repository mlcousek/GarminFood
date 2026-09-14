// BarcodeResolutionTests.swift
//
// Barcode normalisation and resolution tests (design.md D3, tasks 14.1-14.2;
// food-catalog spec's UPC-A/EAN-13 and "cannot be resolved" scenarios). No
// VisionKit, no network -- `BarcodeFoodLookup` is faked.

import XCTest
@testable import FoodLogCore
import GarminKit

final class BarcodeResolutionTests: XCTestCase {
    // MARK: - Normalisation

    func testThirteenDigitCodeWithLeadingZeroYieldsBothCandidates() {
        let candidates = BarcodeNormalization.candidates(forScanned: "0012345678905")
        XCTAssertEqual(candidates, ["0012345678905", "012345678905"])
    }

    func testThirteenDigitCodeWithoutLeadingZeroYieldsOnlyItself() {
        let candidates = BarcodeNormalization.candidates(forScanned: "8594001020010")
        XCTAssertEqual(candidates, ["8594001020010"])
    }

    func testNonThirteenDigitCodeYieldsOnlyItself() {
        XCTAssertEqual(BarcodeNormalization.candidates(forScanned: "12345678"), ["12345678"]) // EAN-8
    }

    // MARK: - Resolution

    private actor FakeLookup: BarcodeFoodLookup {
        private let resultsByEAN: [String: FoodSearchResult?]
        private(set) var queriedEANs: [String] = []

        init(resultsByEAN: [String: FoodSearchResult?]) {
            self.resultsByEAN = resultsByEAN
        }

        func searchFoodByBarcode(ean: String) async throws -> FoodSearchResult? {
            queriedEANs.append(ean)
            return resultsByEAN[ean] ?? nil
        }
    }

    private func decodeSearchResult(_ json: String) throws -> FoodSearchResult {
        try JSONDecoder().decode(FoodSearchResult.self, from: Data(json.utf8))
    }

    func testResolvesUsingTheLeadingZeroStrippedCandidateWhenTheAsIsCodeFails() async throws {
        let result = try decodeSearchResult("""
        { "foodMetaData": { "foodId": "1", "foodName": "Found" }, "nutritionContents": [ { "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100 } ] }
        """)
        let lookup = FakeLookup(resultsByEAN: ["012345678905": result])

        let food = try await BarcodeResolution.resolve(scannedCode: "0012345678905", using: lookup)

        XCTAssertEqual(food?.id, "1")
        let queried = await lookup.queriedEANs
        XCTAssertEqual(queried, ["0012345678905", "012345678905"], "the as-is code must be tried before the stripped one")
    }

    func testUnresolvedBarcodeReturnsNilRatherThanThrowing() async throws {
        let lookup = FakeLookup(resultsByEAN: [:])

        let food = try await BarcodeResolution.resolve(scannedCode: "8594001020010", using: lookup)

        XCTAssertNil(food, "the food-catalog spec treats an unresolved barcode as an offer to create a custom food, not an error")
    }
}

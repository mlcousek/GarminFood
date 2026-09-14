// BarcodeResolution.swift
//
// Barcode-to-food resolution (design.md D3, tasks 14.1-14.2). Deliberately
// minimal: per D3, barcode scanning is DEPRIORITIZED (Garmin's own native
// scanner fails to recognise Czech product barcodes -- owner-confirmed
// 2026-09-14, docs/garmin-food-log-contract.md), so this is a correct,
// functional implementation, not a polished one.
//
// `VNBarcodeSymbology` has no `.upcA` case -- a UPC-A barcode is reported by
// VisionKit as a 13-digit EAN-13 string with a leading zero (design.md D3 /
// food-catalog spec's "A UPC-A product barcode is scanned" scenario). This
// file's normalisation step is pure and unit-testable without any VisionKit
// dependency at all; the actual `DataScannerViewController` UI lives in the
// app target (VisionKit requires UIKit, which this package deliberately
// never imports).

import Foundation
import GarminKit

public enum BarcodeNormalization {
    /// Candidates to try, in order: the scanned code as-is, then (only if it
    /// looks like a zero-padded UPC-A: exactly 13 digits, leading zero) the
    /// 12-digit code with that zero stripped.
    public static func candidates(forScanned code: String) -> [String] {
        var results = [code]
        if code.count == 13, code.hasPrefix("0") {
            results.append(String(code.dropFirst()))
        }
        return results
    }
}

/// The subset of `GarminClient` barcode resolution needs -- same
/// testability rationale as `FoodSearching`.
public protocol BarcodeFoodLookup: Sendable {
    /// `GET /nutrition-service/food/search/barCode?barCode={ean}` (route
    /// confirmed to exist 2026-09-14; success payload shape UNCONFIRMED --
    /// see `GarminClient.searchFoodByBarcode`'s doc comment). Returns `nil`
    /// for "no product for this barcode" (a 404), distinct from throwing on
    /// a genuine failure.
    func searchFoodByBarcode(ean: String) async throws -> FoodSearchResult?
}

extension GarminClient: BarcodeFoodLookup {}

public enum BarcodeResolution {
    /// Tries every normalisation candidate in order, returning the first
    /// food resolved. `nil` means genuinely unresolved -- the food-catalog
    /// spec's "offer custom-food creation" scenario, not an error condition.
    public static func resolve(scannedCode: String, using lookup: some BarcodeFoodLookup) async throws -> Food? {
        for candidate in BarcodeNormalization.candidates(forScanned: scannedCode) {
            if let result = try await lookup.searchFoodByBarcode(ean: candidate), let food = Food(searchResult: result) {
                return food
            }
        }
        return nil
    }
}

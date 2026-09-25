// StandaloneBarcodeResolution.swift
//
// The barcode chain for standalone mode (add-standalone-mode D5, task 3.5,
// standalone-food-catalog spec "Barcodes resolve without Garmin"). Garmin
// mode keeps `BarcodeResolution.resolve` (Garmin first, then the offline
// index) unchanged; this is the path for a phone with no Garmin at all:
//   1. her own custom foods, by the barcode saved on them (the custom-food
//      editor says "Scanning this barcode later finds this food") -- no
//      network;
//   2. the offline Czech index -- no network (spec "Czech product in the
//      offline index": its serving picker opens without any request);
//   3. Open Food Facts' product-by-barcode route (probed 2026-09-25,
//      docs/openfoodfacts-product-route.md), read-only;
//   4. `nil`: the caller opens the custom-food editor with the code filled
//      in (spec "Unknown barcode").
// Every step tries `BarcodeNormalization.candidates` (a zero-padded UPC-A is
// also tried without its leading zero). A step-3 failure (offline, 5xx)
// THROWS rather than returning `nil`, so a transient failure is never read
// as "no product" -- the scan screen then offers retry or a custom food.
//
// Pure orchestration over three seams; the app wires the real stores/index/
// `OpenFoodFactsClient`. Tested by StandaloneBarcodeResolutionTests.

import Foundation

public enum StandaloneBarcodeMatch: Sendable, Equatable {
    /// One of her own custom foods carries this barcode.
    case customFood(CustomFoodDraft)
    /// An Open Food Facts product (offline index or the live route), logged
    /// as itself in standalone mode.
    case product(Food)
}

public enum StandaloneBarcodeResolution {
    public static func resolve(
        scannedCode: String,
        customFoods: [CustomFoodDraft],
        offlineIndex: (any OfflineBarcodeLookup)?,
        productLookup: (any OpenFoodFactsProductLookup)?
    ) async throws -> StandaloneBarcodeMatch? {
        let code = scannedCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return nil }
        let candidates = BarcodeNormalization.candidates(forScanned: code)

        if let draft = customFood(matching: candidates, in: customFoods) {
            return .customFood(draft)
        }
        if let offlineIndex {
            for candidate in candidates {
                if let food = await offlineIndex.food(forBarcode: candidate) {
                    return .product(food)
                }
            }
        }
        if let productLookup {
            for candidate in candidates {
                if let food = try await productLookup.product(barcode: candidate) {
                    return .product(food)
                }
            }
        }
        return nil
    }

    /// The first custom food whose saved barcode is one of `candidates`
    /// (or whose own candidates include the scanned code), oldest first so
    /// the answer is stable when two share a code.
    static func customFood(matching candidates: [String], in customFoods: [CustomFoodDraft]) -> CustomFoodDraft? {
        let scanned = Set(candidates)
        return customFoods
            .sorted { $0.createdAt < $1.createdAt }
            .first { draft in
                guard let saved = draft.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty else { return false }
                return !scanned.isDisjoint(with: BarcodeNormalization.candidates(forScanned: saved))
            }
    }
}

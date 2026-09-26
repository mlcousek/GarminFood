// SupplementBarcodeLookup.swift
//
// add-supplements task 5.3 (design D7 "Barcode chain"): what a scanned
// supplement barcode can PREFILL in the product editor -- never more. The
// chain, probed read-only on 2026-09-26 (docs/supplement-data-sources.md):
//
// 1. Open Food Facts' product route (`/api/v2/product/{code}.json`): name
//    and brand. OFF files many supplements under other product types (a US
//    creatine came back 404 "found with a different product type: beauty")
//    and Czech entries rarely carry nutrients, so only name/brand/quantity
//    are taken from it.
// 2. NIH ODS DSLD, only for codes that are US/Canada UPC-A (12 digits, or
//    EAN-13 starting with 0): `search-filter?q="d ddddd ddddd d"` (the
//    spaced UPC-A form -- unspaced finds nothing) then `/label/{id}`: name,
//    brand, serving and per-serving ingredient amounts where the ingredient
//    maps to one this app knows.
// 3. Nothing found, or the network failed: `nil`, and the user types the
//    label in (manual entry). A lookup never throws to the UI.
//
// The user always confirms the amounts (D7). A successful result is cached
// by barcode in `supplement-barcode-cache.json`, so scanning the same pack
// again works offline. Lookups run from the editor's "Look up" action only,
// never on a confirm path (CLAUDE.md, zero-network-wait).
//
// The network is a `Fetch` closure so tests run on fixture JSON with no
// live calls.
//
// Depends on: SupplementModels, PersistedStoreLoading, SupplementStoreIO,
// OpenFoodFactsClient (User-Agent). Depended on by: the app's product
// editor. Tests: SupplementBarcodeLookupTests, StoreFixtureTests.

import Foundation
import GarminKit

/// What a barcode lookup can prefill.
public struct SupplementBarcodeResult: Codable, Sendable, Equatable {
    public enum Provider: String, Codable, Sendable {
        case openFoodFacts
        case dsld
    }

    public var barcode: String
    public var provider: Provider
    public var name: String
    public var brand: String?
    public var servingDescription: String?
    /// Per serving; empty when the source has none this app can map.
    public var ingredients: [IngredientAmount]

    public init(barcode: String, provider: Provider, name: String, brand: String? = nil, servingDescription: String? = nil, ingredients: [IngredientAmount] = []) {
        self.barcode = barcode
        self.provider = provider
        self.name = name
        self.brand = brand
        self.servingDescription = servingDescription
        self.ingredients = ingredients
    }

    private enum CodingKeys: String, CodingKey { case barcode, provider, name, brand, servingDescription, ingredients }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        barcode = try container.decode(String.self, forKey: .barcode)
        provider = (try? container.decode(Provider.self, forKey: .provider)) ?? .openFoodFacts
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        servingDescription = try container.decodeIfPresent(String.self, forKey: .servingDescription)
        ingredients = (try? container.decodeIfPresent([IngredientAmount].self, forKey: .ingredients)) ?? []
    }
}

/// Successful lookups by barcode (`supplement-barcode-cache.json`).
public actor SupplementBarcodeCache {
    private let fileURL: URL
    private var results: [String: SupplementBarcodeResult] = [:]
    private var loaded = false

    public init(fileURL: URL = SupplementBarcodeCache.defaultFileURL()) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        FoodLogCoreStorage.directory().appendingPathComponent("supplement-barcode-cache.json")
    }

    public func result(for barcode: String) -> SupplementBarcodeResult? {
        loadIfNeeded()
        return results[barcode]
    }

    /// Best effort: a cache that can't be written just isn't one.
    public func store(_ result: SupplementBarcodeResult) {
        loadIfNeeded()
        guard loaded else { return }
        var next = results
        next[result.barcode] = result
        let list = next.values.sorted { $0.barcode < $1.barcode }
        do {
            try SupplementStoreIO.write(list, to: fileURL, category: "SupplementBarcodeCache")
            results = next
        } catch {
            // Logged by SupplementStoreIO; the lookup result is still used.
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        let result = FoodLogCoreStorage.loadPersistedJSON([SupplementBarcodeResult].self, from: fileURL, decoder: JSONDecoder(), category: "SupplementBarcodeCache")
        results = Dictionary((result.value ?? []).map { ($0.barcode, $0) }, uniquingKeysWith: { _, last in last })
        loaded = !result.isUnreadable
    }
}

public struct SupplementBarcodeLookup: Sendable {
    /// GET `url`; returns the body and HTTP status.
    public typealias Fetch = @Sendable (URL) async throws -> (Data, Int)

    private let fetch: Fetch
    private let cache: SupplementBarcodeCache

    public init(cache: SupplementBarcodeCache, fetch: @escaping Fetch = SupplementBarcodeLookup.urlSessionFetch) {
        self.cache = cache
        self.fetch = fetch
    }

    /// The prefill for `rawCode`, or `nil` (manual entry).
    public func lookup(_ rawCode: String) async -> SupplementBarcodeResult? {
        let code = rawCode.filter(\.isNumber)
        guard code.count >= 8 else { return nil }
        if let cached = await cache.result(for: code) { return cached }

        var found: SupplementBarcodeResult?
        do {
            found = try await openFoodFacts(code)
        } catch {
            DiagnosticsLog.log(.warning, category: "SupplementBarcode", "Open Food Facts lookup failed: \(error.localizedDescription)")
        }
        if found == nil, let spaced = Self.spacedUPCA(code) {
            do {
                found = try await dsld(code: code, spacedUPC: spaced)
            } catch {
                DiagnosticsLog.log(.warning, category: "SupplementBarcode", "DSLD lookup failed: \(error.localizedDescription)")
            }
        }
        if let found { await cache.store(found) }
        return found
    }

    // MARK: - Open Food Facts

    func openFoodFacts(_ code: String) async throws -> SupplementBarcodeResult? {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,quantity,serving_size") else { return nil }
        let (data, status) = try await fetch(url)
        guard status == 200 else { return nil }
        return Self.parseOpenFoodFacts(data, barcode: code)
    }

    static func parseOpenFoodFacts(_ data: Data, barcode: String) -> SupplementBarcodeResult? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (root["status"] as? Int) == 1,
              let product = root["product"] as? [String: Any]
        else { return nil }
        let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
        let serving = (product["serving_size"] as? String) ?? (product["quantity"] as? String)
        return SupplementBarcodeResult(
            barcode: barcode,
            provider: .openFoodFacts,
            name: name,
            brand: brand?.isEmpty == true ? nil : brand,
            servingDescription: serving?.isEmpty == true ? nil : serving
        )
    }

    // MARK: - DSLD

    func dsld(code: String, spacedUPC: String) async throws -> SupplementBarcodeResult? {
        var components = URLComponents(string: "https://api.ods.od.nih.gov/dsld/v9/search-filter")
        components?.queryItems = [URLQueryItem(name: "q", value: "\"\(spacedUPC)\""), URLQueryItem(name: "size", value: "5")]
        guard let searchURL = components?.url else { return nil }
        let (searchData, searchStatus) = try await fetch(searchURL)
        guard searchStatus == 200, let id = Self.firstDSLDHit(searchData) else { return nil }
        guard let labelURL = URL(string: "https://api.ods.od.nih.gov/dsld/v9/label/\(id)") else { return nil }
        let (labelData, labelStatus) = try await fetch(labelURL)
        guard labelStatus == 200 else { return nil }
        return Self.parseDSLDLabel(labelData, barcode: code, expectedUPC: spacedUPC)
    }

    static func firstDSLDHit(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hits = root["hits"] as? [[String: Any]],
              let first = hits.first
        else { return nil }
        if let id = first["_id"] as? String { return id }
        if let id = first["_id"] as? Int { return String(id) }
        return nil
    }

    static func parseDSLDLabel(_ data: Data, barcode: String, expectedUPC: String) -> SupplementBarcodeResult? {
        guard let label = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = (label["fullName"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty
        else { return nil }
        // The search is a text match: only accept the label whose UPC is
        // the scanned one.
        if let upc = label["upcSku"] as? String, upc.filter(\.isNumber) != expectedUPC.filter(\.isNumber) {
            return nil
        }
        var serving: String?
        if let sizes = label["servingSizes"] as? [[String: Any]], let first = sizes.first,
           let quantity = first["minQuantity"] as? Double, let unit = first["unit"] as? String {
            serving = NumberDisplay.trimmed(quantity, maxFractionDigits: 2, locale: Locale(identifier: "en_US_POSIX")) + " " + unit
        }
        var ingredients: [IngredientAmount] = []
        for row in (label["ingredientRows"] as? [[String: Any]]) ?? [] {
            guard let ingredient = ingredientID(group: row["ingredientGroup"] as? String, name: row["name"] as? String),
                  let quantities = row["quantity"] as? [[String: Any]], let first = quantities.first,
                  let unit = doseUnit(first["unit"] as? String)
            else { continue }
            let amount = (first["quantity"] as? Double) ?? (first["quantity"] as? Int).map(Double.init)
            ingredients.append(IngredientAmount(ingredient: ingredient, amount: amount, unit: unit))
        }
        return SupplementBarcodeResult(
            barcode: barcode,
            provider: .dsld,
            name: name,
            brand: label["brandName"] as? String,
            servingDescription: serving,
            ingredients: ingredients
        )
    }

    /// DSLD's ingredient group (or name) to this app's ingredient ids.
    static func ingredientID(group: String?, name: String?) -> IngredientID? {
        let text = ((group ?? "") + " " + (name ?? "")).lowercased()
        let table: [(String, IngredientID)] = [
            ("creatine", .creatine), ("beta-alanine", .betaAlanine), ("beta alanine", .betaAlanine),
            ("magnesium", .magnesium), ("vitamin d", .vitaminD), ("vitamin c", .vitaminC), ("zinc", .zinc),
            ("vitamin b12", .vitaminB12), ("vitamin b6", .vitaminB6), ("iron", .iron), ("selenium", .selenium),
            ("caffeine", .caffeine), ("sodium", .sodium), ("potassium", .potassium), ("vitamin k", .vitaminK2),
            ("epa", .omega3EPA_DHA), ("dha", .omega3EPA_DHA), ("omega-3", .omega3EPA_DHA), ("omega 3", .omega3EPA_DHA),
        ]
        // Whole words only: "dha" must not match ashwagandha.
        return table.first { key, _ in
            text.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: key) + #"\b"#, options: .regularExpression) != nil
        }?.1
    }

    /// DSLD writes "Gram(s)", "mg", "mcg", "IU".
    static func doseUnit(_ raw: String?) -> DoseUnit? {
        switch raw?.lowercased() {
        case "gram(s)", "g", "gram", "grams": return .g
        case "mg", "milligram(s)": return .mg
        case "mcg", "µg", "ug", "microgram(s)", "mcg rae", "mcg dfe": return .ug
        case "iu": return .iu
        default: return nil
        }
    }

    /// The spaced UPC-A form DSLD matches ("7 33739 02030 7"), for a 12-digit
    /// UPC-A or an EAN-13 starting with 0; `nil` for any other code (DSLD is
    /// US market only).
    public static func spacedUPCA(_ code: String) -> String? {
        var digits = code.filter(\.isNumber)
        if digits.count == 13, digits.hasPrefix("0") { digits.removeFirst() }
        guard digits.count == 12 else { return nil }
        let chars = Array(digits)
        return String(chars[0]) + " " + String(chars[1...5]) + " " + String(chars[6...10]) + " " + String(chars[11])
    }

    // MARK: - Default network

    public static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(OpenFoodFactsClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

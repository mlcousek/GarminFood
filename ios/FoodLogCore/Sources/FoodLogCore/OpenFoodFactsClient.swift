// OpenFoodFactsClient.swift
//
// The Open Food Facts wire layer (add-czech-food-catalog, rebuilt by
// rebuild-food-search task 3.3). It only fetches and decodes; ranking is
// `SearchRanker`'s job and orchestration is `OpenFoodFactsSource`'s.
// Output is the same `Food`/`Serving` domain model Garmin results use, per
// the czech-food-catalog spec, plus the product's other names so a query
// can match a Czech product by its English name and vice versa.
//
// Endpoints, in order:
//   1. Search-a-licious, `GET https://search.openfoodfacts.org/search`
//      (probed read-only 2026-09-23, rebuild-food-search design.md):
//      public, no auth, 60-260 ms, Elasticsearch-backed. `q` takes Lucene
//      syntax, so the Czech-only filter is `countries_tags:"en:czech-
//      republic"` inside `q`. `brands` comes back as an ARRAY (the legacy
//      endpoint sends a comma-separated string); `product_name` is the
//      product's main-language name (Czech for most Czech products, whose
//      `lang` is "cs" -- `product_name_cs` was absent from every hit in 13
//      sampled queries for exactly that reason) and `product_name_en` /
//      `product_name_cs` appear when a translation exists.
//   2. The legacy `GET /cgi/search.pl` on world.openfoodfacts.org, as the
//      fallback whenever Search-a-licious errors. Still flaky: it returned
//      503 on 7 of 13 probes on 2026-09-23 (and throughout 2026-09-22).
// Both searches are diacritic-sensitive in practice, which is why
// `OpenFoodFactsSource` sends two spellings.
//
// The client-side `rerank` that used to live here (a two-bucket "name
// contains the whole term" partition, added 2026-09-22 after OFF's own
// ranking let the grocery brand "Rohlík" swamp real bread rolls) is gone:
// `SearchRanker` now weighs brand matches at half a name match for every
// source.
//
// 2026-09-22 (implement-micronutrients): every OFF `*_100g` numeric field is
// in OFF's raw base unit -- GRAMS, even for vitamins (live: `vitamin-d_100g:
// 3.4e-06` is 3.4 µg). `milligrams(fromGrams:)`/`micrograms(fromGrams:)`
// convert at decode time; this also fixed `sodium`, which used to be passed
// through as grams into a field documented as mg. OFF's calcium/iron are
// deliberately NOT mapped onto `Serving.calcium`/`.iron`, which hold
// Garmin's %-of-daily-value convention (see `Serving`'s header in Food.swift).
//
// User-Agent: OFF asks integrators to identify themselves. A descriptive UA
// got normal 200s from both endpoints on 2026-09-23; the 503s above hit a
// default curl UA just the same, so they are server load, not UA blocking.

import Foundation
import GarminKit

public enum OpenFoodFactsError: Error, Sendable, Equatable {
    case invalidURL
    case noHTTPResponse
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(description: String)
}

/// One decoded Open Food Facts product.
public struct OFFSearchHit: Sendable, Equatable {
    public let food: Food
    /// The product's other non-empty names (English, generic), for matching.
    public let alternateNames: [String]

    public init(food: Food, alternateNames: [String] = []) {
        self.food = food
        self.alternateNames = alternateNames
    }
}

/// The seam `OpenFoodFactsSource` (and its tests) depend on.
public protocol OpenFoodFactsSearching: Sendable {
    /// One page (up to 50) of products for `term`, optionally limited to
    /// products sold in Czechia. Never re-ranked.
    func search(term: String, czechOnly: Bool) async throws -> [OFFSearchHit]
}

public struct OpenFoodFactsClient: OpenFoodFactsSearching, Sendable {
    static let userAgent = "GarminFood - iOS - Version 1.0 - https://github.com/mlcousek/GarminFood"
    static let pageSize = 50
    static let czechCountryTag = "en:czech-republic"

    private let urlSession: URLSession
    private let searchALiciousBaseURL: String
    private let legacyBaseURL: String

    public init(
        urlSession: URLSession = .shared,
        searchALiciousBaseURL: String = "https://search.openfoodfacts.org",
        legacyBaseURL: String = "https://world.openfoodfacts.org"
    ) {
        self.urlSession = urlSession
        self.searchALiciousBaseURL = searchALiciousBaseURL
        self.legacyBaseURL = legacyBaseURL
    }

    /// Search-a-licious first; the legacy endpoint when it fails (czech-
    /// food-catalog spec "Primary endpoint down"). Cancellation is passed
    /// straight through, never treated as a failure to fall back from.
    public func search(term: String, czechOnly: Bool = true) async throws -> [OFFSearchHit] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            return try await searchALicious(term: trimmed, czechOnly: czechOnly)
        } catch {
            if Task.isCancelled || Self.isCancellation(error) { throw error }
            DiagnosticsLog.log(.warning, category: "OpenFoodFacts", "Search-a-licious failed, falling back to search.pl: \(error)")
            return try await searchLegacy(term: trimmed, czechOnly: czechOnly)
        }
    }

    /// `GET /search?q=<term>[ countries_tags:"en:czech-republic"]&langs=cs,en&page_size=50&fields=...`
    func searchALicious(term: String, czechOnly: Bool) async throws -> [OFFSearchHit] {
        guard var components = URLComponents(string: searchALiciousBaseURL + "/search") else {
            throw OpenFoodFactsError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: Self.searchALiciousQuery(term: term, czechOnly: czechOnly)),
            URLQueryItem(name: "langs", value: "cs,en"),
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_cs,product_name_en,generic_name,generic_name_cs,lang,brands,quantity,nutriments")
        ]
        guard let url = components.url else { throw OpenFoodFactsError.invalidURL }
        let data = try await fetch(url)
        return try Self.decodeSearchALicious(data)
    }

    /// `GET /cgi/search.pl?search_terms={term}&json=1&page_size=50&fields=...`,
    /// with the `tagtype_0=countries` filter when `czechOnly` (confirmed live
    /// 2026-09-16: "tvaroh" -> 134 Czech products).
    func searchLegacy(term: String, czechOnly: Bool) async throws -> [OFFSearchHit] {
        guard var components = URLComponents(string: legacyBaseURL + "/cgi/search.pl") else {
            throw OpenFoodFactsError.invalidURL
        }
        var query = [
            URLQueryItem(name: "search_terms", value: term),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(Self.pageSize)),
            URLQueryItem(name: "fields", value: "code,product_name,product_name_cs,generic_name_cs,lang,brands,nutriments,quantity")
        ]
        if czechOnly {
            query.append(contentsOf: [
                URLQueryItem(name: "tagtype_0", value: "countries"),
                URLQueryItem(name: "tag_contains_0", value: "contains"),
                URLQueryItem(name: "tag_0", value: "czech-republic")
            ])
        }
        components.queryItems = query
        guard let url = components.url else { throw OpenFoodFactsError.invalidURL }
        let data = try await fetch(url)
        return try Self.decodeLegacy(data)
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenFoodFactsError.noHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenFoodFactsError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8).map { String($0.prefix(300)) })
        }
        return data
    }

    /// Search-a-licious reads `q` as Lucene syntax: the user's words have
    /// every Lucene operator character removed so a stray ":" or quote
    /// can't turn into a field query or a syntax error.
    static func searchALiciousQuery(term: String, czechOnly: Bool) -> String {
        let operators = Set("+-!(){}[]^\"~*?:\\/&|")
        let cleaned = String(term.map { operators.contains($0) ? " " : $0 })
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return czechOnly ? "\(cleaned) countries_tags:\"\(czechCountryTag)\"" : cleaned
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    // MARK: - Decoding (pure, fixture-tested)

    /// The legacy `search.pl` shape (`{ count, products: [...] }`) as plain foods.
    static func decode(_ data: Data) throws -> [Food] {
        try decodeLegacy(data).map(\.food)
    }

    static func decodeLegacy(_ data: Data) throws -> [OFFSearchHit] {
        let decoded: OFFSearchResponse
        do {
            decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        } catch {
            throw OpenFoodFactsError.decodingFailed(description: String(describing: error))
        }
        return (decoded.products ?? []).compactMap(Self.hit(from:))
    }

    /// The Search-a-licious shape (`{ hits: [...], page, page_count, count, ... }`).
    static func decodeSearchALicious(_ data: Data) throws -> [OFFSearchHit] {
        let decoded: SearchALiciousResponse
        do {
            decoded = try JSONDecoder().decode(SearchALiciousResponse.self, from: data)
        } catch {
            throw OpenFoodFactsError.decodingFailed(description: String(describing: error))
        }
        return (decoded.hits ?? []).compactMap(Self.hit(from:))
    }

    /// Which name to show, best first: `product_name_cs`, the main
    /// `product_name` when the product's language is Czech, `generic_name_cs`,
    /// then any `product_name`/`product_name_en`/`generic_name`. The rest
    /// become alternate names for matching.
    static func names(for product: OFFProduct) -> (display: String, alternates: [String])? {
        func clean(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        let czechMainName = product.lang == "cs" ? clean(product.productName) : nil
        let ordered = [
            clean(product.productNameCs),
            czechMainName,
            clean(product.genericNameCs),
            clean(product.productName),
            clean(product.productNameEn),
            clean(product.genericName)
        ].compactMap { $0 }
        guard let display = ordered.first else { return nil }
        var alternates: [String] = []
        for name in ordered.dropFirst() where name != display && !alternates.contains(name) {
            alternates.append(name)
        }
        return (display, alternates)
    }

    /// Maps one OFF product into `Food` with a single implicit 100 g
    /// serving (OFF's `*_100g` fields). Skips products without a code or
    /// any usable name, mirroring `Food.init(searchResult:)`'s own rule.
    static func hit(from product: OFFProduct) -> OFFSearchHit? {
        guard let code = product.code, !code.isEmpty else { return nil }
        guard let names = names(for: product) else { return nil }

        let brand = product.brands?.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = product.nutriments
        let serving = Serving(
            id: "100g",
            unit: "g",
            numberOfUnits: 100,
            calories: n?.energyKcal100g,
            carbs: n?.carbohydrates100g,
            protein: n?.proteins100g,
            fat: n?.fat100g,
            fiber: n?.fiber100g,
            sugar: n?.sugars100g,
            saturatedFat: n?.saturatedFat100g,
            cholesterol: milligrams(fromGrams: n?.cholesterol100g),
            sodium: milligrams(fromGrams: n?.sodium100g),
            potassium: milligrams(fromGrams: n?.potassium100g),
            // vitaminA/vitaminC/calcium/iron deliberately not populated --
            // see this file's header.
            vitaminB1: milligrams(fromGrams: n?.vitaminB1_100g),
            vitaminB2: milligrams(fromGrams: n?.vitaminB2_100g),
            vitaminB3: milligrams(fromGrams: n?.vitaminB3_100g),
            vitaminB5: milligrams(fromGrams: n?.vitaminB5_100g),
            vitaminB6: milligrams(fromGrams: n?.vitaminB6_100g),
            vitaminB9: micrograms(fromGrams: n?.vitaminB9_100g),
            vitaminB12: micrograms(fromGrams: n?.vitaminB12_100g),
            vitaminD: micrograms(fromGrams: n?.vitaminD100g),
            vitaminE: milligrams(fromGrams: n?.vitaminE100g),
            vitaminK: micrograms(fromGrams: n?.vitaminK100g),
            magnesium: milligrams(fromGrams: n?.magnesium100g),
            zinc: milligrams(fromGrams: n?.zinc100g),
            phosphorus: milligrams(fromGrams: n?.phosphorus100g),
            selenium: micrograms(fromGrams: n?.selenium100g),
            copper: milligrams(fromGrams: n?.copper100g),
            manganese: milligrams(fromGrams: n?.manganese100g),
            iodine: micrograms(fromGrams: n?.iodine100g),
            omega3: milligrams(fromGrams: n?.omega3Fat100g),
            omega6: milligrams(fromGrams: n?.omega6Fat100g)
        )

        let food = Food(
            id: code,
            name: names.display,
            brandName: (brand?.isEmpty ?? true) ? nil : brand,
            source: .openFoodFacts,
            servings: [serving]
        )
        return OFFSearchHit(food: food, alternateNames: names.alternates)
    }

    private static func milligrams(fromGrams grams: Double?) -> Double? {
        grams.map { $0 * 1_000 }
    }

    private static func micrograms(fromGrams grams: Double?) -> Double? {
        grams.map { $0 * 1_000_000 }
    }
}

// MARK: - Wire format

/// Legacy `search.pl` (confirmed live 2026-09-16, "tvaroh").
struct OFFSearchResponse: Decodable, Sendable {
    let count: Int?
    let products: [OFFProduct]?
}

/// Search-a-licious (probed 2026-09-23). Only the fields this app reads;
/// the response also carries `aggregations`, `facets`, `debug`, `took` ...
struct SearchALiciousResponse: Decodable, Sendable {
    let hits: [OFFProduct]?
    let count: Int?
    let page: Int?
    let pageCount: Int?

    enum CodingKeys: String, CodingKey {
        case hits
        case count
        case page
        case pageCount = "page_count"
    }
}

/// One product, in either endpoint's shape. Every field is decoded
/// leniently: a single odd value (Search-a-licious sends `brands` as an
/// array, search.pl as a string) must never drop the whole product.
struct OFFProduct: Decodable, Sendable {
    let code: String?
    let productName: String?
    let productNameCs: String?
    let productNameEn: String?
    let genericName: String?
    let genericNameCs: String?
    let lang: String?
    let brands: String?
    let quantity: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case productNameCs = "product_name_cs"
        case productNameEn = "product_name_en"
        case genericName = "generic_name"
        case genericNameCs = "generic_name_cs"
        case lang
        case brands
        case quantity
        case nutriments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = Self.lenientString(container, .code)
        productName = Self.lenientString(container, .productName)
        productNameCs = Self.lenientString(container, .productNameCs)
        productNameEn = Self.lenientString(container, .productNameEn)
        genericName = Self.lenientString(container, .genericName)
        genericNameCs = Self.lenientString(container, .genericNameCs)
        lang = Self.lenientString(container, .lang)
        quantity = Self.lenientString(container, .quantity)
        if let list = try? container.decodeIfPresent([String].self, forKey: .brands) {
            let cleaned = list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            brands = cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
        } else {
            brands = Self.lenientString(container, .brands)
        }
        nutriments = try? container.decodeIfPresent(OFFNutriments.self, forKey: .nutriments)
    }

    /// A string, or a number rendered as a string (OFF has sent numeric
    /// barcodes), or nil for anything else.
    private static func lenientString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let number = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return String(number)
        }
        return nil
    }
}

/// Per-100g nutrient fields (note the hyphens -- `energy-kcal_100g`,
/// `saturated-fat_100g` -- unlike the underscore-only fields, exactly as
/// captured in design.md's Context section). Every field is optional per
/// task 27.1's "some products may be missing nutriments entirely, or
/// missing individual fields."
///
/// Numeric fields are decoded leniently (`Double` OR a numeric-looking
/// `String`) because Open Food Facts is well known, independent of this
/// project's own testing, to sometimes send `""` for a missing numeric
/// value instead of omitting the key or sending `null` -- a plain
/// `Double?` would fail the ENTIRE product's decode over one missing
/// field, which task 27.1/27.3's "handle all as optional" explicitly
/// rules out.
///
/// 2026-09-22 (implement-micronutrients): the vitamin/mineral/omega fields
/// below were added after auditing OFF's own published nutrient taxonomy
/// (`static.openfoodfacts.org/data/taxonomies/nutrients.json`) against what
/// this file already decoded -- OFF's real per-product `nutriments` object
/// is far richer than the handful of macros this struct captured before.
/// Field ids match that taxonomy exactly (e.g. `vitamin-b1`, `vitamin-pp`
/// for niacin/B3, `pantothenic-acid` for B5). `vitaminB1_100g` through
/// `vitaminD100g` were live-verified against a real product (a fortified
/// breakfast cereal) via this exact `search.pl` endpoint on 2026-09-22; the
/// rest are confirmed to exist with these ids/units by that same taxonomy
/// file but were not captured live in this session (OFF's anonymous-request
/// rate limit was hit while researching) -- see `Serving`'s header comment
/// in Food.swift for the full per-field citation. All remain optional and
/// silently absent for a product that doesn't declare them, same as every
/// other field here.
struct OFFNutriments: Decodable, Sendable {
    let energyKcal100g: Double?
    let carbohydrates100g: Double?
    let proteins100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?
    let saturatedFat100g: Double?
    let cholesterol100g: Double?
    let potassium100g: Double?
    let vitaminB1_100g: Double?
    let vitaminB2_100g: Double?
    let vitaminB3_100g: Double?
    let vitaminB5_100g: Double?
    let vitaminB6_100g: Double?
    let vitaminB9_100g: Double?
    let vitaminB12_100g: Double?
    let vitaminD100g: Double?
    let vitaminE100g: Double?
    let vitaminK100g: Double?
    let magnesium100g: Double?
    let zinc100g: Double?
    let phosphorus100g: Double?
    let selenium100g: Double?
    let copper100g: Double?
    let manganese100g: Double?
    let iodine100g: Double?
    let omega3Fat100g: Double?
    let omega6Fat100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case proteins100g = "proteins_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
        case saturatedFat100g = "saturated-fat_100g"
        case cholesterol100g = "cholesterol_100g"
        case potassium100g = "potassium_100g"
        case vitaminB1_100g = "vitamin-b1_100g"
        case vitaminB2_100g = "vitamin-b2_100g"
        case vitaminB3_100g = "vitamin-pp_100g"
        case vitaminB5_100g = "pantothenic-acid_100g"
        case vitaminB6_100g = "vitamin-b6_100g"
        case vitaminB9_100g = "vitamin-b9_100g"
        case vitaminB12_100g = "vitamin-b12_100g"
        case vitaminD100g = "vitamin-d_100g"
        case vitaminE100g = "vitamin-e_100g"
        case vitaminK100g = "vitamin-k_100g"
        case magnesium100g = "magnesium_100g"
        case zinc100g = "zinc_100g"
        case phosphorus100g = "phosphorus_100g"
        case selenium100g = "selenium_100g"
        case copper100g = "copper_100g"
        case manganese100g = "manganese_100g"
        case iodine100g = "iodine_100g"
        case omega3Fat100g = "omega-3-fat_100g"
        case omega6Fat100g = "omega-6-fat_100g"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        energyKcal100g = Self.lenientDouble(container, .energyKcal100g)
        carbohydrates100g = Self.lenientDouble(container, .carbohydrates100g)
        proteins100g = Self.lenientDouble(container, .proteins100g)
        fat100g = Self.lenientDouble(container, .fat100g)
        fiber100g = Self.lenientDouble(container, .fiber100g)
        sugars100g = Self.lenientDouble(container, .sugars100g)
        sodium100g = Self.lenientDouble(container, .sodium100g)
        saturatedFat100g = Self.lenientDouble(container, .saturatedFat100g)
        cholesterol100g = Self.lenientDouble(container, .cholesterol100g)
        potassium100g = Self.lenientDouble(container, .potassium100g)
        vitaminB1_100g = Self.lenientDouble(container, .vitaminB1_100g)
        vitaminB2_100g = Self.lenientDouble(container, .vitaminB2_100g)
        vitaminB3_100g = Self.lenientDouble(container, .vitaminB3_100g)
        vitaminB5_100g = Self.lenientDouble(container, .vitaminB5_100g)
        vitaminB6_100g = Self.lenientDouble(container, .vitaminB6_100g)
        vitaminB9_100g = Self.lenientDouble(container, .vitaminB9_100g)
        vitaminB12_100g = Self.lenientDouble(container, .vitaminB12_100g)
        vitaminD100g = Self.lenientDouble(container, .vitaminD100g)
        vitaminE100g = Self.lenientDouble(container, .vitaminE100g)
        vitaminK100g = Self.lenientDouble(container, .vitaminK100g)
        magnesium100g = Self.lenientDouble(container, .magnesium100g)
        zinc100g = Self.lenientDouble(container, .zinc100g)
        phosphorus100g = Self.lenientDouble(container, .phosphorus100g)
        selenium100g = Self.lenientDouble(container, .selenium100g)
        copper100g = Self.lenientDouble(container, .copper100g)
        manganese100g = Self.lenientDouble(container, .manganese100g)
        iodine100g = Self.lenientDouble(container, .iodine100g)
        omega3Fat100g = Self.lenientDouble(container, .omega3Fat100g)
        omega6Fat100g = Self.lenientDouble(container, .omega6Fat100g)
    }

    private static func lenientDouble(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let string = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(string)
        }
        return nil
    }
}

// OpenFoodFactsClient.swift
//
// The second search source (proposal.md / design.md D1-D2, task group 27):
// Open Food Facts's legacy free-text search endpoint, chosen specifically
// because it's the only OFF endpoint confirmed to support free-text search
// today -- the documented v2/v3 API is tag/field-filtered only, and the
// newer Search-a-licious replacement has no confirmed request/response
// shape yet (design.md D2). Confirmed live 2026-09-16: a country-filtered
// search for "tvaroh" returned 134 real Czech products (Pilos, Milko z
// Poděbrad) with full per-100g macros.
//
// Deliberately independent of `GarminClient`/`FoodCatalogSearch` -- this
// hits a completely different host with a completely different wire
// format -- but the OUTPUT is the same `Food`/`Serving` domain model
// `FoodCatalogSearch` already produces, per the czech-food-catalog spec's
// "decoded into the same Food/Serving shape... so the rest of the
// logging flow treats a Czech-database food identically once selected."
//
// 2026-09-22 (implement-micronutrients): re-verified live against this
// exact endpoint that OFF's real `nutriments` object is far richer than the
// handful of macros originally decoded here -- a fortified-cereal search
// result came back with real declared calcium, iron, vitamin B1/B2/B6,
// vitamin D and pantothenic acid (B5) values, none of which this file used
// to extract even though they were already present in every response. See
// `OFFNutriments`'s own header comment below for the full field list this
// pass adds, and `Serving`'s header comment in Food.swift for why some
// overlapping-sounding fields (calcium/iron) are deliberately NOT mapped
// from OFF despite existing in the response.
//
// =====================================================================
// UNCONFIRMED: the `User-Agent` header below needs live re-verification
// =====================================================================
// design.md's Context section, read carefully before touching `userAgent`:
// during this change's research (2026-09-16), sending a plain/default
// User-Agent worked, while a custom one containing certain strings
// appeared to trigger a block (an HTML challenge page came back instead of
// JSON). That result is NOT trusted as the long-term-correct answer --
// sending no identifying UA at all is not good citizenship on a public,
// donation-funded API OFF's own etiquette guidance explicitly asks
// integrators to identify themselves. `userAgent` below is written as a
// single named constant specifically so this can be flipped back to "no
// custom header" in one place if live device testing (not possible in
// this environment -- no network access here either) reconfirms the
// block. Matches this project's existing convention for flagging
// unverified assumptions loudly and in one place (see
// GarminKit/GarminAuthSession.swift's file header for the same pattern).

import Foundation

public enum OpenFoodFactsError: Error, Sendable, Equatable {
    case invalidURL
    case noHTTPResponse
    case httpError(statusCode: Int, body: String?)
    case decodingFailed(description: String)
}

/// The subset of behaviour `FoodCatalogView` needs -- exists so the UI
/// layer and tests can depend on a protocol rather than the concrete
/// network type, same rationale as GarminKit's `FoodSearching` seam.
public protocol OpenFoodFactsSearching: Sendable {
    func search(term: String, czechOnly: Bool) async throws -> [Food]
}

public struct OpenFoodFactsClient: OpenFoodFactsSearching, Sendable {
    /// UNCONFIRMED -- see this file's header. A descriptive UA per OFF's
    /// own etiquette guidance (name - platform - version - contact URL),
    /// not the actual live-tested value.
    static let userAgent = "GarminFood - iOS - Version 1.0 - https://github.com/mlcousek/GarminFood"

    private let urlSession: URLSession
    private let baseURL: String

    public init(urlSession: URLSession = .shared, baseURL: String = "https://world.openfoodfacts.org") {
        self.urlSession = urlSession
        self.baseURL = baseURL
    }

    /// `GET /cgi/search.pl?search_terms={term}&json=1&page_size=50&fields=...`,
    /// with `&tagtype_0=countries&tag_contains_0=contains&tag_0=czech-republic`
    /// appended when `czechOnly` is true (default, per task 27.2). `term` is
    /// URL-encoded automatically by `URLComponents`.
    ///
    /// 2026-09-21: `page_size` raised from 20 to 50 (the owner's own
    /// complaint: "the databases are not full") -- OFF's Czech-specific
    /// tagging is genuinely thin (~1,300 products manufactured-in-CZ at
    /// last count), so a search term that DOES have real matches was
    /// sometimes silently truncating them at the old cap. 50 stays well
    /// under what the legacy `search.pl` endpoint comfortably returns in
    /// one page without materially slowing the debounced per-keystroke
    /// search this feeds.
    public func search(term: String, czechOnly: Bool = true) async throws -> [Food] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: baseURL + "/cgi/search.pl") else {
            throw OpenFoodFactsError.invalidURL
        }
        var query = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "50"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,quantity")
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

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenFoodFactsError.noHTTPResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenFoodFactsError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8))
        }
        return try Self.decode(data)
    }

    /// Pure decoding, split out from `search(term:czechOnly:)` specifically
    /// so task 27.4 ("Unit test the response-decoding against a captured
    /// fixture... pure decoding logic, no network needed for the test
    /// itself") can call it directly with a hand-written JSON fixture.
    static func decode(_ data: Data) throws -> [Food] {
        let decoded: OFFSearchResponse
        do {
            decoded = try JSONDecoder().decode(OFFSearchResponse.self, from: data)
        } catch {
            throw OpenFoodFactsError.decodingFailed(description: String(describing: error))
        }
        return (decoded.products ?? []).compactMap(Self.food(from:))
    }

    /// Maps one OFF product into this package's `Food`/`Serving` shape as a
    /// single, implicit 100g serving -- OFF's `nutriments` fields are
    /// already per-100g-suffixed (`*_100g`), matching how Garmin's own
    /// servings are already modeled elsewhere in this codebase (task 27.3).
    /// Fails only when OFF's own required identifiers (`code`, a non-empty
    /// `product_name`) are unusable -- an unnamed/uncoded "product" isn't
    /// useful to show or later create in Garmin against, mirroring
    /// `Food.init(searchResult:)`'s own failure rule for Garmin results.
    ///
    /// 2026-09-22 (implement-micronutrients): every OFF `*_100g` numeric
    /// field is in OFF's own raw base SI unit -- **grams**, even for a
    /// nutrient whose natural display unit is mg or µg (confirmed live:
    /// `vitamin-d_100g: 3.4e-06` on a real captured 2026-09-22 product is
    /// 3.4 µg, not 3.4 g). `milligrams(fromGrams:)`/`micrograms(fromGrams:)`
    /// below convert at the point every new field is read. This also fixes
    /// a real latent bug in `sodium` (pre-existing field, not new): it used
    /// to pass OFF's raw grams straight into `Serving.sodium` uncoverted,
    /// while that field is documented (and Garmin's own reads confirm) as
    /// mg -- invisible until now only because nothing displayed a
    /// `Serving`'s own `sodium` anywhere in the app yet.
    private static func food(from product: OFFProduct) -> Food? {
        guard let code = product.code, !code.isEmpty else { return nil }
        guard let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }

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
            // Fixed 2026-09-22: was the raw OFF gram value, unconverted --
            // see this function's header comment.
            cholesterol: milligrams(fromGrams: n?.cholesterol100g),
            sodium: milligrams(fromGrams: n?.sodium100g),
            potassium: milligrams(fromGrams: n?.potassium100g),
            // vitaminA/vitaminC/calcium/iron deliberately NOT populated from
            // OFF here -- those four fields on `Serving` are documented
            // (Food.swift) as Garmin/FatSecret's %-of-daily-value
            // convention. OFF has no percent-DV nutrients at all, only
            // absolute per-100g values, so writing an OFF value into those
            // fields would silently swap the unit under the same field name
            // -- exactly the misleading-as-real data this project won't
            // ship. OFF's own calcium/iron DO exist in the raw response but
            // are intentionally left undecoded here for that reason.
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

        return Food(
            id: code,
            name: name,
            brandName: (brand?.isEmpty ?? true) ? nil : brand,
            source: .openFoodFacts,
            servings: [serving]
        )
    }

    private static func milligrams(fromGrams grams: Double?) -> Double? {
        grams.map { $0 * 1_000 }
    }

    private static func micrograms(fromGrams grams: Double?) -> Double? {
        grams.map { $0 * 1_000_000 }
    }
}

// MARK: - Wire format (confirmed live 2026-09-16, real captured "tvaroh" response)

struct OFFSearchResponse: Decodable, Sendable {
    let count: Int?
    let products: [OFFProduct]?
}

struct OFFProduct: Decodable, Sendable {
    let code: String?
    let productName: String?
    let brands: String?
    let quantity: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case quantity
        case nutriments
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

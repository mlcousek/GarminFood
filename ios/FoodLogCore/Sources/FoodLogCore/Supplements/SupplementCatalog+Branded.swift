// SupplementCatalog+Branded.swift
//
// add-custom-ingredients-and-owner-supplements: real products with their
// labels, so the owner adds what is actually in the cupboard in two taps
// instead of retyping every amount. The data is a bundled JSON file,
// Resources/branded-supplements.json, one entry per product, each read off
// its public product page (or the maker's page / the package leaflet when
// the shop page lacked it) and dated `verifiedOn`. The OpenSpec change
// lists every product with its source.
//
// Rules the data follows (design D4):
//   - amounts, forms, serving, pack size and quality facts are what the
//     page states; nothing is filled in from general knowledge -- a value
//     the page doesn't state is simply absent (`packServings` of the joint
//     powder, whose page gives only 700 g);
//   - `quality` holds FACTS the maker or seller states (lab protocols
//     published, a branded raw material, vegan, a registered medicine),
//     never a health claim and never an app certification: the editor's
//     certification toggles (design D7 of add-supplements) stay the user's
//     own check;
//   - `labelDetails` (en + cs) carries label facts that have no field of
//     their own, e.g. EPA and DHA separately where the row is their sum.
//
// Decoding is strict per entry (a malformed entry is a bug caught by
// BrandedSupplementCatalogTests), but a broken file never crashes the app:
// `branded` is then empty and the error is logged.
//
// Depends on: SupplementCatalog (CatalogProduct), SupplementModels
// (IngredientAmount, ProductForm, TimeSlot), GarminKit (DiagnosticsLog).
// Depended on by: the app's catalog picker, `SupplementCatalog.product(id:)`.
// Tests: BrandedSupplementCatalogTests.

import Foundation
import GarminKit

/// A fact about a product's quality as its maker or seller states it.
public struct QualityFact: Codable, Sendable, Equatable, Hashable {
    public struct Kind: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
        public let rawValue: String
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public init(stringLiteral value: String) { self.rawValue = value }

        public init(from decoder: Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }

        /// The maker publishes laboratory protocols (heavy metals,
        /// microbiology...).
        public static let labTested: Kind = "labTested"
        /// The maker states the product was tested at the DSHS Köln lab
        /// against the WADA prohibited list. Not a Kölner Liste listing.
        public static let dshsCologneTested: Kind = "dshsCologneTested"
        /// The maker links a safety certificate from the Czech National
        /// Institute of Public Health (SZÚ).
        public static let szuSafetyCertificate: Kind = "szuSafetyCertificate"
        public static let vegan: Kind = "vegan"
        public static let liposomal: Kind = "liposomal"
        /// Omega-3 in (re-esterified) triglyceride form.
        public static let triglycerideForm: Kind = "triglycerideForm"
        /// A stated oxidation limit; `detail` e.g. "TOTOX ≤ 10".
        public static let oxidationSpec: Kind = "oxidationSpec"
        /// A trademarked raw material; `detail` names it.
        public static let brandedRawMaterial: Kind = "brandedRawMaterial"
        /// A registered medicinal product; `detail` e.g. "SÚKL 0286435, Rx".
        public static let registeredMedicine: Kind = "registeredMedicine"

        public static let known: [Kind] = [
            .labTested, .dshsCologneTested, .szuSafetyCertificate, .vegan, .liposomal,
            .triglycerideForm, .oxidationSpec, .brandedRawMaterial, .registeredMedicine
        ]
    }

    public let kind: Kind
    /// Proper names / figures from the label, shown verbatim.
    public let detail: String?

    public init(kind: Kind, detail: String? = nil) {
        self.kind = kind
        self.detail = detail
    }

    /// One line for the catalog and the product's label section.
    public var text: String {
        let shown = self.detail ?? ""
        switch kind {
        case .labTested:
            return String(localized: "Lab-tested, protocols published by the maker", bundle: .module, comment: "Supplement quality fact stated by the maker.")
        case .dshsCologneTested:
            return String(localized: "Tested at the DSHS Köln lab against the WADA list (maker's statement)", bundle: .module, comment: "Supplement quality fact stated by the maker: an anti-doping test at the Cologne sports university lab.")
        case .szuSafetyCertificate:
            return String(localized: "Safety certificate from SZÚ (Czech public health institute)", bundle: .module, comment: "Supplement quality fact stated by the maker.")
        case .vegan:
            return String(localized: "Vegan (as stated)", bundle: .module, comment: "Supplement quality fact stated by the maker or seller.")
        case .liposomal:
            return String(localized: "Liposomal form", bundle: .module, comment: "Supplement quality fact: the active ingredient is enclosed in liposomes.")
        case .triglycerideForm:
            return String(localized: "Triglyceride form (rTG)", bundle: .module, comment: "Supplement quality fact: omega-3 oil in re-esterified triglyceride form.")
        case .oxidationSpec:
            return String(localized: "Oxidation limit: \(shown)", bundle: .module, comment: "Supplement quality fact: the maker's stated oxidation limit of a fish oil. %@ is e.g. TOTOX ≤ 10.")
        case .brandedRawMaterial:
            return String(localized: "Branded raw material: \(shown)", bundle: .module, comment: "Supplement quality fact: a trademarked ingredient. %@ is its name(s).")
        case .registeredMedicine:
            return String(localized: "Registered medicine: \(shown)", bundle: .module, comment: "Supplement quality fact: the product is a registered medicinal product, not a food supplement. %@ is the registry code.")
        default:
            return shown.isEmpty ? kind.rawValue : kind.rawValue + ": " + shown
        }
    }
}

/// A branded catalog product's pack facts and where they come from.
public struct CatalogLabel: Sendable, Equatable {
    public let brand: String
    /// As printed on the pack; never translated.
    public let productName: String
    public let barcode: String?
    /// Servings in a full pack; `nil` when the page doesn't state it.
    public let packServings: Double?
    /// Capsules/tablets/sachets in a full pack, when stated.
    public let packCount: Int?
    public let sourceURL: URL
    public let otherSources: [URL]
    public let quality: [QualityFact]
    /// `yyyy-MM-dd` the source was read.
    public let verifiedOn: String
    let labelDetailsEN: String?
    let labelDetailsCS: String?

    /// Label facts without a field of their own, in the app's language.
    public var labelDetails: String? {
        let czech = Bundle.module.preferredLocalizations.first?.hasPrefix("cs") == true
        return czech ? (labelDetailsCS ?? labelDetailsEN) : (labelDetailsEN ?? labelDetailsCS)
    }
}

/// One entry of branded-supplements.json.
struct BrandedCatalogEntry: Decodable {
    struct Serving: Decodable {
        let kind: String
        let count: Int?
        let grams: Double?
    }

    struct Details: Decodable {
        let en: String?
        let cs: String?
    }

    let id: String
    let brand: String
    let productName: String
    let form: ProductForm
    let serving: Serving
    let suggestedSlot: TimeSlot
    let ingredients: [IngredientAmount]
    let packServings: Double?
    let packCount: Int?
    let barcode: String?
    let sourceURL: String
    let otherSources: [String]?
    let quality: [QualityFact]?
    let labelDetails: Details?
    let verifiedOn: String

    enum EntryError: Error, Equatable {
        case badServing(String)
        case badURL(String)
    }

    func product() throws -> CatalogProduct {
        let servingValue: CatalogProduct.Serving
        switch (serving.kind, serving.count, serving.grams) {
        case ("units", let count?, _) where count > 0: servingValue = .units(count)
        case ("measure", _, let grams?) where grams > 0: servingValue = .measure(grams: grams)
        case ("sachet", _, let grams?) where grams > 0: servingValue = .sachet(grams: grams)
        default: throw EntryError.badServing(id)
        }
        guard let source = URL(string: sourceURL), source.scheme == "https" else { throw EntryError.badURL(id) }
        let others = try (otherSources ?? []).map { text -> URL in
            guard let url = URL(string: text), url.scheme == "https" else { throw EntryError.badURL(id) }
            return url
        }
        var product = CatalogProduct(
            id: id,
            form: form,
            serving: servingValue,
            ingredients: ingredients,
            suggestedSlot: suggestedSlot
        )
        product.label = CatalogLabel(
            brand: brand,
            productName: productName,
            barcode: barcode,
            packServings: packServings,
            packCount: packCount,
            sourceURL: source,
            otherSources: others,
            quality: quality ?? [],
            verifiedOn: verifiedOn,
            labelDetailsEN: labelDetails?.en,
            labelDetailsCS: labelDetails?.cs
        )
        return product
    }
}

struct BrandedCatalogFile: Decodable {
    let schemaVersion: Int
    let products: [BrandedCatalogEntry]
}

extension SupplementCatalog {
    static let brandedResourceName = "branded-supplements"

    /// The branded products, in file order; empty (and logged) when the
    /// bundled file can't be read.
    public static let branded: [CatalogProduct] = {
        do {
            guard let url = Bundle.module.url(forResource: brandedResourceName, withExtension: "json") else {
                DiagnosticsLog.log(.error, category: "SupplementCatalog", "branded-supplements.json is missing from the bundle")
                return []
            }
            return try decodeBranded(Data(contentsOf: url))
        } catch {
            DiagnosticsLog.log(.error, category: "SupplementCatalog", "could not read branded-supplements.json: \(error)")
            return []
        }
    }()

    /// Decodes a branded catalog file; throws on any malformed entry.
    static func decodeBranded(_ data: Data) throws -> [CatalogProduct] {
        try JSONDecoder().decode(BrandedCatalogFile.self, from: data).products.map { try $0.product() }
    }
}

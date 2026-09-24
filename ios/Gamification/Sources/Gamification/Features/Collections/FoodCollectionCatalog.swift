// FoodCollectionCatalog.swift
//
// add-food-collections design D2: the five collections (Czech Classics,
// Around the World, Fermented Friends, Rainbow, Czech Brands -- 85 entries)
// as static data. Each entry is discovered by ONE `FoodTag` (design D1):
// `dish.*` / `brand.*` from FoodLogCore's `FoodTag+Collections.swift`, the
// core `colour.*` tags for Rainbow. Only ids, emoji and tags live in Swift;
// every name, riddle hint and title is in the package's own
// `Collections.strings` table (en + cs), looked up by a semantic key
// (`entry.<id>.name`, `entry.<id>.hint`, `collection.<id>.title`).
//
// Why a separate `Collections` table instead of `Localizable.strings`:
// six wave-2 changes are built in parallel and each owns only its own
// files; ~200 collection strings appended to the shared table would
// conflict with every sibling. `CollectionsL10nTests` checks the two
// tables list the same keys and cover every catalog entry (the job
// tools/check-localizations.mjs does for `Localizable.strings`).
//
// Entry ids are persisted (CollectionsStore keys discoveries by them), so
// never rename one; add new entries freely.
//
// Depends on: FoodLogCore (FoodTag, FoodTag+Collections). Depended on by:
// CollectionsEvaluator, CollectionsBadges, FoodCollectionsFeature, the
// app's Progress/Collections screens.

import Foundation
import FoodLogCore

/// One discoverable item of a collection.
public struct FoodCollectionEntry: Sendable, Equatable, Hashable, Identifiable {
    /// Globally unique across collections; persisted.
    public let id: String
    public let collectionId: String
    public let emoji: String
    /// Any logged food carrying this tag discovers the entry.
    public let tag: FoodTag

    public init(id: String, collectionId: String, emoji: String, tag: FoodTag) {
        self.id = id
        self.collectionId = collectionId
        self.emoji = emoji
        self.tag = tag
    }

    /// Localized display name (shown only once discovered).
    public var name: String { CollectionsL10n.string("entry.\(id).name") }
    /// Localized riddle hint (shown while undiscovered).
    public var hint: String { CollectionsL10n.string("entry.\(id).hint") }
}

public struct FoodCollection: Sendable, Equatable, Identifiable {
    public let id: String
    /// SF Symbol for the section header and badges.
    public let symbol: String
    public let entries: [FoodCollectionEntry]
    /// Completion badges at these percentages (design D4).
    public let badgePercents: [Int]

    public init(id: String, symbol: String, entries: [FoodCollectionEntry], badgePercents: [Int]) {
        self.id = id
        self.symbol = symbol
        self.entries = entries
        self.badgePercents = badgePercents
    }

    public var title: String { CollectionsL10n.string("collection.\(id).title") }
    public var subtitle: String { CollectionsL10n.string("collection.\(id).subtitle") }
}

public enum FoodCollectionCatalog {
    public static let czechClassicsId = "czech-classics"
    public static let worldId = "world"
    public static let fermentedId = "fermented"
    public static let rainbowId = "rainbow"
    public static let czechBrandsId = "czech-brands"

    /// Discovered by one matching food OR by its parts on one day
    /// (`CollectionsEvaluator`).
    public static let veproKnedloZeloId = "vepro-knedlo-zelo"

    public static let all: [FoodCollection] = [czechClassics, world, fermented, rainbow, czechBrands]

    public static var allEntries: [FoodCollectionEntry] { all.flatMap(\.entries) }

    public static func collection(id: String) -> FoodCollection? {
        all.first { $0.id == id }
    }

    public static func entry(id: String) -> FoodCollectionEntry? {
        allEntries.first { $0.id == id }
    }

    // MARK: - Collections

    static let czechClassics = FoodCollection(
        id: czechClassicsId,
        symbol: "fork.knife",
        entries: entries(czechClassicsId, [
            ("svickova", "🍖", .dishSvickova),
            ("gulas", "🥘", .dishGulas),
            ("rizek", "🍗", .dishRizek),
            ("smazeny-syr", "🧀", .dishSmazenySyr),
            ("knedliky", "🍞", .dishKnedliky),
            ("bramboraky", "🥔", .dishBramboraky),
            ("koprovka", "🌿", .dishKoprovka),
            ("kulajda", "🍄", .dishKulajda),
            ("trdelnik", "🍩", .dishTrdelnik),
            ("buchty", "🥐", .dishBuchty),
            (veproKnedloZeloId, "🐷", .dishVeproKnedloZelo),
            ("tatarak", "🥩", .dishTatarak),
            ("utopenci", "🌭", .dishUtopenci),
            ("nakladany-hermelin", "🫙", .dishNakladanyHermelin),
            ("cesnecka", "🧄", .dishCesnecka),
            ("rajska", "🍅", .dishRajska),
            ("ovocne-knedliky", "🍑", .dishOvocneKnedliky),
            ("palacinky", "🥞", .dishPalacinky),
            ("chlebicek", "🥪", .dishChlebicek),
            ("bramboracka", "🍲", .dishBramboracka),
            ("segedin", "🥣", .dishSegedin),
            ("spanelsky-ptacek", "🐦", .dishSpanelskyPtacek),
            ("kolac", "🥧", .dishKolac),
            ("frgal", "🍐", .dishFrgal)
        ]),
        badgePercents: [25, 50, 100]
    )

    static let world = FoodCollection(
        id: worldId,
        symbol: "globe.europe.africa.fill",
        entries: entries(worldId, [
            ("sushi", "🍣", .dishSushi),
            ("ramen", "🍜", .dishRamen),
            ("curry", "🍛", .dishCurry),
            ("tikka-masala", "🌶️", .dishTikkaMasala),
            ("tacos", "🌮", .dishTacos),
            ("burrito", "🌯", .dishBurrito),
            ("pho", "🥢", .dishPho),
            ("pad-thai", "🥜", .dishPadThai),
            ("pizza", "🍕", .dishPizza),
            ("lasagne", "🍝", .dishLasagne),
            ("risotto", "🍚", .dishRisotto),
            ("gyros", "🫓", .dishGyros),
            ("souvlaki", "🍢", .dishSouvlaki),
            ("falafel", "🧆", .dishFalafel),
            ("hummus", "🫘", .dishHummus),
            ("kebab", "🥙", .dishKebab),
            ("paella", "🥘", .dishPaella),
            ("bibimbap", "🍳", .dishBibimbap),
            ("dim-sum", "🥟", .dishDimSum),
            ("croissant", "🥐", .dishCroissant),
            ("pierogi", "🥟", .dishPierogi),
            ("borscht", "🥣", .dishBorscht)
        ]),
        badgePercents: [25, 50, 100]
    )

    static let fermented = FoodCollection(
        id: fermentedId,
        symbol: "hourglass",
        entries: entries(fermentedId, [
            ("kefir", "🥛", .dishKefir),
            ("kysane-zeli", "🥬", .dishKysaneZeli),
            ("kimchi", "🌶️", .dishKimchi),
            ("jogurt", "🥄", .dishJogurt),
            ("kombucha", "🫖", .dishKombucha),
            ("miso", "🥣", .dishMiso),
            ("tempeh", "🫘", .dishTempeh),
            ("zakys", "🥛", .dishZakys),
            ("tvaruzky", "🧀", .dishTvaruzky),
            ("kvasaky", "🥒", .dishKvasaky),
            ("kvaskovy-chleb", "🍞", .dishKvaskovyChleb)
        ]),
        badgePercents: [25, 50, 100]
    )

    static let rainbow = FoodCollection(
        id: rainbowId,
        symbol: "paintpalette.fill",
        entries: entries(rainbowId, [
            ("rainbow-red", "🍓", .colourRed),
            ("rainbow-orange", "🥕", .colourOrange),
            ("rainbow-yellow", "🍌", .colourYellow),
            ("rainbow-green", "🥦", .colourGreen),
            ("rainbow-purple", "🍆", .colourPurple),
            ("rainbow-white", "🧄", .colourWhite)
        ]),
        // Six entries: a 25 % badge would be one and a half colours.
        badgePercents: [50, 100]
    )

    static let czechBrands = FoodCollection(
        id: czechBrandsId,
        symbol: "cart.fill",
        entries: entries(czechBrandsId, [
            ("brand-madeta", "🧈", .brandMadeta),
            ("brand-kunin", "🥛", .brandKunin),
            ("brand-tatra", "🥛", .brandTatra),
            ("brand-olma", "🥛", .brandOlma),
            ("brand-hollandia", "🥛", .brandHollandia),
            ("brand-pilos", "🧀", .brandPilos),
            ("brand-albert-quality", "🛒", .brandAlbertQuality),
            ("brand-penam", "🍞", .brandPenam),
            ("brand-opavia", "🍪", .brandOpavia),
            ("brand-orion", "🍫", .brandOrion),
            ("brand-kofola", "🥤", .brandKofola),
            ("brand-mattoni", "💧", .brandMattoni),
            ("brand-relax", "🧃", .brandRelax),
            ("brand-hame", "🥫", .brandHame),
            ("brand-vitana", "🍲", .brandVitana),
            ("brand-jihlavanka", "☕️", .brandJihlavanka),
            ("brand-kostelecke-uzeniny", "🥓", .brandKosteleckeUzeniny),
            ("brand-chocenska-mlekarna", "🥛", .brandChocenskaMlekarna),
            ("brand-pribinacek", "🍮", .brandPribinacek),
            ("brand-emco", "🥣", .brandEmco),
            ("brand-bonavita", "🌾", .brandBonavita),
            ("brand-semix", "🌰", .brandSemix)
        ]),
        badgePercents: [25, 50, 100]
    )

    private static func entries(_ collectionId: String, _ items: [(String, String, FoodTag)]) -> [FoodCollectionEntry] {
        items.map { item in
            FoodCollectionEntry(id: item.0, collectionId: collectionId, emoji: item.1, tag: item.2)
        }
    }
}

/// The `Collections.strings` table (see header). Internal lookups; the app
/// reads finished strings through `CollectionsText`.
enum CollectionsL10n {
    static let table = "Collections"

    static func string(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: table)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}

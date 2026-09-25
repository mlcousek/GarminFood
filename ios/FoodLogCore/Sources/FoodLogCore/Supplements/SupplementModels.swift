// SupplementModels.swift
//
// The supplement feature's data model (add-supplements D2): what a product
// contains, when it is planned (schedule + `effectiveFrom` history, D3) and
// what was actually taken (`IntakeRecord`). Pure values -- the JSON stores
// (SupplementPlanStore, SupplementIntakeStore) persist them, the evaluators
// (ScheduleEvaluator, IngredientTotals, StockProjection, LabelScore) read
// them. Garmin plays no part: supplements are local only (proposal
// non-goal), identical in Garmin and standalone mode.
//
// Decoding is deliberately tolerant, because every one of these lands in a
// store file and an undecodable file is quarantined (fix-silent-store-wipe):
//   - identifiers that a later build may extend (ingredient ids, units,
//     product forms, certification bodies, intake kinds) are "open enums":
//     a struct around the raw string, so an unknown value round-trips
//     instead of failing the whole file;
//   - enums with payloads (`TimeSlot`, `SchedulePattern`, `ProductSource`)
//     have hand-written coding with an explicit fallback for unknown kinds
//     (an unknown pattern is never due rather than guessed as daily);
//   - every field that isn't identity is Optional or has a default.
//
// Depended on by everything in Supplements/. Tests: SupplementModelsTests.

import Foundation

// MARK: - Open identifiers

/// A stable ingredient id (design D2). Built-in ids have an evidence card
/// (`EvidenceCatalog`); a custom product may use any other id.
public struct IngredientID: Hashable, Sendable, Codable, Comparable, ExpressibleByStringLiteral {
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

    public static func < (lhs: IngredientID, rhs: IngredientID) -> Bool { lhs.rawValue < rhs.rawValue }

    public static let creatine: IngredientID = "creatine"
    public static let magnesium: IngredientID = "magnesium"
    public static let vitaminD: IngredientID = "vitaminD"
    public static let vitaminC: IngredientID = "vitaminC"
    public static let zinc: IngredientID = "zinc"
    public static let omega3EPA_DHA: IngredientID = "omega3EPA_DHA"
    public static let vitaminB12: IngredientID = "vitaminB12"
    public static let iron: IngredientID = "iron"
    public static let selenium: IngredientID = "selenium"
    public static let vitaminB6: IngredientID = "vitaminB6"
    public static let caffeine: IngredientID = "caffeine"
    public static let betaAlanine: IngredientID = "betaAlanine"
    public static let sodium: IngredientID = "sodium"
    public static let potassium: IngredientID = "potassium"
    public static let vitaminK2: IngredientID = "vitaminK2"

    /// Every ingredient the app ships an evidence card for.
    public static let builtIn: [IngredientID] = [
        .creatine, .magnesium, .vitaminD, .vitaminC, .zinc, .omega3EPA_DHA, .vitaminB12, .iron,
        .selenium, .vitaminB6, .caffeine, .betaAlanine, .sodium, .potassium, .vitaminK2
    ]

    /// The unit daily totals and limits are kept in. An ingredient without
    /// a card counts in mg.
    public var canonicalUnit: DoseUnit {
        switch self {
        case .creatine, .betaAlanine: return .g
        case .vitaminD, .vitaminB12, .selenium, .vitaminK2: return .ug
        default: return .mg
        }
    }
}

/// A dose unit. Mass units convert freely; IU converts only for vitamin D
/// (40 IU = 1 µg, design D2).
public struct DoseUnit: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
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

    public static let g: DoseUnit = "g"
    public static let mg: DoseUnit = "mg"
    /// Stored as "ug" (plain ASCII); shown as "µg".
    public static let ug: DoseUnit = "ug"
    public static let iu: DoseUnit = "IU"

    /// The symbol shown next to a number. Unit symbols are the same in
    /// English and Czech; VoiceOver spells them out via the app's
    /// `SpokenUnits` (design D12).
    public var symbol: String {
        switch self {
        case .ug: return "µg"
        default: return rawValue
        }
    }

    /// Micrograms in one unit of a mass unit, `nil` for IU and unknowns.
    var microgramsPerUnit: Double? {
        switch self {
        case .g: return 1_000_000
        case .mg: return 1_000
        case .ug: return 1
        default: return nil
        }
    }

    /// Vitamin D: 40 IU = 1 µg.
    public static let vitaminDIUPerMicrogram: Double = 40

    /// `amount` of `ingredient` in `from` expressed in `to`, or `nil` when
    /// the two units can't be converted for this ingredient.
    public static func convert(_ amount: Double, of ingredient: IngredientID, from: DoseUnit, to: DoseUnit) -> Double? {
        if from == to { return amount }
        let micrograms: Double
        if let factor = from.microgramsPerUnit {
            micrograms = amount * factor
        } else if from == .iu, ingredient == .vitaminD {
            micrograms = amount / vitaminDIUPerMicrogram
        } else {
            return nil
        }
        if let factor = to.microgramsPerUnit { return micrograms / factor }
        if to == .iu, ingredient == .vitaminD { return micrograms * vitaminDIUPerMicrogram }
        return nil
    }
}

/// The chemical form of an ingredient where it matters (magnesium, design
/// D2: the EFSA supplemental limit is set for readily dissociable salts and
/// oxide). Stored as its raw string on `IngredientAmount.form`.
public struct MagnesiumForm: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let citrate = MagnesiumForm("citrate")
    public static let bisglycinate = MagnesiumForm("bisglycinate")
    public static let oxide = MagnesiumForm("oxide")
    public static let aspartate = MagnesiumForm("aspartate")
    public static let malate = MagnesiumForm("malate")
    public static let lactate = MagnesiumForm("lactate")
    public static let chloride = MagnesiumForm("chloride")
    public static let carbonate = MagnesiumForm("carbonate")
    public static let glycerophosphate = MagnesiumForm("glycerophosphate")
    public static let threonate = MagnesiumForm("threonate")
}

/// capsule, tablet, powder, liquid, gummy (design D2); open for later.
public struct ProductForm: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
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

    public static let capsule: ProductForm = "capsule"
    public static let tablet: ProductForm = "tablet"
    public static let powder: ProductForm = "powder"
    public static let liquid: ProductForm = "liquid"
    public static let gummy: ProductForm = "gummy"
}

/// The lists a user can check a product against (design D7).
public struct CertificationBody: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
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

    public static let nsfCertifiedForSport: CertificationBody = "nsfCertifiedForSport"
    public static let informedSport: CertificationBody = "informedSport"
    public static let koelnerListe: CertificationBody = "koelnerListe"
}

// MARK: - Product

/// One ingredient row of a product label, per serving.
public struct IngredientAmount: Codable, Sendable, Equatable, Hashable {
    public var ingredient: IngredientID
    /// `nil` when the label doesn't state the amount (lowers the label
    /// score's transparency part, never guessed).
    public var amount: Double?
    public var unit: DoseUnit
    /// e.g. `MagnesiumForm.citrate.rawValue`; `nil` when not stated.
    public var form: String?
    /// Display name for an ingredient without a built-in card.
    public var customName: String?

    public init(ingredient: IngredientID, amount: Double?, unit: DoseUnit, form: String? = nil, customName: String? = nil) {
        self.ingredient = ingredient
        self.amount = amount
        self.unit = unit
        self.form = form
        self.customName = customName
    }

    private enum CodingKeys: String, CodingKey { case ingredient, amount, unit, form, customName }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ingredient = try container.decode(IngredientID.self, forKey: .ingredient)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        unit = try container.decodeIfPresent(DoseUnit.self, forKey: .unit) ?? ingredient.canonicalUnit
        form = try container.decodeIfPresent(String.self, forKey: .form)
        customName = try container.decodeIfPresent(String.self, forKey: .customName)
    }

    /// The amount in the ingredient's canonical unit, `nil` when unstated
    /// or not convertible.
    public var canonicalAmount: Double? {
        guard let amount else { return nil }
        return DoseUnit.convert(amount, of: ingredient, from: unit, to: ingredient.canonicalUnit)
    }
}

/// A certification the USER set after checking the official list (design
/// D7). The app never claims one on its own.
public struct Certification: Codable, Sendable, Equatable, Hashable {
    public var body: CertificationBody
    /// `yyyy-MM-dd` the user checked the list.
    public var checkedOn: String

    public init(body: CertificationBody, checkedOn: String) {
        self.body = body
        self.checkedOn = checkedOn
    }
}

/// Where a product came from.
public enum ProductSource: Codable, Sendable, Equatable, Hashable {
    /// `SupplementCatalog` entry id.
    case catalog(String)
    case custom
    /// Lookup provider that prefilled it ("openFoodFacts", "dsld").
    case barcode(String)

    private enum CodingKeys: String, CodingKey { case kind, reference }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "custom"
        let reference = try container.decodeIfPresent(String.self, forKey: .reference) ?? ""
        switch kind {
        case "catalog": self = .catalog(reference)
        case "barcode": self = .barcode(reference)
        default: self = .custom
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .catalog(let id):
            try container.encode("catalog", forKey: .kind)
            try container.encode(id, forKey: .reference)
        case .custom:
            try container.encode("custom", forKey: .kind)
        case .barcode(let provider):
            try container.encode("barcode", forKey: .kind)
            try container.encode(provider, forKey: .reference)
        }
    }
}

/// A product in the user's stack (design D2).
public struct SupplementProduct: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var brand: String?
    public var barcode: String?
    public var form: ProductForm?
    /// Free text, e.g. "2 capsules" / "5 g scoop".
    public var servingDescription: String?
    /// Per serving.
    public var ingredients: [IngredientAmount]
    /// Names of proprietary blends listed WITHOUT per-ingredient amounts.
    public var proprietaryBlends: [String]?
    /// Servings in a full pack.
    public var packServings: Double?
    public var pricePerPack: Double?
    /// ISO 4217; `nil` means CZK (design D2 default).
    public var currency: String?
    public var certifications: [Certification]?
    public var notes: String?
    public var source: ProductSource?
    /// Servings on hand when the stock was last set or refilled...
    public var stockServings: Double?
    /// ...on this `yyyy-MM-dd` day. Intake dated before it doesn't drain the
    /// current pack (design D14).
    public var stockSetOn: String?
    /// The `stockSetOn` a restock reminder was already sent for -- at most
    /// one per pack (design D5).
    public var restockRemindedFor: String?

    public init(
        id: UUID = UUID(),
        name: String,
        brand: String? = nil,
        barcode: String? = nil,
        form: ProductForm? = nil,
        servingDescription: String? = nil,
        ingredients: [IngredientAmount],
        proprietaryBlends: [String]? = nil,
        packServings: Double? = nil,
        pricePerPack: Double? = nil,
        currency: String? = nil,
        certifications: [Certification]? = nil,
        notes: String? = nil,
        source: ProductSource? = nil,
        stockServings: Double? = nil,
        stockSetOn: String? = nil,
        restockRemindedFor: String? = nil
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.form = form
        self.servingDescription = servingDescription
        self.ingredients = ingredients
        self.proprietaryBlends = proprietaryBlends
        self.packServings = packServings
        self.pricePerPack = pricePerPack
        self.currency = currency
        self.certifications = certifications
        self.notes = notes
        self.source = source
        self.stockServings = stockServings
        self.stockSetOn = stockSetOn
        self.restockRemindedFor = restockRemindedFor
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, brand, barcode, form, servingDescription, ingredients, proprietaryBlends
        case packServings, pricePerPack, currency, certifications, notes, source
        case stockServings, stockSetOn, restockRemindedFor
    }

    /// Only `id` is required; everything else decodes as absent/empty.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
        form = try container.decodeIfPresent(ProductForm.self, forKey: .form)
        servingDescription = try container.decodeIfPresent(String.self, forKey: .servingDescription)
        ingredients = try container.decodeIfPresent([IngredientAmount].self, forKey: .ingredients) ?? []
        proprietaryBlends = try container.decodeIfPresent([String].self, forKey: .proprietaryBlends)
        packServings = try container.decodeIfPresent(Double.self, forKey: .packServings)
        pricePerPack = try container.decodeIfPresent(Double.self, forKey: .pricePerPack)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        certifications = try container.decodeIfPresent([Certification].self, forKey: .certifications)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        source = try container.decodeIfPresent(ProductSource.self, forKey: .source)
        stockServings = try container.decodeIfPresent(Double.self, forKey: .stockServings)
        stockSetOn = try container.decodeIfPresent(String.self, forKey: .stockSetOn)
        restockRemindedFor = try container.decodeIfPresent(String.self, forKey: .restockRemindedFor)
    }

    /// `currency` or the CZK default.
    public var effectiveCurrency: String { currency ?? "CZK" }
}

// MARK: - Schedule

/// A time of day items are taken at (design D2).
public enum TimeSlot: Hashable, Sendable, Codable, Comparable {
    case morning
    case withBreakfast
    case preWorkout
    case evening
    /// A user-named slot; `minute` of the day (0..<1440) when it has a time.
    case custom(name: String, minute: Int?)

    /// Stable identity, used in intake keys and notification ids.
    public var key: String {
        switch self {
        case .morning: return "morning"
        case .withBreakfast: return "withBreakfast"
        case .preWorkout: return "preWorkout"
        case .evening: return "evening"
        case .custom(let name, _): return "custom:" + name
        }
    }

    private var rank: Int {
        switch self {
        case .morning: return 0
        case .withBreakfast: return 1
        case .preWorkout: return 2
        case .evening: return 3
        case .custom: return 4
        }
    }

    /// Built-in slots in their fixed order, then custom slots by time, then
    /// by name.
    public static func < (lhs: TimeSlot, rhs: TimeSlot) -> Bool {
        if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
        if case .custom(let leftName, let leftMinute) = lhs, case .custom(let rightName, let rightMinute) = rhs {
            let left = leftMinute ?? Int.max
            let right = rightMinute ?? Int.max
            if left != right { return left < right }
            return leftName < rightName
        }
        return false
    }

    private enum CodingKeys: String, CodingKey { case kind, name, minute }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "custom"
        switch kind {
        case "morning": self = .morning
        case "withBreakfast": self = .withBreakfast
        case "preWorkout": self = .preWorkout
        case "evening": self = .evening
        case "custom":
            let name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            self = .custom(name: name, minute: try container.decodeIfPresent(Int.self, forKey: .minute))
        default:
            // A built-in slot added by a later build: kept as a named slot
            // with the same key text, so its records still group together.
            self = .custom(name: kind, minute: try container.decodeIfPresent(Int.self, forKey: .minute))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .morning: try container.encode("morning", forKey: .kind)
        case .withBreakfast: try container.encode("withBreakfast", forKey: .kind)
        case .preWorkout: try container.encode("preWorkout", forKey: .kind)
        case .evening: try container.encode("evening", forKey: .kind)
        case .custom(let name, let minute):
            try container.encode("custom", forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(minute, forKey: .minute)
        }
    }
}

/// One phase of a repeating cycle: `servingsPerSlot` (0 = an "off" phase)
/// for `days` days.
public struct CyclePhase: Codable, Sendable, Hashable {
    public var servingsPerSlot: Double
    public var days: Int

    public init(servingsPerSlot: Double, days: Int) {
        self.servingsPerSlot = servingsPerSlot
        self.days = days
    }

    private enum CodingKeys: String, CodingKey { case servingsPerSlot, days }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servingsPerSlot = try container.decodeIfPresent(Double.self, forKey: .servingsPerSlot) ?? 0
        days = try container.decodeIfPresent(Int.self, forKey: .days) ?? 0
    }
}

/// Which days a schedule plans (design D2/D3).
public enum SchedulePattern: Hashable, Sendable, Codable {
    case daily
    /// Due on `anchor` and every `n`-th day after it (nothing before it).
    case everyNDays(n: Int, anchor: String)
    /// `Calendar` weekday numbers, 1 = Sunday ... 7 = Saturday.
    case weekdays(Set<Int>)
    /// Days with a Garmin activity or a `race` day-note tag (D3).
    case trainingDays
    /// Phases in order from `anchor`. `repeats`: start over after the last
    /// phase ("8 weeks on, 4 off"); otherwise the last phase continues for
    /// good ("loading week, then maintenance"). Per-slot servings come
    /// from the phase, not from the schedule.
    case cycle(phases: [CyclePhase], anchor: String, repeats: Bool)
    /// A pattern written by a later build. Never due -- guessing "daily"
    /// would invent missed days.
    case unknown(String)

    private enum CodingKeys: String, CodingKey { case kind, n, anchor, weekdays, phases, repeats }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "daily"
        switch kind {
        case "daily":
            self = .daily
        case "everyNDays":
            self = .everyNDays(
                n: try container.decodeIfPresent(Int.self, forKey: .n) ?? 1,
                anchor: try container.decodeIfPresent(String.self, forKey: .anchor) ?? ""
            )
        case "weekdays":
            self = .weekdays(Set(try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? []))
        case "trainingDays":
            self = .trainingDays
        case "cycle":
            self = .cycle(
                phases: try container.decodeIfPresent([CyclePhase].self, forKey: .phases) ?? [],
                anchor: try container.decodeIfPresent(String.self, forKey: .anchor) ?? "",
                repeats: try container.decodeIfPresent(Bool.self, forKey: .repeats) ?? false
            )
        default:
            self = .unknown(kind)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode("daily", forKey: .kind)
        case .everyNDays(let n, let anchor):
            try container.encode("everyNDays", forKey: .kind)
            try container.encode(n, forKey: .n)
            try container.encode(anchor, forKey: .anchor)
        case .weekdays(let days):
            try container.encode("weekdays", forKey: .kind)
            try container.encode(days.sorted(), forKey: .weekdays)
        case .trainingDays:
            try container.encode("trainingDays", forKey: .kind)
        case .cycle(let phases, let anchor, let repeats):
            try container.encode("cycle", forKey: .kind)
            try container.encode(phases, forKey: .phases)
            try container.encode(anchor, forKey: .anchor)
            try container.encode(repeats, forKey: .repeats)
        case .unknown(let kind):
            try container.encode(kind, forKey: .kind)
        }
    }
}

/// When and how much of one product (design D2).
public struct SupplementSchedule: Codable, Sendable, Hashable {
    public var slots: [TimeSlot]
    public var servingsPerSlot: Double
    public var pattern: SchedulePattern

    public init(slots: [TimeSlot], servingsPerSlot: Double = 1, pattern: SchedulePattern = .daily) {
        self.slots = slots
        self.servingsPerSlot = servingsPerSlot
        self.pattern = pattern
    }

    private enum CodingKeys: String, CodingKey { case slots, servingsPerSlot, pattern }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slots = try container.decodeIfPresent([TimeSlot].self, forKey: .slots) ?? []
        servingsPerSlot = try container.decodeIfPresent(Double.self, forKey: .servingsPerSlot) ?? 1
        pattern = try container.decodeIfPresent(SchedulePattern.self, forKey: .pattern) ?? .daily
    }
}

/// A schedule in effect from `effectiveFrom` (inclusive) until the next
/// version. `schedule == nil`: not planned from that day (removed/paused).
public struct ScheduleVersion: Codable, Sendable, Hashable {
    public var effectiveFrom: String
    public var schedule: SupplementSchedule?

    public init(effectiveFrom: String, schedule: SupplementSchedule?) {
        self.effectiveFrom = effectiveFrom
        self.schedule = schedule
    }
}

/// One product's schedule history (design D3: edits apply from their day
/// forward; past days keep the schedule that was active then).
public struct PlanItem: Codable, Sendable, Equatable {
    public let productId: UUID
    /// Sorted by `effectiveFrom`, one version per day at most.
    public private(set) var versions: [ScheduleVersion]

    public init(productId: UUID, versions: [ScheduleVersion] = []) {
        self.productId = productId
        self.versions = Self.normalized(versions)
    }

    private enum CodingKeys: String, CodingKey { case productId, versions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productId = try container.decode(UUID.self, forKey: .productId)
        versions = Self.normalized(try container.decodeIfPresent([ScheduleVersion].self, forKey: .versions) ?? [])
    }

    /// The schedule active on `day`, or `nil` when nothing is planned then
    /// (before the first version, or after a removal).
    public func schedule(on day: String) -> SupplementSchedule? {
        versions.last(where: { $0.effectiveFrom <= day })?.schedule
    }

    /// Sets the schedule from `day` onward (a same-day edit replaces that
    /// day's version; later versions are dropped). No-op when the schedule
    /// already in effect on `day` is identical.
    public mutating func setSchedule(_ schedule: SupplementSchedule?, from day: String) {
        guard SupplementDate.ordinal(day) != nil else { return }
        var next = versions.filter { $0.effectiveFrom < day }
        if let previous = next.last {
            // Identical to what already runs: just drop later versions.
            if previous.schedule != schedule {
                next.append(ScheduleVersion(effectiveFrom: day, schedule: schedule))
            }
        } else if schedule != nil {
            next.append(ScheduleVersion(effectiveFrom: day, schedule: schedule))
        }
        versions = next
    }

    /// Valid days only, sorted, last version wins per day.
    private static func normalized(_ versions: [ScheduleVersion]) -> [ScheduleVersion] {
        var byDay: [String: ScheduleVersion] = [:]
        for version in versions where SupplementDate.ordinal(version.effectiveFrom) != nil {
            byDay[version.effectiveFrom] = version
        }
        return byDay.values.sorted { $0.effectiveFrom < $1.effectiveFrom }
    }
}

/// The user's stack: products plus their schedule histories.
public struct SupplementPlan: Codable, Sendable, Equatable {
    public var products: [SupplementProduct]
    public var items: [PlanItem]

    public init(products: [SupplementProduct] = [], items: [PlanItem] = []) {
        self.products = products
        self.items = items
    }

    private enum CodingKeys: String, CodingKey { case products, items }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        products = try container.decodeIfPresent([SupplementProduct].self, forKey: .products) ?? []
        items = try container.decodeIfPresent([PlanItem].self, forKey: .items) ?? []
    }

    public func product(id: UUID) -> SupplementProduct? {
        products.first { $0.id == id }
    }

    public func item(for productId: UUID) -> PlanItem? {
        items.first { $0.productId == productId }
    }

    /// The schedule of `productId` in effect on `day`.
    public func schedule(of productId: UUID, on day: String) -> SupplementSchedule? {
        item(for: productId)?.schedule(on: day)
    }

    /// Sets a product's schedule from `day` onward (design D3).
    public mutating func setSchedule(_ schedule: SupplementSchedule?, for productId: UUID, from day: String) {
        if let index = items.firstIndex(where: { $0.productId == productId }) {
            items[index].setSchedule(schedule, from: day)
        } else if schedule != nil {
            var item = PlanItem(productId: productId)
            item.setSchedule(schedule, from: day)
            items.append(item)
        }
    }
}

// MARK: - Intake

/// `planned` (a checklist tick) or `extra` (a one-off dose, never replaces
/// a planned item -- spec "A day is stack complete only when...").
public struct IntakeKind: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
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

    public static let planned: IntakeKind = "planned"
    public static let extra: IntakeKind = "extra"
}

/// A taken dose (design D2).
public struct IntakeRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The logged day, `yyyy-MM-dd` (may be up to 365 days in the past, D14).
    public let day: String
    public let productId: UUID
    /// The checklist slot; `nil` for an extra logged without one.
    public let slot: TimeSlot?
    public var servings: Double
    public var takenAt: Date
    public let kind: IntakeKind
    /// `yyyy-MM-dd` the record was WRITTEN. Late entries (> 7 days after
    /// `day`) count for history but grant no XP (D14). `nil` in records
    /// without it: treated as written on `day`.
    public let recordedOn: String?

    public init(
        id: UUID = UUID(),
        day: String,
        productId: UUID,
        slot: TimeSlot?,
        servings: Double,
        takenAt: Date,
        kind: IntakeKind,
        recordedOn: String? = nil
    ) {
        self.id = id
        self.day = day
        self.productId = productId
        self.slot = slot
        self.servings = servings
        self.takenAt = takenAt
        self.kind = kind
        self.recordedOn = recordedOn
    }

    private enum CodingKeys: String, CodingKey { case id, day, productId, slot, servings, takenAt, kind, recordedOn }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        day = try container.decode(String.self, forKey: .day)
        productId = try container.decode(UUID.self, forKey: .productId)
        slot = try container.decodeIfPresent(TimeSlot.self, forKey: .slot)
        servings = try container.decodeIfPresent(Double.self, forKey: .servings) ?? 1
        takenAt = try container.decodeIfPresent(Date.self, forKey: .takenAt) ?? Date(timeIntervalSince1970: 0)
        kind = try container.decodeIfPresent(IntakeKind.self, forKey: .kind) ?? .planned
        recordedOn = try container.decodeIfPresent(String.self, forKey: .recordedOn)
    }

    /// The idempotency key of a planned tick (design D5, 2.1): at most one
    /// planned record per (day, product, slot).
    public var plannedKey: PlannedIntakeKey? {
        guard kind == .planned, let slot else { return nil }
        return PlannedIntakeKey(day: day, productId: productId, slotKey: slot.key)
    }
}

public struct PlannedIntakeKey: Hashable, Sendable {
    public let day: String
    public let productId: UUID
    public let slotKey: String

    public init(day: String, productId: UUID, slotKey: String) {
        self.day = day
        self.productId = productId
        self.slotKey = slotKey
    }
}

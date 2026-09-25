// LayoutModel — the card registry and the persisted layout of the
// customizable screens (add-themes-and-layout design.md D7, D8): the card id
// of every Today card, Log Food shelf and Progress card, each screen's
// `CardSpec` catalog in today's (pre-change) code order, and the stored
// `LayoutConfig` the app keeps as JSON under the `layout.v1` preferences key.
//
// Why it is pure data in this package: the "zero visual change for someone
// who never edits" promise is the default order below, and the only way to
// hold it without a Mac is a golden `swift test` (LayoutResolverTests) that
// pins each catalog to the order the screens render today.
//
// Why decoding is lenient (D7): a layout written by a newer build can name a
// card this build doesn't know. That placement must survive a load-and-save
// here (kept, not rendered -- LayoutResolver rule 2), so ids are plain
// strings in storage, never this build's enums. A garbled placement is
// dropped on its own; only a blob that isn't a JSON object at all is
// `.undecodable`, for the app to quarantine (never silently wipe).
//
// Card titles, icons and variant names are user-facing, so they live in the
// app (GarminFood/Layout/LayoutCardInfo.swift), not here.
//
// Depended on by: LayoutResolver, LayoutPreset (this package); the app's
// LayoutStore, AppPreferences+Layout, TodayView and LayoutEditorSheet.

import Foundation

// MARK: - Screens and card ids

/// A screen whose cards can be reordered, hidden and varied.
public enum LayoutScreen: String, CaseIterable, Sendable {
    case today
    case logFood
    case progress
}

/// The Today cards, in their default (pre-change code) order.
public enum TodayCardID: String, CaseIterable, Codable, Sendable {
    case daySwitcher
    case summary
    case progressStrip
    case fasting
    /// `TodaySlotHost()` -- the gamification banners (seasonal event, weekly
    /// boss), above the meals as add-gamification-signals D12 places it.
    case banners
    case meals
    case logAgain
    case logMeal
    case weightWater
    case dayNote
    case signature
}

/// The Log Food shelves (empty search), in their default order.
public enum LogFoodShelfID: String, CaseIterable, Codable, Sendable {
    case quickPick
    case favorites
    case usual
    case meals
    case recent
    case customFoods
}

/// The Progress cards, in their default order: today's cards with
/// add-gamification-signals D12's slot block under Level, in D12's order.
public enum ProgressCardID: String, CaseIterable, Codable, Sendable {
    case streak
    case level
    case boss
    case bingo
    case seasonal
    case journeys
    case records
    case collections
    case sportBody
    case secrets
    case challenges
    case achievements
    case weight
    case hydration
    case trends
    case goalHistory
}

// MARK: - Variants

/// Today's summary card (D8 variants table).
public enum SummaryVariant: String, CaseIterable, Sendable {
    /// Today's look: the 132 pt ring beside the numbers, macro bars below.
    case ring
    /// A small ring in one row.
    case compact
    /// A big number, no ring.
    case hero
}

/// Today's meal cards.
public enum MealsVariant: String, CaseIterable, Sendable {
    /// Today's look: header, macro bars, entries, Add food / Copy from.
    case expanded
    /// Header and macro bars only; tapping opens the meal's detail.
    case collapsed
}

/// Today's Weight & Water section.
public enum WeightWaterVariant: String, CaseIterable, Sendable {
    case both
    case weight
    case water
}

// MARK: - Card spec

/// What a screen offers for one card: default visibility and variant, and
/// whether it is pinned to an edge or can be hidden.
public struct CardSpec: Hashable, Sendable {
    public enum Pin: String, Hashable, Sendable {
        case top
        case bottom
    }

    public let id: String
    public let defaultVisible: Bool
    /// Raw variant ids, empty for a card without variants.
    public let variants: [String]
    public let defaultVariant: String?
    public let pin: Pin?
    public let hideable: Bool

    public init(
        id: String,
        defaultVisible: Bool = true,
        variants: [String] = [],
        defaultVariant: String? = nil,
        pin: Pin? = nil,
        hideable: Bool = true
    ) {
        self.id = id
        self.defaultVisible = defaultVisible
        self.variants = variants
        self.defaultVariant = defaultVariant
        self.pin = pin
        self.hideable = hideable
    }

    /// Pinned cards keep their edge; everything else can be dragged.
    public var isMovable: Bool { pin == nil }

    /// `stored` if it is one of this card's variants, else the default
    /// (D8 rule 4). `nil` for a card without variants.
    public func validVariant(_ stored: String?) -> String? {
        guard !variants.isEmpty else { return nil }
        if let stored, variants.contains(stored) { return stored }
        return defaultVariant ?? variants.first
    }
}

// MARK: - Catalogs

/// Each screen's cards in their default order. A future card is one enum
/// case, one entry here and one arm in the screen's `switch`.
public enum LayoutCatalog {
    /// Today, in the order `TodayView` rendered before this change.
    ///
    /// - The day switcher is navigation: pinned to the top, never hidden.
    /// - The "GF by Jirka" signature is pinned to the bottom and can't be
    ///   hidden -- owner decision 0.6 is still open, so this keeps today's
    ///   behavior; answering it is a one-word change (`hideable`).
    public static let today: [CardSpec] = [
        CardSpec(id: TodayCardID.daySwitcher.rawValue, pin: .top, hideable: false),
        CardSpec(
            id: TodayCardID.summary.rawValue,
            variants: SummaryVariant.allCases.map(\.rawValue),
            defaultVariant: SummaryVariant.ring.rawValue
        ),
        CardSpec(id: TodayCardID.progressStrip.rawValue),
        CardSpec(id: TodayCardID.fasting.rawValue),
        CardSpec(id: TodayCardID.banners.rawValue),
        CardSpec(
            id: TodayCardID.meals.rawValue,
            variants: MealsVariant.allCases.map(\.rawValue),
            defaultVariant: MealsVariant.expanded.rawValue
        ),
        CardSpec(id: TodayCardID.logAgain.rawValue),
        CardSpec(id: TodayCardID.logMeal.rawValue),
        CardSpec(
            id: TodayCardID.weightWater.rawValue,
            variants: WeightWaterVariant.allCases.map(\.rawValue),
            defaultVariant: WeightWaterVariant.both.rawValue
        ),
        CardSpec(id: TodayCardID.dayNote.rawValue),
        CardSpec(id: TodayCardID.signature.rawValue, pin: .bottom, hideable: false),
    ]

    /// Log Food's empty-search shelves (improve-log-food-shelves' order).
    public static let logFood: [CardSpec] = LogFoodShelfID.allCases.map { CardSpec(id: $0.rawValue) }

    /// Progress (wave 4 renders it; the catalog exists now so a stored
    /// layout and a shared code can already name its cards).
    public static let progress: [CardSpec] = ProgressCardID.allCases.map { CardSpec(id: $0.rawValue) }

    public static func specs(for screen: LayoutScreen) -> [CardSpec] {
        switch screen {
        case .today: return today
        case .logFood: return logFood
        case .progress: return progress
        }
    }
}

// MARK: - Stored placements

/// One card's stored position (its index in `ScreenLayout.placements`),
/// visibility and variant. The id is a plain string so a card unknown to
/// this build survives (D8 rule 2); the variant is kept verbatim for the
/// same reason and validated only when resolved (rule 4).
public struct CardPlacement: Hashable, Sendable {
    public var id: String
    public var isVisible: Bool
    public var variant: String?

    public init(id: String, isVisible: Bool = true, variant: String? = nil) {
        self.id = id
        self.isVisible = isVisible
        self.variant = variant
    }
}

extension CardPlacement: Codable {
    enum CodingKeys: String, CodingKey {
        case id, isVisible, variant
    }

    /// Throws only without a usable id (the element is then dropped by
    /// `ScreenLayout`); every other field falls back on its own.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        guard !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Empty card id")
        }
        self.id = id
        isVisible = (try? container.decodeIfPresent(Bool.self, forKey: .isVisible)) ?? true
        variant = try? container.decodeIfPresent(String.self, forKey: .variant)
    }
}

/// One screen's stored order. Missing cards are placed by the resolver.
public struct ScreenLayout: Hashable, Sendable {
    public var placements: [CardPlacement]

    public init(placements: [CardPlacement] = []) {
        self.placements = placements
    }
}

extension ScreenLayout: Codable {
    enum CodingKeys: String, CodingKey {
        case placements
    }

    /// A garbled element is dropped on its own, never the whole list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let items: [LenientElement<CardPlacement>] =
            (try? container.decodeIfPresent([LenientElement<CardPlacement>].self, forKey: .placements)) ?? []
        placements = items.compactMap(\.value)
    }
}

/// Decodes an array element without failing the array.
struct LenientElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

// MARK: - Config

/// Everything `layout.v1` holds. `nil` for a screen means "never edited":
/// the default order (D8 rule 6).
public struct LayoutConfig: Hashable, Sendable {
    /// Schema version this value was written with; drives `LayoutMigration`.
    public var version: Int
    public var today: ScreenLayout?
    public var logFood: ScreenLayout?
    public var progress: ScreenLayout?
    /// The tab the app opens on (wave 4). `nil` = Today.
    public var startTab: String?
    /// The Today preset last applied (`LayoutPreset` raw value), cleared by
    /// any later Today edit so the editor shows "Custom" (D9).
    public var appliedPreset: String?

    public init(
        version: Int = AppearanceSchema.layoutVersion,
        today: ScreenLayout? = nil,
        logFood: ScreenLayout? = nil,
        progress: ScreenLayout? = nil,
        startTab: String? = nil,
        appliedPreset: String? = nil
    ) {
        self.version = version
        self.today = today
        self.logFood = logFood
        self.progress = progress
        self.startTab = startTab
        self.appliedPreset = appliedPreset
    }

    public static let `default` = LayoutConfig()

    public func layout(for screen: LayoutScreen) -> ScreenLayout? {
        switch screen {
        case .today: return today
        case .logFood: return logFood
        case .progress: return progress
        }
    }

    public mutating func setLayout(_ layout: ScreenLayout?, for screen: LayoutScreen) {
        switch screen {
        case .today: today = layout
        case .logFood: logFood = layout
        case .progress: progress = layout
        }
    }
}

extension LayoutConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case version, today, logFood, progress, startTab, appliedPreset
    }

    /// Lenient: every field independently falls back to its default. Throws
    /// only when the payload is not a JSON object at all.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? AppearanceSchema.layoutVersion
        today = try? container.decodeIfPresent(ScreenLayout.self, forKey: .today)
        logFood = try? container.decodeIfPresent(ScreenLayout.self, forKey: .logFood)
        progress = try? container.decodeIfPresent(ScreenLayout.self, forKey: .progress)
        startTab = try? container.decodeIfPresent(String.self, forKey: .startTab)
        appliedPreset = try? container.decodeIfPresent(String.self, forKey: .appliedPreset)
    }
}

// MARK: - Loading

public extension LayoutConfig {
    enum LoadStatus: Equatable, Sendable {
        /// No stored value: defaults, nothing to report.
        case absent
        /// Decoded (possibly with some fields defaulted) and migrated.
        case loaded
        /// Stored bytes could not be read at all. The app quarantines them,
        /// logs a warning and tells the user once (D7).
        case undecodable
    }

    struct LoadResult: Equatable, Sendable {
        public let config: LayoutConfig
        public let status: LoadStatus
    }

    /// Decode + migrate a stored blob. Never throws.
    static func load(from data: Data?) -> LoadResult {
        guard let data else {
            return LoadResult(config: .default, status: .absent)
        }
        guard let decoded = try? JSONDecoder().decode(LayoutConfig.self, from: data) else {
            return LoadResult(config: .default, status: .undecodable)
        }
        return LoadResult(config: LayoutMigration.migrate(decoded), status: .loaded)
    }

    /// JSON for storage (sorted keys, so identical layouts give identical bytes).
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Migration

/// The seam for future schema changes (D7). At v1 it only stamps the
/// current version -- upward only: a layout written by a newer build keeps
/// its higher version, so this build never labels it as older than it is.
public enum LayoutMigration {
    public static func migrate(_ config: LayoutConfig) -> LayoutConfig {
        var migrated = config
        migrated.version = max(config.version, AppearanceSchema.layoutVersion)
        return migrated
    }
}

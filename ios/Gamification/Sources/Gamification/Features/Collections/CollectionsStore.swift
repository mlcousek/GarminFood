// CollectionsStore.swift
//
// add-food-collections design D3: what the collections feature has to
// remember beyond the 42-day signals window -- every discovery (permanent:
// deleting the food later never undiscovers it), the 859-barcode "mystery"
// Czech products for Brand Explorer, the rainbow days, and whether the
// first-run back-fill has happened (so it gets ONE summary moment).
//
// `<features dir>/collections/collections.json`. Same JSON-file actor and
// unreadable-file contract as the package's other stores
// (`GamificationStorage.loadPersistedJSON` / `ensureSafeToWrite`): an
// undecodable file is quarantined by the loader and treated as empty; a
// file that exists but can't be read (before first unlock) makes `load()`
// return nil, which the feature treats as "skip this run", and `save`
// refuses to overwrite it. Every persisted field is Optional so the format
// can grow and an old file always decodes.
//
// Deviation from the design's sketch, on purpose: named Czech brands are
// NOT stored separately (they are exactly the discovered `czech-brands`
// entries), and rainbow days are stored as day keys, not a count, so a
// re-run over the same window can never count one day twice.
//
// Depends on: GamificationStorage. Depended on by: FoodCollectionsFeature,
// CollectionsEvaluator (the state type).

import Foundation

/// When and with which food an entry was discovered.
public struct CollectionDiscovery: Codable, Sendable, Equatable, Hashable {
    /// `yyyy-MM-dd` nutrition day.
    public var day: String?
    /// The logged food's name (or the parts, for vepřo-knedlo-zelo).
    public var foodName: String?

    public init(day: String?, foodName: String?) {
        self.day = day
        self.foodName = foodName
    }
}

public struct CollectionsState: Codable, Sendable, Equatable {
    /// Keyed by `FoodCollectionEntry.id`.
    public var discovered: [String: CollectionDiscovery]?
    /// Distinct 859-prefixed EANs of products with no brand, capped at
    /// `CollectionsState.mysteryBarcodeCap`.
    public var mysteryCzechBarcodes: [String]?
    /// Distinct days with all six colours, capped at `rainbowDayCap`.
    public var rainbowDayKeys: [String]?
    /// Set on the first successful run (the 42-day back-fill).
    public var backfilledAt: Date?

    public static let mysteryBarcodeCap = 500
    public static let rainbowDayCap = 1000

    public init(
        discovered: [String: CollectionDiscovery]? = nil,
        mysteryCzechBarcodes: [String]? = nil,
        rainbowDayKeys: [String]? = nil,
        backfilledAt: Date? = nil
    ) {
        self.discovered = discovered
        self.mysteryCzechBarcodes = mysteryCzechBarcodes
        self.rainbowDayKeys = rainbowDayKeys
        self.backfilledAt = backfilledAt
    }

    public static let empty = CollectionsState()

    /// The same state with every list trimmed to its cap (a hand-edited or
    /// future file can never grow unbounded in memory).
    public func capped() -> CollectionsState {
        var copy = self
        if let barcodes = copy.mysteryCzechBarcodes, barcodes.count > Self.mysteryBarcodeCap {
            copy.mysteryCzechBarcodes = Array(barcodes.prefix(Self.mysteryBarcodeCap))
        }
        if let days = copy.rainbowDayKeys, days.count > Self.rainbowDayCap {
            copy.rainbowDayKeys = Array(days.prefix(Self.rainbowDayCap))
        }
        return copy
    }
}

public actor CollectionsStore {
    private let fileURL: URL
    private var state: CollectionsState = .empty
    private var loaded = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The persisted state (empty when there is no file yet or it was
    /// undecodable and has been quarantined), or `nil` when the file exists
    /// but can't be read right now -- callers must then do nothing.
    public func load() -> CollectionsState? {
        if loaded { return state }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = GamificationStorage.loadPersistedJSON(
            CollectionsState.self,
            from: fileURL,
            decoder: decoder,
            category: "CollectionsStore"
        )
        // Unreadable: don't latch; `save` refuses to overwrite meanwhile.
        guard !result.isUnreadable else { return nil }
        loaded = true
        state = (result.value ?? .empty).capped()
        return state
    }

    public func save(_ newState: CollectionsState) throws {
        try GamificationStorage.ensureSafeToWrite(loaded: loaded, fileURL: fileURL, category: "CollectionsStore")
        let capped = newState.capped()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(capped)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        state = capped
    }
}

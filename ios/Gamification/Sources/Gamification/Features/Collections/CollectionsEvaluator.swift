// CollectionsEvaluator.swift
//
// add-food-collections design D3/D4: the pure half of the collections
// feature. Given the 42-day `SignalsSnapshot` and the persisted state it
// (1) discovers every catalog entry some logged food carries the tag of --
// oldest day first, so a first run back-fills the whole window and records
// the EARLIEST food that found each entry; (2) discovers vepřo-knedlo-zelo
// from its parts (`meat` + `knedlik` + `dish.zeli`) on ONE day; (3) records
// 859-barcode products with no brand for Brand Explorer and days with all
// six colours; and (4) derives the badges the state has earned and the
// per-collection progress the UI shows.
//
// Discovery is additive only: nothing here ever removes an entry, so a
// deleted log entry never undiscovers anything (spec "Deleted entry").
//
// Depends on: FoodLogCore (SignalsSnapshot, FoodTag, CzechBrands),
// FoodCollectionCatalog, CollectionsState. Depended on by:
// FoodCollectionsFeature, CollectionsEvaluatorTests.

import Foundation
import FoodLogCore

public enum CollectionsEvaluator {
    public struct Result: Sendable, Equatable {
        public let state: CollectionsState
        /// Entry ids discovered by THIS evaluation, in discovery order.
        public let newlyDiscovered: [String]
    }

    public static func evaluate(
        snapshot: SignalsSnapshot,
        state: CollectionsState,
        collections: [FoodCollection] = FoodCollectionCatalog.all
    ) -> Result {
        var discovered = state.discovered ?? [:]
        var mystery = state.mysteryCzechBarcodes ?? []
        var mysterySeen = Set(mystery)
        var rainbowDays = state.rainbowDayKeys ?? []
        var rainbowSeen = Set(rainbowDays)
        var newly: [String] = []

        var entriesByTag: [FoodTag: [FoodCollectionEntry]] = [:]
        for entry in collections.flatMap(\.entries) {
            entriesByTag[entry.tag, default: []].append(entry)
        }
        let hasPartsEntry = collections.contains { collection in
            collection.entries.contains { $0.id == FoodCollectionCatalog.veproKnedloZeloId }
        }

        func discover(_ id: String, day: String, foodName: String?) {
            guard discovered[id] == nil else { return }
            discovered[id] = CollectionDiscovery(day: day, foodName: foodName)
            newly.append(id)
        }

        for day in snapshot.orderedDays {
            for logged in day.entries {
                for tag in logged.tags.sorted() {
                    for entry in entriesByTag[tag] ?? [] {
                        discover(entry.id, day: day.day, foodName: logged.name)
                    }
                }
                if let barcode = mysteryCzechBarcode(logged),
                   !mysterySeen.contains(barcode),
                   mystery.count < CollectionsState.mysteryBarcodeCap {
                    mysterySeen.insert(barcode)
                    mystery.append(barcode)
                }
            }

            if hasPartsEntry, discovered[FoodCollectionCatalog.veproKnedloZeloId] == nil,
               let parts = veproKnedloZeloParts(in: day) {
                discover(FoodCollectionCatalog.veproKnedloZeloId, day: day.day, foodName: parts)
            }

            if isRainbowDay(day), !rainbowSeen.contains(day.day), rainbowDays.count < CollectionsState.rainbowDayCap {
                rainbowSeen.insert(day.day)
                rainbowDays.append(day.day)
            }
        }

        var newState = state
        newState.discovered = discovered
        newState.mysteryCzechBarcodes = mystery
        newState.rainbowDayKeys = rainbowDays
        return Result(state: newState, newlyDiscovered: newly)
    }

    // MARK: - Special rules

    /// A product with no brand text and a Czech (859) EAN: one distinct
    /// "mystery" Czech brand for Brand Explorer (design D3).
    static func mysteryCzechBarcode(_ entry: SignalEntry) -> String? {
        let brand = entry.brand?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard brand.isEmpty, let raw = entry.barcode else { return nil }
        let barcode = raw.trimmingCharacters(in: .whitespaces)
        return CzechBrands.isCzechEAN(barcode) ? barcode : nil
    }

    /// The names of a meat + knedlík + zelí combination logged on one day,
    /// joined for display, or nil. One food may supply several parts.
    static func veproKnedloZeloParts(in day: DaySignals) -> String? {
        guard let meat = day.entries.first(where: { $0.has(.meat) }),
              let knedlik = day.entries.first(where: { $0.has(.knedlik) }),
              let zeli = day.entries.first(where: { $0.has(.dishZeli) }) else { return nil }
        var names: [String] = []
        for entry in [meat, knedlik, zeli] {
            if let name = entry.name, !name.isEmpty, !names.contains(name) {
                names.append(name)
            }
        }
        return names.isEmpty ? nil : names.joined(separator: " + ")
    }

    static func isRainbowDay(_ day: DaySignals) -> Bool {
        let tags = day.allTags
        return FoodTag.allColours.allSatisfy { tags.contains($0) }
    }

    // MARK: - Derived facts

    /// Named Czech brands (discovered brand entries) + mystery barcodes.
    public static func brandsExplored(
        state: CollectionsState,
        collections: [FoodCollection] = FoodCollectionCatalog.all
    ) -> Int {
        let discovered = state.discovered ?? [:]
        let named = collections
            .filter { $0.id == FoodCollectionCatalog.czechBrandsId }
            .flatMap(\.entries)
            .filter { discovered[$0.id] != nil }
            .count
        return named + (state.mysteryCzechBarcodes?.count ?? 0)
    }

    public static func rainbowDayCount(state: CollectionsState) -> Int {
        state.rainbowDayKeys?.count ?? 0
    }

    /// Whether `count` of `total` reaches `percent` (exact at the
    /// threshold: 6 of 24 is 25 %).
    static func reaches(_ count: Int, of total: Int, percent: Int) -> Bool {
        total > 0 && count * 100 >= total * percent
    }

    /// Every badge id the state has earned (already-unlocked ones included;
    /// the host skips those).
    public static func earnedBadgeIds(
        state: CollectionsState,
        collections: [FoodCollection] = FoodCollectionCatalog.all
    ) -> [String] {
        let discovered = state.discovered ?? [:]
        var ids: [String] = []
        var found = 0
        var total = 0
        for collection in collections {
            let count = collection.entries.filter { discovered[$0.id] != nil }.count
            found += count
            total += collection.entries.count
            for percent in collection.badgePercents where reaches(count, of: collection.entries.count, percent: percent) {
                ids.append(CollectionsBadges.completionId(collectionId: collection.id, percent: percent))
            }
        }

        let rainbowDays = rainbowDayCount(state: state)
        for threshold in CollectionsBadges.rainbowDayThresholds where rainbowDays >= threshold {
            ids.append(CollectionsBadges.rainbowDayId(threshold))
        }
        let brands = brandsExplored(state: state, collections: collections)
        for threshold in CollectionsBadges.brandExplorerThresholds where brands >= threshold {
            ids.append(CollectionsBadges.brandExplorerId(threshold))
        }
        for percent in CollectionsBadges.pokedexPercents where reaches(found, of: total, percent: percent) {
            ids.append(CollectionsBadges.pokedexId(percent))
        }
        return ids
    }

    /// What the album screen shows.
    public static func overview(
        state: CollectionsState,
        collections: [FoodCollection] = FoodCollectionCatalog.all
    ) -> CollectionsOverview {
        let discovered = state.discovered ?? [:]
        let progress = collections.map { collection in
            var mine: [String: CollectionDiscovery] = [:]
            for entry in collection.entries {
                if let discovery = discovered[entry.id] { mine[entry.id] = discovery }
            }
            return FoodCollectionProgress(collection: collection, discoveries: mine)
        }
        return CollectionsOverview(
            collections: progress,
            brandsExplored: brandsExplored(state: state, collections: collections),
            rainbowDays: rainbowDayCount(state: state)
        )
    }
}

/// One collection with the discoveries of its entries.
public struct FoodCollectionProgress: Sendable, Equatable, Identifiable {
    public let collection: FoodCollection
    /// Keyed by entry id; only discovered entries.
    public let discoveries: [String: CollectionDiscovery]

    public init(collection: FoodCollection, discoveries: [String: CollectionDiscovery]) {
        self.collection = collection
        self.discoveries = discoveries
    }

    public var id: String { collection.id }
    public var discoveredCount: Int { discoveries.count }
    public var totalCount: Int { collection.entries.count }
    public var fraction: Double { totalCount == 0 ? 0 : Double(discoveredCount) / Double(totalCount) }

    public func discovery(for entry: FoodCollectionEntry) -> CollectionDiscovery? {
        discoveries[entry.id]
    }
}

/// Everything the Progress slot and the album screen read.
public struct CollectionsOverview: Sendable, Equatable {
    public let collections: [FoodCollectionProgress]
    public let brandsExplored: Int
    public let rainbowDays: Int

    public init(collections: [FoodCollectionProgress], brandsExplored: Int, rainbowDays: Int) {
        self.collections = collections
        self.brandsExplored = brandsExplored
        self.rainbowDays = rainbowDays
    }

    public var discoveredCount: Int { collections.reduce(0) { $0 + $1.discoveredCount } }
    public var totalCount: Int { collections.reduce(0) { $0 + $1.totalCount } }
    public var fraction: Double { totalCount == 0 ? 0 : Double(discoveredCount) / Double(totalCount) }

    public static let empty = CollectionsEvaluator.overview(state: .empty)
}

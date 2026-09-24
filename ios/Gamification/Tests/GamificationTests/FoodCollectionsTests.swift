// FoodCollectionsTests.swift
//
// add-food-collections design D3/D4/D6 and the spec scenarios: discovery by
// name (svíčková) and by brand only (Madeta), permanence after the matching
// entry is gone, vepřo-knedlo-zelo by parts on ONE day only, the first-run
// back-fill with a single summary moment, one combined moment for several
// discoveries, percentage badges at exact thresholds (6/24 = 25 %), Rainbow
// 50/100 only, Brand Explorer with an 859 "mystery" product (distinct
// counting + cap), grant keys, and the store's round-trip / old-file /
// garbage-file contract. Real `CollectionsStore` files in a unique temp
// directory per test (never mocked), real `FoodTagger` tags on named foods --
// the same pipeline the app runs.

import XCTest
import FoodLogCore
@testable import Gamification

final class FoodCollectionsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoodCollectionsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private func noon(_ key: String) -> Date {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return Date(timeIntervalSince1970: 0) }
        return TestClock.date(parts[0], parts[1], parts[2])
    }

    private func dayKey(_ day: Int) -> String {
        day < 10 ? "2026-09-0\(day)" : "2026-09-\(day)"
    }

    /// A named food tagged by the real `FoodTagger`.
    private func food(_ name: String, brand: String? = nil, barcode: String? = nil, day: String) -> SignalEntry {
        SignalEntry(
            foodId: "\(name)|\(brand ?? "")|\(barcode ?? "")",
            name: name,
            brand: brand,
            barcode: barcode,
            tags: FoodTagger.tags(name: name, brand: brand, barcode: barcode),
            timestamp: noon(day),
            meal: .lunch
        )
    }

    /// An entry carrying exactly `tags` (for threshold tests independent of
    /// the tag rules).
    private func tagged(_ tags: Set<FoodTag>, name: String = "food", day: String) -> SignalEntry {
        SignalEntry(foodId: name, name: name, tags: tags, timestamp: noon(day), meal: .lunch)
    }

    private func snapshot(_ entriesByDay: [String: [SignalEntry]]) -> SignalsSnapshot {
        var days: [String: DaySignals] = [:]
        for (key, entries) in entriesByDay {
            days[key] = DaySignals(day: key, date: noon(key), entries: entries)
        }
        let keys = days.keys.sorted()
        return SignalsSnapshot(days: days, today: keys.last ?? dayKey(24), windowDays: keys)
    }

    private func context(_ snapshot: SignalsSnapshot, unlocked: Set<String> = []) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: noon(snapshot.today.isEmpty ? dayKey(24) : snapshot.today),
            calendar: TestClock.calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: unlocked,
            isConfirmPath: false
        )
    }

    private func makeFeature() -> FoodCollectionsFeature {
        FoodCollectionsFeature(directory: directory)
    }

    private func collection(_ id: String) throws -> FoodCollection {
        try XCTUnwrap(FoodCollectionCatalog.collection(id: id))
    }

    // MARK: - Catalog

    func testCatalogShape() {
        let counts = FoodCollectionCatalog.all.map { $0.entries.count }
        XCTAssertEqual(FoodCollectionCatalog.all.map(\.id), ["czech-classics", "world", "fermented", "rainbow", "czech-brands"])
        XCTAssertEqual(counts, [24, 22, 11, 6, 22])
        let ids = FoodCollectionCatalog.allEntries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "entry ids must be unique")
        let tags = FoodCollectionCatalog.allEntries.map(\.tag)
        XCTAssertEqual(Set(tags).count, tags.count, "one tag per entry")
    }

    func testBrandEntriesCoverCzechBrandsList() {
        XCTAssertEqual(
            FoodCollectionCatalog.collection(id: FoodCollectionCatalog.czechBrandsId)?.entries.count,
            CzechBrands.names.count
        )
    }

    // MARK: - Discovery

    func testSvickovaIsDiscoveredWithDayAndFoodName() async {
        let name = "Svíčková na smetaně s knedlíkem"
        let update = await makeFeature().update(context(snapshot([dayKey(20): [food(name, day: dayKey(20))]])))
        let overview = await makeFeature().overview()
        let classics = overview.collections.first { $0.id == FoodCollectionCatalog.czechClassicsId }
        XCTAssertEqual(classics?.discoveries["svickova"], CollectionDiscovery(day: dayKey(20), foodName: name))
        XCTAssertTrue(update.grants.contains(RewardGrant(key: "collections.found.svickova", kind: .xp(XPAward.collectionDiscovery))))
    }

    func testBrandIsMatchedByBrandNotName() {
        let result = CollectionsEvaluator.evaluate(
            snapshot: snapshot([dayKey(10): [
                food("Tvaroh", brand: "Madeta", day: dayKey(10)),
                food("Kofola original", day: dayKey(10)),
            ]]),
            state: .empty
        )
        XCTAssertNotNil(result.state.discovered?["brand-madeta"])
        XCTAssertNil(result.state.discovered?["brand-kofola"], "a brand in the NAME must not count")
    }

    func testDiscoveryIsPermanentAfterTheEntryIsDeleted() async {
        let feature = makeFeature()
        _ = await feature.update(context(snapshot([dayKey(5): [food("Kimchi", day: dayKey(5))]])))
        // The only kimchi entry is gone from the window.
        let later = await feature.update(context(snapshot([dayKey(6): [food("Voda", day: dayKey(6))]])))
        let overview = await feature.overview()
        let fermented = overview.collections.first { $0.id == FoodCollectionCatalog.fermentedId }
        XCTAssertNotNil(fermented?.discoveries["kimchi"])
        XCTAssertTrue(later.grants.contains { $0.key == "collections.found.kimchi" }, "grant is re-emitted (ledger dedupes)")
        XCTAssertTrue(later.moments.isEmpty)
    }

    func testEarliestFoodIsRecorded() {
        let result = CollectionsEvaluator.evaluate(
            snapshot: snapshot([
                dayKey(3): [food("Pizza Margherita", day: dayKey(3))],
                dayKey(9): [food("Pizza Quattro formaggi", day: dayKey(9))],
            ]),
            state: .empty
        )
        XCTAssertEqual(result.state.discovered?["pizza"]?.day, dayKey(3))
        XCTAssertEqual(result.newlyDiscovered.filter { $0 == "pizza" }.count, 1)
    }

    func testVeproKnedloZeloFromPartsOnOneDay() {
        let day = dayKey(12)
        let result = CollectionsEvaluator.evaluate(
            snapshot: snapshot([day: [
                food("Vepřová pečeně", day: day),
                food("Houskový knedlík", day: day),
                food("Dušené zelí", day: day),
            ]]),
            state: .empty
        )
        let discovery = result.state.discovered?[FoodCollectionCatalog.veproKnedloZeloId]
        XCTAssertEqual(discovery?.day, day)
        XCTAssertEqual(discovery?.foodName, "Vepřová pečeně + Houskový knedlík + Dušené zelí")
    }

    func testVeproKnedloZeloPartsAcrossTwoDaysDoNotCount() {
        let result = CollectionsEvaluator.evaluate(
            snapshot: snapshot([
                dayKey(12): [food("Vepřová pečeně", day: dayKey(12)), food("Houskový knedlík", day: dayKey(12))],
                dayKey(13): [food("Dušené zelí", day: dayKey(13))],
            ]),
            state: .empty
        )
        XCTAssertNil(result.state.discovered?[FoodCollectionCatalog.veproKnedloZeloId])
    }

    // MARK: - Moments

    func testFirstRunBackfillShowsExactlyOneSummaryMoment() async throws {
        let entries = Array(FoodCollectionCatalog.allEntries.filter { $0.collectionId != FoodCollectionCatalog.rainbowId }.prefix(17))
        XCTAssertEqual(entries.count, 17)
        var byDay: [String: [SignalEntry]] = [:]
        for (index, entry) in entries.enumerated() {
            let key = dayKey(1 + index)
            byDay[key, default: []].append(tagged([entry.tag], name: entry.id, day: key))
        }
        let feature = makeFeature()
        let update = await feature.update(context(snapshot(byDay)))
        XCTAssertEqual(update.grants.count, 17)
        XCTAssertEqual(update.moments.count, 1)
        let moment = try XCTUnwrap(update.moments.first)
        XCTAssertEqual(moment.featureId, FoodCollectionsFeature.id)
        XCTAssertEqual(moment.style, .celebration)
        XCTAssertEqual(moment.xpAwarded, 17 * XPAward.collectionDiscovery)
        let overview = await feature.overview()
        XCTAssertEqual(overview.discoveredCount, 17)
        XCTAssertEqual(overview.totalCount, 85)

        // Same window again: nothing new, no moment.
        let again = await feature.update(context(snapshot(byDay)))
        XCTAssertTrue(again.moments.isEmpty)
        XCTAssertEqual(Set(again.grants), Set(update.grants))
    }

    func testSeveralDiscoveriesProduceOneCombinedMoment() async throws {
        let feature = makeFeature()
        // First run with nothing matching: the back-fill is done, no moment.
        let first = await feature.update(context(snapshot([dayKey(1): [food("Voda", day: dayKey(1))]])))
        XCTAssertTrue(first.moments.isEmpty)

        let day = dayKey(2)
        let update = await feature.update(context(snapshot([day: [
            tagged([.dishKimchi], name: "Kimchi", day: day),
            tagged([.dishPho], name: "Pho bo", day: day),
            tagged([.dishKefir], name: "Kefír", day: day),
        ]])))
        XCTAssertEqual(update.moments.count, 1)
        XCTAssertEqual(update.moments.first?.xpAwarded, 3 * XPAward.collectionDiscovery)

        let single = await feature.update(context(snapshot([dayKey(3): [tagged([.dishSushi], name: "Sushi", day: dayKey(3))]])))
        XCTAssertEqual(single.moments.count, 1)
        XCTAssertEqual(single.moments.first?.xpAwarded, XPAward.collectionDiscovery)
    }

    // MARK: - Badges

    func testQuarterOfCzechClassicsAtExactlySixOfTwentyFour() throws {
        let classics = try collection(FoodCollectionCatalog.czechClassicsId)
        let badge = CollectionsBadges.completionId(collectionId: classics.id, percent: 25)
        func state(_ count: Int) -> CollectionsState {
            var discovered: [String: CollectionDiscovery] = [:]
            for entry in classics.entries.prefix(count) {
                discovered[entry.id] = CollectionDiscovery(day: dayKey(1), foodName: entry.id)
            }
            return CollectionsState(discovered: discovered)
        }
        XCTAssertFalse(CollectionsEvaluator.earnedBadgeIds(state: state(5)).contains(badge))
        XCTAssertTrue(CollectionsEvaluator.earnedBadgeIds(state: state(6)).contains(badge))
        XCTAssertFalse(CollectionsEvaluator.earnedBadgeIds(state: state(11)).contains(
            CollectionsBadges.completionId(collectionId: classics.id, percent: 50)))
        XCTAssertTrue(CollectionsEvaluator.earnedBadgeIds(state: state(12)).contains(
            CollectionsBadges.completionId(collectionId: classics.id, percent: 50)))
        XCTAssertTrue(CollectionsEvaluator.earnedBadgeIds(state: state(24)).contains(
            CollectionsBadges.completionId(collectionId: classics.id, percent: 100)))
    }

    func testSixthClassicUnlocksBadgeAndGrantsXPThroughTheFeature() async throws {
        let classics = try collection(FoodCollectionCatalog.czechClassicsId)
        let feature = makeFeature()
        let five = classics.entries.prefix(5).map { tagged([$0.tag], name: $0.id, day: dayKey(1)) }
        let first = await feature.update(context(snapshot([dayKey(1): five])))
        let badge = CollectionsBadges.completionId(collectionId: classics.id, percent: 25)
        XCTAssertFalse(first.unlockBadgeIds.contains(badge))

        let sixth = classics.entries[5]
        let update = await feature.update(context(snapshot([
            dayKey(1): five,
            dayKey(2): [tagged([sixth.tag], name: sixth.id, day: dayKey(2))],
        ])))
        XCTAssertTrue(update.unlockBadgeIds.contains(badge))
        XCTAssertTrue(update.grants.contains(RewardGrant(
            key: FoodCollectionsFeature.discoveryGrantKey(entryId: sixth.id),
            kind: .xp(XPAward.collectionDiscovery)
        )))

        // Already unlocked badges are not requested again.
        let again = await feature.update(context(snapshot([dayKey(2): []]), unlocked: [badge]))
        XCTAssertFalse(again.unlockBadgeIds.contains(badge))
    }

    func testRainbowHasOnlyHalfAndFullBadges() throws {
        let rainbow = try collection(FoodCollectionCatalog.rainbowId)
        XCTAssertEqual(rainbow.badgePercents, [50, 100])
        let ids = CollectionsBadges.all().map(\.id)
        XCTAssertFalse(ids.contains("collection.rainbow.25"))
        XCTAssertTrue(ids.contains("collection.rainbow.50"))
    }

    func testRainbowDayNeedsAllSixColoursOnOneDay() {
        let five = Set(FoodTag.allColours.prefix(5))
        let partial = CollectionsEvaluator.evaluate(
            snapshot: snapshot([dayKey(4): [tagged(five, day: dayKey(4))]]),
            state: .empty
        )
        XCTAssertEqual(CollectionsEvaluator.rainbowDayCount(state: partial.state), 0)

        let full = CollectionsEvaluator.evaluate(
            snapshot: snapshot([dayKey(4): [
                tagged(five, name: "salad", day: dayKey(4)),
                tagged([.colourWhite], name: "cauliflower", day: dayKey(4)),
            ]]),
            state: partial.state
        )
        XCTAssertEqual(CollectionsEvaluator.rainbowDayCount(state: full.state), 1)
        XCTAssertTrue(CollectionsEvaluator.earnedBadgeIds(state: full.state).contains("collection.rainbow-day"))
        XCTAssertFalse(CollectionsEvaluator.earnedBadgeIds(state: full.state).contains("collection.rainbow-day-10"))

        // The same day evaluated again is not counted twice.
        let rerun = CollectionsEvaluator.evaluate(
            snapshot: snapshot([dayKey(4): [tagged(Set(FoodTag.allColours), day: dayKey(4))]]),
            state: full.state
        )
        XCTAssertEqual(CollectionsEvaluator.rainbowDayCount(state: rerun.state), 1)
    }

    func testMysteryCzechBrandMakesTheTenth() async {
        let named = ["Madeta", "Kunín", "Tatra", "Olma", "Hollandia", "Pilos", "Penam", "Opavia", "Orion"]
        let day = dayKey(15)
        var entries = named.map { food("Výrobek", brand: $0, day: day) }
        let feature = makeFeature()
        let before = await feature.update(context(snapshot([day: entries])))
        XCTAssertFalse(before.unlockBadgeIds.contains(CollectionsBadges.brandExplorerId(10)))
        let overviewBefore = await feature.overview()
        XCTAssertEqual(overviewBefore.brandsExplored, 9)

        entries.append(food("Neznámý sýr", barcode: "8595678901234", day: day))
        let update = await feature.update(context(snapshot([day: entries])))
        XCTAssertTrue(update.unlockBadgeIds.contains(CollectionsBadges.brandExplorerId(10)))
        let overview = await feature.overview()
        XCTAssertEqual(overview.brandsExplored, 10)
    }

    func testMysteryBarcodesAreDistinctBrandlessCzechAndCapped() {
        let day = dayKey(16)
        let result = CollectionsEvaluator.evaluate(
            snapshot: snapshot([day: [
                food("Sýr A", barcode: "8595678901234", day: day),
                food("Sýr A znovu", barcode: "8595678901234", day: day),
                food("Import", barcode: "4001234567890", day: day),
                food("Značkový", brand: "Neznámá značka", barcode: "8591111111111", day: day),
            ]]),
            state: .empty
        )
        XCTAssertEqual(result.state.mysteryCzechBarcodes, ["8595678901234"])

        let full = (0..<CollectionsState.mysteryBarcodeCap).map { String(8_590_000_000_000 + $0) }
        let capped = CollectionsEvaluator.evaluate(
            snapshot: snapshot([day: [food("Nový", barcode: "8599999999999", day: day)]]),
            state: CollectionsState(mysteryCzechBarcodes: full)
        )
        XCTAssertEqual(capped.state.mysteryCzechBarcodes?.count, CollectionsState.mysteryBarcodeCap)
        XCTAssertFalse(capped.state.mysteryCzechBarcodes?.contains("8599999999999") ?? true)
    }

    func testBadgeDefinitions() {
        let badges = makeFeature().badges
        XCTAssertEqual(badges.count, 14 + 2 + 3 + 2)
        XCTAssertEqual(Set(badges.map(\.id)).count, badges.count)
        XCTAssertTrue(badges.allSatisfy { $0.featureId == FoodCollectionsFeature.id })
        XCTAssertTrue(badges.allSatisfy { $0.condition == .featureEvaluated })
        XCTAssertTrue(badges.allSatisfy { $0.id.hasPrefix("collection.") })
        XCTAssertTrue(badges.allSatisfy { !$0.title.hasPrefix("badge.") }, "every badge title is in Collections.strings")
        let rarity = Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0.rarity) })
        XCTAssertEqual(rarity["collection.czech-classics.25"], .common)
        XCTAssertEqual(rarity["collection.czech-classics.50"], .rare)
        XCTAssertEqual(rarity["collection.czech-classics.100"], .epic)
        XCTAssertEqual(rarity["collection.rainbow-day"], .rare)
        XCTAssertEqual(rarity["collection.rainbow-day-10"], .epic)
        XCTAssertEqual(rarity["collection.brand-explorer-10"], .uncommon)
        XCTAssertEqual(rarity["collection.brand-explorer-50"], .epic)
        XCTAssertEqual(rarity["collection.pokedex-50"], .epic)
        XCTAssertEqual(rarity["collection.pokedex-100"], .legendary)
        XCTAssertEqual(BadgeRegistry.duplicateIds(features: [makeFeature()]), [])
    }

    func testEveryEarnedBadgeIsDeclared() {
        var discovered: [String: CollectionDiscovery] = [:]
        for entry in FoodCollectionCatalog.allEntries {
            discovered[entry.id] = CollectionDiscovery(day: dayKey(1), foodName: entry.id)
        }
        let state = CollectionsState(
            discovered: discovered,
            mysteryCzechBarcodes: (0..<40).map { String(8_590_000_000_000 + $0) },
            rainbowDayKeys: (1...10).map { dayKey($0) }
        )
        let earned = CollectionsEvaluator.earnedBadgeIds(state: state)
        let declared = Set(CollectionsBadges.all().map(\.id))
        XCTAssertEqual(Set(earned), declared, "a full album earns every badge, and only declared ones")
    }

    // MARK: - Store

    func testStoreRoundTrip() async throws {
        let url = directory.appendingPathComponent("collections.json")
        let store = CollectionsStore(fileURL: url)
        let loaded = await store.load()
        XCTAssertEqual(loaded, CollectionsState.empty)
        let state = CollectionsState(
            discovered: ["kimchi": CollectionDiscovery(day: "2026-09-01", foodName: "Kimchi")],
            mysteryCzechBarcodes: ["8595678901234"],
            rainbowDayKeys: ["2026-09-02"],
            backfilledAt: TestClock.date(2026, 9, 2)
        )
        try await store.save(state)
        let reread = await CollectionsStore(fileURL: url).load()
        XCTAssertEqual(reread, state)
    }

    func testStoreDecodesAnOldMinimalFile() async throws {
        let url = directory.appendingPathComponent("collections.json")
        try Data(#"{"discovered":{"pho":{"day":"2026-08-30"}}}"#.utf8).write(to: url)
        let loaded = await CollectionsStore(fileURL: url).load()
        XCTAssertEqual(loaded?.discovered?["pho"]?.day, "2026-08-30")
        XCTAssertNil(loaded?.discovered?["pho"]?.foodName)
        XCTAssertNil(loaded?.backfilledAt)
    }

    func testStoreTreatsAGarbageFileAsEmpty() async throws {
        let url = directory.appendingPathComponent("collections.json")
        try Data("not json".utf8).write(to: url)
        let store = CollectionsStore(fileURL: url)
        let loaded = await store.load()
        XCTAssertEqual(loaded, CollectionsState.empty, "undecodable = quarantined and empty, not nil (nil means unreadable)")
        try await store.save(CollectionsState(rainbowDayKeys: ["2026-09-03"]))
        let reread = await CollectionsStore(fileURL: url).load()
        XCTAssertEqual(reread?.rainbowDayKeys, ["2026-09-03"])
    }
}

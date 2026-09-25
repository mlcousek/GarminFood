// StoreFixtureTests.swift
//
// add-data-safety D2 (see docs/data-compatibility.md): every JSON file a
// FoodLogCore store persists on the owner's phone has a committed fixture
// under Fixtures/Stores/, written exactly as the CURRENT code encodes it
// (same JSONEncoder date strategy -- `.iso8601` for most stores, the default
// seconds-since-2001 Double for `food-cache.json`, the FoodLog month shards
// and `offline-index-status.json` -- same key names and CodingKeys, enum raw
// values, Optional-nil keys omitted). Each test copies its fixture into a
// fresh temp directory under the store's real file name and reads it back
// THROUGH THE REAL STORE -- not a bare `JSONDecoder` -- because the failure
// this guards against is silent: `FoodLogCoreStorage.loadPersistedJSON`
// (GarminKit's `PersistedJSON.load`) quarantines an undecodable file (renames
// it to `<name>.unreadable-<stamp>.json`) and the store simply reads as
// EMPTY. So every test asserts specific non-empty decoded values AND that no
// `.unreadable-` file appeared anywhere under the copy's temp directory.
//
// THE RULE: never edit or delete an existing fixture. A fixture is a frozen
// sample of a file that already exists on a real device. When a store's
// format changes, ADD a new fixture next to the old one (e.g.
// `custom-foods.v2.json`) with its own test, and keep the old one decoding --
// if an old fixture stops decoding, the change is what's wrong, not the
// fixture.
//
// `testEveryPersistedFileHasAFixture` keeps this list honest: it scans
// Sources/FoodLogCore for literal `"<name>.json"` file names (and the
// interpolated `"\(month).json"` FoodLog shard name) and fails if a store
// file has no fixture, or if a fixture file isn't covered by a test here.
// Sources/FoodLogCore/Backup is skipped: its catalog names store files
// (this package's and other packages') for backup, it doesn't persist them
// itself.
//
// Depends on FoodLogCore's stores via `@testable import`, and on GarminKit
// only for `MealType`. The fixture directory is excluded from the test
// target in Package.swift and located on disk via `#filePath`, not bundled
// as a resource.

import XCTest
import GarminKit
@testable import FoodLogCore

final class StoreFixtureTests: XCTestCase {
    // MARK: - Fixture registry

    /// `Fixtures/Stores/`, next to this file.
    private static let fixturesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Stores", isDirectory: true)

    /// `ios/FoodLogCore/Sources/FoodLogCore`, derived from this file's
    /// location (`ios/FoodLogCore/Tests/FoodLogCoreTests/StoreFixtureTests.swift`).
    private static let sourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FoodLogCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // FoodLogCore (package root)
        .appendingPathComponent("Sources/FoodLogCore", isDirectory: true)

    /// Every fixture a test below loads. A `.json` file in Fixtures/Stores
    /// that is not listed here is an orphan and fails
    /// `testEveryPersistedFileHasAFixture`.
    private static let allFixtures: [String] = [
        "usage-history.json",
        "serving-defaults.json",
        "custom-foods.json",
        "meal-presets.json",
        "food-cache.json",
        "favorite-foods.json",
        "fasting-sessions.json",
        "day-notes.json",
        "weight-entries.json",
        "hydration-entries.json",
        "garmin-health-cache.json",
        "day-log-digests.json",
        "activity-cache.json",
        "food-provenance.json",
        "offline-index-status.json",
        "FoodLog-2026-09.json",
    ]

    /// Store files whose names are interpolated, which the literal-name
    /// regex can't see: the interpolated source spelling -> its fixture.
    private static let dynamicStoreFixtures: [String: String] = [
        // LocalFoodLogStore.fileURL(month:) -- `FoodLog/<yyyy-MM>.json`.
        "\\(month).json": "FoodLog-2026-09.json",
    ]

    /// Literal `"<name>.json"` strings in Sources/FoodLogCore that are NOT a
    /// persisted store file (name -> reason). Empty today: every literal
    /// match outside Backup/ is a store with a fixture. (The offline index
    /// manifest URL `".../manifest.json"` doesn't match -- no quote directly
    /// before the name -- and is a network fetch, not a store;
    /// `"czech-food-index.json.gz"` doesn't end in `.json"`.)
    private static let exempt: [String: String] = [:]

    // MARK: - Helpers

    private struct FixtureCopy {
        /// The copied file, at the store's real file name.
        let file: URL
        /// The fresh temp directory it lives under (possibly nested).
        let root: URL
    }

    /// Copies `name` from Fixtures/Stores into a fresh, unique temp
    /// directory, at `relativePath` (default: the fixture's own name).
    private func copyFixture(_ name: String, to relativePath: String? = nil) throws -> FixtureCopy {
        let fileManager = FileManager.default
        let source = Self.fixturesDirectory.appendingPathComponent(name)
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("foodlogcore-fixture-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent(relativePath ?? name)
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return FixtureCopy(file: destination, root: root)
    }

    /// Fails if the loader quarantined anything anywhere under the copy's
    /// temp directory, or if the fixture copy itself is no longer there.
    private func assertNotQuarantined(_ copy: FixtureCopy, file: StaticString = #filePath, line: UInt = #line) {
        var quarantined: [String] = []
        if let enumerator = FileManager.default.enumerator(atPath: copy.root.path) {
            while let path = enumerator.nextObject() as? String {
                if path.contains(".unreadable-") { quarantined.append(path) }
            }
        }
        XCTAssertTrue(quarantined.isEmpty, "the store could not decode its fixture and quarantined it: \(quarantined)", file: file, line: line)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.file.path), "fixture copy \(copy.file.lastPathComponent) is gone", file: file, line: line)
    }

    /// `.iso8601` JSONEncoder/Decoder use internet date-time, no fractional
    /// seconds -- the same default options as `ISO8601DateFormatter()`.
    private func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    /// The default (`.deferredToDate`) Date encoding: seconds since
    /// 2001-01-01T00:00:00Z as a JSON number.
    private func ref(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - usage-history.json (UsageHistoryStore: [UsageEvent], .iso8601)

    func testUsageHistoryFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("usage-history.json")

        let events = await UsageHistoryStore(fileURL: copy.file).all()

        assertNotQuarantined(copy)
        XCTAssertEqual(events.count, 3)
        guard events.count == 3 else { return }

        // Oldest shape: neither `nutritionDay` nor `mealType`.
        XCTAssertEqual(events[0].foodId, "5638212")
        XCTAssertEqual(events[0].servingId, "5801234")
        XCTAssertEqual(events[0].numberOfUnits, 1)
        XCTAssertEqual(events[0].timestamp, iso("2026-09-15T06:40:00Z"))
        XCTAssertNil(events[0].nutritionDay)
        XCTAssertNil(events[0].mealType)

        // `nutritionDay` (2026-09-16) but no `mealType`.
        XCTAssertEqual(events[1].numberOfUnits, 1.5)
        XCTAssertEqual(events[1].timestamp, iso("2026-09-20T06:45:00Z"))
        XCTAssertEqual(events[1].nutritionDay, "2026-09-20")
        XCTAssertNil(events[1].mealType)

        // Current shape: a custom food, backdated a day, with its meal.
        XCTAssertEqual(events[2].foodId, "3F9A1C2E-7B4D-4E8F-9A0B-1C2D3E4F5A61")
        XCTAssertEqual(events[2].servingId, CustomFoodDraft.servingId)
        XCTAssertEqual(events[2].numberOfUnits, 2)
        XCTAssertEqual(events[2].nutritionDay, "2026-09-22")
        XCTAssertEqual(events[2].mealType, .lunch)
    }

    // MARK: - serving-defaults.json (ServingDefaultStore: [ServingDefault], .iso8601)

    func testServingDefaultsFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("serving-defaults.json")

        let store = ServingDefaultStore(fileURL: copy.file)
        let all = await store.all()
        let oatmeal = await store.defaultServing(forFoodId: "5638212")
        let custom = await store.defaultServing(forFoodId: "3F9A1C2E-7B4D-4E8F-9A0B-1C2D3E4F5A61")

        assertNotQuarantined(copy)
        XCTAssertEqual(all.count, 2)

        XCTAssertEqual(oatmeal?.servingId, "5801234")
        XCTAssertEqual(oatmeal?.numberOfUnits, 1.5)
        XCTAssertEqual(oatmeal?.updatedAt, iso("2026-09-20T06:45:00Z"))

        XCTAssertEqual(custom?.servingId, "custom")
        XCTAssertEqual(custom?.numberOfUnits, 2)
        XCTAssertEqual(custom?.updatedAt, iso("2026-09-23T11:05:00Z"))
    }

    // MARK: - custom-foods.json (CustomFoodStore: [CustomFoodDraft], .iso8601)

    func testCustomFoodsFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("custom-foods.json")

        // Newest `createdAt` first.
        let foods = await CustomFoodStore(fileURL: copy.file).all()

        assertNotQuarantined(copy)
        XCTAssertEqual(foods.count, 3)
        guard foods.count == 3 else { return }

        // Every optional field present.
        let bar = foods[0]
        XCTAssertEqual(bar.id, UUID(uuidString: "A2B3C4D5-E6F7-4819-8A2B-3C4D5E6F7A82"))
        XCTAssertEqual(bar.name, "Proteinová tyčinka")
        XCTAssertEqual(bar.brandName, "Nutrend")
        XCTAssertEqual(bar.servingUnit, "g")
        XCTAssertEqual(bar.numberOfUnits, 55)
        XCTAssertEqual(bar.calories, 199.5)
        XCTAssertEqual(bar.carbs, 14.2)
        XCTAssertEqual(bar.protein, 20)
        XCTAssertEqual(bar.fat, 6.1)
        XCTAssertEqual(bar.fiber, 3)
        XCTAssertEqual(bar.sugar, 1.8)
        XCTAssertEqual(bar.saturatedFat, 3.4)
        XCTAssertEqual(bar.sodium, 120)
        XCTAssertEqual(bar.createdAt, iso("2026-09-18T09:00:00Z"))
        XCTAssertEqual(bar.backingFoodId, "90123456")
        XCTAssertEqual(bar.backingFoodName, "Protein Bar (custom)")
        XCTAssertEqual(bar.backingServingId, "91234567")
        XCTAssertEqual(bar.backingQuantityMultiplier, 1)
        XCTAssertEqual(bar.note, "Barcode 8594001234567 not found")
        XCTAssertEqual(bar.backingRegionCode, "CZ")
        XCTAssertEqual(bar.backingLanguageCode, "cs")
        XCTAssertEqual(bar.barcode, "8594001234567")
        XCTAssertTrue(bar.hasGarminBacking)

        // The pre-region/language/barcode shape: no brand, macros or note.
        let dumplings = foods[1]
        XCTAssertEqual(dumplings.id, UUID(uuidString: "3F9A1C2E-7B4D-4E8F-9A0B-1C2D3E4F5A61"))
        XCTAssertEqual(dumplings.name, "Babiččiny knedlíky")
        XCTAssertNil(dumplings.brandName)
        XCTAssertNil(dumplings.calories)
        XCTAssertNil(dumplings.sodium)
        XCTAssertNil(dumplings.note)
        XCTAssertNil(dumplings.backingRegionCode)
        XCTAssertNil(dumplings.backingLanguageCode)
        XCTAssertEqual(dumplings.createdAt, iso("2026-09-10T17:20:00Z"))
        // Optional since add-standalone-mode D5 (nil without a backing food).
        let target = try XCTUnwrap(dumplings.resolvedLoggingTarget(quantity: 4))
        XCTAssertEqual(target.foodId, "4471203")
        XCTAssertEqual(target.servingId, "4629981")
        XCTAssertEqual(target.numberOfUnits, 2)
    }

    // MARK: - meal-presets.json (MealPresetStore: [MealPreset], .iso8601)

    func testMealPresetsFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("meal-presets.json")

        // Newest `createdAt` first.
        let presets = await MealPresetStore(fileURL: copy.file).all()

        assertNotQuarantined(copy)
        XCTAssertEqual(presets.count, 2)
        guard presets.count == 2 else { return }

        // A preset with a custom-food ingredient (embedded draft) and an
        // Open Food Facts one; never synced to Garmin.
        let sunday = presets[0]
        XCTAssertEqual(sunday.id, UUID(uuidString: "B1C2D3E4-F5A6-4B7C-8D9E-0F1A2B3C4D02"))
        XCTAssertEqual(sunday.name, "Knedlíky s kefírem")
        XCTAssertEqual(sunday.note, "Neděle")
        XCTAssertEqual(sunday.createdAt, iso("2026-09-21T10:00:00Z"))
        XCTAssertNil(sunday.garminCustomMealId)
        XCTAssertNil(sunday.garminSyncedAt)
        XCTAssertTrue(sunday.hasUnsyncableIngredients)
        XCTAssertEqual(sunday.ingredients.count, 2)
        if sunday.ingredients.count == 2 {
            let dumpling = sunday.ingredients[0]
            XCTAssertEqual(dumpling.id, UUID(uuidString: "C1D2E3F4-A5B6-4C7D-8E9F-0A1B2C3D4E21"))
            XCTAssertEqual(dumpling.food.source, .custom)
            XCTAssertEqual(dumpling.serving.id, "custom")
            XCTAssertEqual(dumpling.quantity, 4)
            XCTAssertEqual(dumpling.customFoodDraft?.backingFoodId, "4471203")
            XCTAssertEqual(dumpling.customFoodDraft?.backingQuantityMultiplier, 0.5)
            XCTAssertEqual(dumpling.customFoodDraft?.createdAt, iso("2026-09-10T17:20:00Z"))

            let kefir = sunday.ingredients[1]
            XCTAssertEqual(kefir.food.source, .openFoodFacts)
            XCTAssertEqual(kefir.food.brandName, "Olma")
            XCTAssertEqual(kefir.serving.calories, 50)
            XCTAssertEqual(kefir.quantity, 2.5)
            XCTAssertNil(kefir.customFoodDraft)
        }

        // A Garmin + FatSecret preset, synced to a Garmin custom meal.
        let breakfast = presets[1]
        XCTAssertEqual(breakfast.id, UUID(uuidString: "B1C2D3E4-F5A6-4B7C-8D9E-0F1A2B3C4D01"))
        XCTAssertEqual(breakfast.name, "Snídaně ovesná")
        XCTAssertNil(breakfast.note)
        XCTAssertEqual(breakfast.createdAt, iso("2026-09-12T06:30:00Z"))
        XCTAssertEqual(breakfast.garminCustomMealId, 123456)
        XCTAssertEqual(breakfast.garminSyncedAt, iso("2026-09-12T06:31:10Z"))
        XCTAssertFalse(breakfast.hasUnsyncableIngredients)
        XCTAssertEqual(breakfast.ingredients.map(\.food.source), [.garmin, .fatSecret])
        XCTAssertEqual(breakfast.ingredients.first?.food.regionCode, "CZ")
        XCTAssertEqual(breakfast.ingredients.first?.quantity, 1.5)
        let totals = breakfast.totals()
        XCTAssertEqual(totals.calories, 384, accuracy: 1e-9)
        XCTAssertEqual(totals.protein, 11.05, accuracy: 1e-9)
    }

    // MARK: - food-cache.json (FoodCacheStore: [Food], default JSONDecoder)

    func testFoodCacheFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("food-cache.json")

        let store = FoodCacheStore(fileURL: copy.file)
        let all = await store.all()
        let oatmeal = await store.food(forId: "5638212")
        let banana = await store.food(forId: "34567")
        let kefir = await store.food(forId: "8594001234567")
        let custom = await store.food(forId: "3F9A1C2E-7B4D-4E8F-9A0B-1C2D3E4F5A61")

        assertNotQuarantined(copy)
        XCTAssertEqual(all.count, 4)

        // Garmin food, every Garmin-side optional present.
        XCTAssertEqual(oatmeal?.name, "Oatmeal")
        XCTAssertEqual(oatmeal?.brandName, "Emco")
        XCTAssertEqual(oatmeal?.source, .garmin)
        XCTAssertEqual(oatmeal?.garminIsFavorite, true)
        XCTAssertEqual(oatmeal?.garminIsRecent, false)
        XCTAssertEqual(oatmeal?.regionCode, "CZ")
        XCTAssertEqual(oatmeal?.languageCode, "cs")
        XCTAssertNil(oatmeal?.imageURL)
        XCTAssertEqual(oatmeal?.servings.first?.id, "5801234")
        XCTAssertEqual(oatmeal?.servings.first?.calories, 186)
        XCTAssertEqual(oatmeal?.servings.first?.monounsaturatedFat, 1.2)
        XCTAssertEqual(oatmeal?.servings.first?.iron, 10)
        XCTAssertNil(oatmeal?.servings.first?.vitaminB1)

        // FatSecret food, two servings, sparse macros.
        XCTAssertEqual(banana?.source, .fatSecret)
        XCTAssertNil(banana?.brandName)
        XCTAssertNil(banana?.garminIsFavorite)
        XCTAssertNil(banana?.regionCode)
        XCTAssertEqual(banana?.servings.count, 2)
        XCTAssertEqual(banana?.servings.first?.displayLabel, "medium")
        XCTAssertEqual(banana?.servings.last?.calories, 89)
        XCTAssertNil(banana?.servings.last?.protein)

        // Open Food Facts food with micronutrients.
        XCTAssertEqual(kefir?.source, .openFoodFacts)
        XCTAssertEqual(kefir?.brandName, "Olma")
        XCTAssertEqual(kefir?.servings.first?.vitaminB2, 0.18)
        XCTAssertEqual(kefir?.servings.first?.vitaminB12, 0.4)
        XCTAssertEqual(kefir?.servings.first?.vitaminD, 0.1)
        XCTAssertNil(kefir?.servings.first?.vitaminA)

        // Custom food as cached by `CustomFoodDraft.asFood()`.
        XCTAssertEqual(custom?.source, .custom)
        XCTAssertEqual(custom?.servings.first?.id, CustomFoodDraft.servingId)
        XCTAssertEqual(custom?.servings.first?.unit, "kus")
        XCTAssertNil(custom?.servings.first?.calories)
    }

    // MARK: - favorite-foods.json (FavoriteFoodStore: [FavoriteFood], .iso8601)

    func testFavoriteFoodsFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("favorite-foods.json")

        let store = FavoriteFoodStore(fileURL: copy.file)
        // Newest `favoritedAt` first.
        let favorites = await store.all()
        let oatmealIsFavorite = await store.isFavorite(foodId: "5638212")
        let bananaIsFavorite = await store.isFavorite(foodId: "34567")

        assertNotQuarantined(copy)
        XCTAssertEqual(favorites.count, 2)
        guard favorites.count == 2 else { return }

        XCTAssertEqual(favorites[0].id, "8594001234567")
        XCTAssertEqual(favorites[0].favoritedAt, iso("2026-09-22T15:30:00Z"))
        XCTAssertEqual(favorites[0].food.source, .openFoodFacts)
        XCTAssertNil(favorites[0].food.regionCode)
        XCTAssertEqual(favorites[0].food.servings.first?.vitaminB2, 0.18)

        XCTAssertEqual(favorites[1].id, "5638212")
        XCTAssertEqual(favorites[1].favoritedAt, iso("2026-09-19T07:00:00Z"))
        XCTAssertEqual(favorites[1].food.source, .garmin)
        XCTAssertEqual(favorites[1].food.garminIsRecent, true)
        XCTAssertEqual(favorites[1].food.servings.first?.carbs, 30.5)

        XCTAssertTrue(oatmealIsFavorite)
        XCTAssertFalse(bananaIsFavorite)
    }

    // MARK: - fasting-sessions.json (FastingSessionStore: {active?, history}, .iso8601)

    /// Nothing writes this file any more (redesign-fasting-schedule); the
    /// fixture is the shape the retired manual-fasting builds wrote, which
    /// `FastingScheduleMigration` must still be able to read.
    func testFastingSessionsFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("fasting-sessions.json")

        let store = FastingSessionStore(fileURL: copy.file)
        let active = await store.active()
        // Newest `startedAt` first.
        let history = await store.history()

        assertNotQuarantined(copy)

        XCTAssertEqual(active?.id, UUID(uuidString: "D1E2F3A4-B5C6-4D7E-8F9A-0B1C2D3E4F01"))
        XCTAssertEqual(active?.protocolKind, .sixteenEight)
        XCTAssertEqual(active?.startedAt, iso("2026-09-22T18:30:00Z"))
        XCTAssertNil(active?.fastingEndedAt)
        XCTAssertNil(active?.eatingEndedAt)

        XCTAssertEqual(history.count, 2)
        guard history.count == 2 else { return }

        XCTAssertEqual(history[0].id, UUID(uuidString: "D1E2F3A4-B5C6-4D7E-8F9A-0B1C2D3E4F03"))
        XCTAssertEqual(history[0].protocolKind, .omad)
        XCTAssertEqual(history[0].fastingEndedAt, iso("2026-09-22T17:40:00Z"))
        XCTAssertEqual(history[0].eatingEndedAt, iso("2026-09-22T18:30:00Z"))

        XCTAssertEqual(history[1].protocolKind, .custom(fastingHours: 14.5, eatingHours: 9.5))
        XCTAssertEqual(history[1].protocolKind.fastingHours, 14.5)
        XCTAssertEqual(history[1].startedAt, iso("2026-09-20T19:00:00Z"))
        XCTAssertEqual(history[1].fastingEndedAt, iso("2026-09-21T09:30:00Z"))
    }

    // MARK: - day-notes.json (DayNoteStore: [DayNote], .iso8601, hand-written Codable)

    func testDayNotesFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("day-notes.json")

        let store = DayNoteStore(fileURL: copy.file)
        let all = await store.all()
        let raceDay = await store.note(for: "2026-09-19")

        assertNotQuarantined(copy)
        XCTAssertEqual(all.map(\.day), ["2026-09-19", "2026-09-20", "2026-09-21"])
        guard all.count == 3 else { return }

        XCTAssertEqual(raceDay?.text, "Half marathon PB")
        XCTAssertEqual(raceDay?.tags, [.race, .celebration])
        XCTAssertEqual(raceDay?.updatedAt, iso("2026-09-19T20:15:00Z"))

        // Tags only, no text.
        XCTAssertEqual(all[1].text, "")
        XCTAssertEqual(all[1].tags, [.restDay])
        XCTAssertEqual(all[1].updatedAt, iso("2026-09-20T21:00:00Z"))

        // Text only (with a newline), no tags.
        XCTAssertEqual(all[2].text, "Grilovačka u Petra\nhodně piva")
        XCTAssertEqual(all[2].tags, [])
        XCTAssertEqual(all[2].updatedAt, iso("2026-09-21T22:40:00Z"))
    }

    // MARK: - weight-entries.json (WeightStore: [WeightEntry], .iso8601)

    func testWeightEntriesFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("weight-entries.json")

        // Newest `loggedAt` first.
        let entries = await WeightStore(fileURL: copy.file).all()

        assertNotQuarantined(copy)
        XCTAssertEqual(entries.count, 3)
        guard entries.count == 3 else { return }

        // Backdated, with a note.
        XCTAssertEqual(entries[0].id, UUID(uuidString: "E1F2A3B4-C5D6-4E7F-8A9B-0C1D2E3F4A02"))
        XCTAssertEqual(entries[0].weightKg, 81.9)
        XCTAssertEqual(entries[0].loggedAt, iso("2026-09-20T06:15:00Z"))
        XCTAssertEqual(entries[0].createdAt, iso("2026-09-21T08:00:00Z"))
        XCTAssertEqual(entries[0].note, "po závodě")
        XCTAssertEqual(entries[0].outboxEntryId, UUID(uuidString: "5A1B2C3D-4E5F-4061-8273-94A5B6C7D802"))

        XCTAssertEqual(entries[1].weightKg, 82.4)
        XCTAssertNil(entries[1].note)
        XCTAssertEqual(entries[1].outboxEntryId, UUID(uuidString: "5A1B2C3D-4E5F-4061-8273-94A5B6C7D801"))

        // No outbox link.
        XCTAssertEqual(entries[2].weightKg, 83)
        XCTAssertEqual(entries[2].loggedAt, iso("2026-09-10T05:50:00Z"))
        XCTAssertNil(entries[2].outboxEntryId)

        let delta = try XCTUnwrap(WeightHistory.delta(latest: entries[0], previous: entries[1]))
        XCTAssertEqual(delta, -0.5, accuracy: 1e-9)
    }

    // MARK: - hydration-entries.json (HydrationStore: [HydrationEntry], .iso8601)

    func testHydrationEntriesFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("hydration-entries.json")

        // Newest `loggedAt` first.
        let entries = await HydrationStore(fileURL: copy.file).all()

        assertNotQuarantined(copy)
        XCTAssertEqual(entries.count, 3)
        guard entries.count == 3 else { return }

        XCTAssertEqual(entries.map(\.valueInML), [330.5, 500, 250])

        XCTAssertEqual(entries[0].id, UUID(uuidString: "F1A2B3C4-D5E6-4F7A-8B9C-0D1E2F3A4B03"))
        XCTAssertEqual(entries[0].loggedAt, iso("2026-09-21T09:10:00Z"))
        XCTAssertNil(entries[0].outboxEntryId)

        // Backdated drink.
        XCTAssertEqual(entries[1].loggedAt, iso("2026-09-20T12:30:00Z"))
        XCTAssertEqual(entries[1].createdAt, iso("2026-09-20T18:05:00Z"))
        XCTAssertEqual(entries[1].outboxEntryId, UUID(uuidString: "7C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E02"))

        XCTAssertEqual(entries[2].outboxEntryId, UUID(uuidString: "7C2D3E4F-5A6B-4C7D-8E9F-0A1B2C3D4E01"))

        let total = HydrationHistory.total(for: entries, on: iso("2026-09-20T15:00:00Z"), calendar: utcCalendar)
        XCTAssertEqual(total, 750)
    }

    // MARK: - garmin-health-cache.json (GarminHealthCacheStore: GarminHealthSnapshot, .iso8601)

    func testGarminHealthCacheFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("garmin-health-cache.json")

        let snapshot = await GarminHealthCacheStore(fileURL: copy.file).current()

        assertNotQuarantined(copy)
        XCTAssertEqual(snapshot.weighInDays.count, 3)
        XCTAssertEqual(snapshot.hydrationDays.count, 2)

        // An empty day is meaningful ("Garmin had nothing") and must survive.
        XCTAssertEqual(snapshot.weighInDays["2026-09-22"]?.weighIns.isEmpty, true)
        XCTAssertEqual(snapshot.weighInDayFetchTimes["2026-09-22"], iso("2026-09-22T08:00:00Z"))
        XCTAssertEqual(snapshot.weighInDays["2026-09-21"]?.weighIns.count, 2)

        // Newest `timestampGMT` first, de-duplicated.
        let weighIns = snapshot.allWeighIns
        XCTAssertEqual(weighIns.map(\.samplePk), [1790014200000, 1789969500000, 1789882200000])
        guard weighIns.count == 3 else { return }

        // A smart-scale sample, full body composition.
        let scale = weighIns[0]
        XCTAssertEqual(scale.calendarDate, "2026-09-21")
        XCTAssertEqual(scale.weightGrams, 83100.5)
        XCTAssertEqual(scale.timestampGMT, 1790014200000)
        XCTAssertEqual(scale.localWallClockMillis, 1790021400000)
        XCTAssertEqual(scale.sourceType, "INDEX_SCALE")
        XCTAssertEqual(scale.weightDelta, 800)
        XCTAssertEqual(scale.bmi, 24.6)
        XCTAssertEqual(scale.bodyFat, 18.2)
        XCTAssertEqual(scale.muscleMass, 38200)
        XCTAssertEqual(scale.metabolicAge, 31)

        // A manual sample without `weightDelta` or body composition.
        XCTAssertEqual(weighIns[1].sourceType, "MANUAL")
        XCTAssertNil(weighIns[1].weightDelta)
        XCTAssertNil(weighIns[1].bmi)

        let manual = weighIns[2]
        XCTAssertEqual(manual.weightKg, 81.9, accuracy: 1e-9)
        XCTAssertEqual(manual.timestamp, iso("2026-09-20T05:30:00Z"))
        XCTAssertEqual(try XCTUnwrap(manual.weightDelta), -500, accuracy: 1e-6)

        // Water: one full day, one sparse.
        let full = snapshot.hydrationDays["2026-09-21"]
        XCTAssertEqual(full?.daily.calendarDate, "2026-09-21")
        XCTAssertEqual(full?.daily.valueInML, 2250)
        XCTAssertEqual(full?.daily.goalInML, 2800)
        XCTAssertEqual(full?.daily.lastEntryTimestampLocal, "2026-09-21T21:05:12.387")
        XCTAssertEqual(full?.daily.sweatLossInML, 640)
        XCTAssertEqual(full?.daily.activityIntakeInML, 0)
        XCTAssertEqual(full?.fetchedAt, iso("2026-09-21T21:10:00Z"))
        let sparse = snapshot.hydrationDays["2026-09-22"]
        XCTAssertEqual(sparse?.daily.valueInML, 500)
        XCTAssertNil(sparse?.daily.goalInML)
        XCTAssertNil(sparse?.daily.calendarDate)

        XCTAssertEqual(snapshot.weightGoal?.startingWeightGrams, 80400)
        XCTAssertEqual(snapshot.weightGoal?.targetWeightGrams, 76000)
        XCTAssertEqual(snapshot.weightGoal?.weightChangeRateGramsPerWeek, 250)
        XCTAssertEqual(snapshot.weightGoal?.weightChangeType, "LOSS")
        XCTAssertEqual(snapshot.weightGoal?.fetchedAt, iso("2026-09-22T08:00:02Z"))
        XCTAssertEqual(snapshot.lastFullWeightRangeFetchAt, iso("2026-09-22T08:00:00Z"))
    }

    // MARK: - day-log-digests.json (DayLogDigestStore: [DayLogDigest], .iso8601)

    func testDayLogDigestsFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("day-log-digests.json")

        let store = DayLogDigestStore(fileURL: copy.file)
        let all = await store.all()
        let full = await store.digest(for: "2026-09-20")
        let noGoals = await store.digest(for: "2026-09-21")
        let empty = await store.digest(for: "2026-09-22")

        assertNotQuarantined(copy)
        XCTAssertEqual(all.map(\.day), ["2026-09-20", "2026-09-21", "2026-09-22"])

        // Goals, fibre/sugar totals, one rich entry and one sparse one.
        XCTAssertEqual(full?.fetchedAt, iso("2026-09-20T19:45:00Z"))
        XCTAssertEqual(full?.totals.calories, 2140)
        XCTAssertEqual(full?.totals.sugar, 64.4)
        XCTAssertEqual(full?.goals?.protein, 140)
        XCTAssertEqual(full?.entries.count, 2)
        let oats = full?.entries.first
        XCTAssertEqual(oats?.foodId, "5638212")
        XCTAssertEqual(oats?.brand, "Emco")
        XCTAssertEqual(oats?.timestamp, iso("2026-09-20T06:45:00Z"))
        XCTAssertEqual(oats?.mealType, MealType.breakfast.rawValue)
        XCTAssertEqual(oats?.fiber, 7.5)
        XCTAssertEqual(oats?.fromThisApp, true)
        let banana = full?.entries.last
        XCTAssertEqual(banana?.name, "Banana")
        XCTAssertNil(banana?.brand)
        XCTAssertNil(banana?.timestamp)
        XCTAssertNil(banana?.mealType)
        XCTAssertNil(banana?.fiber)
        XCTAssertNil(banana?.fromThisApp)

        // No goals, unknown fibre/sugar.
        XCTAssertNil(noGoals?.goals)
        XCTAssertNil(noGoals?.totals.fiber)
        XCTAssertEqual(noGoals?.totals.calories, 540)
        XCTAssertEqual(noGoals?.entries.first?.mealType, "LUNCH")
        XCTAssertEqual(noGoals?.entries.first?.fromThisApp, false)
        XCTAssertNil(noGoals?.entries.first?.name)

        // Nothing logged: zero totals, a calories-only goal.
        XCTAssertEqual(empty?.totals, MacroTotals.zero)
        XCTAssertEqual(empty?.goals?.calories, 2300)
        XCTAssertNil(empty?.goals?.protein)
        XCTAssertEqual(empty?.entries.isEmpty, true)
    }

    // MARK: - activity-cache.json (ActivityCacheStore: [DayActivity], .iso8601)

    func testActivityCacheFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("activity-cache.json")

        let store = ActivityCacheStore(fileURL: copy.file)
        let all = await store.all()
        let raceDay = await store.day("2026-09-20")
        let restDay = await store.day("2026-09-21")
        let kcalOnly = await store.day("2026-09-22")

        assertNotQuarantined(copy)
        XCTAssertEqual(all.map(\.day), ["2026-09-20", "2026-09-21", "2026-09-22"])

        XCTAssertEqual(raceDay?.activeKcal, 812)
        XCTAssertEqual(raceDay?.fetchedAt, iso("2026-09-20T19:45:00Z"))
        XCTAssertEqual(raceDay?.activities?.count, 2)
        let run = raceDay?.activities?.first
        XCTAssertEqual(run?.id, "20412345678")
        XCTAssertEqual(run?.typeKey, "running")
        XCTAssertEqual(run?.day, "2026-09-20")
        XCTAssertEqual(run?.start, iso("2026-09-20T05:10:00Z"))
        XCTAssertEqual(run?.durationS, 5421.3)
        XCTAssertEqual(run?.calories, 1104)
        XCTAssertEqual(run?.distanceM, 21097.5)
        let walk = raceDay?.activities?.last
        XCTAssertEqual(walk?.typeKey, "walking")
        XCTAssertNil(walk?.calories)
        XCTAssertNil(walk?.distanceM)

        // Read, none happened (`[]`) vs never read (`nil`).
        XCTAssertEqual(restDay?.activities?.isEmpty, true)
        XCTAssertNil(restDay?.activeKcal)
        XCTAssertNotNil(kcalOnly)
        XCTAssertNil(kcalOnly?.activities)
        XCTAssertEqual(kcalOnly?.activeKcal, 145.5)
        XCTAssertEqual(kcalOnly?.fetchedAt, iso("2026-09-22T08:00:00Z"))
    }

    // MARK: - food-provenance.json (FoodProvenanceStore: [FoodProvenance], .iso8601)

    func testFoodProvenanceFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("food-provenance.json")

        let store = FoodProvenanceStore(fileURL: copy.file)
        let all = await store.all()
        let brandOnly = await store.provenance(for: "4471203")
        let full = await store.provenance(for: "90123456")
        let barcodeOnly = await store.provenance(for: "91000001")

        assertNotQuarantined(copy)
        XCTAssertEqual(all.count, 3)

        XCTAssertEqual(brandOnly?.brand, "Hamé")
        XCTAssertNil(brandOnly?.barcode)
        XCTAssertEqual(brandOnly?.recordedAt, iso("2026-09-15T10:00:00Z"))

        XCTAssertEqual(full?.barcode, "8594001234567")
        XCTAssertEqual(full?.brand, "Olma")
        XCTAssertEqual(full?.recordedAt, iso("2026-09-18T09:00:00Z"))

        XCTAssertEqual(barcodeOnly?.barcode, "8590000000017")
        XCTAssertNil(barcodeOnly?.brand)
        XCTAssertNil(barcodeOnly?.recordedAt)
    }

    // MARK: - OfflineIndex/offline-index-status.json (OfflineIndexStore: OfflineIndexStatus, default JSONDecoder)

    func testOfflineIndexStatusFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("offline-index-status.json")

        // Loaded in `init`; nothing here touches the network.
        let store = OfflineIndexStore(holder: OfflineFoodIndexHolder(), directory: copy.root)
        let status = await store.currentStatus()

        assertNotQuarantined(copy)
        XCTAssertEqual(status.installedVersion, "2026-09-21")
        XCTAssertEqual(status.installedCount, 4213)
        XCTAssertEqual(status.installedBytes, 312345)
        XCTAssertEqual(status.installedSHA256, "3a7bd3e2360a3d29eea436fcfb7e44c735d117c42d1c1835420b6b9942dd4f1b")
        XCTAssertTrue(status.isInstalled)
        XCTAssertEqual(status.installedAt, ref(811711800.25))
        XCTAssertEqual(status.lastCheckAt, ref(811911600))
        XCTAssertEqual(status.lastError, "Offline database manifest failed: httpStatus(503)")
        XCTAssertEqual(status.lastErrorAt, ref(811911600.5))
    }

    // MARK: - FoodLog/<yyyy-MM>.json (LocalFoodLogStore: [LocalLogEntry], default JSONEncoder, .sortedKeys)

    func testLocalFoodLogMonthFixtureDecodesThroughTheRealStore() async throws {
        let copy = try copyFixture("FoodLog-2026-09.json", to: "FoodLog/2026-09.json")

        let store = LocalFoodLogStore(directoryURL: copy.file.deletingLastPathComponent())
        let day20 = try await store.entries(forDay: "2026-09-20")
        let month = try await store.entries(fromDay: "2026-09-01", toDay: "2026-09-30")
        let byId = await store.entry(id: UUID(uuidString: "A7B8C9D0-E1F2-4A3B-8C4D-5E6F7A8B9C03")!)

        assertNotQuarantined(copy)
        XCTAssertEqual(day20.count, 2)
        XCTAssertEqual(month.count, 3)
        guard day20.count == 2, month.count == 3 else { return }

        // A Garmin food with its full serving snapshot and nutrients.
        let breakfast = day20[0]
        XCTAssertEqual(breakfast.id, UUID(uuidString: "A7B8C9D0-E1F2-4A3B-8C4D-5E6F7A8B9C01"))
        XCTAssertEqual(breakfast.day, "2026-09-20")
        XCTAssertEqual(breakfast.mealType, .breakfast)
        XCTAssertEqual(breakfast.loggedAt, ref(811579500.5))
        XCTAssertEqual(breakfast.food.id, "5638212")
        XCTAssertEqual(breakfast.food.source, .garmin)
        XCTAssertEqual(breakfast.food.name, "Oatmeal")
        XCTAssertEqual(breakfast.food.brandName, "Emco")
        XCTAssertEqual(breakfast.food.regionCode, "CZ")
        XCTAssertEqual(breakfast.food.languageCode, "cs")
        XCTAssertNil(breakfast.food.barcode)
        XCTAssertEqual(breakfast.servingId, "5801234")
        XCTAssertEqual(breakfast.servingUnit, "g")
        XCTAssertEqual(breakfast.servingNumberOfUnits, 50)
        XCTAssertEqual(breakfast.servingLabel, "50 g")
        XCTAssertEqual(breakfast.quantity, 1.5)
        XCTAssertEqual(breakfast.amount(.calories), 279)
        XCTAssertEqual(breakfast.amount(.protein), 9.75)
        XCTAssertEqual(breakfast.amount(.sugar), 0.9)
        XCTAssertNil(breakfast.amount(.vitaminB1))
        XCTAssertNil(breakfast.customFoodId)
        XCTAssertNil(breakfast.presetId)
        XCTAssertNil(breakfast.editedAt)

        // A custom food, edited later, no nutrients known.
        let lunch = day20[1]
        XCTAssertEqual(lunch.mealType, .lunch)
        XCTAssertEqual(lunch.loggedAt, ref(811599000))
        XCTAssertEqual(lunch.food.source, .custom)
        XCTAssertNil(lunch.food.brandName)
        XCTAssertEqual(lunch.customFoodId, UUID(uuidString: "3F9A1C2E-7B4D-4E8F-9A0B-1C2D3E4F5A61"))
        XCTAssertEqual(lunch.editedAt, ref(811620000.25))
        XCTAssertEqual(lunch.quantity, 4)
        XCTAssertTrue(lunch.nutrients.isEmpty)

        // An Open Food Facts food from a meal preset, the next day.
        let dinner = month[2]
        XCTAssertEqual(dinner.day, "2026-09-21")
        XCTAssertEqual(dinner.mealType, .dinner)
        XCTAssertEqual(dinner.loggedAt, ref(811711800))
        XCTAssertEqual(dinner.food.source, .openFoodFacts)
        XCTAssertEqual(dinner.food.barcode, "8594001234567")
        XCTAssertEqual(dinner.presetId, UUID(uuidString: "B1C2D3E4-F5A6-4B7C-8D9E-0F1A2B3C4D02"))
        XCTAssertEqual(dinner.amount(.vitaminB12), 1)
        XCTAssertEqual(dinner.amount(.vitaminB2), 0.45)
        XCTAssertEqual(dinner.quantity, 2.5)
        XCTAssertEqual(byId, dinner)
    }

    // MARK: - Coverage of the fixture set itself

    func testEveryPersistedFileHasAFixture() throws {
        let fileManager = FileManager.default

        // 1. The fixtures on disk are exactly the ones the tests above use.
        let onDisk = try fileManager.contentsOfDirectory(atPath: Self.fixturesDirectory.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertEqual(
            Set(onDisk), Set(Self.allFixtures),
            "Fixtures/Stores and StoreFixtureTests.allFixtures disagree -- add a test for a new fixture, never delete an old one (see docs/data-compatibility.md)"
        )

        // 2. Collect every .swift file under Sources/FoodLogCore, except the
        //    backup module's (its catalog names store files it doesn't own).
        guard let enumerator = fileManager.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: nil) else {
            return XCTFail("couldn't enumerate \(Self.sourcesDirectory.path)")
        }
        var sourceFiles: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            if fileURL.pathComponents.contains("Backup") { continue }
            sourceFiles.append(fileURL)
        }
        XCTAssertFalse(sourceFiles.isEmpty, "found no Swift sources at \(Self.sourcesDirectory.path)")

        // `"<name>.json"` -- a literal file name.
        let literalName = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]+)\\.json\"")
        // `"<prefix>\(identifier).json"` -- an interpolated name (prefix may be empty).
        let interpolatedName = try NSRegularExpression(pattern: "\"([A-Za-z0-9_-]*)\\\\\\(([A-Za-z0-9_]+)\\)\\.json\"")

        var literalFileNames = Set<String>()
        var interpolatedNames = Set<String>()
        for fileURL in sourceFiles {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in literalName.matches(in: text, range: range) {
                if let captured = Range(match.range(at: 1), in: text) {
                    literalFileNames.insert(String(text[captured]) + ".json")
                }
            }
            for match in interpolatedName.matches(in: text, range: range) {
                if let prefix = Range(match.range(at: 1), in: text),
                   let identifier = Range(match.range(at: 2), in: text) {
                    interpolatedNames.insert(String(text[prefix]) + "\\(" + String(text[identifier]) + ").json")
                }
            }
        }

        // Sanity: the scan actually sees the stores we know about, so a
        // broken path or regex can't make this test pass vacuously.
        XCTAssertTrue(literalFileNames.contains("usage-history.json"), "scan found: \(literalFileNames.sorted())")
        XCTAssertTrue(literalFileNames.contains("offline-index-status.json"), "scan found: \(literalFileNames.sorted())")
        XCTAssertGreaterThanOrEqual(literalFileNames.count, 15, "scan found: \(literalFileNames.sorted())")

        // 3. Every literal store file name has a fixture (or a stated reason not to).
        let fixtures = Set(Self.allFixtures)
        for name in literalFileNames.sorted() where Self.exempt[name] == nil {
            XCTAssertTrue(
                fixtures.contains(name),
                "\(name) is persisted by Sources/FoodLogCore but has no fixture -- add Fixtures/Stores/\(name) and a test in StoreFixtureTests (see docs/data-compatibility.md), or an entry in `exempt` with the reason"
            )
        }

        // 4. Every interpolated store name has a fixture...
        XCTAssertEqual(
            interpolatedNames, Set(Self.dynamicStoreFixtures.keys),
            "interpolated store file names in Sources/FoodLogCore changed -- add a Fixtures/Stores/<name> for each and list it in `dynamicStoreFixtures` (see docs/data-compatibility.md)"
        )
        // ...and each listed one really exists and is tested.
        for (sourceName, fixture) in Self.dynamicStoreFixtures.sorted(by: { $0.key < $1.key }) {
            XCTAssertTrue(
                fileManager.fileExists(atPath: Self.fixturesDirectory.appendingPathComponent(fixture).path),
                "missing fixture for \(sourceName) -- add Fixtures/Stores/\(fixture) (see docs/data-compatibility.md)"
            )
            XCTAssertTrue(fixtures.contains(fixture), "\(fixture) is not in `allFixtures`")
        }
    }
}

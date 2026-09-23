// FoodSearchEngineTests.swift
//
// rebuild-food-search tasks 3.1-3.4: the three sources and the streaming
// engine. Sources are exercised against fakes of their network seams
// (`GarminFoodSearching`, `OpenFoodFactsSearching`) and REAL local stores
// on unique temp files (the LogEntryCoordinatorTests convention); the
// engine against scripted `FoodSearchSource`s, with the debounce set to 0.

import XCTest
@testable import FoodLogCore
import GarminKit

// MARK: - Helpers

private func tempURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("foodlogcore-search-\(name)-\(UUID().uuidString).json")
}

private func food(_ id: String, _ name: String, source: FoodSource = .fatSecret, kcal: Double = 100) -> Food {
    Food(id: id, name: name, source: source, servings: [Serving(id: "s", unit: "g", numberOfUnits: 100, calories: kcal)])
}

private func draft(_ name: String) -> CustomFoodDraft {
    CustomFoodDraft(name: name, servingUnit: "g", numberOfUnits: 100, calories: 110, backingFoodId: "g-1", backingFoodName: "Tvaroh", backingServingId: "s")
}

private func garminResponse(_ foods: [(id: String, name: String)], more: Bool) -> FoodSearchResponse {
    let results = foods.map { item in
        #"{ "foodMetaData": { "foodId": "\#(item.id)", "foodName": "\#(item.name)", "source": "FATSECRET", "regionCode": "CZ", "languageCode": "en" }, "nutritionContents": [ { "servingId": "s1", "servingUnit": "g", "numberOfUnits": 100, "calories": 100 } ] }"#
    }
    let json = #"{ "results": [\#(results.joined(separator: ","))], "moreDataAvailable": \#(more) }"#
    // Force-try is fine in a test helper: the JSON above is a fixed literal.
    return try! JSONDecoder().decode(FoodSearchResponse.self, from: Data(json.utf8))
}

private actor CallLog {
    private(set) var calls: [String] = []
    func record(_ call: String) { calls.append(call) }
}

/// A scripted source for engine tests.
private struct ScriptedSource: FoodSearchSource {
    let origin: SearchOrigin
    let isRemote: Bool
    let log: CallLog
    let answer: @Sendable (SearchQuery, Int) async throws -> SourcePage

    func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage {
        await log.record("\(origin.rawValue)|\(query.raw)|\(page)")
        return try await answer(query, page)
    }
}

private func page(_ foods: [Food], origin: SearchOrigin, hasMore: Bool = false) -> SourcePage {
    SourcePage(candidates: foods.map { SearchCandidate(food: $0, origin: origin) }, hasMore: hasMore)
}

// MARK: - LocalFoodSource

final class LocalFoodSourceTests: XCTestCase {
    func testLibraryHoldsCustomFoodsFavoritesAndLoggedFoodsOnce() {
        let custom = draft("Domácí tvaroh")
        let rohlik = food("g-1", "Rohlík")
        let jogurt = food("g-2", "Jogurt")
        let neverLogged = food("g-3", "Chléb")
        let offProduct = food("859", "Kefírové mléko", source: .openFoodFacts)
        let deletedCustom = food(UUID().uuidString, "Smazaný koláč", source: .custom)

        let library = LocalFoodSource.candidates(
            customFoods: [custom],
            favorites: [FavoriteFood(food: jogurt), FavoriteFood(food: offProduct), FavoriteFood(food: deletedCustom)],
            cachedFoods: ["g-1": rohlik, "g-2": jogurt, "g-3": neverLogged],
            usage: [
                UsageEvent(foodId: "g-1", servingId: "s", numberOfUnits: 1, timestamp: Date()),
                UsageEvent(foodId: "g-2", servingId: "s", numberOfUnits: 1, timestamp: Date())
            ]
        )

        XCTAssertEqual(library.map(\.food.name), ["Domácí tvaroh", "Jogurt", "Rohlík"])
        XCTAssertTrue(library.allSatisfy { $0.origin == .local })
        XCTAssertEqual(library.first?.customDraft, custom)
    }

    /// food-catalog spec "Own custom food found by typing".
    func testOwnCustomFoodIsFoundByTypingThroughTheEngine() async throws {
        let customFoods = CustomFoodStore(fileURL: tempURL("custom"))
        try await customFoods.upsert(draft("Domácí tvaroh"))
        let local = LocalFoodSource(
            customFoods: customFoods,
            favorites: FavoriteFoodStore(fileURL: tempURL("fav")),
            foodCache: FoodCacheStore(fileURL: tempURL("cache")),
            usageHistory: UsageHistoryStore(fileURL: tempURL("usage"))
        )
        let engine = FoodSearchEngine(sources: [local], debounceNanoseconds: 0)

        let snapshot = await engine.search("tvaroh")

        XCTAssertEqual(snapshot.results.map(\.food.name), ["Domácí tvaroh"])
        XCTAssertEqual(snapshot.results.first?.origin, .local)
        XCTAssertNotNil(snapshot.results.first?.customDraft)
    }

    func testPersonalContextComesFromUsageAndFavorites() async throws {
        let usage = UsageHistoryStore(fileURL: tempURL("usage"))
        try await usage.record(foodId: "g-1", servingId: "s", numberOfUnits: 1, timestamp: Date())
        let favorites = FavoriteFoodStore(fileURL: tempURL("fav"))
        try await favorites.toggle(food("g-2", "Jogurt"))
        let local = LocalFoodSource(
            customFoods: CustomFoodStore(fileURL: tempURL("custom")),
            favorites: favorites,
            foodCache: FoodCacheStore(fileURL: tempURL("cache")),
            usageHistory: usage
        )

        let context = await local.personalContext()

        XCTAssertEqual(context.decayedUseCounts["g-1"] ?? 0, 1, accuracy: 0.01)
        XCTAssertEqual(context.favoriteFoodIds, ["g-2"])
    }
}

// MARK: - GarminFoodSource

private actor FakeGarmin: GarminFoodSearching {
    struct Request: Equatable {
        let term: String
        let start: Int
        let limit: Int
        let regionCode: String?
    }

    private(set) var requests: [Request] = []
    private let answers: [String: FoodSearchResponse]
    private let failingTerms: Set<String>

    init(answers: [String: FoodSearchResponse], failingTerms: Set<String> = []) {
        self.answers = answers
        self.failingTerms = failingTerms
    }

    func searchFood(term: String, start: Int, limit: Int, regionCode: String?) async throws -> FoodSearchResponse {
        requests.append(Request(term: term, start: start, limit: limit, regionCode: regionCode))
        if failingTerms.contains(term) { throw URLError(.notConnectedToInternet) }
        return answers[term] ?? garminResponse([], more: false)
    }
}

final class GarminFoodSourceTests: XCTestCase {
    func testSendsBothSpellingsInTheCzechRegionAndMergesThem() async throws {
        let garmin = FakeGarmin(answers: [
            "bílý jogurt": garminResponse([("1", "Jogurt Bílý"), ("2", "Řecký Jogurt Bílý")], more: false),
            "bily jogurt": garminResponse([("3", "Bily Jogurt Klasik"), ("1", "Jogurt Bílý")], more: true)
        ])
        let source = GarminFoodSource(searcher: garmin)

        let result = try await source.search(SearchQuery("Bílý jogurt"), page: 0, options: SearchOptions())

        let requests = await garmin.requests
        XCTAssertEqual(Set(requests.map(\.term)), ["bílý jogurt", "bily jogurt"])
        XCTAssertTrue(requests.allSatisfy { $0.start == 0 && $0.limit == 50 && $0.regionCode == "CZ" })
        // Round-robin, duplicates dropped.
        XCTAssertEqual(result.candidates.map(\.food.id), ["1", "3", "2"])
        XCTAssertTrue(result.candidates.allSatisfy { $0.origin == .garmin })
        XCTAssertEqual(result.candidates.first?.food.regionCode, "CZ")
        XCTAssertTrue(result.hasMore)
    }

    func testLaterPagesStartAtAMultipleOfTheLimit() async throws {
        let garmin = FakeGarmin(answers: [:])
        let source = GarminFoodSource(searcher: garmin)

        _ = try await source.search(SearchQuery("tvaroh"), page: 2, options: SearchOptions())

        let requests = await garmin.requests
        XCTAssertEqual(requests, [FakeGarmin.Request(term: "tvaroh", start: 100, limit: 50, regionCode: "CZ")])
    }

    func testOneFailingSpellingDoesNotHideTheOther() async throws {
        let garmin = FakeGarmin(answers: ["mléko": garminResponse([("1", "Mléko")], more: false)], failingTerms: ["mleko"])
        let source = GarminFoodSource(searcher: garmin)

        let result = try await source.search(SearchQuery("mleko"), page: 0, options: SearchOptions())

        XCTAssertEqual(result.candidates.map(\.food.name), ["Mléko"])
    }

    func testEverySpellingFailingThrows() async {
        let garmin = FakeGarmin(answers: [:], failingTerms: ["tvaroh"])
        let source = GarminFoodSource(searcher: garmin)

        do {
            _ = try await source.search(SearchQuery("tvaroh"), page: 0, options: SearchOptions())
            XCTFail("expected the failure to surface")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
    }
}

// MARK: - OpenFoodFactsSource

private actor FakeOpenFoodFacts: OpenFoodFactsSearching {
    private(set) var requests: [String] = []
    private let czech: [String: [OFFSearchHit]]
    private let worldwide: [String: [OFFSearchHit]]

    init(czech: [String: [OFFSearchHit]] = [:], worldwide: [String: [OFFSearchHit]] = [:]) {
        self.czech = czech
        self.worldwide = worldwide
    }

    func search(term: String, czechOnly: Bool) async throws -> [OFFSearchHit] {
        requests.append("\(term)|\(czechOnly ? "cz" : "all")")
        return (czechOnly ? czech[term] : worldwide[term]) ?? []
    }
}

final class OpenFoodFactsSourceTests: XCTestCase {
    private func hit(_ id: String, _ name: String, aliases: [String] = []) -> OFFSearchHit {
        OFFSearchHit(food: food(id, name, source: .openFoodFacts), alternateNames: aliases)
    }

    func testSearchesBothSpellingsAndKeepsAlternateNames() async throws {
        let off = FakeOpenFoodFacts(czech: [
            "mleko": [hit("1", "Mleko", aliases: ["Milk"])],
            "mléko": [hit("2", "Mléko polotučné"), hit("1", "Mleko")]
        ])
        let source = OpenFoodFactsSource(client: off)

        let result = try await source.search(SearchQuery("mleko"), page: 0, options: SearchOptions(czechOnly: true))

        let requests = await off.requests
        XCTAssertEqual(Set(requests), ["mleko|cz", "mléko|cz"])
        XCTAssertEqual(result.candidates.map(\.food.id), ["1", "2"])
        XCTAssertEqual(result.candidates.first?.alternateNames, ["Milk"])
        XCTAssertTrue(result.candidates.allSatisfy { $0.origin == .openFoodFacts })
        XCTAssertNil(result.note)
    }

    func testEmptyCzechResultFallsBackToWorldwideWithANote() async throws {
        let off = FakeOpenFoodFacts(worldwide: ["kefir": [hit("9", "Lifeway Kefir")]])
        let source = OpenFoodFactsSource(client: off)

        let result = try await source.search(SearchQuery("kefir"), page: 0, options: SearchOptions(czechOnly: true))

        XCTAssertEqual(result.candidates.map(\.food.id), ["9"])
        XCTAssertEqual(result.note, OpenFoodFactsSource.worldwideFallbackNote)
    }

    func testCzechOnlyOffSearchesWorldwideOnce() async throws {
        let off = FakeOpenFoodFacts(worldwide: ["kefir": [hit("9", "Lifeway Kefir")]])
        let source = OpenFoodFactsSource(client: off)

        _ = try await source.search(SearchQuery("kefir"), page: 0, options: SearchOptions(czechOnly: false))

        let requests = await off.requests
        XCTAssertEqual(requests, ["kefir|all"])
    }

    func testThereIsNoSecondPage() async throws {
        let off = FakeOpenFoodFacts(czech: ["kefir": [hit("1", "Kefir")]])
        let result = try await OpenFoodFactsSource(client: off).search(SearchQuery("kefir"), page: 1, options: SearchOptions())
        XCTAssertTrue(result.candidates.isEmpty)
        let requests = await off.requests
        XCTAssertTrue(requests.isEmpty)
    }
}

// MARK: - FoodSearchEngine

final class FoodSearchEngineTests: XCTestCase {
    private func collect(_ engine: FoodSearchEngine, _ query: String, options: SearchOptions = SearchOptions()) async -> [SearchSnapshot] {
        var snapshots: [SearchSnapshot] = []
        for await snapshot in engine.results(for: query, options: options) {
            snapshots.append(snapshot)
        }
        return snapshots
    }

    /// food-catalog spec "Results appear instantly": local first, remote after.
    func testLocalResultsComeFirstThenRemoteResultsMergeIn() async {
        let log = CallLog()
        let local = ScriptedSource(origin: .local, isRemote: false, log: log) { _, _ in page([food("l1", "Domácí tvaroh", source: .custom)], origin: .local) }
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([food("g1", "Tvaroh")], origin: .garmin, hasMore: true) }
        let engine = FoodSearchEngine(sources: [local, garmin], debounceNanoseconds: 0)

        let snapshots = await collect(engine, "tvaroh")

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].results.map(\.food.id), ["l1"])
        XCTAssertEqual(snapshots[0].statuses[.garmin], .loading)
        XCTAssertFalse(snapshots[0].isComplete)
        XCTAssertEqual(Set(snapshots[1].results.map(\.food.id)), ["l1", "g1"])
        XCTAssertEqual(snapshots[1].statuses[.garmin], .finished(hasMore: true))
        XCTAssertEqual(snapshots[1].statuses[.local], .finished(hasMore: false))
        XCTAssertTrue(snapshots[1].isComplete)
    }

    func testRemoteAnswersAreCachedPerTerm() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([food("g1", "Tvaroh")], origin: .garmin) }
        let engine = FoodSearchEngine(sources: [garmin], debounceNanoseconds: 0)

        _ = await collect(engine, "tvaroh")
        let again = await collect(engine, "Tvaroh ")

        let calls = await log.calls
        XCTAssertEqual(calls.count, 1, "the second, identically-normalized query is served from the term cache")
        XCTAssertEqual(again.count, 1, "a fully cached query needs only the immediate snapshot")
        XCTAssertEqual(again.first?.results.map(\.food.id), ["g1"])
        XCTAssertEqual(again.first?.isComplete, true)
    }

    func testCacheEntriesExpire() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([food("g1", "Tvaroh")], origin: .garmin) }
        let clock = TestClock()
        let engine = FoodSearchEngine(sources: [garmin], debounceNanoseconds: 0, cacheLifetime: 60, clock: { clock.now })

        _ = await collect(engine, "tvaroh")
        clock.advance(by: 61)
        _ = await collect(engine, "tvaroh")

        let calls = await log.calls
        XCTAssertEqual(calls.count, 2)
    }

    /// Design D5: a failing source is a per-source status, never a global error.
    func testAFailingSourceBecomesItsOwnStatusAndOthersStillShow() async {
        let log = CallLog()
        let local = ScriptedSource(origin: .local, isRemote: false, log: log) { _, _ in page([food("l1", "Tvaroh")], origin: .local) }
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in throw URLError(.notConnectedToInternet) }
        let off = ScriptedSource(origin: .openFoodFacts, isRemote: true, log: log) { _, _ in throw GarminAuthError.notSignedIn }
        let engine = FoodSearchEngine(sources: [local, garmin, off], debounceNanoseconds: 0)

        let final = await engine.search("tvaroh")

        XCTAssertEqual(final.results.map(\.food.id), ["l1"])
        XCTAssertEqual(final.statuses[.local], .finished(hasMore: false))
        guard case .failed(let garminFailure)? = final.statuses[.garmin], case .failed(let offFailure)? = final.statuses[.openFoodFacts] else {
            return XCTFail("expected both remote sources to be failed: \(final.statuses)")
        }
        XCTAssertEqual(garminFailure.kind, .unavailable)
        XCTAssertEqual(offFailure.kind, .signedOut)
        XCTAssertTrue(final.isComplete)
    }

    /// food-catalog spec "Fast typing": a cancelled request is not an error.
    func testCancelledRequestsAreNeverReportedAsFailures() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in throw URLError(.cancelled) }
        let other = ScriptedSource(origin: .openFoodFacts, isRemote: true, log: log) { _, _ in throw CancellationError() }
        let engine = FoodSearchEngine(sources: [garmin, other], debounceNanoseconds: 0)

        let final = await engine.search("tvaroh")

        XCTAssertEqual(final.statuses[.garmin], .finished(hasMore: false))
        XCTAssertEqual(final.statuses[.openFoodFacts], .finished(hasMore: false))
    }

    func testStoppingTheStreamCancelsTheDebouncedRemoteSearch() async throws {
        let log = CallLog()
        let local = ScriptedSource(origin: .local, isRemote: false, log: log) { _, _ in page([], origin: .local) }
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([food("g1", "Tvaroh")], origin: .garmin) }
        let engine = FoodSearchEngine(sources: [local, garmin], debounceNanoseconds: 300_000_000)

        for await _ in engine.results(for: "tvaroh") {
            break // the next keystroke arrived
        }
        try await Task.sleep(nanoseconds: 500_000_000)

        let calls = await log.calls
        XCTAssertEqual(calls, ["local|tvaroh|0"], "Garmin must never be asked for an abandoned query")
    }

    /// Design D5: previous results stay visible while the next query loads.
    func testPreviousRemoteResultsStayVisibleWhileTheNextQueryLoads() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { query, _ in
            query.raw == "tvaroh"
                ? page([food("g1", "Tvaroh měkký"), food("g2", "Tvaroh tvrdý")], origin: .garmin)
                : page([food("g3", "Měkký tvaroh")], origin: .garmin)
        }
        let engine = FoodSearchEngine(sources: [garmin], debounceNanoseconds: 0)

        _ = await collect(engine, "tvaroh")
        let next = await collect(engine, "tvaroh mekky")

        XCTAssertEqual(next.first?.statuses[.garmin], .loading)
        XCTAssertEqual(next.first?.results.first?.food.id, "g1", "the still-matching row from the last answer is shown provisionally")
        XCTAssertEqual(next.last?.results.map(\.food.id), ["g3"], "the real answer replaces the provisional rows")
    }

    func testGarminResultsAreBackFilledIntoTheFoodCache() async {
        let cache = FoodCacheStore(fileURL: tempURL("cache"))
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([food("g1", "Tvaroh")], origin: .garmin) }
        let engine = FoodSearchEngine(sources: [garmin], foodCache: cache, debounceNanoseconds: 0)

        _ = await engine.search("tvaroh")

        let cached = await cache.food(forId: "g1")
        XCTAssertEqual(cached?.name, "Tvaroh")
    }

    func testOneLetterQueriesSkipRemoteSources() async {
        let log = CallLog()
        let local = ScriptedSource(origin: .local, isRemote: false, log: log) { _, _ in page([food("l1", "Rohlík")], origin: .local) }
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([], origin: .garmin) }
        let engine = FoodSearchEngine(sources: [local, garmin], debounceNanoseconds: 0)

        let snapshots = await collect(engine, "r")

        let calls = await log.calls
        XCTAssertEqual(calls, ["local|r|0"])
        XCTAssertEqual(snapshots.last?.results.map(\.food.id), ["l1"])
        XCTAssertNil(snapshots.last?.statuses[.garmin])
        XCTAssertEqual(snapshots.last?.isComplete, true)
    }

    func testOriginsOptionLimitsWhichSourcesAreAsked() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([food("g1", "Tvaroh")], origin: .garmin) }
        let off = ScriptedSource(origin: .openFoodFacts, isRemote: true, log: log) { _, _ in page([food("o1", "Tvaroh", source: .openFoodFacts)], origin: .openFoodFacts) }
        let engine = FoodSearchEngine(sources: [garmin, off], debounceNanoseconds: 0)

        let final = await engine.search("tvaroh", options: SearchOptions(origins: [.garmin]))

        let calls = await log.calls
        XCTAssertEqual(calls, ["garmin|tvaroh|0"])
        XCTAssertEqual(final.results.map(\.food.id), ["g1"])
    }

    func testShowMoreAsksForTheNextPageAndReusesTheCachedFirstPage() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, pageIndex in
            pageIndex == 0
                ? page([food("g1", "Tvaroh")], origin: .garmin, hasMore: true)
                : page([food("g2", "Tvaroh jemný")], origin: .garmin, hasMore: false)
        }
        let engine = FoodSearchEngine(sources: [garmin], debounceNanoseconds: 0)

        _ = await engine.search("tvaroh")
        let more = await engine.search("tvaroh", options: SearchOptions(pages: [.garmin: 2]))

        let calls = await log.calls
        XCTAssertEqual(calls, ["garmin|tvaroh|0", "garmin|tvaroh|1"])
        XCTAssertEqual(Set(more.results.map(\.food.id)), ["g1", "g2"])
        XCTAssertEqual(more.statuses[.garmin], .finished(hasMore: false))
    }

    func testOpenFoodFactsWorldwideNoteReachesTheSnapshot() async {
        let log = CallLog()
        let off = ScriptedSource(origin: .openFoodFacts, isRemote: true, log: log) { _, _ in
            SourcePage(candidates: [SearchCandidate(food: food("o1", "Kefir", source: .openFoodFacts), origin: .openFoodFacts)], note: "worldwide")
        }
        let engine = FoodSearchEngine(sources: [off], debounceNanoseconds: 0)

        let final = await engine.search("kefir")

        XCTAssertEqual(final.notes[.openFoodFacts], "worldwide")
    }

    func testBlankQueryYieldsOneEmptyCompleteSnapshot() async {
        let log = CallLog()
        let garmin = ScriptedSource(origin: .garmin, isRemote: true, log: log) { _, _ in page([], origin: .garmin) }
        let engine = FoodSearchEngine(sources: [garmin], debounceNanoseconds: 0)

        let snapshots = await collect(engine, "   ")

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(snapshots[0].results.isEmpty)
        XCTAssertTrue(snapshots[0].isComplete)
        let calls = await log.calls
        XCTAssertTrue(calls.isEmpty)
    }
}

/// A settable clock for cache-expiry tests.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

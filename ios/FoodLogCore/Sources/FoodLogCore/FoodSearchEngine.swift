// FoodSearchEngine.swift
//
// The one food-search pipeline (rebuild-food-search task 3.4, design.md
// D5), replacing FoodCatalogView's two independent debounced tasks. Before
// it, every keystroke waited 300 ms plus the network, a spinner replaced
// the old results, a cancelled request flashed an error, and Garmin and
// OFF results sat in two unmerged lists.
//
// Per query, `results(for:options:)` streams `SearchSnapshot`s:
//   1. Immediately: the local sources (your own foods; later the offline
//      Czech index) plus any remote pages already in the term cache, ranked
//      together. While a remote source is still loading, its results from
//      the PREVIOUS query are re-ranked against the new query and included
//      provisionally, so rows that still match stay on screen instead of
//      blinking out on every keystroke.
//   2. After a 250 ms debounce (restarted by every keystroke, because the
//      caller cancels the stream), each remote source is asked in parallel;
//      a new snapshot follows each answer.
// Cancellation (CancellationError / URLError.cancelled) is never reported;
// a failing source becomes that source's `.failed` status, never a global
// error. Remote pages are kept in an LRU term cache (100 terms, 15 min)
// keyed by the typed, diacritic-preserving term, and Garmin results are
// back-filled into `FoodCacheStore` so a food, once logged, can be shown
// offline later.
//
// `search(_:options:)` is the one-shot variant (no debounce, waits for
// every source) used by Siri and the OFF -> Garmin match.
//
// Also here: `SearchResultOrdering` (the "rows don't jump" merge the view
// applies across snapshots of one query) and `SearchConfidence` (when a
// voice command may log the top hit without asking).
//
// Depends on the FoodSearchSource implementations and SearchRanker; built
// by the app's composition root (`FoodSearchEngine.standard`). Tested by
// FoodSearchEngineTests.

import Foundation
import GarminKit

public actor FoodSearchEngine {
    public static let defaultDebounceNanoseconds: UInt64 = 250_000_000

    private let sources: [any FoodSearchSource]
    private let personalization: @Sendable () async -> SearchPersonalContext
    private let foodCache: FoodCacheStore?
    private let weights: SearchWeights
    private let debounceNanoseconds: UInt64
    private let minimumRemoteQueryLength: Int
    private let clock: @Sendable () -> Date
    private var termCache: SearchTermCache<SourcePage>
    /// The most recent complete remote answer per source, shown
    /// provisionally (re-ranked) while the next query's answer loads.
    private var lastRemoteCandidates: [SearchOrigin: [SearchCandidate]] = [:]

    public init(
        sources: [any FoodSearchSource],
        personalization: @escaping @Sendable () async -> SearchPersonalContext = { SearchPersonalContext.empty },
        foodCache: FoodCacheStore? = nil,
        weights: SearchWeights = .standard,
        debounceNanoseconds: UInt64 = FoodSearchEngine.defaultDebounceNanoseconds,
        cacheCapacity: Int = 100,
        cacheLifetime: TimeInterval = 15 * 60,
        minimumRemoteQueryLength: Int = 2,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.sources = sources
        self.personalization = personalization
        self.foodCache = foodCache
        self.weights = weights
        self.debounceNanoseconds = debounceNanoseconds
        self.minimumRemoteQueryLength = minimumRemoteQueryLength
        self.clock = clock
        self.termCache = SearchTermCache(capacity: cacheCapacity, lifetime: cacheLifetime)
    }

    /// The app's standard wiring: your own foods, Garmin (Czech region),
    /// the downloaded Czech offline index (when a holder is passed; it
    /// answers empty until an index is loaded) and live Open Food Facts,
    /// personalized from the same local stores.
    public static func standard(
        garmin: any GarminFoodSearching,
        customFoods: CustomFoodStore,
        favorites: FavoriteFoodStore,
        foodCache: FoodCacheStore,
        usageHistory: UsageHistoryStore,
        openFoodFacts: any OpenFoodFactsSearching = OpenFoodFactsClient(),
        offlineIndex: OfflineFoodIndexHolder? = nil
    ) -> FoodSearchEngine {
        let local = LocalFoodSource(customFoods: customFoods, favorites: favorites, foodCache: foodCache, usageHistory: usageHistory)
        var sources: [any FoodSearchSource] = [local, GarminSearchSource(searcher: garmin)]
        if let offlineIndex {
            sources.append(OfflineCzechIndexSource(holder: offlineIndex))
        }
        sources.append(OpenFoodFactsSource(client: openFoodFacts))
        return FoodSearchEngine(
            sources: sources,
            personalization: { await local.personalContext() },
            foodCache: foodCache
        )
    }

    /// Streams snapshots for one query; cancel the consuming task (e.g. the
    /// next keystroke restarting SwiftUI's `.task(id:)`) to stop it.
    public nonisolated func results(for rawQuery: String, options: SearchOptions = SearchOptions()) -> AsyncStream<SearchSnapshot> {
        AsyncStream { continuation in
            let task = Task {
                _ = await self.run(rawQuery, options: options, debounce: true) { snapshot in
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Every source's answer at once, without debounce.
    public func search(_ rawQuery: String, options: SearchOptions = SearchOptions()) async -> SearchSnapshot {
        await run(rawQuery, options: options, debounce: false, emit: nil)
    }

    // MARK: - Pipeline

    private struct FetchRequest: Sendable {
        let source: any FoodSearchSource
        let page: Int
    }

    private struct FetchOutcome: Sendable {
        let origin: SearchOrigin
        let page: Int
        let result: Result<SourcePage, Error>
    }

    /// Pages, pending fetches and failures for one run.
    private struct RunState {
        var pages: [SearchOrigin: [Int: SourcePage]] = [:]
        var pendingCounts: [SearchOrigin: Int] = [:]
        var failures: [SearchOrigin: SearchFailure] = [:]
        var statuses: [SearchOrigin: SourceStatus] = [:]

        mutating func store(_ page: SourcePage, origin: SearchOrigin, index: Int) {
            pages[origin, default: [:]][index] = page
        }

        /// All pages of `origin` in page order, each food once; nil when none arrived.
        func candidates(for origin: SearchOrigin) -> [SearchCandidate]? {
            guard let byIndex = pages[origin], !byIndex.isEmpty else { return nil }
            var seen = Set<String>()
            var merged: [SearchCandidate] = []
            for (_, page) in byIndex.sorted(by: { $0.key < $1.key }) {
                for candidate in page.candidates where seen.insert(candidate.food.id).inserted {
                    merged.append(candidate)
                }
            }
            return merged
        }

        func hasMore(_ origin: SearchOrigin) -> Bool {
            guard let byIndex = pages[origin], let lastIndex = byIndex.keys.max() else { return false }
            return byIndex[lastIndex]?.hasMore ?? false
        }

        func note(for origin: SearchOrigin) -> String? {
            guard let byIndex = pages[origin] else { return nil }
            return byIndex.sorted(by: { $0.key < $1.key }).compactMap { $0.value.note }.first
        }

        /// The settled status once nothing is pending for `origin`.
        func settledStatus(for origin: SearchOrigin) -> SourceStatus {
            if let failure = failures[origin] { return .failed(failure) }
            return .finished(hasMore: hasMore(origin))
        }
    }

    private func run(
        _ rawQuery: String,
        options: SearchOptions,
        debounce: Bool,
        emit: (@Sendable (SearchSnapshot) -> Void)?
    ) async -> SearchSnapshot {
        let query = SearchQuery(rawQuery)
        guard !query.isEmpty else {
            let empty = SearchSnapshot.empty(query: rawQuery)
            emit?(empty)
            return empty
        }

        let active = sources.filter { options.includes($0.origin) }
        let activeOrigins = active.map { $0.origin }
        let remoteOrigins = Set(active.filter { $0.isRemote }.map { $0.origin })
        let personal = await personalization()
        var state = RunState()

        // 1. Local sources, answered now.
        let immediate = active.filter { !$0.isRemote }.map { FetchRequest(source: $0, page: 0) }
        let immediateOutcomes = await Self.fetchAll(immediate, query: query, options: options)
        for outcome in immediateOutcomes {
            switch outcome.result {
            case .success(let page):
                state.store(page, origin: outcome.origin, index: 0)
                state.statuses[outcome.origin] = .finished(hasMore: page.hasMore)
            case .failure(let error):
                if Self.isCancellation(error) { return SearchSnapshot.empty(query: rawQuery) }
                state.statuses[outcome.origin] = .failed(SearchFailure(error: error))
            }
        }

        // 2. Remote sources: cached pages now, the rest after the debounce.
        var pending: [FetchRequest] = []
        if query.remoteKey.count >= minimumRemoteQueryLength {
            let now = clock()
            for source in active where source.isRemote {
                let pageCount = max(1, options.pages[source.origin] ?? 1)
                var missing = 0
                for page in 0..<pageCount {
                    let key = Self.cacheKey(origin: source.origin, query: query, options: options, page: page)
                    if let cached = termCache.value(forKey: key, now: now) {
                        state.store(cached, origin: source.origin, index: page)
                    } else {
                        pending.append(FetchRequest(source: source, page: page))
                        missing += 1
                    }
                }
                if missing > 0 {
                    state.pendingCounts[source.origin] = missing
                    state.statuses[source.origin] = .loading
                } else {
                    state.statuses[source.origin] = state.settledStatus(for: source.origin)
                    rememberCandidates(for: source.origin, state: state)
                }
            }
        }

        var snapshot = makeSnapshot(rawQuery, query: query, state: state, personal: personal, remoteOrigins: remoteOrigins, activeOrigins: activeOrigins)
        emit?(snapshot)
        guard !pending.isEmpty else { return snapshot }

        if debounce {
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return snapshot
            }
        }
        if Task.isCancelled { return snapshot }

        await withTaskGroup(of: FetchOutcome.self) { group in
            for request in pending {
                group.addTask { await Self.fetchOne(request, query: query, options: options) }
            }
            for await outcome in group {
                if Task.isCancelled { continue }
                let origin = outcome.origin
                switch outcome.result {
                case .success(let page):
                    termCache.insert(page, forKey: Self.cacheKey(origin: origin, query: query, options: options, page: outcome.page), now: clock())
                    state.store(page, origin: origin, index: outcome.page)
                    if origin == .garmin, let foodCache, !page.candidates.isEmpty {
                        await foodCache.upsert(page.candidates.map(\.food))
                    }
                case .failure(let error):
                    // A cancelled request is simply not an answer; an actual
                    // failure becomes this source's footnote.
                    if !Self.isCancellation(error) {
                        state.failures[origin] = SearchFailure(error: error)
                        DiagnosticsLog.log(.warning, category: "FoodSearch", "\(origin.rawValue) search failed: \(error)")
                    }
                }
                let remaining = (state.pendingCounts[origin] ?? 1) - 1
                state.pendingCounts[origin] = remaining
                if remaining <= 0 {
                    state.statuses[origin] = state.settledStatus(for: origin)
                    if state.failures[origin] == nil {
                        rememberCandidates(for: origin, state: state)
                    }
                }
                if Task.isCancelled { continue }
                snapshot = makeSnapshot(rawQuery, query: query, state: state, personal: personal, remoteOrigins: remoteOrigins, activeOrigins: activeOrigins)
                emit?(snapshot)
            }
        }
        return snapshot
    }

    private func rememberCandidates(for origin: SearchOrigin, state: RunState) {
        if let candidates = state.candidates(for: origin) {
            lastRemoteCandidates[origin] = Self.withSourceRanks(candidates)
        }
    }

    private func makeSnapshot(
        _ rawQuery: String,
        query: SearchQuery,
        state: RunState,
        personal: SearchPersonalContext,
        remoteOrigins: Set<SearchOrigin>,
        activeOrigins: [SearchOrigin]
    ) -> SearchSnapshot {
        var candidates: [SearchCandidate] = []
        var notes: [SearchOrigin: String] = [:]
        for origin in activeOrigins {
            if let list = state.candidates(for: origin) {
                candidates += remoteOrigins.contains(origin) ? Self.withSourceRanks(list) : list
                if let note = state.note(for: origin) { notes[origin] = note }
            } else if state.statuses[origin] == .loading, let previous = lastRemoteCandidates[origin] {
                candidates += previous
            }
        }
        let results = SearchRanker.rank(query, candidates: candidates, personal: personal, weights: weights)
        return SearchSnapshot(query: rawQuery, results: results, statuses: state.statuses, notes: notes)
    }

    private static func withSourceRanks(_ candidates: [SearchCandidate]) -> [SearchCandidate] {
        candidates.enumerated().map { index, candidate in
            var ranked = candidate
            ranked.sourceRank = index
            ranked.sourceCount = candidates.count
            return ranked
        }
    }

    private static func fetchAll(_ requests: [FetchRequest], query: SearchQuery, options: SearchOptions) async -> [FetchOutcome] {
        await withTaskGroup(of: FetchOutcome.self, returning: [FetchOutcome].self) { group in
            for request in requests {
                group.addTask { await fetchOne(request, query: query, options: options) }
            }
            var outcomes: [FetchOutcome] = []
            for await outcome in group { outcomes.append(outcome) }
            return outcomes
        }
    }

    private static func fetchOne(_ request: FetchRequest, query: SearchQuery, options: SearchOptions) async -> FetchOutcome {
        do {
            let page = try await request.source.search(query, page: request.page, options: options)
            return FetchOutcome(origin: request.source.origin, page: request.page, result: .success(page))
        } catch {
            return FetchOutcome(origin: request.source.origin, page: request.page, result: .failure(error))
        }
    }

    static func cacheKey(origin: SearchOrigin, query: SearchQuery, options: SearchOptions, page: Int) -> String {
        "\(origin.rawValue)|\(options.czechOnly ? "cz" : "all")|\(page)|\(query.remoteKey)"
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

/// A small LRU cache with a time-to-live, for remote result pages.
struct SearchTermCache<Value> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    let capacity: Int
    let lifetime: TimeInterval
    private var entries: [String: Entry] = [:]
    /// Least recently used first.
    private var recency: [String] = []

    init(capacity: Int, lifetime: TimeInterval) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
    }

    var count: Int { entries.count }

    mutating func value(forKey key: String, now: Date) -> Value? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) <= lifetime else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.value
    }

    mutating func insert(_ value: Value, forKey key: String, now: Date) {
        entries[key] = Entry(value: value, storedAt: now)
        touch(key)
        while recency.count > capacity, let oldest = recency.first {
            remove(oldest)
        }
    }

    private mutating func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private mutating func remove(_ key: String) {
        entries.removeValue(forKey: key)
        recency.removeAll { $0 == key }
    }
}

/// Keeps a result list from jumping while one query's snapshots arrive
/// (design.md D5): rows already shown keep their relative order, rows no
/// longer present leave, new rows are slotted in by score.
public enum SearchResultOrdering {
    public static func stableMerge(previous: [SearchResult], incoming: [SearchResult]) -> [SearchResult] {
        let incomingById = Dictionary(incoming.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var merged = previous.compactMap { incomingById[$0.id] }
        let keptIds = Set(merged.map(\.id))
        for row in incoming where !keptIds.contains(row.id) {
            let index = merged.firstIndex { $0.score < row.score } ?? merged.count
            merged.insert(row, at: index)
        }
        return merged
    }
}

/// Whether a voice command ("log rohlík") may act on the top hit alone
/// (rebuild-food-search task 4.3).
public enum SearchConfidence {
    public enum Decision: Sendable, Equatable {
        case confident(SearchResult)
        /// Up to three plausible results to offer back instead of guessing.
        case ambiguous([SearchResult])
        case noMatch
    }

    /// The top hit's words must all match, nearly exactly...
    public static let minimumTextScore = 0.85
    /// ...and it must lead the runner-up by a clear margin (a food the user
    /// logs often earns that margin through the personal boost).
    public static let minimumLead = 0.05

    public static func decide(_ results: [SearchResult]) -> Decision {
        guard let top = results.first else { return .noMatch }
        let strongMatch = top.coversQuery && top.textScore >= minimumTextScore
        let clearLead = results.dropFirst().first.map { top.score - $0.score >= minimumLead } ?? true
        if strongMatch && clearLead { return .confident(top) }
        return .ambiguous(Array(results.prefix(3)))
    }
}

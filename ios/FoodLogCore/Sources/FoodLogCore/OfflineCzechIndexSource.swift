// OfflineCzechIndexSource.swift
//
// The downloaded Czech Open Food Facts index as a `FoodSearchSource`
// (add-offline-czech-food-index task 3.2). It answers from memory with no
// network: `isRemote == false`, so FoodSearchEngine asks it on every
// keystroke alongside the user's own foods, never debounced. That is why
// OfflineFoodIndex answers nothing for a single letter and stops scoring
// once the next keystroke cancels this search (a cancelled search throws
// CancellationError here, like any other source). Its results
// are ranked and deduped with every other source's by `SearchRanker`. A
// product also found by live OFF search merges by EAN (SearchDedup's
// identity key), and live OFF still runs to catch products newer than the
// last weekly build.
//
// Local-first: search must never wait for the index. The loaded index
// sits in `OfflineFoodIndexHolder`, a lock-protected box read
// synchronously. So while OfflineIndexStore is still decoding (a few
// hundred ms after launch) or when nothing is downloaded yet, this source
// simply answers empty, and search behaves exactly as it did without it
// (spec "No index yet").
//
// The holder is also the barcode fallback (`OfflineBarcodeLookup`, used by
// BarcodeResolution). Depends on OfflineFoodIndex. Built by the app's
// composition root; tested by OfflineFoodIndexTests.

import Foundation

/// The currently loaded offline index, shared by the search source, the
/// barcode fallback and the store that installs new versions. Reads never
/// block on a decode in progress.
public final class OfflineFoodIndexHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var current: OfflineFoodIndex?

    public init(index: OfflineFoodIndex? = nil) {
        self.current = index
    }

    public var index: OfflineFoodIndex? {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    public func replace(with index: OfflineFoodIndex?) {
        lock.lock()
        current = index
        lock.unlock()
    }
}

/// Where the barcode flow looks after Garmin misses (design.md D4).
public protocol OfflineBarcodeLookup: Sendable {
    /// An Open Food Facts-shaped food for `code`, or nil.
    func food(forBarcode code: String) async -> Food?
}

extension OfflineFoodIndexHolder: OfflineBarcodeLookup {
    public func food(forBarcode code: String) async -> Food? {
        index?.product(code: code)?.food
    }
}

public struct OfflineCzechIndexSource: FoodSearchSource {
    private let holder: OfflineFoodIndexHolder

    public init(holder: OfflineFoodIndexHolder) {
        self.holder = holder
    }

    public var origin: SearchOrigin { .offlineIndex }
    public var isRemote: Bool { false }

    /// The index is Czech-only by construction, so `options.czechOnly` has
    /// nothing to filter. Page 0 only: the top 50 is already more than the
    /// ranked list shows.
    public func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage {
        guard page == 0, let index = holder.index else { return SourcePage() }
        try Task.checkCancellation()
        let candidates = index.candidates(for: query)
        // `candidates(for:)` stops early and answers empty once cancelled;
        // report that as the cancellation it is, not as "no matches".
        try Task.checkCancellation()
        return SourcePage(candidates: candidates)
    }
}

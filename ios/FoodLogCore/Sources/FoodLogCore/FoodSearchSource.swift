// FoodSearchSource.swift
//
// The vocabulary of the unified food search (rebuild-food-search): one
// protocol every database plugs into, and the value types that flow from a
// source, through `SearchRanker`, to the screen. Before this there were two
// unrelated pipelines (Garmin's `FoodCatalogSearch` and the OFF client's
// own two-bucket rerank) whose results were shown as separate, unmerged
// lists, and the user's own foods weren't searched at all.
//
// A source only FINDS candidates; it never scores them. Ranking, the
// garbage threshold and cross-source dedup happen once, in `SearchRanker`,
// so every source -- local foods, Garmin, Open Food Facts, and later the
// offline Czech index (add-offline-czech-food-index) -- is judged by the
// same Czech-aware rules. That offline index is why `isRemote` exists:
// it answers instantly from memory like the local source, so it must not
// be debounced or skipped for short queries the way network sources are.
//
// Depended on by FoodSearchEngine (orchestration), the source
// implementations, and the app's SearchResultsSection. No SwiftUI.

import Foundation
import GarminKit

/// Where a result came from. Order matters: it is the dedup precedence
/// (design.md D4 -- the directly loggable copy wins) and the final
/// tie-breaker when two results score the same.
public enum SearchOrigin: String, Sendable, Hashable, CaseIterable, Codable {
    /// The user's own foods: custom foods, favorites, and foods they've logged.
    case local
    /// Garmin's food database (`GET /nutrition-service/food/search`).
    case garmin
    /// The downloadable Czech Open Food Facts index (add-offline-czech-food-index).
    case offlineIndex
    /// Live Open Food Facts search.
    case openFoodFacts

    /// Lower wins when two sources carry the same product.
    public var precedence: Int {
        switch self {
        case .local: return 0
        case .garmin: return 1
        case .offlineIndex: return 2
        case .openFoodFacts: return 3
        }
    }

    /// Whether a result can be logged straight away IN GARMIN MODE. Open
    /// Food Facts products (live or offline) first need the Garmin match
    /// step (`MatchConfirmationView`), because Garmin only accepts its own
    /// foods. Also the ranking prior (`SearchRanker`) and the "real Garmin
    /// foods only" filter of the custom-food backing picker, which exist
    /// only in Garmin mode. Anything that routes a tap uses
    /// `isDirectlyLoggable(in:)`.
    public var isDirectlyLoggable: Bool {
        isDirectlyLoggable(in: .garminConnected)
    }

    /// add-standalone-mode D5: in standalone mode EVERY origin is logged as
    /// itself (serving picker, then the confirm screen; the local log keeps
    /// its nutrients), so nothing needs a Garmin match. Garmin mode keeps
    /// today's rule.
    public func isDirectlyLoggable(in mode: DataMode) -> Bool {
        switch mode {
        case .standalone: return true
        case .garminConnected: return self == .local || self == .garmin
        }
    }
}

/// One food a source found, before scoring.
public struct SearchCandidate: Sendable, Equatable {
    public let food: Food
    public let origin: SearchOrigin
    /// Other names the product is known by (e.g. OFF's English name when
    /// the Czech one is displayed). Matched at `SearchWeights.aliasFactor`.
    public var alternateNames: [String]
    /// Set for the user's own custom foods, so a tap can route through the
    /// draft (a custom food's id means nothing to Garmin).
    public var customDraft: CustomFoodDraft?
    /// Position in the source's own result order and that list's length.
    /// Filled in by `FoodSearchEngine` for remote sources so Garmin's own
    /// relevance signal survives as a small tie-breaker; 0/0 means "no
    /// source order" (local foods).
    public var sourceRank: Int
    public var sourceCount: Int

    public init(
        food: Food,
        origin: SearchOrigin,
        alternateNames: [String] = [],
        customDraft: CustomFoodDraft? = nil,
        sourceRank: Int = 0,
        sourceCount: Int = 0
    ) {
        self.food = food
        self.origin = origin
        self.alternateNames = alternateNames
        self.customDraft = customDraft
        self.sourceRank = sourceRank
        self.sourceCount = sourceCount
    }
}

/// One ranked row of the unified result list.
public struct SearchResult: Sendable, Equatable, Identifiable {
    public let food: Food
    public let origin: SearchOrigin
    /// Other sources that carried the same product (merged away by
    /// `SearchDedup`), in precedence order -- shown as "also in …".
    public let alsoIn: [SearchOrigin]
    /// The full ranking score (relevance + personal + priors).
    public let score: Double
    /// The text-match part alone (0...1), before bonuses -- what
    /// `SearchConfidence` judges.
    public let textScore: Double
    /// Every query word matched something in the name or brand.
    public let coversQuery: Bool
    public let customDraft: CustomFoodDraft?

    public init(
        food: Food,
        origin: SearchOrigin,
        alsoIn: [SearchOrigin] = [],
        score: Double,
        textScore: Double,
        coversQuery: Bool,
        customDraft: CustomFoodDraft? = nil
    ) {
        self.food = food
        self.origin = origin
        self.alsoIn = alsoIn
        self.score = score
        self.textScore = textScore
        self.coversQuery = coversQuery
        self.customDraft = customDraft
    }

    public var id: String { "\(origin.rawValue):\(food.id)" }
}

/// One page of a source's answer.
public struct SourcePage: Sendable, Equatable {
    public var candidates: [SearchCandidate]
    /// The source has another page ("Show more").
    public var hasMore: Bool
    /// A short user-facing note about how this page was produced, e.g. that
    /// Open Food Facts fell back to worldwide results.
    public var note: String?

    public init(candidates: [SearchCandidate] = [], hasMore: Bool = false, note: String? = nil) {
        self.candidates = candidates
        self.hasMore = hasMore
        self.note = note
    }
}

public struct SearchOptions: Sendable, Equatable {
    /// Limit Open Food Facts to products sold in Czechia (the catalog's
    /// "Czech only" toggle). Falls back to worldwide when that finds nothing.
    public var czechOnly: Bool
    /// Only these sources are asked; `nil` means all of them.
    public var origins: Set<SearchOrigin>?
    /// How many pages to include per remote source ("Show more"); 1 when absent.
    public var pages: [SearchOrigin: Int]

    public init(czechOnly: Bool = true, origins: Set<SearchOrigin>? = nil, pages: [SearchOrigin: Int] = [:]) {
        self.czechOnly = czechOnly
        self.origins = origins
        self.pages = pages
    }

    public func includes(_ origin: SearchOrigin) -> Bool {
        origins?.contains(origin) ?? true
    }
}

/// Why a source produced nothing. Deliberately coarse: the UI turns it into
/// a per-source footnote, never a global error (design.md D5), except that
/// a signed-out Garmin stays loud (CLAUDE.md: auth failures are loud).
public struct SearchFailure: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Garmin has no usable login -- the user must sign in again.
        case signedOut
        /// Network, server or decoding trouble.
        case unavailable
    }

    public let kind: Kind
    /// For DiagnosticsLog and debugging, not for display.
    public let detail: String

    public init(kind: Kind, detail: String) {
        self.kind = kind
        self.detail = detail
    }

    public init(error: Error) {
        if let auth = error as? GarminAuthError, auth == .notSignedIn || auth == .longLivedTokenExpired {
            self.init(kind: .signedOut, detail: String(describing: error))
        } else {
            self.init(kind: .unavailable, detail: String(describing: error))
        }
    }
}

public enum SourceStatus: Sendable, Equatable {
    case loading
    case finished(hasMore: Bool)
    case failed(SearchFailure)
}

/// Everything the screen needs at one moment of one query.
public struct SearchSnapshot: Sendable, Equatable {
    public let query: String
    public let results: [SearchResult]
    /// One entry per source that was asked.
    public let statuses: [SearchOrigin: SourceStatus]
    public let notes: [SearchOrigin: String]

    public init(query: String, results: [SearchResult], statuses: [SearchOrigin: SourceStatus], notes: [SearchOrigin: String] = [:]) {
        self.query = query
        self.results = results
        self.statuses = statuses
        self.notes = notes
    }

    public static func empty(query: String) -> SearchSnapshot {
        SearchSnapshot(query: query, results: [], statuses: [:])
    }

    /// Every asked source has answered (successfully or not). "No matches"
    /// may only be shown once this is true.
    public var isComplete: Bool {
        !statuses.values.contains(.loading)
    }
}

/// A database the unified search can ask.
public protocol FoodSearchSource: Sendable {
    var origin: SearchOrigin { get }
    /// Network-backed sources are debounced, cached and skipped for
    /// one-letter queries; the others answer on every keystroke.
    var isRemote: Bool { get }
    /// Candidates for `query` -- not yet scored or filtered; `SearchRanker`
    /// does that. `page` is 0-based.
    func search(_ query: SearchQuery, page: Int, options: SearchOptions) async throws -> SourcePage
}

/// What the user's own history says about each food, for the personal boost.
public struct SearchPersonalContext: Sendable, Equatable {
    /// Log count per food id, each log decayed by age (half-life
    /// `defaultHalfLifeDays`), so both frequency and recency count.
    public var decayedUseCounts: [String: Double]
    public var favoriteFoodIds: Set<String>

    public static let defaultHalfLifeDays = 30.0
    public static let empty = SearchPersonalContext()

    public init(decayedUseCounts: [String: Double] = [:], favoriteFoodIds: Set<String> = []) {
        self.decayedUseCounts = decayedUseCounts
        self.favoriteFoodIds = favoriteFoodIds
    }

    public static func build(
        events: [UsageEvent],
        favoriteFoodIds: Set<String>,
        now: Date = Date(),
        halfLifeDays: Double = SearchPersonalContext.defaultHalfLifeDays
    ) -> SearchPersonalContext {
        var counts: [String: Double] = [:]
        for event in events {
            let ageInDays = max(0, now.timeIntervalSince(event.timestamp) / 86_400)
            counts[event.foodId, default: 0] += pow(0.5, ageInDays / max(halfLifeDays, 0.0001))
        }
        return SearchPersonalContext(decayedUseCounts: counts, favoriteFoodIds: favoriteFoodIds)
    }
}

// SearchResultsSection.swift
//
// The catalog's search results as ONE ranked list (rebuild-food-search task
// 4.1). Before this, FoodCatalogView showed three separately-loaded
// sections while typing -- a name-filtered custom-food list, Garmin's raw
// "Results" and a separate "Czech database" list -- each with its own
// spinner and error text, so the same product could appear twice and a
// cancelled request flashed an error on every fast keystroke.
//
// Lives in its own file (not inside FoodCatalogView) so the search UI and
// the empty-query shelves can change independently. It owns no routing:
// every tap goes back through closures the catalog passes in, so the
// picker rules from fix-testing-feedback-quick-wins stay in one place
// (FoodCatalogView.select / selectCustomFood / matchingTarget).
//
// `FoodSearchModel` consumes `FoodSearchEngine`'s snapshot stream for the
// current query and keeps rows stable across snapshots of that query
// (`SearchResultOrdering.stableMerge`); ranking, dedup and per-source
// status all come from FoodLogCore. Previous results stay on screen while
// a new query loads; "No matches" appears only once every source answered;
// a failing source is a footnote, and a signed-out Garmin says so plainly.
//
// Depends on FoodLogCore (engine, SearchResult) and the design-system
// components (FoodListRow, FavoriteToggleButton, EmptyStateView).

import SwiftUI
import Observation
import FoodLogCore

/// The current query's results, kept stable while snapshots stream in.
@MainActor
@Observable
final class FoodSearchModel {
    private(set) var results: [SearchResult] = []
    private(set) var snapshot: SearchSnapshot?
    /// Bumped by "Show more"; part of the hosting view's `.task(id:)`, so
    /// the same query re-runs with one more page (the pages already fetched
    /// come straight from the engine's term cache).
    private(set) var reloadToken = 0

    @ObservationIgnored private var activeQuery = ""
    @ObservationIgnored private var pages: [SearchOrigin: Int] = [:]

    /// Runs until the stream ends or the calling task is cancelled (the
    /// next keystroke restarting `.task(id:)`). Cancellation just stops
    /// here -- it is never shown.
    func run(query rawQuery: String, engine: FoodSearchEngine, options: SearchOptions) async {
        let query = SearchText.typedPhrase(rawQuery)
        guard !query.isEmpty else {
            results = []
            snapshot = nil
            activeQuery = ""
            pages = [:]
            return
        }

        let isSameQuery = query == activeQuery
        if !isSameQuery { pages = [:] }
        activeQuery = query
        var requestOptions = options
        requestOptions.pages = pages

        var isFirstSnapshot = true
        for await next in engine.results(for: rawQuery, options: requestOptions) {
            if Task.isCancelled { break }
            if isFirstSnapshot && !isSameQuery {
                // A new query: its ranking replaces the old one wholesale
                // (the engine already carries still-matching remote rows over).
                results = next.results
            } else {
                results = SearchResultOrdering.stableMerge(previous: results, incoming: next.results)
            }
            snapshot = next
            isFirstSnapshot = false
        }
    }

    func showMore(from origin: SearchOrigin) {
        pages[origin] = (pages[origin] ?? 1) + 1
        reloadToken += 1
    }
}

@MainActor
struct SearchResultsSection: View {
    let model: FoodSearchModel
    /// `pickBackingFood`: only a real Garmin food can back a custom food, so
    /// the user's custom foods and Open Food Facts products are hidden.
    var garminFoodsOnly = false
    /// The Open Food Facts "Czech only" switch; `nil` hides it (when Open
    /// Food Facts isn't searched at all).
    var czechOnly: Binding<Bool>?
    /// Favorite stars; `nil` hides them (picker modes).
    var isFavorite: ((Food) -> Bool)?
    var onToggleFavorite: ((Food) -> Void)?
    /// A Garmin food (or one of the user's logged Garmin foods).
    let onSelectFood: (Food) -> Void
    let onSelectCustomFood: (CustomFoodDraft) -> Void
    /// An Open Food Facts product -- needs the Garmin match step first.
    let onSelectOpenFoodFactsFood: (Food) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleResults: [SearchResult] {
        guard garminFoodsOnly else { return model.results }
        return model.results.filter { result in
            result.origin.isDirectlyLoggable && result.customDraft == nil && result.food.source != .custom
        }
    }

    var body: some View {
        Section {
            ForEach(visibleResults) { result in
                row(for: result)
            }
            statusRows
        } header: {
            if !visibleResults.isEmpty {
                SectionHeader(title: "Results")
            }
        }
        .animation(reduceMotion ? nil : .default, value: visibleResults.map(\.id))
    }

    // MARK: - Rows

    @ViewBuilder
    private func row(for result: SearchResult) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                select(result)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    FoodListRow(food: result.food, serving: result.food.servings.first)
                    SearchSourceBadges(result: result)
                        .padding(.bottom, Theme.Spacing.xs)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(hint(for: result))
            if let isFavorite, let onToggleFavorite, result.origin.isDirectlyLoggable {
                FavoriteToggleButton(isFavorite: isFavorite(result.food)) {
                    onToggleFavorite(result.food)
                }
            }
        }
    }

    private func hint(for result: SearchResult) -> String {
        result.origin.isDirectlyLoggable ? "Selects this food" : "Finds the matching Garmin food first"
    }

    private func select(_ result: SearchResult) {
        if let draft = result.customDraft {
            onSelectCustomFood(draft)
        } else if result.origin.isDirectlyLoggable {
            onSelectFood(result.food)
        } else {
            onSelectOpenFoodFactsFood(result.food)
        }
    }

    // MARK: - Status, footnotes, paging

    @ViewBuilder
    private var statusRows: some View {
        if let snapshot = model.snapshot {
            if !snapshot.isComplete {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loadingText(snapshot))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }

            ForEach(footnotes(for: snapshot), id: \.self) { note in
                Label(note.text, systemImage: note.systemImage)
                    .font(.caption)
                    .foregroundStyle(note.isWarning ? Theme.warning : .secondary)
            }

            if case .finished(hasMore: true)? = snapshot.statuses[.garmin] {
                Button {
                    model.showMore(from: .garmin)
                } label: {
                    Label("Show more from Garmin", systemImage: "chevron.down")
                        .font(.subheadline)
                }
            }

            if snapshot.isComplete, visibleResults.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No matches",
                    message: garminFoodsOnly
                        ? "Garmin's database doesn't seem to have this. Try another spelling."
                        : "Try another spelling, or create it as a custom food."
                )
                .listRowSeparator(.hidden)
            }
        }

        if let czechOnly {
            Toggle("Open Food Facts: Czech products only", isOn: czechOnly)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Limit Open Food Facts results to Czech products")
        }
    }

    private func loadingText(_ snapshot: SearchSnapshot) -> String {
        let loading = SearchOrigin.allCases.filter { snapshot.statuses[$0] == .loading }
        let names = loading.map { $0.displayName }
        guard !names.isEmpty else { return "Searching…" }
        return "Searching " + ListFormatter.localizedString(byJoining: names) + "…"
    }

    private func footnotes(for snapshot: SearchSnapshot) -> [SearchFootnote] {
        let databaseOrigins: [SearchOrigin] = [.garmin, .offlineIndex, .openFoodFacts]
        let onlineOrigins: [SearchOrigin] = [.garmin, .openFoodFacts]
        let askedOnline = onlineOrigins.filter { snapshot.statuses[$0] != nil }
        let failures = databaseOrigins.compactMap { origin -> (origin: SearchOrigin, failure: SearchFailure)? in
            if case .failed(let failure)? = snapshot.statuses[origin] {
                return (origin, failure)
            }
            return nil
        }

        var notes: [SearchFootnote] = []
        // Auth failures are loud (CLAUDE.md): say exactly what to do.
        if failures.contains(where: { $0.origin == .garmin && $0.failure.kind == .signedOut }) {
            notes.append(SearchFootnote(
                text: "Sign in to Garmin again (Settings) to search its food database.",
                systemImage: "person.crop.circle.badge.exclamationmark",
                isWarning: true
            ))
        }
        let unavailable = failures.filter { $0.failure.kind == .unavailable }.map { $0.origin }
        // Offline typing (food-catalog spec): every online database failed,
        // so say that once instead of once per database.
        let allOnlineUnavailable = !askedOnline.isEmpty
            && askedOnline.allSatisfy { origin in unavailable.contains(origin) }
        if allOnlineUnavailable {
            let hasOfflineResults = snapshot.results.contains { $0.origin == .offlineIndex }
            notes.append(SearchFootnote(
                text: hasOfflineResults
                    ? "Online food databases are unavailable right now, so these are your foods and the offline Czech database."
                    : "Online food databases are unavailable right now, so these are foods you already have.",
                systemImage: "wifi.slash",
                isWarning: false
            ))
        }
        for origin in unavailable where !(allOnlineUnavailable && onlineOrigins.contains(origin)) {
            notes.append(SearchFootnote(
                text: "\(origin.sentenceName) is unavailable right now, so its results are missing.",
                systemImage: "exclamationmark.icloud",
                isWarning: false
            ))
        }
        if let note = snapshot.notes[.openFoodFacts] {
            notes.append(SearchFootnote(text: note, systemImage: "globe.europe.africa", isWarning: false))
        }
        return notes
    }
}

private struct SearchFootnote: Hashable {
    let text: String
    let systemImage: String
    let isWarning: Bool
}

/// "Garmin" / "Open Food Facts" / "Yours", plus "also in …" when the same
/// product came from more than one source (design.md D4 provenance).
private struct SearchSourceBadges: View {
    let result: SearchResult

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(result.origin.badgeTitle)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, Theme.Spacing.xs)
                .padding(.vertical, 1)
                .background(result.origin.badgeColor.opacity(0.15), in: Capsule())
                .foregroundStyle(result.origin.badgeColor)
            if !result.alsoIn.isEmpty {
                Text("also in " + result.alsoIn.map { $0.displayName }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let source = "From \(result.origin.displayName)"
        guard !result.alsoIn.isEmpty else { return source }
        return source + ", also in " + result.alsoIn.map { $0.displayName }.joined(separator: ", ")
    }
}

private extension SearchOrigin {
    var displayName: String {
        switch self {
        case .local: return "your foods"
        case .garmin: return "Garmin"
        case .offlineIndex: return "the offline Czech database"
        case .openFoodFacts: return "Open Food Facts"
        }
    }

    /// `displayName` for the start of a sentence.
    var sentenceName: String {
        switch self {
        case .local: return "Your foods"
        case .garmin: return "Garmin"
        case .offlineIndex: return "The offline Czech database"
        case .openFoodFacts: return "Open Food Facts"
        }
    }

    var badgeTitle: String {
        switch self {
        case .local: return "Yours"
        case .garmin: return "Garmin"
        case .offlineIndex: return "Czech DB"
        case .openFoodFacts: return "Open Food Facts"
        }
    }

    var badgeColor: Color {
        switch self {
        case .local: return Theme.accent
        case .garmin: return Theme.carbs
        case .offlineIndex: return Theme.grace
        case .openFoodFacts: return Theme.success
        }
    }
}

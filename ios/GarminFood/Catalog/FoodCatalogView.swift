// FoodCatalogView.swift
//
// The food catalog screen (tasks 12-13): search, a locally-ranked quick-pick
// shelf, custom foods, and a barcode-scan entry point. Doubles as the
// "pick the closest matching Garmin food" picker for the custom-food editor
// (design.md D4) via `mode`, per config.yaml's "small, composable views"
// principle -- one screen, two jobs, rather than a near-duplicate second
// screen.
//
// What gets logged/committed is decided by `LogEntryConfirmView`, reached
// via `LogTarget` (see LogTarget.swift) -- this screen's only job is
// choosing WHAT to log, never committing it itself.

import SwiftUI
import FoodLogCore
import GarminKit

// `@MainActor` on this and the other flow screens (LogEntryConfirmView,
// CustomFoodEditorView, BarcodeScanScreen) so their private helper methods
// (which launch `Task { ... }` blocks that mutate `@State`) are guaranteed
// to run on the main actor -- an unstructured `Task` only inherits the
// actor of the LEXICAL context where it's created, not of whatever called
// the enclosing method, so a plain (non-isolated) method launching a Task
// from a Button action is not automatically MainActor-safe without this.
@MainActor
struct FoodCatalogView: View {
    enum Mode {
        /// The primary, real logging flow.
        case logFood
        /// Reused by the custom-food editor to pick the existing Garmin
        /// food+serving a custom food is backed by (design.md D4).
        case pickBackingFood(onPick: (Food, Serving) -> Void)
    }

    var mode: Mode = .logFood

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [Food] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?

    // Czech (Open Food Facts) results (add-czech-food-catalog task 28.1) --
    // deliberately separate state from the Garmin search above, never
    // merged, per design.md D5.
    @State private var czechOnly = true
    @State private var czechSearchResults: [Food] = []
    @State private var isCzechSearching = false
    @State private var czechSearchErrorMessage: String?
    @State private var matchingTarget: Food?

    @State private var quickPickItems: [QuickPickItem] = []
    @State private var customFoods: [CustomFoodDraft] = []

    @State private var logTarget: LogTarget?
    @State private var foodAwaitingServingPick: Food?
    @State private var isPresentingCustomFoodEditor = false
    @State private var isPresentingBarcodeScanner = false
    @State private var barcodeNoteForNewCustomFood: String?

    private var isPickingBackingFood: Bool {
        if case .pickBackingFood = mode { return true }
        return false
    }

    var body: some View {
        List {
            if !isPickingBackingFood, searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                if !quickPickItems.isEmpty {
                    Section {
                        QuickPickShelf(items: quickPickItems) { item in
                            logTarget = .catalog(food: item.food, initialServing: item.serving)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    } header: {
                        SectionHeader(title: "Quick pick")
                    }
                }

                if !customFoods.isEmpty {
                    Section {
                        ForEach(customFoods) { draft in
                            Button {
                                logTarget = .custom(draft)
                            } label: {
                                FoodListRow(food: draft.asFood(), serving: draft.asFood().servings.first)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        SectionHeader(title: "Your custom foods")
                    }
                }
            }

            Section {
                if isSearching {
                    HStack {
                        ProgressView()
                        Text("Searching Garmin's food database…")
                            .foregroundStyle(.secondary)
                    }
                } else if let searchErrorMessage {
                    Text(searchErrorMessage)
                        .foregroundStyle(.secondary)
                } else if searchResults.isEmpty, !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No matches",
                        message: "Garmin's database doesn't have this. You can create it as a custom food instead."
                    )
                } else {
                    ForEach(searchResults) { food in
                        Button {
                            select(food)
                        } label: {
                            FoodListRow(food: food, serving: food.servings.first)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                if !searchResults.isEmpty { SectionHeader(title: "Results") }
            }

            // Czech (Open Food Facts) results -- visibly separate from
            // Garmin's own "Results" section above, per design.md D5 /
            // the czech-food-catalog spec's "never merged" requirement.
            // Hidden in `pickBackingFood` mode: that picker's whole job is
            // finding an existing GARMIN food to back a custom food, so an
            // OFF result (which itself needs matching/creation) doesn't
            // belong there.
            if !isPickingBackingFood, !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Section {
                    if isCzechSearching {
                        HStack {
                            ProgressView()
                            Text("Searching Open Food Facts…")
                                .foregroundStyle(.secondary)
                        }
                    } else if let czechSearchErrorMessage {
                        Text(czechSearchErrorMessage)
                            .foregroundStyle(.secondary)
                    } else if czechSearchResults.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "No Czech-database matches",
                            message: "Open Food Facts doesn't have this yet."
                        )
                    } else {
                        ForEach(czechSearchResults) { food in
                            Button {
                                matchingTarget = food
                            } label: {
                                FoodListRow(food: food, serving: food.servings.first)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text("Czech database (Open Food Facts)")
                            .font(.sectionHeader)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Czech only", isOn: $czechOnly)
                            .font(.caption)
                            .fixedSize()
                            .accessibilityLabel("Limit Open Food Facts results to Czech products")
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if searchText.trimmingCharacters(in: .whitespaces).isEmpty, quickPickItems.isEmpty, customFoods.isEmpty, !isPickingBackingFood {
                EmptyStateView(
                    systemImage: "fork.knife",
                    title: "Nothing logged yet",
                    message: "Search for a food to get started -- your most-logged foods will show up here as a quick pick."
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search foods (rohlík, chleba, tvaroh…)")
        .navigationTitle(isPickingBackingFood ? "Pick closest match" : "Log Food")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !isPickingBackingFood {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingBarcodeScanner = true
                    } label: {
                        Label("Scan barcode", systemImage: "barcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        barcodeNoteForNewCustomFood = nil
                        isPresentingCustomFoodEditor = true
                    } label: {
                        Label("New custom food", systemImage: "plus")
                    }
                }
            }
        }
        .task {
            await loadLocalData()
            presentScannerIfRouteIsPending()
        }
        .task(id: searchText) { await performSearch() }
        .task(id: "\(searchText)#\(czechOnly)") { await performCzechSearch() }
        // Wired for add-glanceable-surfaces' barcode-scan Control
        // (Shared/OpenBarcodeScannerIntent.swift): that intent only ever
        // sets `AppNavigationBridge`'s pending route once its `perform()`
        // genuinely executes in THIS app's own process (see that file's
        // header) -- by then this view may already be on screen (hence the
        // `.onChange` below) or not yet (hence the `.task` above also
        // checking on appear); either ordering is covered.
        .onChange(of: AppNavigationBridge.shared.pendingRoute) { _, _ in
            presentScannerIfRouteIsPending()
        }
        .sheet(item: $foodAwaitingServingPick) { food in
            ServingPickerSheet(food: food) { serving in
                handleServingPicked(food: food, serving: serving)
            }
        }
        .sheet(isPresented: $isPresentingCustomFoodEditor, onDismiss: { Task { await loadLocalData() } }) {
            NavigationStack {
                CustomFoodEditorView(prefillNote: barcodeNoteForNewCustomFood)
            }
        }
        .fullScreenCover(isPresented: $isPresentingBarcodeScanner) {
            BarcodeScanScreen(
                onResolved: { food in
                    isPresentingBarcodeScanner = false
                    select(food)
                },
                onUnresolved: { code in
                    isPresentingBarcodeScanner = false
                    barcodeNoteForNewCustomFood = "Scanned barcode: \(code) (not found in Garmin's database)"
                    isPresentingCustomFoodEditor = true
                },
                onCancel: { isPresentingBarcodeScanner = false }
            )
        }
        .navigationDestination(item: $logTarget) { target in
            LogEntryConfirmView(target: target)
        }
        // Task 28.2: picking a Czech-database result routes into the
        // matching flow instead of straight to the confirm screen.
        .navigationDestination(item: $matchingTarget) { offFood in
            MatchConfirmationView(offFood: offFood)
        }
    }

    /// Presents the barcode scanner if `AppNavigationBridge` has a pending
    /// request for it (add-glanceable-surfaces' barcode-scan Control) --
    /// consumes the request immediately so it can never re-trigger itself on
    /// a later, unrelated view update. Skipped in `pickBackingFood` mode: a
    /// Control-driven scan should only ever land on the primary logging
    /// flow, never the custom-food editor's internal "pick a backing food"
    /// screen.
    private func presentScannerIfRouteIsPending() {
        guard !isPickingBackingFood, AppNavigationBridge.shared.pendingRoute == .barcodeScanner else { return }
        _ = AppNavigationBridge.shared.consume()
        isPresentingBarcodeScanner = true
    }

    private func select(_ food: Food) {
        switch mode {
        case .pickBackingFood:
            foodAwaitingServingPick = food
        case .logFood:
            Task {
                let remembered = await environment.servingDefaults.defaultServing(forFoodId: food.id)
                if let serving = ServingResolution.resolve(remembered, in: food) {
                    logTarget = .catalog(food: food, initialServing: serving)
                } else {
                    foodAwaitingServingPick = food
                }
            }
        }
    }

    private func handleServingPicked(food: Food, serving: Serving) {
        switch mode {
        case .pickBackingFood(let onPick):
            onPick(food, serving)
            dismiss()
        case .logFood:
            logTarget = .catalog(food: food, initialServing: serving)
        }
    }

    private func loadLocalData() async {
        let events = await environment.usageHistory.all()
        let ranked = QuickPick.rank(events: events)
        let cache = await environment.foodCache.all()

        quickPickItems = ranked.compactMap { entry -> QuickPickItem? in
            guard let food = cache[entry.foodId] else { return nil }
            guard let serving = food.servings.first(where: { $0.id == entry.servingId }) else { return nil }
            return QuickPickItem(food: food, serving: serving, numberOfUnits: entry.numberOfUnits)
        }

        if !isPickingBackingFood {
            customFoods = await environment.customFoodStore.all()
        }
    }

    private func performSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            searchResults = []
            searchErrorMessage = nil
            return
        }

        // Debounce: `.task(id:)` cancels and restarts this whole task every
        // time `searchText` changes, so a cancelled sleep here means a newer
        // keystroke has already superseded this search.
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await environment.catalogSearch.search(term: trimmed)
            searchErrorMessage = nil
        } catch {
            searchResults = []
            searchErrorMessage = "Couldn't reach Garmin right now. Check your connection or try again."
        }
    }

    /// Task 28.1: the Czech (Open Food Facts) search, "debounced the same
    /// way the existing Garmin search already is". A completely separate
    /// `.task(id:)`/debounce from `performSearch()` above -- the two
    /// sources are independent network calls to independent hosts, per
    /// design.md D5, so one failing or being slow never blocks the other.
    private func performCzechSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            czechSearchResults = []
            czechSearchErrorMessage = nil
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }

        isCzechSearching = true
        defer { isCzechSearching = false }
        do {
            czechSearchResults = try await environment.openFoodFactsClient.search(term: trimmed, czechOnly: czechOnly)
            czechSearchErrorMessage = nil
        } catch {
            czechSearchResults = []
            czechSearchErrorMessage = "Couldn't reach Open Food Facts right now. Check your connection or try again."
        }
    }
}

struct QuickPickItem: Identifiable {
    let food: Food
    let serving: Serving
    let numberOfUnits: Double
    var id: String { "\(food.id)#\(serving.id)" }
}

/// What `LogEntryConfirmView` is confirming -- either a catalog food (with
/// an optional already-resolved serving) or a custom food (design.md D4).
enum LogTarget: Identifiable, Hashable {
    case catalog(food: Food, initialServing: Serving?)
    case custom(CustomFoodDraft)

    var id: String {
        switch self {
        case .catalog(let food, _): return "catalog:\(food.id)"
        case .custom(let draft): return "custom:\(draft.id.uuidString)"
        }
    }
}

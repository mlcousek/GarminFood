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
        /// Reused by the meal-preset editor to add an ingredient -- either a
        /// real catalog food+serving, or one of the user's own custom foods,
        /// in which case the third argument carries the draft the preset
        /// needs to log it correctly later (see MealPreset.swift).
        case pickIngredient(onPick: (Food, Serving, CustomFoodDraft?) -> Void)
    }

    var mode: Mode = .logFood
    /// Where this catalog was opened from, if a specific meal/day
    /// (meal-dashboard spec) -- passed explicitly down to whatever confirm
    /// screen a picked food eventually reaches, per LogContext.swift's
    /// header on why this is no longer relayed through the environment.
    var logContext: LogContext = .empty

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var searchResults: [Food] = []
    @State private var isSearching = false
    @State private var searchErrorMessage: String?

    // Czech (Open Food Facts) results (add-czech-food-catalog task 28.1) --
    // deliberately separate state from the Garmin search above, never
    // merged, per design.md D5.
    /// Persisted in preferences, so the choice survives a relaunch.
    private var czechOnly: Bool { environment.preferences.czechOnlySearch }

    private var czechOnlyBinding: Binding<Bool> {
        Binding(
            get: { environment.preferences.czechOnlySearch },
            set: { environment.preferences.czechOnlySearch = $0 }
        )
    }
    @State private var czechSearchResults: [Food] = []
    @State private var isCzechSearching = false
    @State private var czechSearchErrorMessage: String?
    /// 2026-09-21: true when the Czech-scoped search came back empty and
    /// `czechSearchResults` above was filled by an automatic global
    /// (non-Czech-filtered) retry instead -- see `performCzechSearch()`.
    /// OFF's Czech tagging is thin enough that plenty of real matches for
    /// a term simply never got the country tag added; without this, the
    /// "Czech only" toggle could silently hide a food that genuinely
    /// exists in Open Food Facts, which read as "the database isn't full"
    /// even when a match was sitting right there, just untagged.
    @State private var czechSearchUsedGlobalFallback = false
    @State private var matchingTarget: Food?

    @State private var quickPickItems: [QuickPickItem] = []
    @State private var customFoods: [CustomFoodDraft] = []
    @State private var mealPresets: [MealPreset] = []
    // add-favorite-foods: the local favorites list, plus a derived id set
    // for O(1) `isFoodFavorited` lookups from row rendering (rebuilt
    // whenever `favoriteFoods` changes, which is cheap -- this list is
    // expected to stay small, same assumption `customFoods` already makes).
    @State private var favoriteFoods: [FavoriteFood] = []
    private var favoriteFoodIds: Set<String> { Set(favoriteFoods.map(\.id)) }

    @State private var logTarget: LogTarget?
    @State private var mealPresetTarget: MealPreset?
    @State private var foodAwaitingServingPick: Food?
    @State private var isPresentingCustomFoodEditor = false
    @State private var isPresentingMealPresetEditor = false
    @State private var mealPresetBeingEdited: MealPreset?
    @State private var isPresentingBarcodeScanner = false
    @State private var barcodeNoteForNewCustomFood: String?

    private var isPickingBackingFood: Bool {
        if case .pickBackingFood = mode { return true }
        return false
    }

    private var isPickingIngredient: Bool {
        if case .pickIngredient = mode { return true }
        return false
    }

    /// True for either "pick something for another screen" mode -- neither
    /// should show meal presets (a preset is a group of separately-logged
    /// entries, not itself a pickable food/serving) or the Czech search
    /// section (that flow ends in Garmin matching/creation, not a plain
    /// food+serving pick).
    private var isPicking: Bool { isPickingBackingFood || isPickingIngredient }

    var body: some View {
        List {
            if !isPickingBackingFood, searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                if !quickPickItems.isEmpty {
                    Section {
                        QuickPickShelf(
                            items: quickPickItems,
                            onTap: { item in
                                logTarget = .catalog(food: item.food, initialServing: item.serving)
                            },
                            isFavorite: isPicking ? nil : { isFoodFavorited($0) },
                            onToggleFavorite: isPicking ? nil : { toggleFavorite($0) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    } header: {
                        SectionHeader(title: "Quick pick")
                    }
                }

                // add-favorite-foods: same visibility rule as the quick-pick
                // shelf above (shown whenever not picking a BACKING food;
                // still shown while picking an ingredient, same as quick
                // pick). The star toggle itself is `nil` in EITHER picker
                // mode, per this feature's own scope note -- favoriting
                // isn't offered while picking for another screen, only tap-
                // to-select is.
                if !isPickingBackingFood, !favoriteFoods.isEmpty {
                    Section {
                        FavoritesShelf(
                            items: favoriteFoods,
                            onTap: { food in select(food) },
                            onToggleFavorite: isPicking ? nil : { toggleFavorite($0) }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    } header: {
                        SectionHeader(title: "Favorites")
                    }
                }

                if !customFoods.isEmpty {
                    Section {
                        ForEach(customFoods) { draft in
                            HStack(spacing: Theme.Spacing.sm) {
                                Button {
                                    selectCustomFood(draft)
                                } label: {
                                    FoodListRow(food: draft.asFood(), serving: draft.asFood().servings.first)
                                }
                                .buttonStyle(.plain)
                                if !isPicking {
                                    FavoriteToggleButton(isFavorite: isFoodFavorited(draft.asFood())) {
                                        toggleFavorite(draft.asFood())
                                    }
                                }
                            }
                        }
                    } header: {
                        SectionHeader(title: "Your custom foods")
                    }
                }

                // Meal presets (multiple ingredients logged together in one
                // action) aren't a pickable food+serving themselves, so this
                // section is hidden while picking FOR another screen.
                if !isPicking, !mealPresets.isEmpty {
                    Section {
                        ForEach(mealPresets) { preset in
                            Button {
                                mealPresetTarget = preset
                            } label: {
                                MealPresetRow(preset: preset)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await deleteMealPreset(preset) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    mealPresetBeingEdited = preset
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Theme.accent)
                            }
                        }
                    } header: {
                        SectionHeader(title: "Your meals")
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
                        HStack(spacing: Theme.Spacing.sm) {
                            Button {
                                select(food)
                            } label: {
                                FoodListRow(food: food, serving: food.servings.first)
                            }
                            .buttonStyle(.plain)
                            if !isPicking {
                                FavoriteToggleButton(isFavorite: isFoodFavorited(food)) {
                                    toggleFavorite(food)
                                }
                            }
                        }
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
            if !isPicking, !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
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
                        if czechSearchUsedGlobalFallback {
                            Text("No Czech-tagged matches -- showing worldwide Open Food Facts results instead.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                        Toggle("Czech only", isOn: czechOnlyBinding)
                            .font(.caption)
                            .fixedSize()
                            .accessibilityLabel("Limit Open Food Facts results to Czech products")
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if searchText.trimmingCharacters(in: .whitespaces).isEmpty, quickPickItems.isEmpty, customFoods.isEmpty, mealPresets.isEmpty, favoriteFoods.isEmpty, !isPickingBackingFood {
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
        .navigationTitle(navigationTitle)
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
                if !isPickingIngredient {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingMealPresetEditor = true
                        } label: {
                            Label("New meal", systemImage: "square.stack.3d.up")
                        }
                    }
                }
            }
        }
        .onAppear { environment.router.catalogDidAppear() }
        .onDisappear { environment.router.catalogDidDisappear() }
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
        .sheet(isPresented: $isPresentingMealPresetEditor, onDismiss: { Task { await loadLocalData() } }) {
            NavigationStack {
                MealPresetEditorView()
            }
        }
        .sheet(item: $mealPresetBeingEdited, onDismiss: { Task { await loadLocalData() } }) { preset in
            NavigationStack {
                MealPresetEditorView(existing: preset)
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
            LogEntryConfirmView(target: target, presetMealType: logContext.mealType, presetDate: logContext.date)
        }
        // Task 28.2: picking a Czech-database result routes into the
        // matching flow instead of straight to the confirm screen.
        .navigationDestination(item: $matchingTarget) { offFood in
            MatchConfirmationView(offFood: offFood, presetMealType: logContext.mealType, presetDate: logContext.date)
        }
        .navigationDestination(item: $mealPresetTarget) { preset in
            MealPresetConfirmView(preset: preset, presetMealType: logContext.mealType, presetDate: logContext.date)
        }
    }

    private var navigationTitle: String {
        if isPickingBackingFood { return "Pick closest match" }
        if isPickingIngredient { return "Add ingredient" }
        return "Log Food"
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
        case .pickBackingFood, .pickIngredient:
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
        case .pickIngredient(let onPick):
            onPick(food, serving, nil)
            dismiss()
        case .logFood:
            logTarget = .catalog(food: food, initialServing: serving)
        }
    }

    /// A custom food has exactly one implicit serving (`CustomFoodDraft.
    /// servingId`), so -- unlike a catalog food -- picking one never goes
    /// through the serving-picker sheet in any mode.
    private func selectCustomFood(_ draft: CustomFoodDraft) {
        switch mode {
        case .pickIngredient(let onPick):
            let asFood = draft.asFood()
            guard let serving = asFood.servings.first else { return }
            onPick(asFood, serving, draft)
            dismiss()
        case .pickBackingFood, .logFood:
            logTarget = .custom(draft)
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
            favoriteFoods = await environment.favoriteFoodStore.all()
        }
        if !isPicking {
            mealPresets = await environment.mealPresetStore.all()
        }
    }

    // MARK: - Favorites (add-favorite-foods)

    private func isFoodFavorited(_ food: Food) -> Bool {
        favoriteFoodIds.contains(food.id)
    }

    /// Local-first by construction: `FavoriteFoodStore.toggle` is a
    /// synchronous JSON-file write wrapped in `async` purely because it's
    /// actor-isolated, not because it waits on any network -- there is no
    /// Garmin route this syncs to (FavoriteFood.swift's header explains
    /// why), so there is nothing to enqueue or drain here, unlike a food
    /// LOG action. `try?` matches this file's own existing convention for
    /// a local-store mutation that's immediately followed by a UI refresh
    /// (see `deleteMealPreset` below) -- a write failure here has no
    /// dedicated error UI, same as that one.
    private func toggleFavorite(_ food: Food) {
        Task {
            try? await environment.favoriteFoodStore.toggle(food)
            favoriteFoods = await environment.favoriteFoodStore.all()
        }
    }

    private func deleteMealPreset(_ preset: MealPreset) async {
        try? await environment.mealPresetStore.delete(id: preset.id)
        mealPresets.removeAll { $0.id == preset.id }
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
            searchErrorMessage = GarminErrorPresentation.searchErrorMessage(for: error)
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
            czechSearchUsedGlobalFallback = false
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
            let scoped = try await environment.openFoodFactsClient.search(term: trimmed, czechOnly: czechOnly)
            // 2026-09-21: if the "Czech only" filter is on but came back
            // empty, retry once against ALL of Open Food Facts before
            // giving up -- OFF's Czech tagging is too thin to trust an
            // empty result as "this food doesn't exist in the database."
            // Skipped entirely when the toggle is already off (that search
            // WAS the global one) or already found something.
            if czechOnly, scoped.isEmpty {
                guard !Task.isCancelled else { return }
                czechSearchResults = try await environment.openFoodFactsClient.search(term: trimmed, czechOnly: false)
                czechSearchUsedGlobalFallback = !czechSearchResults.isEmpty
            } else {
                czechSearchResults = scoped
                czechSearchUsedGlobalFallback = false
            }
            czechSearchErrorMessage = nil
        } catch {
            czechSearchResults = []
            czechSearchUsedGlobalFallback = false
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

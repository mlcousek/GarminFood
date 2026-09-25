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
        /// needs to log it correctly later (see MealPreset.swift). The
        /// fourth is the starting quantity multiplier: a Quick pick card's
        /// own remembered quantity, `1` for every other source
        /// (fix-testing-feedback-quick-wins, food-catalog spec "Quick pick
        /// tapped while adding an ingredient").
        case pickIngredient(onPick: (Food, Serving, CustomFoodDraft?, Double) -> Void)
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
    /// rebuild-food-search: one ranked list across your own foods, Garmin
    /// and Open Food Facts -- see SearchResultsSection.swift.
    @State private var searchModel = FoodSearchModel()

    /// Open Food Facts' "Czech only" filter, persisted in preferences so the
    /// choice survives a relaunch.
    private var czechOnly: Bool { environment.preferences.czechOnlySearch }

    private var czechOnlyBinding: Binding<Bool> {
        Binding(
            get: { environment.preferences.czechOnlySearch },
            set: { environment.preferences.czechOnlySearch = $0 }
        )
    }
    @State private var matchingTarget: Food?

    @State private var quickPickItems: [QuickPickItem] = []
    // improve-log-food-shelves: the "Usual for <meal>" and "Recent" shelves,
    // ranked from the same usage history as Quick pick (MealUsualRanker /
    // RecentRanker) and rendered with the same card and tap path.
    @State private var usualItems: [QuickPickItem] = []
    @State private var usualMealType: MealType = MealTypeDefaulting.defaultMealType()
    @State private var recentItems: [QuickPickItem] = []
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
    /// add-standalone-mode 3.5: an unknown scanned code, filled into the
    /// custom-food editor's barcode field (standalone only).
    @State private var barcodeForNewCustomFood: String?

    private var isPickingBackingFood: Bool {
        if case .pickBackingFood = mode { return true }
        return false
    }

    private var isPickingIngredient: Bool {
        if case .pickIngredient = mode { return true }
        return false
    }

    /// True for either "pick something for another screen" mode -- neither
    /// shows meal presets (a preset is a group of separately-logged
    /// entries, not itself a pickable food/serving) or favorite toggles.
    /// Every tap in either mode hands the food back to the caller and never
    /// logs anything (fix-testing-feedback-quick-wins, food-catalog spec "A
    /// tap in picker mode never logs a food").
    private var isPicking: Bool { isPickingBackingFood || isPickingIngredient }

    /// add-standalone-mode: every standalone branch below is gated on this.
    private var dataMode: DataMode { environment.dataMode }

    private var isSearchActive: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// `pickBackingFood` only ever needs a real Garmin food, so Open Food
    /// Facts isn't asked at all there.
    private var searchOptions: SearchOptions {
        SearchOptions(czechOnly: czechOnly, origins: isPickingBackingFood ? [.local, .garmin] : nil)
    }

    var body: some View {
        List {
            // improve-log-food-shelves: with no query, five swipeable card
            // shelves in a fixed order -- Quick pick, Favorites, Usual for
            // <meal>, Meals, Recent -- then the custom-food list. A shelf
            // with no items is hidden, so the next one moves up. Hidden
            // entirely in `pickBackingFood` (only a real Garmin search
            // result can back a custom food). In `pickIngredient` every
            // shelf tap goes through the mode-aware paths
            // (`selectQuickPick` / `select`, fix-testing-feedback-quick-
            // wins) and hands the food back instead of logging, favorite
            // stars are off, and the Meals shelf is hidden (presets can't
            // nest).
            if !isPickingBackingFood, searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                if !quickPickItems.isEmpty {
                    shelfSection(title: String(localized: "Quick pick")) {
                        rememberedFoodShelf(quickPickItems)
                    }
                }

                if !favoriteFoods.isEmpty {
                    shelfSection(title: String(localized: "Favorites")) {
                        FavoritesShelf(
                            items: favoriteFoods,
                            onTap: { food in select(food) },
                            onToggleFavorite: isPicking ? nil : { toggleFavorite($0) },
                            cardAccessibilityHint: isPickingIngredient ? String(localized: "Adds this to the meal") : String(localized: "Logs this food")
                        )
                    }
                }

                if !usualItems.isEmpty {
                    shelfSection(title: usualShelfTitle) {
                        rememberedFoodShelf(usualItems)
                    }
                }

                if !isPicking, !mealPresets.isEmpty {
                    shelfSection(title: String(localized: "Meals")) {
                        MealPresetShelf(
                            presets: mealPresets,
                            onTap: { preset in mealPresetTarget = preset },
                            onEdit: { preset in mealPresetBeingEdited = preset },
                            onDelete: { preset in Task { await deleteMealPreset(preset) } }
                        )
                    }
                }

                if !recentItems.isEmpty {
                    shelfSection(title: String(localized: "Recent")) {
                        rememberedFoodShelf(recentItems)
                    }
                }

                if !customFoods.isEmpty {
                    Section {
                        ForEach(customFoods) { draft in
                            customFoodRow(draft)
                        }
                    } header: {
                        SectionHeader(title: String(localized: "Your custom foods"))
                    }
                }
            }

            // rebuild-food-search: while a query is typed, ONE ranked list
            // across your own foods, Garmin and Open Food Facts. Taps route
            // back through the same helpers the shelves use, so the picker
            // rules hold for every source: a Garmin/local food -> select(),
            // a custom food -> selectCustomFood(), an Open Food Facts product
            // -> the match flow (matchingTarget). `pickBackingFood` shows
            // real Garmin foods only.
            if isSearchActive {
                SearchResultsSection(
                    model: searchModel,
                    garminFoodsOnly: isPickingBackingFood,
                    czechOnly: isPickingBackingFood ? nil : czechOnlyBinding,
                    isFavorite: isPicking ? nil : { isFoodFavorited($0) },
                    onToggleFavorite: isPicking ? nil : { toggleFavorite($0) },
                    onSelectFood: { select($0) },
                    onSelectCustomFood: { selectCustomFood($0) },
                    onSelectOpenFoodFactsFood: { matchingTarget = $0 },
                    dataMode: dataMode
                )
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
                        barcodeForNewCustomFood = nil
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
        // add-standalone-mode D5: the mode picks the engine (standalone has
        // no Garmin source) and is part of the id, so flipping it re-runs.
        .task(id: "\(searchText)#\(czechOnly)#\(searchModel.reloadToken)#\(dataMode.rawValue)") {
            await searchModel.run(query: searchText, engine: environment.catalogSearchEngine, options: searchOptions)
        }
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
                CustomFoodEditorView(prefillNote: barcodeNoteForNewCustomFood, prefillBarcode: barcodeForNewCustomFood)
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
                    // A hit from the offline Czech index (add-offline-czech-
                    // food-index D4) is an Open Food Facts product: like a
                    // tapped OFF search result, it needs its Garmin match first
                    // -- in Garmin mode. Standalone logs it as itself (D5).
                    if food.source == .openFoodFacts, dataMode == .garminConnected {
                        matchingTarget = food
                    } else {
                        select(food)
                    }
                },
                onUnresolved: { code in
                    isPresentingBarcodeScanner = false
                    if dataMode == .standalone {
                        // add-standalone-mode 3.5 (spec "Unknown barcode"):
                        // the code goes into the editor's barcode field, so
                        // scanning it again finds the new food.
                        barcodeNoteForNewCustomFood = nil
                        barcodeForNewCustomFood = code
                    } else {
                        barcodeNoteForNewCustomFood = String(localized: "Scanned barcode: \(code) (not found in Garmin's database)")
                        barcodeForNewCustomFood = nil
                    }
                    isPresentingCustomFoodEditor = true
                },
                onCancel: { isPresentingBarcodeScanner = false },
                // Standalone chain only: the code is on one of her own
                // custom foods -- the same path as tapping it in the list.
                onResolvedCustomFood: { draft in
                    isPresentingBarcodeScanner = false
                    selectCustomFood(draft)
                }
            )
        }
        .navigationDestination(item: $logTarget) { target in
            LogEntryConfirmView(target: target, presetMealType: logContext.mealType, presetDate: logContext.date)
        }
        // Task 28.2: picking a Czech-database result routes into the
        // matching flow instead of straight to the confirm screen.
        .navigationDestination(item: $matchingTarget) { offFood in
            MatchConfirmationView(
                offFood: offFood,
                presetMealType: logContext.mealType,
                presetDate: logContext.date,
                onPickMatched: matchPickHandler
            )
        }
        .navigationDestination(item: $mealPresetTarget) { preset in
            MealPresetConfirmView(preset: preset, presetMealType: logContext.mealType, presetDate: logContext.date)
        }
    }

    private var navigationTitle: String {
        if isPickingBackingFood { return String(localized: "Pick closest match") }
        if isPickingIngredient { return String(localized: "Add ingredient") }
        return String(localized: "Log Food")
    }

    /// "Usual for <meal>" as one whole-sentence key per meal (Czech needs
    /// a different case/phrasing per meal, so no glued-in meal name).
    private var usualShelfTitle: String {
        switch usualMealType {
        case .breakfast: return String(localized: "Usual for breakfast")
        case .lunch: return String(localized: "Usual for lunch")
        case .dinner: return String(localized: "Usual for dinner")
        case .snacks: return String(localized: "Usual for snacks")
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

    /// One row of the custom-food list, shared by the full list (empty
    /// query) and the name-matched list (typed query).
    @ViewBuilder
    private func customFoodRow(_ draft: CustomFoodDraft) -> some View {
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

    /// One empty-query shelf as an edge-to-edge List section with a header
    /// (improve-log-food-shelves) -- the shelf scrolls horizontally inside
    /// its own row, so the row gets no insets or separator.
    private func shelfSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        let shelf = content()
        return Section {
            shelf
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        } header: {
            SectionHeader(title: title)
        }
    }

    /// The Quick pick, Usual for <meal> and Recent shelves: all three are a
    /// remembered food+serving+quantity, so all three share one card and
    /// one tap path -- `selectQuickPick`, which is what keeps a tap in
    /// `pickIngredient` returning the food instead of logging it.
    private func rememberedFoodShelf(_ items: [QuickPickItem]) -> some View {
        QuickPickShelf(
            items: items,
            onTap: { item in selectQuickPick(item) },
            isFavorite: isPicking ? nil : { isFoodFavorited($0) },
            onToggleFavorite: isPicking ? nil : { toggleFavorite($0) },
            cardAccessibilityHint: isPickingIngredient ? String(localized: "Adds this to the meal") : String(localized: "Logs this again")
        )
    }

    /// Hands a matched (or newly created) Garmin food from the OFF match
    /// flow back through the same path a picked serving takes, so an OFF
    /// product becomes a meal ingredient instead of a log entry. `nil`
    /// outside `pickIngredient`, which keeps `MatchConfirmationView` on its
    /// normal log-it path.
    private var matchPickHandler: ((Food, Serving) -> Void)? {
        guard isPickingIngredient else { return nil }
        return { food, serving in
            handleServingPicked(food: food, serving: serving)
        }
    }

    /// The Quick pick shelf's tap (fix-testing-feedback-quick-wins task
    /// 1.1). It used to set `logTarget` unconditionally, so tapping a card
    /// while adding a meal ingredient LOGGED the food instead. Now:
    /// `pickIngredient` hands the card's food, serving AND quantity back;
    /// `logFood` opens the confirm screen as before. A custom food on the
    /// shelf (cached as a `.custom`-source `Food`) is resolved back to its
    /// `CustomFoodDraft` first in every mode, so it is never treated as a
    /// Garmin food id.
    private func selectQuickPick(_ item: QuickPickItem) {
        Task {
            let draft = await customDraft(for: item.food)
            // A custom food whose draft was deleted: its id means nothing to
            // Garmin, so neither logging nor adding it is possible.
            if item.food.source == .custom, draft == nil { return }
            let food = draft?.asFood() ?? item.food
            let serving = food.servings.first(where: { $0.id == item.serving.id }) ?? item.serving
            // Same rule as `select`: an Open Food Facts product remembered
            // in standalone mode needs its Garmin match in Garmin mode.
            if food.source == .openFoodFacts, dataMode == .garminConnected, !isPickingBackingFood {
                matchingTarget = food
                return
            }

            switch mode {
            case .pickIngredient(let onPick):
                onPick(food, serving, draft, item.numberOfUnits)
                dismiss()
            case .pickBackingFood(let onPick):
                // The shelf isn't shown in this mode; if it ever is, only a
                // real Garmin food can back a custom food.
                guard draft == nil else { return }
                onPick(food, serving)
                dismiss()
            case .logFood:
                // The card's own remembered amount, not one serving
                // (LogTarget's doc comment).
                if let draft {
                    logTarget = .custom(draft, initialQuantity: item.numberOfUnits)
                } else {
                    logTarget = .catalog(food: food, initialServing: serving, initialQuantity: item.numberOfUnits)
                }
            }
        }
    }

    /// The `CustomFoodDraft` behind a `.custom`-source `Food` (a custom food
    /// reached via the Quick pick or Favorites shelf, which only store the
    /// `Food`), or `nil` for any other food. Falls back to the store when
    /// `customFoods` isn't loaded (yet, or at all in `pickBackingFood`).
    private func customDraft(for food: Food) async -> CustomFoodDraft? {
        guard food.source == .custom else { return nil }
        if let loaded = customFoods.first(where: { $0.id.uuidString == food.id }) {
            return loaded
        }
        return await environment.customFoodStore.all().first(where: { $0.id.uuidString == food.id })
    }

    private func select(_ food: Food) {
        // A custom food from the Favorites shelf routes through its draft,
        // exactly like tapping it in the custom-food list.
        if food.source == .custom {
            Task {
                if let draft = await customDraft(for: food) {
                    selectCustomFood(draft)
                }
            }
            return
        }
        // add-standalone-mode: an Open Food Facts product can only become
        // one of "your" foods (favorite, cache) in standalone mode. If one
        // is tapped in Garmin mode (after a mode switch), it still gets its
        // Garmin match first, never a direct Garmin log of an OFF id.
        if food.source == .openFoodFacts, dataMode == .garminConnected, !isPickingBackingFood {
            matchingTarget = food
            return
        }
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
            onPick(food, serving, nil, 1)
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
            onPick(asFood, serving, draft, 1)
            dismiss()
        case .pickBackingFood:
            // A custom food can't back another custom food (its own backing
            // must be a real Garmin food), and a picker tap must never log.
            return
        case .logFood:
            logTarget = .custom(draft)
        }
    }

    private func loadLocalData() async {
        let events = await environment.usageHistory.all()
        let cache = await environment.foodCache.all()

        // Loaded first: the shelves below resolve a custom food through its
        // draft (`shelfItem`).
        if !isPickingBackingFood {
            customFoods = await environment.customFoodStore.all()
            favoriteFoods = await environment.favoriteFoodStore.all()
        }
        if !isPicking {
            mealPresets = await environment.mealPresetStore.all()
        }

        quickPickItems = QuickPick.rank(events: events).compactMap { entry in
            shelfItem(foodId: entry.foodId, servingId: entry.servingId, numberOfUnits: entry.numberOfUnits, cache: cache)
        }

        // improve-log-food-shelves: the meal comes from where Log Food was
        // opened (a meal card), else the same default the confirm screen
        // would pick, so the shelf matches the meal the entry will land in.
        let mealType = defaultShelfMealType()
        usualMealType = mealType
        usualItems = MealUsualRanker.rank(events: events, mealType: mealType).compactMap { entry in
            shelfItem(foodId: entry.foodId, servingId: entry.servingId, numberOfUnits: entry.numberOfUnits, cache: cache)
        }
        recentItems = RecentRanker.rank(events: events).compactMap { entry in
            shelfItem(foodId: entry.foodId, servingId: entry.servingId, numberOfUnits: entry.numberOfUnits, cache: cache)
        }
    }

    /// Resolves a ranked usage entry to a card: a custom food from its
    /// current draft (the cache only holds a snapshot from its last save,
    /// or nothing), anything else from the food cache, plus the exact
    /// serving it was logged with. `nil` -- the card is skipped -- when the
    /// food, its serving, or a custom food's draft is gone, rather than
    /// showing a card a tap can't log (`selectQuickPick` ignores a custom
    /// food without a draft).
    private func shelfItem(foodId: String, servingId: String, numberOfUnits: Double, cache: [String: Food]) -> QuickPickItem? {
        let food: Food
        if let draft = customFoods.first(where: { $0.id.uuidString == foodId }) {
            food = draft.asFood()
        } else if let cached = cache[foodId], cached.source != .custom {
            food = cached
        } else {
            return nil
        }
        guard let serving = food.servings.first(where: { $0.id == servingId }) else { return nil }
        return QuickPickItem(food: food, serving: serving, numberOfUnits: numberOfUnits)
    }

    /// The meal the "Usual for <meal>" shelf ranks for: `logContext`'s meal
    /// when opened from a meal card, otherwise exactly what
    /// `LogEntryConfirmView` would default to -- Garmin's meal windows when
    /// that preference is on, the fixed time-of-day table when not.
    private func defaultShelfMealType() -> MealType {
        if let mealType = logContext.mealType { return mealType }
        if environment.preferences.useGarminMealWindows {
            return MealWindowDefaulting.mealType(at: Date(), windows: environment.dayLog.latestWindows)
        }
        return MealTypeDefaulting.defaultMealType()
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
}

struct QuickPickItem: Identifiable {
    let food: Food
    let serving: Serving
    let numberOfUnits: Double
    var id: String { "\(food.id)#\(serving.id)" }
}

/// What `LogEntryConfirmView` is confirming -- either a catalog food (with
/// an optional already-resolved serving) or a custom food (design.md D4).
///
/// `initialQuantity` is the amount the confirm screen starts at, `nil`
/// meaning one serving. A Quick pick / Usual / Recent / Log again card
/// passes the amount it SHOWS ("2×, 580 kcal") -- it used to be dropped
/// here, so the card said 2 servings and the screen logged 1.
enum LogTarget: Identifiable, Hashable {
    case catalog(food: Food, initialServing: Serving?, initialQuantity: Double? = nil)
    case custom(CustomFoodDraft, initialQuantity: Double? = nil)

    var id: String {
        switch self {
        case .catalog(let food, _, _): return "catalog:\(food.id)"
        case .custom(let draft, _): return "custom:\(draft.id.uuidString)"
        }
    }
}

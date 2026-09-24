// MatchConfirmationView.swift
//
// The matching/creation flow for a Czech-database (Open Food Facts) food
// (design.md D3/D4, garmin-food-matching spec, task groups 29-30). Reached
// by tapping a Czech-database result in `FoodCatalogView` instead of the
// normal serving-picker/confirm flow -- selecting a Garmin result is
// unchanged.
//
// Re-searches Garmin for the OFF product's own name (via
// `AppEnvironment.foodSearchEngine`, rebuild-food-search), runs the pure
// `GarminFoodMatching.match` heuristic against the
// results, and ALWAYS shows the outcome to the user before anything is
// logged or created -- design.md D3's "never resolved invisibly" rule.
// Once a real Garmin food is settled on (an existing match, or one just
// created via `CreateInGarminConfirmView` below), it's handed to the
// EXACT SAME `LogEntryConfirmView`/`LogTarget.catalog` path a normal
// Garmin search result already uses -- a matched/created OFF food is
// indistinguishable from any other Garmin food from that point on.
//
// Picker variant (fix-testing-feedback-quick-wins task 1.2): when
// `FoodCatalogView` is open to add a meal-preset ingredient it passes
// `onPickMatched`, and the settled Garmin food is handed back through it
// (after a serving pick) instead of reaching `LogEntryConfirmView` --
// nothing is logged. The match itself, and the explicit-tap-only
// create-in-Garmin fallback, are unchanged.

import SwiftUI
import FoodLogCore
import GarminKit

private enum MatchState {
    case loading
    case matched(Food)
    case noMatch
    case error(String)
}

@MainActor
struct MatchConfirmationView: View {
    let offFood: Food
    /// Threaded through from whichever meal/day this search started from
    /// (meal-dashboard spec) -- see LogContext.swift's header.
    var presetMealType: MealType? = nil
    var presetDate: Date? = nil
    /// Set only by the ingredient picker: the matched Garmin food and the
    /// serving the user chose go here instead of to the log-entry flow.
    var onPickMatched: ((Food, Serving) -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var state: MatchState = .loading
    @State private var logTarget: LogTarget?
    @State private var isPresentingCreateInGarmin = false
    @State private var isPresentingFallbackSearch = false
    @State private var foodAwaitingServingPick: Food?

    private var isPicking: Bool { onPickMatched != nil }

    var body: some View {
        content
            .padding(Theme.Spacing.lg)
            .navigationTitle("Match in Garmin")
            .navigationBarTitleDisplayMode(.inline)
            .task { await runMatch() }
            .navigationDestination(item: $logTarget) { target in
                LogEntryConfirmView(target: target, presetMealType: presetMealType, presetDate: presetDate)
            }
            .navigationDestination(isPresented: $isPresentingCreateInGarmin) {
                CreateInGarminConfirmView(
                    offFood: offFood,
                    presetMealType: presetMealType,
                    presetDate: presetDate,
                    onPickCreated: onPickMatched
                )
            }
            .navigationDestination(isPresented: $isPresentingFallbackSearch) {
                FoodCatalogView(logContext: LogContext(mealType: presetMealType, date: presetDate))
            }
            .sheet(item: $foodAwaitingServingPick) { food in
                ServingPickerSheet(food: food) { serving in
                    onPickMatched?(food, serving)
                }
            }
    }

    /// "Use a different Garmin food": the logging flow pushes a fresh
    /// catalog to search in; the picker instead pops back to the picker's
    /// own search, which is already the right place (and never logs).
    private func chooseDifferentGarminFood() {
        if isPicking {
            dismiss()
        } else {
            isPresentingFallbackSearch = true
        }
    }

    private var differentFoodTitle: String {
        isPicking
            ? String(localized: "Pick a different Garmin food instead")
            : String(localized: "Log anyway with a different Garmin food")
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                Text("Checking Garmin's database for a match…")
                    .font(.foodSubtitle)
                    .foregroundStyle(.secondary)
            }
        case .matched(let candidate):
            matchedView(candidate)
        case .noMatch:
            noMatchView
        case .error(let message):
            VStack(spacing: Theme.Spacing.lg) {
                EmptyStateView(systemImage: "wifi.exclamationmark", title: String(localized: "Couldn't check Garmin"), message: message)
                PrimaryButton(title: String(localized: "Try again")) {
                    state = .loading
                    Task { await runMatch() }
                }
            }
        }
    }

    @ViewBuilder
    private func matchedView(_ candidate: Food) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.success)
                Text("Found a match in Garmin")
                    .font(.headline)
                FoodListRow(food: candidate, serving: candidate.servings.first)
                    .padding(.horizontal, Theme.Spacing.md)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            PrimaryButton(title: String(localized: "Use this match")) {
                if isPicking {
                    foodAwaitingServingPick = candidate
                } else {
                    logTarget = .catalog(food: candidate, initialServing: candidate.servings.first)
                }
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button("That's not right — no match found") {
                    state = .noMatch
                }
                .font(.foodSubtitle)
                .foregroundStyle(.secondary)

                Button(differentFoodTitle) {
                    chooseDifferentGarminFood()
                }
                .font(.foodSubtitle)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var noMatchView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            EmptyStateView(
                systemImage: "questionmark.circle",
                title: String(localized: "No match found"),
                message: String(localized: "Garmin's database doesn't seem to have \"\(offFood.name)\". You can create it there, or log against a different Garmin food instead.")
            )

            PrimaryButton(title: String(localized: "Create in Garmin")) {
                isPresentingCreateInGarmin = true
            }

            Button(differentFoodTitle) {
                chooseDifferentGarminFood()
            }
            .font(.foodSubtitle)

            Spacer()
        }
    }

    /// rebuild-food-search task 4.2: searches for the product's own words
    /// (brand and pack size stripped, `GarminFoodMatching.searchQuery`)
    /// through the unified engine, so candidates arrive ranked and the
    /// user's own logged Garmin foods count too. Only real Garmin foods are
    /// candidates -- never a custom food or another Open Food Facts product.
    private func runMatch() async {
        let query = GarminFoodMatching.searchQuery(for: offFood)
        let snapshot = await environment.foodSearchEngine.search(query, options: SearchOptions(origins: [.local, .garmin]))
        let candidates = snapshot.results
            .filter { $0.origin.isDirectlyLoggable && $0.customDraft == nil && $0.food.source != .custom }
            .map(\.food)
        if candidates.isEmpty, case .failed(let failure)? = snapshot.statuses[.garmin] {
            state = .error(GarminErrorPresentation.searchFailureMessage(for: failure))
            return
        }
        switch GarminFoodMatching.match(offFood: offFood, garminCandidates: candidates) {
        case .matched(let food): state = .matched(food)
        case .noMatch: state = .noMatch
        }
    }
}

// MARK: - Create-in-Garmin confirmation (design.md D4, task group 30)

/// The gated fallback (task 30.2/30.4): shows the EXACT name and macro
/// values about to be sent to Garmin and requires an explicit tap before
/// anything is created. This is the ONLY call site of
/// `GarminClient.createCustomFood` in the entire app -- per design.md D4
/// and task 30.4, that call must never happen automatically anywhere else.
@MainActor
struct CreateInGarminConfirmView: View {
    let offFood: Food
    /// Threaded through from whichever meal/day this search started from
    /// (meal-dashboard spec) -- see LogContext.swift's header.
    var presetMealType: MealType? = nil
    var presetDate: Date? = nil
    /// The ingredient picker's hand-back (see `MatchConfirmationView.
    /// onPickMatched`): when set, the newly created food goes here with the
    /// one serving just sent to Garmin, instead of to the log-entry flow.
    /// The create call itself still needs the same explicit tap.
    var onPickCreated: ((Food, Serving) -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var logTarget: LogTarget?

    private var serving: Serving? { offFood.servings.first }

    var body: some View {
        Form {
            Section("This will be sent to Garmin") {
                LabeledContent("Name", value: offFood.name)
                LabeledContent("Serving", value: serving?.displayLabel ?? "100 g")
                if let calories = serving?.calories {
                    LabeledContent("Calories") {
                        MacroBadge(value: calories, unit: " kcal", accessibleUnit: "kilocalories")
                    }
                }
                if let protein = serving?.protein {
                    LabeledContent("Protein", value: "\(protein.wholeNumberText) g")
                }
                if let carbs = serving?.carbs {
                    LabeledContent("Carbs", value: "\(carbs.wholeNumberText) g")
                }
                if let fat = serving?.fat {
                    LabeledContent("Fat", value: "\(fat.wholeNumberText) g")
                }
            }

            Section {
                Text("This is an experimental, best-effort write — Garmin's exact expected request shape for creating a food has never been confirmed. If it fails, nothing is created, and you can log against a different Garmin food instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("Create in Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: String(localized: "Create in Garmin"), isDisabled: isCreating || serving?.calories == nil) {
                createInGarmin()
            }
            .padding(Theme.Spacing.md)
            .background(.bar)
        }
        .interactiveDismissDisabled(isCreating)
        .navigationDestination(item: $logTarget) { target in
            LogEntryConfirmView(target: target, presetMealType: presetMealType, presetDate: presetDate)
        }
        .overlay {
            if serving?.calories == nil {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: String(localized: "Missing calories"),
                    message: String(localized: "This item has no calorie value from Open Food Facts, so it can't be created in Garmin.")
                )
            }
        }
    }

    private func createInGarmin() {
        guard let calories = serving?.calories else { return }
        isCreating = true
        errorMessage = nil
        Task {
            defer { isCreating = false }
            do {
                // The one explicit, user-triggered call (task 30.4) --
                // never invoked from anywhere else in this codebase.
                let result = try await environment.garminClient.createCustomFood(
                    name: offFood.name,
                    servingUnit: serving?.unit ?? "g",
                    numberOfUnits: serving?.numberOfUnits ?? 100,
                    calories: calories,
                    protein: serving?.protein,
                    carbs: serving?.carbs,
                    fat: serving?.fat,
                    regionCode: environment.profile.settings?.regionCode,
                    languageCode: environment.profile.settings?.languageCode
                )
                guard let createdFood = Food(searchResult: result) else {
                    errorMessage = String(localized: "Garmin accepted the food but returned a shape we couldn't read. Try logging against a different Garmin food instead.")
                    return
                }
                // Picker variant: hand the created food back as an
                // ingredient; nothing is logged.
                if let onPickCreated {
                    guard let createdServing = createdFood.servings.first else {
                        errorMessage = String(localized: "Garmin created the food but returned no serving for it. Pick a different Garmin food instead.")
                        return
                    }
                    onPickCreated(createdFood, createdServing)
                    return
                }
                // Task 30.3: the created food is treated exactly like any
                // other Garmin food from here on -- straight into the
                // normal log-entry confirm flow.
                logTarget = .catalog(food: createdFood, initialServing: createdFood.servings.first)
            } catch {
                errorMessage = String(localized: "Couldn't create this food in Garmin. Try again, or log against a different Garmin food instead.")
            }
        }
    }
}

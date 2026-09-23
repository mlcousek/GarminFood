// MatchConfirmationView.swift
//
// The matching/creation flow for a Czech-database (Open Food Facts) food
// (design.md D3/D4, garmin-food-matching spec, task groups 29-30). Reached
// by tapping a Czech-database result in `FoodCatalogView` instead of the
// normal serving-picker/confirm flow -- selecting a Garmin result is
// unchanged.
//
// Re-searches Garmin for the OFF product's own name (via the existing
// `AppEnvironment.catalogSearch`, no new network client needed for that
// half), runs the pure `GarminFoodMatching.match` heuristic against the
// results, and ALWAYS shows the outcome to the user before anything is
// logged or created -- design.md D3's "never resolved invisibly" rule.
// Once a real Garmin food is settled on (an existing match, or one just
// created via `CreateInGarminConfirmView` below), it's handed to the
// EXACT SAME `LogEntryConfirmView`/`LogTarget.catalog` path a normal
// Garmin search result already uses -- a matched/created OFF food is
// indistinguishable from any other Garmin food from that point on.

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

    @Environment(AppEnvironment.self) private var environment

    @State private var state: MatchState = .loading
    @State private var logTarget: LogTarget?
    @State private var isPresentingCreateInGarmin = false
    @State private var isPresentingFallbackSearch = false

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
                CreateInGarminConfirmView(offFood: offFood, presetMealType: presetMealType, presetDate: presetDate)
            }
            .navigationDestination(isPresented: $isPresentingFallbackSearch) {
                FoodCatalogView(logContext: LogContext(mealType: presetMealType, date: presetDate))
            }
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
                EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't check Garmin", message: message)
                PrimaryButton(title: "Try again") {
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

            PrimaryButton(title: "Use this match") {
                logTarget = .catalog(food: candidate, initialServing: candidate.servings.first)
            }

            VStack(spacing: Theme.Spacing.sm) {
                Button("That's not right — no match found") {
                    state = .noMatch
                }
                .font(.foodSubtitle)
                .foregroundStyle(.secondary)

                Button("Log anyway with a different Garmin food") {
                    isPresentingFallbackSearch = true
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
                title: "No match found",
                message: "Garmin's database doesn't seem to have \"\(offFood.name)\". You can create it there, or log against a different Garmin food instead."
            )

            PrimaryButton(title: "Create in Garmin") {
                isPresentingCreateInGarmin = true
            }

            Button("Log anyway with a different Garmin food") {
                isPresentingFallbackSearch = true
            }
            .font(.foodSubtitle)

            Spacer()
        }
    }

    private func runMatch() async {
        do {
            let candidates = try await environment.catalogSearch.search(term: offFood.name)
            switch GarminFoodMatching.match(offFood: offFood, garminCandidates: candidates) {
            case .matched(let food): state = .matched(food)
            case .noMatch: state = .noMatch
            }
        } catch {
            state = .error(GarminErrorPresentation.searchErrorMessage(for: error))
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
                    LabeledContent("Protein", value: "\(Int(protein.rounded())) g")
                }
                if let carbs = serving?.carbs {
                    LabeledContent("Carbs", value: "\(Int(carbs.rounded())) g")
                }
                if let fat = serving?.fat {
                    LabeledContent("Fat", value: "\(Int(fat.rounded())) g")
                }
            }

            Section {
                Text("This is an experimental, best-effort write — Garmin's exact expected request shape for creating a food has never been confirmed. If it fails, nothing is created, and you can log against a different Garmin food instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Create in Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Create in Garmin", isDisabled: isCreating || serving?.calories == nil) {
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
                    title: "Missing calories",
                    message: "This item has no calorie value from Open Food Facts, so it can't be created in Garmin."
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
                    errorMessage = "Garmin accepted the food but returned a shape we couldn't read. Try logging against a different Garmin food instead."
                    return
                }
                // Task 30.3: the created food is treated exactly like any
                // other Garmin food from here on -- straight into the
                // normal log-entry confirm flow.
                logTarget = .catalog(food: createdFood, initialServing: createdFood.servings.first)
            } catch {
                errorMessage = "Couldn't create this food in Garmin. Try again, or log against a different Garmin food instead."
            }
        }
    }
}

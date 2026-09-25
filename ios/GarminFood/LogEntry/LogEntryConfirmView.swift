// LogEntryConfirmView.swift
//
// The confirm screen (task 16.1): chosen food, chosen serving, quantity,
// meal type (defaulted from time of day, task 16.1/MealTypeDefaulting), and
// date (defaulting to today, editable) -- food-log-entry spec's "Meal type
// and date default sensibly but remain editable" requirement.
//
// On confirm: commits via `LogEntryCoordinator` (FoodLogCore), which itself
// calls straight into `GarminKit.Outbox.logFood` -- a local JSON-file append,
// no network call. This view shows success IMMEDIATELY on that return, per
// the spec's "MUST NOT require network connectivity to complete the
// confirmation" / "completes without waiting for the Garmin delivery to
// finish" requirements. A best-effort outbox drain is kicked off AFTER
// success is already shown, deliberately unawaited by the confirm action
// itself (see `confirm()` below) -- see `AppEnvironment.drainAndReconcile()`.
//
// implement-micronutrients (2026-09-22): also shows `selectedServing`'s full
// nutrient breakdown (`NutritionBreakdownSections`, DesignSystem/Components.swift)
// -- this is the point a `Serving`'s Open-Food-Facts-only vitamin/mineral
// panel is actually known and food-specific, unlike `MealDetailView`'s
// "Nutrients" section which is capped at whatever Garmin's own daily/meal
// aggregate returns (see `MealDashboard.nutrients`'s header comment).
//
// add-standalone-mode D5 (standalone only; Garmin mode is unchanged): an Open
// Food Facts / offline-index product arrives here directly, logged as
// itself. A serving with no calories can't be confirmed and offers "create
// a custom food" instead; one missing a carb/protein/fat value says "some
// values missing" (`NutritionCompleteness`, FoodLogCore).

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct LogEntryConfirmView: View {
    let target: LogTarget

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where this log was started from, if anywhere specific (meal-dashboard
    /// spec: "Adding from a meal pre-selects that meal and day") -- passed
    /// explicitly by every call site now (see LogContext.swift's header for
    /// why this is no longer read from the environment).
    private let presetMealType: MealType?
    private let presetDate: Date?
    @State private var didApplyContext = false

    /// The multiplier of `selectedServing` being logged -- `1` means
    /// exactly one serving. This is exactly what's sent to Garmin as
    /// `servingQty` (`FoodLogWriteBody`, confirmed by the project's first
    /// real write 2026-09-16), so every other calculation in this view
    /// must treat it the same way. `nil` while the typed text isn't a
    /// valid amount (`ServingQuantityField` -- which is also where a typed
    /// gram amount becomes this multiplier).
    @State private var quantity: Double?
    @State private var mealType: MealType
    @State private var date: Date
    @State private var selectedServing: Serving?
    @State private var isPresentingServingPicker = false
    @State private var isSaving = false
    @State private var didConfirm = false
    @State private var discrepancyNote: String?
    @State private var errorMessage: String?
    @State private var isPresentingCustomFoodEditor = false
    /// add-standalone-mode D5: the custom food after "Choose a Garmin
    /// match" saved it with a backing food (Garmin mode only).
    @State private var updatedDraft: CustomFoodDraft?
    @State private var isPresentingGarminMatchEditor = false
    @FocusState private var isAmountFieldFocused: Bool

    init(target: LogTarget, presetMealType: MealType? = nil, presetDate: Date? = nil) {
        self.target = target
        self.presetMealType = presetMealType
        self.presetDate = presetDate
        let initialQuantity: Double?
        switch target {
        case .catalog(_, let serving, let remembered):
            _selectedServing = State(initialValue: serving)
            initialQuantity = remembered
        case .custom(let draft, let remembered):
            _selectedServing = State(initialValue: draft.asFood().servings.first)
            initialQuantity = remembered
        }
        // One full serving unless the target carries a remembered amount
        // (a Quick pick / Usual / Recent card's "2×"; see `LogTarget`) --
        // always a MULTIPLIER, see `quantity`'s own doc comment.
        // 2026-09-18 bug, fixed before any user could rely on the wrong
        // value: this used to default to the SERVING's own defined amount
        // (e.g. 100 for a "100g" serving), while the Stepper below it was
        // range-limited to 0.25...50 -- a starting value already outside
        // its own control's valid range. The first tap of "+" snapped it
        // down to 50 rather than incrementing, which read as the app
        // randomly jumping to "50 servings" the moment you touched it.
        // A remembered amount outside `LogQuantity`'s bound falls back to 1.
        _quantity = State(initialValue: initialQuantity.map { LogQuantity.isValid($0) ? $0 : 1 } ?? 1)
        // (A remembered amount is still a multiplier; `ServingQuantityField`
        // shows it in grams when that's the input mode -- amount-in-grams.)
        // 2026-09-21 bug fix: `presetMealType` is applied HERE, directly in
        // `init`, rather than corrected afterward in `applyContextOnce()` --
        // the previous version always started `mealType` at the time-of-day
        // default and only overwrote it once `.onAppear` fired and read an
        // environment value that had to have survived up to three separate
        // view pushes. Setting the real starting value up front removes
        // that relay from the equation entirely for the meal/date presets;
        // `applyContextOnce()` now only handles the "no explicit preset"
        // Garmin-meal-windows fallback, which reads `AppEnvironment`
        // (a single app-root environment object, not a per-push relay).
        _mealType = State(initialValue: presetMealType ?? MealTypeDefaulting.defaultMealType())
        _date = State(initialValue: presetDate ?? Date())
    }

    private var food: Food {
        switch target {
        case .catalog(let food, _, _): return food
        case .custom(let draft, _): return (updatedDraft ?? draft).asFood()
        }
    }

    /// The custom food being confirmed, including a just-picked Garmin match.
    private var customDraft: CustomFoodDraft? {
        guard case .custom(let draft, _) = target else { return nil }
        return updatedDraft ?? draft
    }

    /// add-standalone-mode D5: a custom food created without Garmin, seen in
    /// Garmin mode, must get a Garmin match before it can be logged there --
    /// never logged silently or dropped. Always false in standalone mode and
    /// for every food created in Garmin mode.
    private var needsGarminMatch: Bool {
        guard environment.dataMode == .garminConnected, let customDraft else { return false }
        return !customDraft.hasGarminBacking
    }

    private var isCustom: Bool {
        if case .custom = target { return true }
        return false
    }

    /// add-standalone-mode D5: how complete the chosen serving's nutrition
    /// is -- only in standalone mode and only for a catalog food (a custom
    /// food is her own numbers). `nil` in Garmin mode, so nothing below
    /// changes there.
    private var standaloneCompleteness: NutritionCompleteness? {
        guard environment.dataMode == .standalone, !isCustom, let selectedServing else { return nil }
        return selectedServing.completeness
    }

    private var caloriesForQuantity: Double? {
        // A serving's `calories` is for one full serving, and `quantity` is
        // already the multiplier (see its doc comment) -- a straight
        // multiply, matching MealDashboard's identical scaling of a logged
        // entry's macros. The previous `calories * (quantity / servingUnits)`
        // was correct only if `quantity` meant an absolute amount in the
        // serving's own unit, which it never was: this screen's Stepper
        // only ever produced small multiplier-range values (0.25...50), so
        // the on-screen preview was silently wrong -- too low by roughly
        // the serving size -- for any serving where `numberOfUnits != 1`
        // (a "100g" serving showed calories about 100x too small).
        guard let calories = selectedServing?.calories, let quantity else { return nil }
        return calories * quantity
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(food.name)
                        .font(.title3.weight(.semibold))
                    if let brandName = food.brandName, !brandName.isEmpty {
                        Text(brandName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)

                if !isCustom {
                    Button {
                        isPresentingServingPicker = true
                    } label: {
                        HStack {
                            Text("Serving")
                            Spacer()
                            Text(selectedServing?.displayLabel ?? String(localized: "Choose…"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Grams/ml whenever the serving states its size ("100g",
                // "g" x 100, "serving (118 g)"), servings otherwise -- and
                // the out-of-range message -- all in `ServingQuantityField`
                // (amount-in-grams). `quantity` stays the multiplier.
                ServingQuantityField(
                    serving: selectedServing,
                    quantity: $quantity,
                    isFocused: $isAmountFieldFocused
                )

                if let caloriesForQuantity {
                    HStack {
                        Text("Calories")
                        Spacer()
                        MacroBadge.calories(caloriesForQuantity)
                    }
                }
            }

            if let standaloneCompleteness, standaloneCompleteness != .complete {
                completenessSection(standaloneCompleteness)
            }

            if needsGarminMatch {
                Section {
                    Label(String(localized: "Needs a Garmin match before it can be logged to Garmin."), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                    Button(String(localized: "Choose a Garmin match")) {
                        isPresentingGarminMatchEditor = true
                    }
                }
            }

            // implement-micronutrients (2026-09-22): the full vitamin/
            // mineral/macro panel for the SERVING actually being logged --
            // per-serving values (not scaled by `quantity`, matching how
            // this project already shows an un-scaled `calories`/label on
            // `FoodListRow`/`ServingPickerSheet` elsewhere; only the
            // headline "Calories" row above is quantity-scaled today). Real
            // data for a Garmin/FatSecret result is just the existing four
            // %DV fields; a real Open Food Facts result can show the much
            // larger panel `OpenFoodFactsClient` now decodes -- either way,
            // only whatever `selectedServing` actually carries appears
            // (`NutritionBreakdownSections`' own "never a fabricated zero"
            // rule), so this section is silently absent for a serving with
            // nothing beyond calories/macros.
            if let selectedServing, !selectedServing.detailedNutrients.filter({ $0.kind != .calories }).isEmpty {
                NutritionBreakdownSections(nutrients: selectedServing.detailedNutrients)
            }

            Section("When") {
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.dashboardOrder, id: \.self) { meal in
                        Label(meal.displayName, systemImage: meal.symbolName).tag(meal)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            // redesign-fasting-schedule 2.4: a note, never a block.
            FastingLogNoteSection(logDate: date)

            if let discrepancyNote {
                Section {
                    Label(discrepancyNote, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: didConfirm ? "Logged!" : "Log it", isDisabled: !canConfirm || isSaving) {
                confirm()
            }
            .padding(Theme.Spacing.md)
            .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isAmountFieldFocused = false }
            }
        }
        .sheet(isPresented: $isPresentingServingPicker) {
            ServingPickerSheet(food: food) { serving in
                selectedServing = serving
                // One full serving of whichever was just picked -- see
                // `quantity`'s doc comment for why this must never be the
                // serving's own `numberOfUnits`.
                quantity = 1
            }
        }
        .sensoryFeedback(.success, trigger: didConfirm) { _, confirmed in
            confirmed && Haptics.isEnabled
        }
        .animation(Theme.confirmAnimation(reduceMotion: reduceMotion), value: didConfirm)
        .interactiveDismissDisabled(isSaving)
        .onAppear(perform: applyContextOnce)
        .sheet(isPresented: $isPresentingCustomFoodEditor) {
            NavigationStack {
                CustomFoodEditorView(
                    prefillName: food.name,
                    prefillBrand: food.brandName,
                    prefillBarcode: food.source == .openFoodFacts ? food.id : nil
                )
            }
        }
        .sheet(isPresented: $isPresentingGarminMatchEditor) {
            NavigationStack {
                CustomFoodEditorView(existing: customDraft, onSaved: { saved in
                    updatedDraft = saved
                    selectedServing = saved.asFood().servings.first
                })
            }
        }
    }

    /// Standalone only (`standaloneCompleteness`).
    @ViewBuilder
    private func completenessSection(_ completeness: NutritionCompleteness) -> some View {
        Section {
            switch completeness {
            case .caloriesUnknown:
                Label(String(localized: "This food has no calorie value, so it can't be logged."), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.warning)
                Button(String(localized: "Create a custom food instead")) {
                    isPresentingCustomFoodEditor = true
                }
            case .someValuesMissing:
                Label(String(localized: "Some values missing: nutrients this food doesn't list count as 0 in your totals."), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .complete:
                EmptyView()
            }
        }
    }

    /// A meal chosen on the dashboard (`presetMealType`, already applied in
    /// `init`) always wins. Otherwise the meal comes from Garmin's meal
    /// windows (design D4) when that preference is on. Applied once, so the
    /// user's own picks are never overwritten.
    private func applyContextOnce() {
        guard !didApplyContext else { return }
        didApplyContext = true
        guard presetMealType == nil, environment.preferences.useGarminMealWindows else { return }
        mealType = MealWindowDefaulting.mealType(at: Date(), windows: environment.dayLog.latestWindows)
    }

    /// `!isSaving` is load-bearing, not redundant with the button's own
    /// `isDisabled`: that's applied on the next render, so a second tap
    /// landing before SwiftUI redraws still reaches `confirm()`, and
    /// `didConfirm` only flips after the awaited commit -- without this, a
    /// quick double-tap logged the same food to Garmin twice.
    /// `MealPresetConfirmView.canConfirm` already guards the same way.
    private var canConfirm: Bool {
        !didConfirm && !isSaving && (isCustom || selectedServing != nil) && isQuantityValid
            && (standaloneCompleteness?.isLoggable ?? true)
            && !needsGarminMatch
    }

    /// The same bound `LogEntryCoordinator` enforces (finite, > 0,
    /// <= `LogQuantity.maximum`). Checked here too so an absurd typed amount
    /// disables the button with a reason, rather than only failing on tap.
    private var isQuantityValid: Bool {
        quantity.map(LogQuantity.isValid) ?? false
    }

    private func confirm() {
        guard canConfirm, let quantity else { return }
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            let dateString = NutritionDate.string(from: date)
            do {
                switch target {
                case .catalog:
                    guard let selectedServing else { return }
                    try await environment.logEntryCoordinator.confirm(
                        food: food,
                        serving: selectedServing,
                        numberOfUnits: quantity,
                        mealType: mealType,
                        date: dateString,
                        regionCode: environment.profile.settings?.regionCode,
                        languageCode: environment.profile.settings?.languageCode
                    )
                case .custom(let draft, _):
                    let (_, note) = try await environment.logEntryCoordinator.confirmCustomFood(
                        updatedDraft ?? draft,
                        quantity: quantity,
                        mealType: mealType,
                        date: dateString,
                        regionCode: environment.profile.settings?.regionCode,
                        languageCode: environment.profile.settings?.languageCode
                    )
                    // Empty in standalone mode: a custom food is logged as
                    // itself there, so there is no Garmin stand-in to explain.
                    discrepancyNote = note.isEmpty ? nil : note
                }

                // Success is shown NOW -- the commit above is already
                // durable (a local JSON append via `Outbox.logFood`), per
                // the spec's zero-network-wait requirement. Draining is
                // fire-and-forget from here on; the confirm action itself
                // never awaits it.
                didConfirm = true
                // Gamification is the deliberate second step right after the
                // durable commit (GamificationEngine.swift's header): awards
                // XP, detects a level-up / streak milestone / challenge
                // completion, and enqueues the "moment" that the shell's
                // MomentOverlay presents. Local disk only -- no network wait
                // added to the confirm flow.
                await environment.gamificationEngine.handleLogConfirmed(calories: caloriesForQuantity)
                // Shows the entry in its meal immediately, records the Siri
                // donation, and starts delivery without waiting for it.
                await environment.logConfirmed(food: isCustom ? nil : food, date: dateString)
                try? await Task.sleep(nanoseconds: 500_000_000)
                dismiss()
            } catch let error as LogQuantityError {
                errorMessage = error.localizedDescription
            } catch let error as StandaloneLoggingError {
                errorMessage = error.localizedDescription
            } catch let error as CustomFoodLoggingError {
                errorMessage = error.localizedDescription
            } catch {
                DiagnosticsLog.log(.error, category: "LogEntryConfirmView", "confirm failed for foodId=\(food.id): \(error)")
                errorMessage = String(localized: "Couldn't save this entry. Try again.")
            }
        }
    }
}

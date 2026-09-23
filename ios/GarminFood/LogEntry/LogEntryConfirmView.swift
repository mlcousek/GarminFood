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
    /// must treat it the same way.
    @State private var quantity: Double
    @State private var mealType: MealType
    @State private var date: Date
    @State private var selectedServing: Serving?
    @State private var isPresentingServingPicker = false
    @State private var isSaving = false
    @State private var didConfirm = false
    @State private var discrepancyNote: String?
    @State private var errorMessage: String?
    @FocusState private var isAmountFieldFocused: Bool

    init(target: LogTarget, presetMealType: MealType? = nil, presetDate: Date? = nil) {
        self.target = target
        self.presetMealType = presetMealType
        self.presetDate = presetDate
        switch target {
        case .catalog(_, let serving):
            _selectedServing = State(initialValue: serving)
        case .custom(let draft):
            _selectedServing = State(initialValue: draft.asFood().servings.first)
        }
        // One full serving, always -- see `quantity`'s own doc comment.
        // 2026-09-18 bug, fixed before any user could rely on the wrong
        // value: this used to default to the SERVING's own defined amount
        // (e.g. 100 for a "100g" serving), while the Stepper below it was
        // range-limited to 0.25...50 -- a starting value already outside
        // its own control's valid range. The first tap of "+" snapped it
        // down to 50 rather than incrementing, which read as the app
        // randomly jumping to "50 servings" the moment you touched it.
        _quantity = State(initialValue: 1)
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
        case .catalog(let food, _): return food
        case .custom(let draft): return draft.asFood()
        }
    }

    private var isCustom: Bool {
        if case .custom = target { return true }
        return false
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
        guard let calories = selectedServing?.calories else { return nil }
        return calories * quantity
    }

    /// Grams, ml, and the like are amounts a user actually knows and wants
    /// to type ("70g"); "medium", "cup", "slice" are not -- there is no
    /// unit conversion available for those without knowing the food's
    /// density, which Garmin doesn't provide. Case/whitespace-insensitive,
    /// since Garmin's own data uses "G" and "g" for the same thing.
    private var isDirectlyEnterableAmount: Bool {
        guard let unit = selectedServing?.unit.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return ["g", "gram", "grams", "ml", "milliliter", "milliliters", "millilitre", "millilitres"].contains(unit)
    }

    /// The amount of `selectedServing.unit` this logs, e.g. 70 (g) for a
    /// "100g" serving at `quantity == 0.7`. Read/write: typing a new amount
    /// recomputes `quantity` against the serving's own defined size, which
    /// is the whole point -- the user thinks in grams, Garmin's API thinks
    /// in servings, and this is the one place those two convert.
    private var amountBinding: Binding<Double> {
        Binding(
            get: {
                guard let base = selectedServing?.numberOfUnits else { return quantity }
                return quantity * base
            },
            set: { newAmount in
                guard let base = selectedServing?.numberOfUnits, base > 0 else { return }
                quantity = newAmount / base
            }
        )
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
                            Text(selectedServing?.displayLabel ?? "Choose…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if isDirectlyEnterableAmount {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("Amount", value: amountBinding, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isAmountFieldFocused)
                            .frame(minWidth: 60)
                        Text(selectedServing?.unit.lowercased() ?? "g")
                            .foregroundStyle(.secondary)
                    }
                    if let selectedServing {
                        // The conversion made explicit, since the whole
                        // point of typing grams is not having to think in
                        // servings -- but showing it builds trust that the
                        // right number is what actually reaches Garmin.
                        Text("= \(quantity.formattedQuantity) of a \(selectedServing.displayLabel) serving")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("Quantity", value: $quantity, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($isAmountFieldFocused)
                            .frame(minWidth: 60)
                        if let unit = selectedServing?.unit, !unit.isEmpty {
                            Text(unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let caloriesForQuantity {
                    HStack {
                        Text("Calories")
                        Spacer()
                        MacroBadge(value: caloriesForQuantity, unit: " kcal", accessibleUnit: "kilocalories")
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

            if let discrepancyNote {
                Section {
                    Label(discrepancyNote, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
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
        !didConfirm && !isSaving && (isCustom || selectedServing != nil) && quantity > 0
    }

    private func confirm() {
        guard canConfirm else { return }
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
                case .custom(let draft):
                    let (_, note) = try await environment.logEntryCoordinator.confirmCustomFood(
                        draft,
                        quantity: quantity,
                        mealType: mealType,
                        date: dateString,
                        regionCode: environment.profile.settings?.regionCode,
                        languageCode: environment.profile.settings?.languageCode
                    )
                    discrepancyNote = note
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
            } catch {
                DiagnosticsLog.log(.error, category: "LogEntryConfirmView", "confirm failed for foodId=\(food.id): \(error)")
                errorMessage = "Couldn't save this entry. Try again."
            }
        }
    }
}

private extension Double {
    var formattedQuantity: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.2f", self)
    }
}

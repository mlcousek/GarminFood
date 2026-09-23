// MealPresetConfirmView.swift
//
// The meal-preset confirm screen -- mirrors `LogEntryConfirmView`'s shape
// (meal type/date default sensibly but stay editable, commits durably and
// shows success immediately, per the food-log-entry spec) but for an entire
// preset at once: every ingredient shown with its own contribution, a
// "Portions" multiplier to scale the whole preset up or down, and one "Log
// it" action that enqueues one outbox entry PER ingredient via
// `LogEntryCoordinator.confirmMealPreset` -- see that method's header for
// why this is durable-and-immediate exactly like a single food confirm.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct MealPresetConfirmView: View {
    let preset: MealPreset

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let presetMealType: MealType?
    private let presetDate: Date?
    @State private var didApplyContext = false

    /// Scales every ingredient's own preset quantity together -- "1" logs
    /// the preset exactly as composed.
    @State private var portions: Double = 1
    @State private var mealType: MealType
    @State private var date: Date
    @State private var isSaving = false
    @State private var didConfirm = false
    @State private var errorMessage: String?
    @FocusState private var isPortionsFieldFocused: Bool

    init(preset: MealPreset, presetMealType: MealType? = nil, presetDate: Date? = nil) {
        self.preset = preset
        self.presetMealType = presetMealType
        self.presetDate = presetDate
        _mealType = State(initialValue: presetMealType ?? MealTypeDefaulting.defaultMealType())
        _date = State(initialValue: presetDate ?? Date())
    }

    private var totals: MealPreset.Totals { preset.totals(servingsMultiplier: portions) }

    private var canConfirm: Bool { !didConfirm && !isSaving && !preset.ingredients.isEmpty && portionsAreValid }

    /// Every ingredient's scaled amount within `LogQuantity`'s bound -- the
    /// same check `LogEntryCoordinator.confirmMealPreset` makes up front.
    private var portionsAreValid: Bool {
        LogQuantity.isValid(portions) && preset.ingredients.allSatisfy { LogQuantity.isValid($0.quantity * portions) }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(preset.name)
                        .font(.title3.weight(.semibold))
                    Text("\(preset.ingredients.count) ingredient\(preset.ingredients.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Theme.Spacing.xs)

                HStack {
                    Text("Portions")
                    Spacer()
                    TextField("Portions", value: $portions, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isPortionsFieldFocused)
                        .frame(minWidth: 50)
                }

                HStack {
                    Text("Calories")
                    Spacer()
                    MacroBadge(value: totals.calories, unit: " kcal", accessibleUnit: "kilocalories")
                }
            }

            Section("Ingredients") {
                ForEach(preset.ingredients) { ingredient in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ingredient.food.name)
                                .font(.subheadline)
                            Text("\((ingredient.quantity * portions).formattedQuantity) × \(ingredient.serving.displayLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                        if let calories = ingredient.calories {
                            MacroBadge(value: calories * portions, unit: " kcal", accessibleUnit: "kilocalories")
                        }
                    }
                }
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

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Confirm meal")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: didConfirm ? "Logged!" : "Log it", isDisabled: !canConfirm, action: confirm)
                .padding(Theme.Spacing.md)
                .background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isPortionsFieldFocused = false }
            }
        }
        .sensoryFeedback(.success, trigger: didConfirm) { _, confirmed in
            confirmed && Haptics.isEnabled
        }
        .animation(Theme.confirmAnimation(reduceMotion: reduceMotion), value: didConfirm)
        .interactiveDismissDisabled(isSaving)
        .onAppear(perform: applyContextOnce)
    }

    /// Same rule as `LogEntryConfirmView.applyContextOnce()`: a preset meal
    /// chosen on the dashboard always wins; otherwise fall back to Garmin's
    /// own meal windows when that preference is on.
    private func applyContextOnce() {
        guard !didApplyContext else { return }
        didApplyContext = true
        guard presetMealType == nil, environment.preferences.useGarminMealWindows else { return }
        mealType = MealWindowDefaulting.mealType(at: Date(), windows: environment.dayLog.latestWindows)
    }

    private func confirm() {
        guard canConfirm else { return }
        isSaving = true
        errorMessage = nil

        Task {
            defer { isSaving = false }
            let dateString = NutritionDate.string(from: date)
            do {
                try await environment.logEntryCoordinator.confirmMealPreset(
                    preset,
                    servingsMultiplier: portions,
                    mealType: mealType,
                    date: dateString,
                    regionCode: environment.profile.settings?.regionCode,
                    languageCode: environment.profile.settings?.languageCode
                )

                // Success shown immediately, matching LogEntryConfirmView's
                // own zero-network-wait contract -- every ingredient is
                // already a durable local commit by the time this runs.
                didConfirm = true
                await environment.gamificationEngine.handleLogConfirmed(calories: totals.calories)
                await environment.logConfirmed(food: nil, date: dateString)
                try? await Task.sleep(nanoseconds: 500_000_000)
                dismiss()
            } catch let error as LogQuantityError {
                errorMessage = error.localizedDescription
            } catch {
                DiagnosticsLog.log(.error, category: "MealPresetConfirmView", "confirmMealPreset failed for preset=\(preset.name): \(error)")
                errorMessage = "Couldn't log this meal. Some ingredients may already be saved -- check the sync queue."
            }
        }
    }
}

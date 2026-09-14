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

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct LogEntryConfirmView: View {
    let target: LogTarget

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var quantity: Double
    @State private var mealType: MealType
    @State private var date: Date
    @State private var selectedServing: Serving?
    @State private var isPresentingServingPicker = false
    @State private var isSaving = false
    @State private var didConfirm = false
    @State private var discrepancyNote: String?
    @State private var errorMessage: String?

    init(target: LogTarget) {
        self.target = target
        let initialQuantity: Double
        switch target {
        case .catalog(_, let serving):
            initialQuantity = serving?.numberOfUnits ?? 1
            _selectedServing = State(initialValue: serving)
        case .custom(let draft):
            initialQuantity = 1
            _selectedServing = State(initialValue: draft.asFood().servings.first)
        }
        _quantity = State(initialValue: initialQuantity)
        _mealType = State(initialValue: MealTypeDefaulting.defaultMealType())
        _date = State(initialValue: Date())
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
        guard let calories = selectedServing?.calories, let servingUnits = selectedServing?.numberOfUnits, servingUnits > 0 else { return nil }
        return calories * (quantity / servingUnits)
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

                Stepper(value: $quantity, in: 0.25...50, step: 0.25) {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        Text(quantity.formattedQuantity)
                            .foregroundStyle(.secondary)
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

            Section("When") {
                Picker("Meal", selection: $mealType) {
                    ForEach(MealType.allCases, id: \.self) { meal in
                        Text(meal.rawValue.capitalized).tag(meal)
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
        .sheet(isPresented: $isPresentingServingPicker) {
            ServingPickerSheet(food: food) { serving in
                selectedServing = serving
                quantity = serving.numberOfUnits
            }
        }
        .sensoryFeedback(.success, trigger: didConfirm)
        .animation(Theme.confirmAnimation(reduceMotion: reduceMotion), value: didConfirm)
        .interactiveDismissDisabled(isSaving)
    }

    private var canConfirm: Bool {
        !didConfirm && (isCustom || selectedServing != nil) && quantity > 0
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
                        date: dateString
                    )
                case .custom(let draft):
                    let (_, note) = try await environment.logEntryCoordinator.confirmCustomFood(
                        draft,
                        quantity: quantity,
                        mealType: mealType,
                        date: dateString
                    )
                    discrepancyNote = note
                }

                // Success is shown NOW -- the commit above is already
                // durable (a local JSON append via `Outbox.logFood`), per
                // the spec's zero-network-wait requirement. Draining is
                // fire-and-forget from here on; the confirm action itself
                // never awaits it.
                didConfirm = true
                Task { await environment.drainAndReconcile() }
                try? await Task.sleep(nanoseconds: 500_000_000)
                dismiss()
            } catch {
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

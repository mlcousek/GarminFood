// LocalNutritionPlanSection.swift
//
// Settings -> "Nutrition plan" in STANDALONE mode (add-standalone-mode D6,
// task 4.3). In Garmin mode that section shows Garmin's plan read-only
// (SettingsView); a standalone install has no Garmin, so its plan is the
// local goal (`LocalGoalStore`) and is editable here, with "Recalculate"
// opening the goal calculator.
//
// Thin: shows `AppEnvironment.currentLocalGoal` (the goal in effect today)
// and presents `LocalGoalEditorView`, which does the saving. Saving adds a
// goal starting today, so the footer says earlier days keep their targets.
//
// Depends on: AppEnvironment (currentLocalGoal, reloadLocalGoal),
// LocalGoalEditorView. Depended on by: SettingsView.

import SwiftUI
import FoodLogCore

@MainActor
struct LocalNutritionPlanSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isEditing = false
    @State private var opensCalculator = false

    var body: some View {
        let goal = environment.currentLocalGoal

        Section {
            row(String(localized: "Calorie goal"), value: goal.map { "\($0.calories.wholeNumberText) kcal" })
            row(String(localized: "Carbs"), value: grams(goal?.carbsG))
            row(String(localized: "Protein"), value: grams(goal?.proteinG))
            row(String(localized: "Fat"), value: grams(goal?.fatG))
            Button(goal == nil ? String(localized: "Set targets") : String(localized: "Edit targets")) {
                opensCalculator = false
                isEditing = true
            }
            Button(String(localized: "Recalculate")) {
                opensCalculator = true
                isEditing = true
            }
        } header: {
            Text("Nutrition plan")
        } footer: {
            Text(goal == nil
                 ? String(localized: "No targets yet: Today shows what you ate without a goal. Stays on this phone.")
                 : String(localized: "Changes apply from today; earlier days keep the targets they had. Stays on this phone."))
        }
        .task { await environment.reloadLocalGoal() }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                LocalGoalEditorView(context: .settings, opensCalculatorFirst: opensCalculator) {
                    isEditing = false
                }
            }
        }
    }

    private func row(_ title: String, value: String?) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value ?? "—")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func grams(_ value: Double?) -> String? {
        value.map { "\($0.wholeNumberText) g" }
    }
}

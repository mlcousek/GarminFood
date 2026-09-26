// LocalGoalEditorView.swift
//
// Editing standalone mode's daily targets (add-standalone-mode D6, tasks
// 4.3 and 5.1): calories plus optional protein, carbs and fat, each typed
// by hand or filled from the goal calculator ("Calculate a suggestion").
// Saving writes a NEW goal starting today (`AppEnvironment.saveLocalGoal`),
// so earlier days keep theirs. Used from Settings' Nutrition plan and as
// onboarding's skippable goal step, where "Skip" leaves no target at all
// (spec "No goal set").
//
// Thin: parsing is FoodLogCore's `DecimalInput`, validation is
// `LocalNutritionGoals.isValid` behind `LocalGoalStore.save`, the maths is
// `GoalCalculator`. States plainly that these are general estimates, not
// medical advice.
//
// Depends on: AppEnvironment (currentLocalGoal, saveLocalGoal),
// GoalCalculatorView. Depended on by: LocalNutritionPlanSection,
// OnboardingView.

import SwiftUI
import FoodLogCore

@MainActor
struct LocalGoalEditorView: View {
    enum Context {
        case settings
        case onboarding
    }

    let context: Context
    /// Open the calculator right away ("Recalculate").
    var opensCalculatorFirst = false
    /// Called after a save, a cancel or a skip.
    let onFinished: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var floorNote: String?
    @State private var isPresentingCalculator = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var didLoad = false

    var body: some View {
        Form {
            Section {
                Button {
                    isPresentingCalculator = true
                } label: {
                    Label("Calculate a suggestion", systemImage: "function")
                }
            } footer: {
                Text("A few questions about you give a starting point. You can change every number before saving.")
            }

            Section {
                numberRow(String(localized: "Calories"), unit: "kcal", text: $caloriesText)
                numberRow(String(localized: "Protein"), unit: "g", text: $proteinText)
                numberRow(String(localized: "Carbs"), unit: "g", text: $carbsText)
                numberRow(String(localized: "Fat"), unit: "g", text: $fatText)
            } header: {
                Text("Daily targets")
            } footer: {
                if let floorNote {
                    Text(floorNote)
                } else {
                    Text("Protein, carbs and fat are optional.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            Section {
                Text("These are general estimates, not medical advice. If you're pregnant, have a medical condition or want to lose weight fast, ask a doctor or dietitian first.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Text("Daily targets"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(context == .onboarding ? String(localized: "Skip") : String(localized: "Cancel")) {
                    onFinished()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save")) {
                    Task { await save() }
                }
                .disabled(isSaving || caloriesText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $isPresentingCalculator) {
            NavigationStack {
                GoalCalculatorView { suggestion in
                    apply(suggestion)
                    isPresentingCalculator = false
                }
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await environment.reloadLocalGoal()
            if let goal = environment.currentLocalGoal {
                caloriesText = goal.calories.wholeNumberText
                proteinText = goal.proteinG?.wholeNumberText ?? ""
                carbsText = goal.carbsG?.wholeNumberText ?? ""
                fatText = goal.fatG?.wholeNumberText ?? ""
            }
            if opensCalculatorFirst {
                isPresentingCalculator = true
            }
        }
    }

    private func numberRow(_ title: String, unit: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func apply(_ suggestion: GoalCalculator.Suggestion) {
        caloriesText = suggestion.calories.wholeNumberText
        proteinText = suggestion.proteinG.wholeNumberText
        carbsText = suggestion.carbsG.wholeNumberText
        fatText = suggestion.fatG.wholeNumberText
        floorNote = GoalCalculatorView.floorExplanation(suggestion)
        errorMessage = nil
    }

    /// An empty macro field means "no target" (nil); a non-number is an
    /// error, never silently dropped.
    private func optionalNumber(_ text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .some(nil) }
        guard let value = DecimalInput.parse(trimmed) else { return nil }
        return .some(value)
    }

    private func save() async {
        guard let calories = DecimalInput.parse(caloriesText),
              let protein = optionalNumber(proteinText),
              let carbs = optionalNumber(carbsText),
              let fat = optionalNumber(fatText)
        else {
            errorMessage = String(localized: "Enter numbers only, like 1800.")
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await environment.saveLocalGoal(calories: calories, proteinG: protein, carbsG: carbs, fatG: fat)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

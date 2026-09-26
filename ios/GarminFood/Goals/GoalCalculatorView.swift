// GoalCalculatorView.swift
//
// The goal calculator's questions (add-standalone-mode D6, task 4.3): sex,
// birth year, height, weight, activity, goal and pace, answered here and
// turned into a suggestion by FoodLogCore's pure `GoalCalculator` (where the
// floors and pace limits live and are unit-tested). "Use these numbers"
// hands the suggestion back to `LocalGoalEditorView`, where every number can
// still be changed before anything is saved -- this screen saves nothing.
//
// The weight defaults to the latest weigh-in on this phone
// (`WeightLoader.latest`). Only paces the calculator allows for that weight
// are offered, so a refused pace can't be picked. Says why it asks for sex
// (it only picks the formula's constant) and when a floor raised the target.
//
// Depends on: AppEnvironment (weightLoader), GoalCalculator.
// Depended on by: LocalGoalEditorView.

import SwiftUI
import FoodLogCore

@MainActor
struct GoalCalculatorView: View {
    let onUse: (GoalCalculator.Suggestion) -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var sex: GoalCalculator.Sex = .female
    @State private var birthYear = Calendar.current.component(.year, from: Date()) - 30
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var activity: GoalCalculator.ActivityLevel = .light
    @State private var direction: GoalCalculator.Direction = .maintain
    @State private var pace = 0.5
    @State private var didPrefill = false

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    private var weightKg: Double? { DecimalInput.parse(weightText) }

    private var input: GoalCalculator.Input? {
        guard let height = DecimalInput.parse(heightText), let weight = weightKg else { return nil }
        return GoalCalculator.Input(sex: sex, birthYear: birthYear, heightCm: height, weightKg: weight, activity: activity, direction: direction, paceKgPerWeek: pace)
    }

    private var result: Result<GoalCalculator.Suggestion, GoalCalculator.InputError>? {
        guard let input else { return nil }
        do {
            return .success(try GoalCalculator.suggest(input, currentYear: currentYear))
        } catch let error as GoalCalculator.InputError {
            return .failure(error)
        } catch {
            return nil
        }
    }

    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Sex"), selection: $sex) {
                    Text("Female").tag(GoalCalculator.Sex.female)
                    Text("Male").tag(GoalCalculator.Sex.male)
                }
                Stepper(value: $birthYear, in: (currentYear - 100)...(currentYear - 14)) {
                    Text("Born in \(String(birthYear))")
                }
                HStack {
                    Text("Height")
                    Spacer()
                    TextField(text: $heightText, prompt: Text(verbatim: "165")) { Text("Height") }
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Text(verbatim: "cm").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField(text: $weightText, prompt: Text(verbatim: "60")) { Text("Weight") }
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    Text(verbatim: "kg").foregroundStyle(.secondary)
                }
            } header: {
                Text("About you")
            } footer: {
                Text("Sex only picks the formula's constant (Mifflin-St Jeor). Nothing leaves this phone.")
            }

            Section {
                Picker(String(localized: "Activity"), selection: $activity) {
                    Text("Mostly sitting").tag(GoalCalculator.ActivityLevel.sedentary)
                    Text("Lightly active").tag(GoalCalculator.ActivityLevel.light)
                    Text("Moderately active").tag(GoalCalculator.ActivityLevel.moderate)
                    Text("Very active").tag(GoalCalculator.ActivityLevel.very)
                    Text("Extremely active").tag(GoalCalculator.ActivityLevel.extra)
                }
                Picker(String(localized: "Goal"), selection: $direction) {
                    Text("Lose weight").tag(GoalCalculator.Direction.lose)
                    Text("Keep my weight").tag(GoalCalculator.Direction.maintain)
                    Text("Gain weight").tag(GoalCalculator.Direction.gain)
                }
                if direction != .maintain {
                    Picker(String(localized: "Pace"), selection: $pace) {
                        ForEach(allowedPaces, id: \.self) { value in
                            Text("\(value.formatted(.number.precision(.fractionLength(2)))) kg a week").tag(value)
                        }
                    }
                }
            } header: {
                Text("Activity and goal")
            } footer: {
                if direction != .maintain {
                    Text("At most 0.75 kg a week, and never more than one percent of your body weight.")
                }
            }

            Section {
                switch result {
                case .success(let suggestion)?:
                    resultRow(String(localized: "Calories"), "\(suggestion.calories.wholeNumberText) kcal")
                    resultRow(String(localized: "Protein"), "\(suggestion.proteinG.wholeNumberText) g")
                    resultRow(String(localized: "Carbs"), "\(suggestion.carbsG.wholeNumberText) g")
                    resultRow(String(localized: "Fat"), "\(suggestion.fatG.wholeNumberText) g")
                    if let note = Self.floorExplanation(suggestion) {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                    Button(String(localized: "Use these numbers")) {
                        onUse(suggestion)
                    }
                case .failure(let error)?:
                    Text(Self.message(for: error))
                        .foregroundStyle(Theme.danger)
                case nil:
                    Text("Enter your height and weight.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Suggestion")
            } footer: {
                Text("General estimates, not medical advice.")
            }
        }
        .navigationTitle(Text("Goal calculator"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel")) { dismiss() }
            }
        }
        .onChange(of: weightText) { _, _ in keepPaceAllowed() }
        .task {
            guard !didPrefill else { return }
            didPrefill = true
            await environment.weightLoader.refresh()
            if weightText.isEmpty, let latest = environment.weightLoader.latest {
                weightText = latest.weightKg.formatted(.number.precision(.fractionLength(0...1)))
            }
            keepPaceAllowed()
        }
    }

    private var allowedPaces: [Double] {
        GoalCalculator.allowedPaces(weightKg: weightKg ?? 100)
    }

    private func keepPaceAllowed() {
        if !allowedPaces.contains(pace), let fastest = allowedPaces.last {
            pace = fastest
        }
    }

    private func resultRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Why a floor raised the target, or `nil` when none did.
    static func floorExplanation(_ suggestion: GoalCalculator.Suggestion) -> String? {
        switch suggestion.appliedFloor {
        case .minimumCalories?:
            return String(localized: "Raised to 1200 kcal: a lower daily target isn't safe without a doctor.")
        case .bmr?:
            return String(localized: "Raised to what your body burns at rest: going lower isn't safe without a doctor.")
        case nil:
            return nil
        }
    }

    static func message(for error: GoalCalculator.InputError) -> String {
        switch error {
        case .ageOutOfRange:
            return String(localized: "The calculator works for ages 14 to 100.")
        case .heightOutOfRange:
            return String(localized: "Enter a height between 100 and 250 cm.")
        case .weightOutOfRange:
            return String(localized: "Enter a weight between 30 and 300 kg.")
        case .paceTooFast:
            return String(localized: "That pace is too fast for your weight. Pick a slower one.")
        }
    }
}

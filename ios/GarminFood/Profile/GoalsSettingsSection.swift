// GoalsSettingsSection.swift
//
// Settings -> Goals (sync-weight-hydration-with-garmin task 3.5, design.md
// D5): the water goal and the weight goal default to Garmin's own
// (`goalInML` from the hydration read, `targetWeightGoal`/`startingWeight`
// from nutrition settings, both cached by `GarminHealthSync`), and each can
// be overridden locally with a "Use Garmin's goal" way back. Overrides live
// in `AppPreferences` (goals.* keys) and are NEVER written to Garmin
// (proposal non-goal), which the footer says plainly.
//
// Its own Section view, embedded in SettingsView with one line, like
// FastingSettingsSection. Reads the effective values from the loaders so
// what's shown here is exactly what the cards use.

import SwiftUI
import FoodLogCore

@MainActor
struct GoalsSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let preferences = environment.preferences
        let water = environment.hydrationLoader
        let weight = environment.weightLoader

        Section {
            // Water
            HStack {
                Text("Water goal")
                Spacer()
                Text("\(water.goalML.formattedML) ml")
                    .foregroundStyle(.secondary)
                Text(originLabel(water.goal.origin))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .accessibilityElement(children: .combine)

            Toggle("Use Garmin's water goal", isOn: Binding(
                get: { preferences.waterGoalOverrideML == nil },
                set: { useGarmin in
                    preferences.waterGoalOverrideML = useGarmin ? nil : water.goalML
                }
            ))

            if preferences.waterGoalOverrideML != nil {
                Stepper(value: Binding(
                    get: { preferences.waterGoalOverrideML ?? water.goalML },
                    set: { preferences.waterGoalOverrideML = $0 }
                ), in: 500...6000, step: 100) {
                    Text("My goal: \((preferences.waterGoalOverrideML ?? water.goalML).wholeNumberText) ml")
                }
            }

            // Weight
            HStack {
                Text("Weight goal")
                Spacer()
                if let goal = weight.goal {
                    Text("\(goal.targetKg.formattedKg) kg")
                        .foregroundStyle(.secondary)
                    Text(originLabel(goal.origin))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("Not set")
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Toggle("Use Garmin's weight goal", isOn: Binding(
                get: { preferences.weightGoalOverrideKg == nil && preferences.weightGoalStartKg == nil },
                set: { useGarmin in
                    if useGarmin {
                        preferences.weightGoalOverrideKg = nil
                        preferences.weightGoalStartKg = nil
                    } else {
                        preferences.weightGoalOverrideKg = weight.goal?.targetKg ?? weight.latest?.weightKg.roundedToHalf ?? 75
                    }
                }
            ))

            if preferences.weightGoalOverrideKg != nil || preferences.weightGoalStartKg != nil {
                Stepper(value: Binding(
                    get: { targetKg(preferences, weight) },
                    set: { preferences.weightGoalOverrideKg = $0 }
                ), in: 30...250, step: 0.5) {
                    Text("Target: \(targetKg(preferences, weight).formattedKg) kg")
                }
                Stepper(value: Binding(
                    get: { startKg(preferences, weight) },
                    set: { preferences.weightGoalStartKg = $0 }
                ), in: 30...250, step: 0.5) {
                    Text("Starting weight: \(startKg(preferences, weight).formattedKg) kg")
                }
            }
        } header: {
            Text("Goals")
        } footer: {
            Text(footerText(garminWater: water.garminGoalML, garminTarget: weight.garminTargetKg))
        }
    }

    /// The target the stepper shows: my override, else Garmin's, else 75.
    private func targetKg(_ preferences: AppPreferences, _ weight: WeightLoader) -> Double {
        if let override = preferences.weightGoalOverrideKg { return override }
        if let garmin = weight.garminTargetKg { return garmin }
        return 75
    }

    /// The start the stepper shows: my override, else Garmin's, else the
    /// latest weigh-in, else 80.
    private func startKg(_ preferences: AppPreferences, _ weight: WeightLoader) -> Double {
        if let override = preferences.weightGoalStartKg { return override }
        if let garmin = weight.garminStartKg { return garmin }
        if let latest = weight.latest { return latest.weightKg.roundedToHalf }
        return 80
    }

    private func originLabel(_ origin: GoalOrigin) -> String {
        switch origin {
        case .garmin: return "Garmin"
        case .override: return "Mine"
        case .fallback: return "Default"
        }
    }

    private func footerText(garminWater: Double?, garminTarget: Double?) -> String {
        var parts: [String] = []
        if let garminWater {
            parts.append("Garmin's water goal: \(garminWater.formattedML) ml.")
        }
        if let garminTarget {
            parts.append("Garmin's weight goal: \(garminTarget.formattedKg) kg.")
        }
        parts.append("Your own goals stay on this phone; Garmin Connect isn't changed.")
        return parts.joined(separator: " ")
    }
}

private extension Double {
    /// Nearest 0.5 -- a sensible stepper starting point from a weigh-in.
    var roundedToHalf: Double { (self * 2).rounded() / 2 }
}

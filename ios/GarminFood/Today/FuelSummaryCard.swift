// FuelSummaryCard.swift
//
// add-winter-arc-nutrition-and-rewards (A1): the Today summary in the
// training experience on a plan day with a carb band. It leads with what
// the plan asks for -- carbs against the day's g/kg band (x weight) and
// protein against about 1.6 g/kg -- and shows calories only as a
// secondary line. Nothing here is ever a warning colour: eating above the
// band or the calorie target on a training day is fine, and a day clearly
// under the band late in the evening gets one gentle, secondary note
// (FuelDayEvaluator's rule).
//
// Every number and judgement comes from FoodLogCore's `FuelDaySummary`;
// this view only lays it out. Without a band (a rest day, no weight known,
// food-first) TodayView keeps `DaySummaryCard`, whose ring then only
// softens "over" on a training day (`FuelDayEvaluator.displayBand`).
//
// Depends on: FoodLogCore (FuelDaySummary, MacroProgress), the design
// system. Depended on by: TodayView (`.summary` slot).

import SwiftUI
import FoodLogCore

struct FuelSummaryCard: View {
    let summary: FuelDaySummary
    let calories: MacroProgress
    let isStale: Bool
    let isLoading: Bool
    let hasGarminData: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(summary.isCarbLoad ? String(localized: "Carb-load day", comment: "Today summary title on a carb-load day of the training plan.") : String(localized: "Fuel for today's training", comment: "Today summary title in the training experience: carbs and protein for the plan day."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)

            carbs
            protein

            Text(caloriesText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if summary.showsUnderFuellingNote {
                Label {
                    Text("Carbs are well under today's range. A carb-rich dinner helps you recover for tomorrow.", comment: "Gentle note late in the day when carbs are clearly below the training day's range.")
                } icon: {
                    Image(systemName: "fork.knife")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            statusLine
        }
        .card()
    }

    // MARK: Carbs

    private var carbs: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(String(localized: "\(summary.carbsG.wholeNumberText) g"))
                    .heroNumberFont()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("Carbs")
                    .font(.heroUnit)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(summary.carbStatus == .inBand ? Theme.success : Color.secondary)
            }
            ProgressView(value: summary.carbFraction)
                .tint(Theme.carbs)
            Text(rangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Carbs: \(summary.carbsG.wholeNumberText) grams, range \(summary.carbBand.lowerBound.wholeNumberText) to \(summary.carbBand.upperBound.wholeNumberText) grams", comment: "VoiceOver for the training day's carbs: eaten, then the plan's range."))
        .accessibilityValue(statusText)
    }

    private var rangeText: String {
        let low = summary.carbBand.lowerBound.wholeNumberText
        let high = summary.carbBand.upperBound.wholeNumberText
        if low == high {
            return String(localized: "Target \(low) g", comment: "Carb-load day: the single carbohydrate target in grams.")
        }
        return String(localized: "Range \(low)–\(high) g", comment: "The training day's carbohydrate range in grams (from the plan's g/kg band).")
    }

    private var statusText: String {
        switch summary.carbStatus {
        case .below: return String(localized: "Below range", comment: "Carbs are under the training day's range (never shown as a warning).")
        case .inBand: return String(localized: "In range", comment: "Carbs are inside the training day's range.")
        case .above: return String(localized: "Above range", comment: "Carbs are over the training day's range (fine on a training day, never a warning).")
        }
    }

    // MARK: Protein

    private var protein: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text("Protein")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.xs)
                Text(String(localized: "\(summary.proteinG.wholeNumberText) g"))
                    .font(.macroValue)
                if let target = summary.proteinTargetG {
                    Text(String(localized: "About \(target.wholeNumberText) g", comment: "The plan's protein target for the day, about 1.6 g per kg."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = summary.proteinFraction {
                ProgressView(value: fraction)
                    .tint(Theme.protein)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Calories (secondary)

    private var caloriesText: String {
        let eaten = calories.consumed.wholeNumberText
        guard let goal = calories.goal, goal > 0 else {
            return String(localized: "\(eaten) kcal eaten", comment: "Training day summary: calories eaten, secondary line without a target.")
        }
        return String(localized: "\(eaten) kcal eaten · target \(goal.wholeNumberText) kcal", comment: "Training day summary: calories eaten and the calorie target, a secondary line only.")
    }

    @ViewBuilder
    private var statusLine: some View {
        if isLoading {
            Label("Updating…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isStale {
            Label("Showing the last loaded numbers", systemImage: "wifi.exclamationmark")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        } else if !hasGarminData {
            Label("Not loaded from Garmin yet", systemImage: "icloud.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// TodayHeroView.swift
//
// The home screen's hero, and the app's signature element. Two decisions
// worth stating because they go against the genre default:
//
// 1. NO calorie ring. Every food tracker draws a donut; here the NUMBER is
//    the object -- a large rounded tabular-numeral count -- with a thin
//    horizontal fill bar under it that reads like a fuel gauge. The bar's
//    tint encodes state (under goal / on target / over), so the colour is
//    information, not decoration.
// 2. The flame + streak count is the eyebrow ABOVE the number, not a badge
//    tucked in a corner. The two things the owner asked to be primary --
//    the streak and today's intake -- are the first two things the eye
//    lands on, in that order, and nothing else on the screen competes.
//
// Loading/empty/stale/no-goal are each a designed state (config.yaml), not
// SwiftUI's default. Reduce Motion collapses the bar's fill animation to a
// plain state change.

import SwiftUI
import Gamification

struct TodayHeroView: View {
    let summary: TodaySummary?
    let isStale: Bool
    let streak: StreakEngine.Status

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            StreakEyebrow(streak: streak)

            calorieCount

            if let summary {
                FuelBar(fraction: summary.goalFraction, state: summary.goalState)
                    .frame(height: 10)
                    .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: summary.consumedCalories)
                goalLine(summary)
                MacroRow(summary: summary)
            } else {
                FuelBar(fraction: 0, state: .noGoal)
                    .frame(height: 10)
                Text("Pulling today's log from Garmin…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.heroBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pieces

    private var calorieCount: some View {
        HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.sm) {
            Text(summary.map { Int($0.consumedCalories.rounded()) } ?? 0, format: .number)
                .font(.heroNumber)
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: summary?.consumedCalories)
                .redacted(reason: summary == nil ? .placeholder : [])
            Text("kcal")
                .font(.heroUnit)
                .foregroundStyle(.secondary)
            if isStale {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Showing the last known total")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleCountLabel)
    }

    @ViewBuilder
    private func goalLine(_ summary: TodaySummary) -> some View {
        switch summary.goalState {
        case .noGoal:
            Text("Eaten today")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .under:
            let remaining = Int((summary.remainingCalories ?? 0).rounded())
            let goal = Int((summary.goalCalories ?? 0).rounded())
            Text("\(remaining, format: .number) left of \(goal, format: .number)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        case .onTarget:
            Label("On target", systemImage: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.success)
        case .over:
            let over = Int((-(summary.remainingCalories ?? 0)).rounded())
            Text("\(over, format: .number) over your goal")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.over)
        }
    }

    private var accessibleCountLabel: String {
        guard let summary else { return "Today's calories are loading" }
        let eaten = Int(summary.consumedCalories.rounded())
        if let goal = summary.goalCalories {
            return "\(eaten) of \(Int(goal.rounded())) kilocalories eaten today"
        }
        return "\(eaten) kilocalories eaten today"
    }
}

// MARK: - Streak eyebrow

/// The flame. Three visual states, all encoded in the flame itself rather
/// than a separate status label: alive (warm gradient), at risk today
/// (dimmed, with a nudge), and no streak yet (outline, with an invitation).
private struct StreakEyebrow: View {
    let streak: StreakEngine.Status

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: streak.length > 0 ? "flame.fill" : "flame")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(flameStyle)
                .symbolEffect(.pulse, options: .repeating, isActive: streak.isAtRiskToday)

            if streak.length > 0 {
                Text("\(streak.length)")
                    .font(.streakNumber)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("day streak")
                    .font(.streakLabel)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start a streak")
                    .font(.streakLabel)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if streak.isAtRiskToday {
                Text("Log something to keep it")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.ember)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(Theme.ember.opacity(0.12), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleLabel)
    }

    private var flameStyle: AnyShapeStyle {
        if streak.length == 0 { return AnyShapeStyle(.tertiary) }
        if streak.isAtRiskToday { return AnyShapeStyle(Theme.ember.opacity(0.55)) }
        return AnyShapeStyle(Theme.flameGradient)
    }

    private var accessibleLabel: String {
        if streak.length == 0 { return "No streak yet. Log a food today to start one." }
        let base = "\(streak.length) day streak"
        return streak.isAtRiskToday ? "\(base), at risk. Log something today to keep it." : base
    }
}

// MARK: - Fuel bar

private struct FuelBar: View {
    let fraction: Double?
    let state: TodaySummary.GoalState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let fraction {
                    Capsule()
                        .fill(fill)
                        .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 10 : 0))
                }
            }
        }
        .accessibilityHidden(true) // the count + goal line already say it
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .under, .noGoal: return AnyShapeStyle(Theme.accent)
        case .onTarget: return AnyShapeStyle(Theme.success)
        case .over: return AnyShapeStyle(Theme.over)
        }
    }
}

// MARK: - Macro row

private struct MacroRow: View {
    let summary: TodaySummary

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            macro("Protein", summary.protein)
            macro("Carbs", summary.carbs)
            macro("Fat", summary.fat)
        }
        .padding(.top, Theme.Spacing.xs)
    }

    private func macro(_ name: String, _ grams: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(grams.map { "\(Int($0.rounded()))g" } ?? "—")
                .font(.macroValue)
                .foregroundStyle(.primary)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(grams.map { "\(Int($0.rounded())) grams" } ?? "unknown")")
    }
}

#Preview("Streak alive, under goal") {
    TodayHeroView(
        summary: TodaySummary(consumedCalories: 1738, goalCalories: 2300, protein: 89, carbs: 234, fat: 49, fetchedAt: .now),
        isStale: false,
        streak: StreakEngine.Status(length: 12, hasLoggedToday: true, isAtRiskToday: false, lastLoggedDay: .now)
    )
    .padding()
}

#Preview("At risk, no goal") {
    TodayHeroView(
        summary: TodaySummary(consumedCalories: 420, goalCalories: nil, protein: 20, carbs: 50, fat: 10, fetchedAt: .now),
        isStale: true,
        streak: StreakEngine.Status(length: 5, hasLoggedToday: false, isAtRiskToday: true, lastLoggedDay: .now)
    )
    .padding()
}

#Preview("Loading, no streak") {
    TodayHeroView(
        summary: nil,
        isStale: false,
        streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil)
    )
    .padding()
}

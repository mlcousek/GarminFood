// HabitLadderView.swift
//
// Where each habit of the ladder stands (add-training-today-and-plan task
// 5.5, design D10, spec "The habit ladder shows where each habit stands"):
// every step in order with its state (active, next, later), its why, its
// start date or earliest start, its schedule in words, the 14-day window
// against the gate ("not recorded yet" when the vault has nothing) and the
// "Gate met" note where the vault says so.
//
// Read-only: no control to start, pause or tick a habit -- starting a step
// stays a desk decision. Everything shown is `HabitLadderModel` from
// TrainingCore's PlanBuilder. Reached from Plan's toolbar and from Today's
// habits card.
//
// Depended on by: PlanTabView, TodayView.

import SwiftUI
import TrainingCore

struct HabitLadderView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let ladder = environment.training.planBuilder().habitLadder()
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if let gate = ladder.gateText {
                    Label {
                        Text(verbatim: gate)
                    } icon: {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                if let empty = ladder.emptyText {
                    TrainingEmptyStateView(state: TrainingEmptyState(kind: .noActivePlan, symbol: "stairs", title: empty, message: nil))
                        .card()
                }
                ForEach(ladder.rows) { row in
                    HabitLadderRow(row: row)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle("Habit ladder")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HabitLadderRow: View {
    let row: HabitLadderRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                if let icon = row.icon {
                    Text(verbatim: icon)
                        .font(.title2)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.label)
                        .font(.headline)
                    if let dose = row.dose {
                        Text(verbatim: dose)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let state = row.stateText {
                    Label {
                        Text(verbatim: state)
                    } icon: {
                        Image(systemName: stateSymbol)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(row.state == .active ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary))
                }
            }
            if let why = row.why {
                Text(verbatim: why)
                    .font(.subheadline)
            }
            let details = [row.schedule, row.dateText].compactMap { $0 }
            if !details.isEmpty {
                Text(verbatim: details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.sm) {
                if let fraction = row.fraction {
                    ProgressView(value: min(max(fraction, 0), 1))
                        .tint(Theme.accent)
                        .frame(maxWidth: 120)
                }
                Text(verbatim: row.adherence)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let gateMet = row.gateMetText {
                Label {
                    Text(verbatim: gateMet)
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
            }
        }
        .card()
        .opacity(row.state == .later ? 0.75 : 1)
        .accessibilityElement(children: .combine)
    }

    private var stateSymbol: String {
        switch row.state {
        case .active?: return "play.circle.fill"
        case .next?: return "arrow.right.circle"
        case .later?, nil: return "clock"
        }
    }
}

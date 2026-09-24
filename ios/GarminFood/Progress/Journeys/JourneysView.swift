// JourneysView.swift
//
// add-journeys-and-records design D9: the full journeys screen. Per journey:
// the total so far, the conversion stated in one line (so protein-as-metres
// never pretends to be science), the current stage, a bar to the next
// milestone with the distance left, and a vertical milestone path of the
// current stage (reached = filled, next = pulsing unless Reduce Motion).
// Past the last finite water milestone it shows the share of the Podolí
// pool instead.
//
// Thin: everything comes from `JourneysFeature.journeys()` (Gamification,
// unit-tested); names and conversion lines arrive already localized,
// hence `Text(verbatim:)` for them.
//
// Depends on: AppEnvironment, JourneysFeature, JourneyFormat, Theme.
// Depended on by: JourneysSlotView.

import SwiftUI
import Gamification

@MainActor
struct JourneysView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var journeys: [JourneyProgress] = []

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                ForEach(journeys) { journey in
                    JourneyCard(progress: journey)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(Text("Journeys"))
        .task(id: featureHost?.summaries[JourneysFeature.id]) {
            await reload()
        }
    }

    private func reload() async {
        guard let feature = featureHost?.feature(JourneysFeature.self) else { return }
        journeys = await feature.journeys().filter(\.isAvailable)
    }
}

private struct JourneyCard: View {
    let progress: JourneyProgress

    private var definition: JourneyDefinition { progress.definition }

    private var stageMilestones: [JourneyMilestone] {
        definition.milestones.filter { $0.stageIndex == progress.stageIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: definition.symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: definition.name)
                        .font(.headline)
                    Text("Total: \(JourneyFormat.amount(progress.total, unit: definition.unit))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(verbatim: definition.conversionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if definition.stages.count > 1, let stage = progress.stage {
                Text("Stage \(progress.stageIndex + 1) of \(definition.stages.count): \(stage.name)")
                    .font(.caption.weight(.semibold))
            }

            if let next = progress.next {
                ProgressView(value: progress.fractionToNext)
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
                Text("Next: \(next.name) · \(JourneyFormat.amount(progress.remainingToNext ?? 0, unit: definition.unit)) to go")
                    .font(.subheadline)
            } else if let endless = definition.endless, let share = progress.endlessPercent {
                ProgressView(value: min(share / 100, 1))
                    .tint(Theme.water)
                    .accessibilityHidden(true)
                Text("\(endless.name): \(JourneyFormat.percent(value: share)) filled")
                    .font(.subheadline)
            } else {
                Text("All milestones reached!")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.success)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stageMilestones.enumerated()), id: \.element.id) { index, milestone in
                    MilestoneStep(
                        milestone: milestone,
                        amount: JourneyFormat.milestoneAmount(milestone, in: definition),
                        state: state(of: milestone),
                        isLast: index == stageMilestones.count - 1
                    )
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
        .card()
    }

    private func state(of milestone: JourneyMilestone) -> MilestoneStep.StepState {
        if milestone.threshold <= progress.total { return .reached }
        if milestone.id == progress.next?.id { return .next }
        return .ahead
    }
}

private struct MilestoneStep: View {
    enum StepState {
        case reached, next, ahead
    }

    let milestone: JourneyMilestone
    let amount: String
    let state: StepState
    let isLast: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(spacing: 0) {
                marker
                    .frame(width: 16, height: 16)
                if !isLast {
                    Rectangle()
                        .fill(state == .reached ? Theme.accent : Theme.stroke)
                        .frame(width: 2)
                        .frame(minHeight: 18)
                }
            }
            HStack {
                Text(verbatim: milestone.name)
                    .font(state == .next ? Font.subheadline.weight(.semibold) : Font.subheadline)
                    .foregroundStyle(state == .ahead ? Color.secondary : Color.primary)
                Spacer()
                Text(verbatim: amount)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, isLast ? 0 : Theme.Spacing.sm)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var marker: some View {
        switch state {
        case .reached:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        case .next:
            Circle()
                .strokeBorder(Theme.accent, lineWidth: 3)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                .onAppear {
                    if !reduceMotion { pulse = true }
                }
        case .ahead:
            Circle()
                .strokeBorder(Theme.stroke, lineWidth: 2)
        }
    }

    private var accessibilityText: Text {
        switch state {
        case .reached: return Text("\(milestone.name), \(amount), reached")
        case .next: return Text("\(milestone.name), \(amount), next milestone")
        case .ahead: return Text("\(milestone.name), \(amount), not reached yet")
        }
    }
}

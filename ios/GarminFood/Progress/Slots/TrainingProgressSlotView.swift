// TrainingProgressSlotView.swift
//
// add-training-gamification-and-150-levels (design D10): the Progress tab's
// training section -- the slot add-winter-arc-nutrition-and-rewards left for
// later. Shown only in the training experience, right under the Level card:
//   - this week: check-ins, kept plan days, strength sessions;
//   - streaks: check-in days, habit days, weeks kept in a row;
//   - the three ladders closest to their next badge, and how many training
//     badges are earned.
// It opens `TrainingProgressView`, the full list of every training ladder
// with its count and next step.
//
// Thin on purpose: every number and every label except this file's few
// section titles comes from `TrainingRewardsFeature.progressModel()`
// (Gamification's `TrainingProgressModel`, unit-tested there, text already
// localized). The model is reloaded after every completed feature pass
// (`FeatureHost.completedRuns`), because a check-in or a tick changes it
// without changing the feature's hub summary.
//
// Outside the training experience the slot renders nothing.
//
// Depends on: AppEnvironment, FeatureHost, TrainingRewardsFeature,
// TrainingProgressModel. Depended on by: ProgressHomeView (the Level arm).

import SwiftUI
import Gamification

@MainActor
struct TrainingProgressSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: TrainingProgressModel = .empty

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    private var isShown: Bool {
        guard let featureHost, featureHost.isTrainingExperience else { return false }
        return featureHost.feature(TrainingRewardsFeature.self) != nil
    }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs (see SeasonalBannerSlot).
        VStack(spacing: 0) {
            if isShown {
                NavigationLink {
                    TrainingProgressView()
                } label: {
                    card
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.completedRuns) {
            await reload()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "figure.run")
                    .foregroundStyle(Theme.accent)
                Text("Training")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .accessibilityHidden(true)

            if !model.thisWeek.isEmpty {
                TrainingStatStrip(stats: model.thisWeek)
            }
            TrainingStatStrip(stats: model.streaks)

            ForEach(model.highlights()) { row in
                TrainingLadderRowView(row: row)
            }

            Text("Training badges: \(model.tiersReached) of \(model.tierCount)", comment: "Progress tab, training card: training badges earned, then all of them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens training progress"))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(TrainingRewardsFeature.self) else { return }
        model = await feature.progressModel()
    }
}

/// Up to three numbers side by side, each over its label.
private struct TrainingStatStrip: View {
    let stats: [TrainingProgressModel.Stat]

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: stat.value)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text(verbatim: stat.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// One ladder: icon, name, "31 · next: 100" and the bar to the next badge.
private struct TrainingLadderRowView: View {
    let row: TrainingProgressModel.LadderRow

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: row.symbol)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.title)
                        .font(.subheadline)
                    Spacer()
                    Text(verbatim: row.detail)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: row.fraction)
                    .tint(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - The full list

/// Every training ladder with its count and next step, this week and the
/// streaks -- the screen behind the Progress tab's training card.
@MainActor
struct TrainingProgressView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var model: TrainingProgressModel = .empty

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        List {
            if !model.thisWeek.isEmpty {
                Section("This week") {
                    ForEach(model.thisWeek) { stat in
                        statRow(stat)
                    }
                }
            }
            Section("Streaks") {
                ForEach(model.streaks) { stat in
                    statRow(stat)
                }
            }
            Section {
                ForEach(model.ladders) { row in
                    TrainingLadderRowView(row: row)
                }
            } header: {
                Text("Ladders")
            } footer: {
                Text("Training XP is for following the plan and for honest check-ins. Rest days count. Extra kilometres do not.")
            }
        }
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: featureHost?.completedRuns) {
            guard let feature = featureHost?.feature(TrainingRewardsFeature.self) else { return }
            model = await feature.progressModel()
        }
    }

    private func statRow(_ stat: TrainingProgressModel.Stat) -> some View {
        HStack {
            Label {
                Text(verbatim: stat.title)
            } icon: {
                Image(systemName: stat.symbol)
            }
            Spacer()
            Text(verbatim: stat.value)
                .font(.body.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

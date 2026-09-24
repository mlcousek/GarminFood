// SeasonalBannerSlot.swift
//
// add-seasonal-events design D5: the Today-tab banner for the Czech
// seasonal event running right now (or, in the 3 days before one opens, its
// "coming soon" teaser) -- title, window end, and each quest with a
// checkmark, so logging "Houbová polévka" visibly ticks the mushroom quest.
// When several events overlap it shows the one ending soonest (the Progress
// slot lists all of them). Renders nothing outside every window.
//
// Thin by design: all state comes from `SeasonalEventsFeature.bannerEvent`
// (Gamification, unit-tested); this view only reloads it whenever the
// feature host publishes a new seasonal summary (i.e. after every refresh /
// log confirm) and lays it out. Quest and event titles arrive already
// localized from the package, hence `Text(verbatim:)`/`Text(String)` for them.
//
// Depends on: AppEnvironment (gamificationEngine.featureHost),
// SeasonalEventsFeature, SeasonalQuestRow. Depended on by: TodaySlotHost.

import SwiftUI
import Gamification

@MainActor
struct SeasonalBannerSlot: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var status: SeasonalEventStatus?

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs, so the first load would never happen.
        VStack(spacing: 0) {
            if let status {
                SeasonalBannerCard(status: status)
            }
        }
        .task(id: featureHost?.summaries[SeasonalEventsFeature.id]) {
            await reload()
        }
    }

    private func reload() async {
        guard let feature = featureHost?.feature(SeasonalEventsFeature.self) else {
            status = nil
            return
        }
        status = await feature.bannerEvent()
    }
}

private struct SeasonalBannerCard: View {
    let status: SeasonalEventStatus

    private var dateText: String {
        let date = status.phase == .active ? status.end : status.start
        guard let value = date.date(in: .current) else { return date.dayKey }
        return value.formatted(.dateTime.day().month(.wide))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: status.symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.phase == .active ? "Seasonal event" : "Coming soon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(verbatim: status.title)
                        .font(.headline)
                }
                Spacer(minLength: 0)
                Text(status.phase == .active ? "Until \(dateText)" : "Starts \(dateText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if status.phase == .active {
                if status.isCompleted {
                    Label("Event complete!", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.success)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(status.quests) { quest in
                        SeasonalQuestRow(quest: quest)
                    }
                }
            } else {
                Text(verbatim: status.teaser)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// One quest line with a checkmark (shared by the banner and the Progress
/// events screen).
struct SeasonalQuestRow: View {
    let quest: SeasonalQuestStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Image(systemName: quest.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(quest.isDone ? Theme.success : Color.secondary)
                .accessibilityHidden(true)
            Text(verbatim: quest.title)
                .font(.subheadline)
                .foregroundStyle(quest.isDone ? Color.secondary : Color.primary)
                .strikethrough(quest.isDone)
            if quest.isBonus {
                Text("Bonus +25 XP")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            Spacer(minLength: 0)
            if quest.target > 1 {
                Text(verbatim: "\(quest.progress)/\(quest.target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: quest.title))
        .accessibilityValue(quest.isDone
            ? Text("Done")
            : Text("\(quest.progress) of \(quest.target)"))
    }
}

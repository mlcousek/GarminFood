// SeasonalEventsView.swift
//
// add-seasonal-events design D5/D6: the full seasonal-events screen behind
// the Progress slot -- a showcase of the limited-edition badges (locked
// until earned, with the years earned) plus the collector badges, then this
// year's events as a timeline in window order: dates, state (active /
// coming soon / done / missed / later) and each quest with a checkmark.
//
// Thin: statuses come from `SeasonalEventsFeature.yearOverview` and badge
// definitions from `SeasonalEventCatalog` (Gamification, unit-tested); the
// unlocked set is the engine's `unlockedAchievements`. Display strings from
// the package are already localized, hence `Text(verbatim:)` for them.
//
// Depends on: AppEnvironment, SeasonalEventsFeature, SeasonalEventCatalog,
// BadgeMedallion, SeasonalQuestRow (Today/Slots/SeasonalBannerSlot.swift),
// seasonalDayText (Progress/Slots/SeasonalSlotView.swift).
// Depended on by: SeasonalSlotView.

import SwiftUI
import Gamification

@MainActor
struct SeasonalEventsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var overview: [SeasonalEventStatus] = []
    @State private var upcoming: [SeasonalEventStatus] = []

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }
    private var unlocked: [String: Date] { environment.gamificationEngine.unlockedAchievements }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                badgeShowcase
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "This year"))
                    ForEach(timeline) { status in
                        SeasonalEventRow(status: status)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Seasonal events")
        .task(id: featureHost?.summaries[SeasonalEventsFeature.id]) {
            await reload()
        }
    }

    /// This year's events plus next year's teasers (New Year's Day from
    /// 29 December), in window order.
    private var timeline: [SeasonalEventStatus] {
        let ids = Set(overview.map(\.id))
        return overview + upcoming.filter { !ids.contains($0.id) }
    }

    private var badgeShowcase: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Limited-edition badges"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.md) {
                ForEach(SeasonalEventCatalog.badges) { badge in
                    SeasonalBadgeCell(
                        badge: badge,
                        isUnlocked: unlocked[badge.id] != nil,
                        years: years(for: badge)
                    )
                }
            }
            .card()
        }
    }

    private func years(for badge: AchievementDefinition) -> [Int] {
        guard let eventId = badge.limitedEditionEventId else { return [] }
        return overview.first { $0.eventId == eventId }?.completedYears ?? []
    }

    private func reload() async {
        guard let feature = featureHost?.feature(SeasonalEventsFeature.self) else { return }
        overview = await feature.yearOverview()
        upcoming = await feature.upcomingEvents()
    }
}

private struct SeasonalBadgeCell: View {
    let badge: AchievementDefinition
    let isUnlocked: Bool
    let years: [Int]

    private var yearsText: String {
        years.map(String.init).joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            BadgeMedallion(symbol: badge.badgeSymbol, rarity: badge.rarity, isLocked: !isUnlocked, size: 52)
            Text(verbatim: badge.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(isUnlocked ? Color.primary : Color.secondary)
            if !years.isEmpty {
                Text(verbatim: yearsText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: badge.title))
        .accessibilityValue(isUnlocked
            ? (years.isEmpty ? Text("Unlocked") : Text("Earned \(yearsText)"))
            : Text("Locked"))
        .accessibilityHint(Text(verbatim: badge.subtitle))
    }
}

private struct SeasonalEventRow: View {
    let status: SeasonalEventStatus

    private var rangeText: String {
        status.start == status.end
            ? seasonalDayText(status.start)
            : "\(seasonalDayText(status.start)) – \(seasonalDayText(status.end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: status.symbol)
                    .font(.title3)
                    .foregroundStyle(status.phase == .active ? Theme.accent : Color.secondary)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: status.title)
                        .font(.headline)
                    Text(verbatim: rangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                phaseLabel
            }
            Text(verbatim: status.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if status.phase == .active || status.phase == .ended || status.isCompleted {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(status.quests) { quest in
                        SeasonalQuestRow(quest: quest)
                    }
                }
            }
            if !status.completedYears.isEmpty {
                Text("Earned \(status.completedYears.map(String.init).joined(separator: ", "))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var phaseLabel: some View {
        switch status.phase {
        case .active:
            if status.isCompleted {
                Label("Done", systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
            } else {
                Text("Active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        case .upcoming:
            Text("Coming soon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
        case .ended:
            if status.isCompleted {
                Label("Done", systemImage: "checkmark.seal.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.success)
            } else {
                Text("Missed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        case .later:
            Text("Later")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

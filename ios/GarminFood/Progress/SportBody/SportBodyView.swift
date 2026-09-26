// SportBodyView.swift
//
// add-sport-and-body-achievements design D6: the full Sport & Body screen
// behind the Progress slot --
//   1. recent activities (last 14 days), each with its fuel / recovery ticks
//      and the entries that counted (carbs and minutes before the start;
//      protein within the hour after; what was eaten during);
//   2. weight milestones against the effective goal (start, target, latest
//      weigh-in, progress bar, each milestone badge locked/unlocked);
//   3. the kept-fast streak and the next fasting badge;
//   4. every sport & body badge with lifetime counts.
//
// Thin: all data comes from `SportAndBodyFeature` (Gamification,
// unit-tested); display strings from the package are already localized,
// hence `Text(verbatim:)` for them. No activity data is a neutral
// "appears after sync" line, never an error (spec "Activities
// unavailable"). VoiceOver: each activity row and milestone is one element
// with a spoken summary; everything uses Dynamic Type text styles and
// `Theme` tokens (dark mode / themes).
//
// Depends on: AppEnvironment, SportAndBodyFeature, SportBodyCatalog,
// BodyRules, SportActivityKind, BadgeMedallion, SectionHeader, MilestoneChip
// (Progress/Slots/SportBodySlotView.swift).
// Depended on by: SportBodySlotView.

import SwiftUI
import FoodLogCore
import Gamification

@MainActor
struct SportBodyView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var activities: [SportActivityEvaluation] = []
    @State private var progress: SportBodyProgress?
    @State private var lifetime = SportLifetimeCounts(fuelled: 0, recovered: 0, earnedDays: 0, raceDays: 0)
    @State private var activitiesAvailable = false

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }
    private var unlocked: [String: Date] { environment.gamificationEngine.unlockedAchievements }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                activitiesSection
                weightSection
                fastingSection
                badgesSection
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Sport & Body")
        // Keyed on completed passes, not the hub summary: the summary only
        // holds this month's counts, so a new weigh-in or fast wouldn't
        // refresh the weight/fasting card while the screen is open.
        .task(id: featureHost?.completedRuns) {
            await reload()
        }
    }

    private func reload() async {
        guard let feature = featureHost?.feature(SportAndBodyFeature.self) else { return }
        activities = await feature.recentActivities()
        progress = await feature.bodyProgress()
        lifetime = await feature.lifetimeCounts()
        activitiesAvailable = await feature.activitiesAvailable()
    }

    // MARK: - Activities

    private var activitiesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Recent activities"))
            if activities.isEmpty {
                Text(activitiesAvailable
                     ? LocalizedStringKey("No counted activities in the last 14 days.")
                     : LocalizedStringKey("Activities appear here once Garmin has synced them."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                ForEach(activities) { evaluation in
                    SportActivityRow(evaluation: evaluation)
                }
            }
        }
    }

    // MARK: - Weight

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Weight goal"))
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let weight = progress?.weight {
                    WeightGoalSummary(weight: weight)
                    ForEach(BodyRules.applicableMilestoneIds(direction: weight.direction), id: \.self) { id in
                        if let badge = SportBodyCatalog.badge(id: id) {
                            BadgeLine(badge: badge, isUnlocked: unlocked[id] != nil)
                        }
                    }
                } else {
                    Text("Set a weight goal in Garmin Connect or Settings to track milestones.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .card()
        }
    }

    // MARK: - Fasting

    private var fastingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Fasting"))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "flame.fill")
                        .font(.title2)
                        .foregroundStyle((progress?.fastingStreak ?? 0) > 0 ? Theme.ember : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fasting streak")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(progress?.fastingStreak ?? 0) days")
                            .font(.title3.weight(.semibold).monospacedDigit())
                    }
                }
                .accessibilityElement(children: .combine)
                if let next = progress?.nextFastingTier {
                    Text("Next badge at \(next.threshold) days")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("All fasting badges earned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.success)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Badges

    private var badgesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Sport & body badges"))
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Fuelled \(lifetime.fuelled) · Recovered \(lifetime.recovered) · Earned days \(lifetime.earnedDays) · Race days \(lifetime.raceDays)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.md) {
                    ForEach(SportBodyCatalog.badges) { badge in
                        SportBadgeCell(badge: badge, isUnlocked: unlocked[badge.id] != nil)
                    }
                }
            }
            .card()
        }
    }
}

// MARK: - Activity row

private struct SportActivityRow: View {
    let evaluation: SportActivityEvaluation

    private var activity: ActivitySummary { evaluation.activity }
    private var kind: SportActivityKind { SportActivityKind(typeKey: activity.typeKey) }

    private var durationText: String {
        Duration.seconds(activity.durationS).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    Text(verbatim: "\(activity.start.formatted(date: .abbreviated, time: .shortened)) · \(durationText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if evaluation.activityClass == .endurance {
                StatusTick(isOn: evaluation.isFuelled, onText: "Fuelled", offText: "Not fuelled")
                ForEach(Array(evaluation.fuelEntries.enumerated()), id: \.offset) { _, entry in
                    EntryLine(text: fuelText(entry))
                }
            }
            StatusTick(isOn: evaluation.isRecovered, onText: "Recovered", offText: "Not recovered")
            if !evaluation.recoveryEntries.isEmpty {
                ForEach(Array(evaluation.recoveryEntries.enumerated()), id: \.offset) { _, entry in
                    EntryLine(text: Text("\(entryName(entry)) · \(grams(entry.protein)) g protein"))
                }
                EntryLine(text: Text("\(grams(evaluation.recoveryProteinGrams)) g protein within 60 min"))
            }
            if !evaluation.duringEntries.isEmpty {
                EntryLine(text: Text("Eaten during: \(evaluation.duringEntries.count)"))
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func fuelText(_ entry: SignalEntry) -> Text {
        let minutes = Int((activity.start.timeIntervalSince(entry.timestamp) / 60).rounded())
        if let carbs = entry.carbs {
            return Text("\(entryName(entry)) · \(Int(carbs.rounded())) g carbs, \(minutes) min before")
        }
        return Text("\(entryName(entry)) · carb-rich, \(minutes) min before")
    }

    private func entryName(_ entry: SignalEntry) -> String {
        entry.name ?? entry.foodId
    }

    private func grams(_ value: Double?) -> Int {
        Int((value ?? 0).rounded())
    }

    private var name: LocalizedStringKey {
        switch kind {
        case .run: return "Run"
        case .ride: return "Ride"
        case .hike: return "Hike"
        case .swim: return "Swim"
        case .walk: return "Walk"
        case .ski: return "Ski"
        case .row: return "Row"
        case .strength: return "Strength"
        case .other: return "Workout"
        }
    }

    private var symbol: String {
        switch kind {
        case .run: return "figure.run"
        case .ride: return "figure.outdoor.cycle"
        case .hike: return "figure.hiking"
        case .swim: return "figure.pool.swim"
        case .walk: return "figure.walk"
        case .ski: return "figure.skiing.crosscountry"
        case .row: return "figure.rower"
        case .strength: return "dumbbell.fill"
        case .other: return "figure.mixed.cardio"
        }
    }
}

private struct StatusTick: View {
    let isOn: Bool
    let onText: LocalizedStringKey
    let offText: LocalizedStringKey

    var body: some View {
        Label {
            Text(isOn ? onText : offText)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
        } icon: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Theme.success : Color.secondary)
        }
        .foregroundStyle(isOn ? Color.primary : Color.secondary)
    }
}

private struct EntryLine: View {
    let text: Text

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, Theme.Spacing.lg)
    }
}

// MARK: - Weight

private struct WeightGoalSummary: View {
    let weight: WeightMilestoneProgress

    /// The app's weight convention (`formattedKg`, as on the Weight screen).
    private func kg(_ value: Double) -> String {
        "\(value.formattedKg) kg"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let start = weight.startKg {
                Text("Start \(kg(start)) · Target \(kg(weight.targetKg))")
                    .font(.subheadline)
            } else {
                Text("Target \(kg(weight.targetKg))")
                    .font(.subheadline)
            }
            if let latest = weight.latestKg {
                Text("Latest \(kg(latest))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if weight.direction == .maintenance {
                Text("Maintenance goal: stay within 1 kg of your target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fraction = weight.fraction {
                ProgressView(value: fraction)
                    .tint(Theme.accent)
                    .accessibilityValue(Text(verbatim: fraction.formatted(.percent.precision(.fractionLength(0)))))
            }
        }
    }
}

private struct BadgeLine: View {
    let badge: AchievementDefinition
    let isUnlocked: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            BadgeMedallion(symbol: badge.badgeSymbol, rarity: badge.rarity, isLocked: !isUnlocked, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: badge.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isUnlocked ? Color.primary : Color.secondary)
                Text(verbatim: badge.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: badge.title))
        .accessibilityValue(isUnlocked ? Text("Unlocked") : Text("Locked"))
        .accessibilityHint(Text(verbatim: badge.subtitle))
    }
}

private struct SportBadgeCell: View {
    let badge: AchievementDefinition
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            BadgeMedallion(symbol: badge.badgeSymbol, rarity: badge.rarity, isLocked: !isUnlocked, size: 52)
            Text(verbatim: badge.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(isUnlocked ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: badge.title))
        .accessibilityValue(isUnlocked ? Text("Unlocked") : Text("Locked"))
        .accessibilityHint(Text(verbatim: badge.subtitle))
    }
}

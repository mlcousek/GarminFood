// AchievementsView.swift
//
// achievements spec's "visible on a dedicated screen with locked and
// unlocked state" requirement (expand-gamification-depth design.md D6),
// elevated for the "badges with images, tiers" ask: a hero completion ring
// (reusing `ProgressRing` from Components.swift), badges grouped by
// category using real layered `BadgeMedallion`s instead of a flat circle +
// glyph, and a detail sheet on tap showing the achievement's rarity and
// full description. Locked badges stay a greyed medallion + lock glyph;
// unlocked ones show their rarity's colour, rim, and (for epic/legendary)
// a shine -- see BadgeMedallion.swift for why there's no literal image
// asset.

import SwiftUI
import Gamification

@MainActor
struct AchievementsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selected: AchievementDefinition?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        let engine = environment.gamificationEngine
        let unlocked = engine.unlockedAchievements
        let catalog = engine.achievementCatalog

        List {
            Section {
                AchievementsHeroCard(unlockedCount: unlocked.count, totalCount: catalog.count)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ForEach(AchievementCategory.allCases, id: \.self) { category in
                let items = catalog.filter { $0.category == category }
                if !items.isEmpty {
                    Section(title(for: category)) {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(items) { definition in
                                Button {
                                    selected = definition
                                } label: {
                                    AchievementBadgeView(definition: definition, unlockedDate: unlocked[definition.id])
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { definition in
            AchievementDetailSheet(definition: definition, unlockedDate: unlocked[definition.id])
                .presentationDetents([.medium, .large])
        }
    }

    private func title(for category: AchievementCategory) -> String {
        switch category {
        case .streak: return "Streaks"
        case .level: return "Levels"
        case .volume: return "Logging Volume"
        case .variety: return "Variety"
        case .challenges: return "Challenges"
        case .dailyChallenges: return "Daily Challenges"
        case .goalHitting: return "Goal Hitting"
        case .extreme: return "Extreme Days"
        case .funnyFacts: return "Fun Facts"
        case .calendar: return "Calendar"
        case .meta: return "Completionist"
        }
    }
}

// MARK: - Hero

private struct AchievementsHeroCard: View {
    let unlockedCount: Int
    let totalCount: Int

    private var fraction: Double { totalCount > 0 ? Double(unlockedCount) / Double(totalCount) : 0 }
    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ProgressRing(fraction: fraction, lineWidth: 12) {
                VStack(spacing: 0) {
                    Text("\(percent)%")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                    Text("\(unlockedCount)/\(totalCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            Text("achievements unlocked")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .card()
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unlockedCount) of \(totalCount) achievements unlocked, \(percent) percent")
    }
}

// MARK: - Grid badge

private struct AchievementBadgeView: View {
    let definition: AchievementDefinition
    let unlockedDate: Date?

    private var isUnlocked: Bool { unlockedDate != nil }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            BadgeMedallion(symbol: definition.badgeSymbol, rarity: definition.rarity, isLocked: !isUnlocked, size: 60)
            Text(definition.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isUnlocked ? .primary : .secondary)
                .lineLimit(2)
            if let unlockedDate {
                Text(unlockedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(definition.rarity.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens achievement details")
    }

    private var accessibilityLabel: String {
        if let unlockedDate {
            return "\(definition.title), \(definition.rarity.displayName) achievement, unlocked \(unlockedDate.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "\(definition.title), locked, \(definition.rarity.displayName) achievement. \(definition.subtitle)"
        }
    }
}

// MARK: - Detail sheet

private struct AchievementDetailSheet: View {
    let definition: AchievementDefinition
    let unlockedDate: Date?

    @Environment(\.dismiss) private var dismiss

    private var isUnlocked: Bool { unlockedDate != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    BadgeMedallion(symbol: definition.badgeSymbol, rarity: definition.rarity, isLocked: !isUnlocked, size: 120)
                        .padding(.top, Theme.Spacing.md)

                    VStack(spacing: Theme.Spacing.xs) {
                        Text(definition.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(definition.rarity.displayName)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                    }

                    Text(definition.subtitle)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if let unlockedDate {
                        Label("Unlocked \(unlockedDate.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    } else {
                        Label("Locked -- keep going", systemImage: "lock.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Achievement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview("AchievementsHeroCard") {
    AchievementsHeroCard(unlockedCount: 58, totalCount: 122)
        .padding()
        .background(Theme.groupedBackground)
}

#Preview("AchievementBadgeView") {
    HStack {
        AchievementBadgeView(
            definition: AchievementCatalog.all[0],
            unlockedDate: Date()
        )
        AchievementBadgeView(
            definition: AchievementCatalog.all.last!,
            unlockedDate: nil
        )
    }
    .padding()
}

#Preview("AchievementDetailSheet -- unlocked") {
    AchievementDetailSheet(definition: AchievementCatalog.all[0], unlockedDate: Date())
}

#Preview("AchievementDetailSheet -- locked") {
    AchievementDetailSheet(definition: AchievementCatalog.all.last!, unlockedDate: nil)
}

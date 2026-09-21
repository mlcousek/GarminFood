// AchievementsView.swift
//
// achievements spec's "visible on a dedicated screen with locked and
// unlocked state" requirement (expand-gamification-depth design.md D6):
// every definition in `GamificationEngine.achievementCatalog`, grouped by
// category, locked shown as a greyed silhouette + lock glyph, unlocked
// shown in color with its unlock date.

import SwiftUI
import Gamification

@MainActor
struct AchievementsView: View {
    @Environment(AppEnvironment.self) private var environment

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        let engine = environment.gamificationEngine
        let unlocked = engine.unlockedAchievements
        let catalog = engine.achievementCatalog

        List {
            Section {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("\(unlocked.count) / \(catalog.count)")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text("achievements unlocked")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: catalog.isEmpty ? 0 : Double(unlocked.count) / Double(catalog.count))
                        .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(unlocked.count) of \(catalog.count) achievements unlocked")
            }

            ForEach(AchievementCategory.allCases, id: \.self) { category in
                let items = catalog.filter { $0.category == category }
                if !items.isEmpty {
                    Section(title(for: category)) {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(items) { definition in
                                AchievementBadgeView(definition: definition, unlockedDate: unlocked[definition.id])
                            }
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
            }
        }
        .navigationTitle("Achievements")
        .navigationBarTitleDisplayMode(.inline)
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

private struct AchievementBadgeView: View {
    let definition: AchievementDefinition
    let unlockedDate: Date?

    private var isUnlocked: Bool { unlockedDate != nil }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? AnyShapeStyle(Theme.flameGradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
                    .frame(width: 56, height: 56)
                Image(systemName: isUnlocked ? definition.badgeSymbol : "lock.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isUnlocked ? .white : Color.secondary)
            }
            Text(definition.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isUnlocked ? .primary : .secondary)
                .lineLimit(2)
            if let unlockedDate {
                Text(unlockedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let unlockedDate {
            return "\(definition.title), unlocked \(unlockedDate.formatted(date: .abbreviated, time: .omitted))"
        } else {
            return "\(definition.title), locked. \(definition.subtitle)"
        }
    }
}

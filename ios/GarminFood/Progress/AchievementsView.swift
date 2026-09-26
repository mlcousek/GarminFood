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
//
// add-gamification-signals D9/D12: the catalog is `BadgeRegistry` (core +
// every feature's badges, via `GamificationEngine.achievementCatalog`).
// Secret badges get their own group of "???" tiles (count shown, titles and
// symbols hidden until unlocked); limited-edition (seasonal) badges get a
// "Limited edition" group; everything else stays grouped by category.
//
// add-secret-achievements D4: `AchievementsView(focus: .secrets)` (from the
// Progress tab's SecretsSlotView) scrolls to the Secret group once on
// appear; plain `AchievementsView()` is unchanged.

import SwiftUI
import Gamification

@MainActor
struct AchievementsView: View {
    /// A group to scroll to when the screen opens.
    enum Focus {
        case secrets
    }

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: AchievementDefinition?
    @State private var didFocus = false

    private let focus: Focus?
    private static let secretGroupId = "achievements-secret-group"

    init(focus: Focus? = nil) {
        self.focus = focus
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: 3)

    var body: some View {
        let engine = environment.gamificationEngine
        let unlocked = engine.unlockedAchievements
        let catalog = engine.achievementCatalog

        ScrollViewReader { proxy in
            List {
                Section {
                    AchievementsHeroCard(unlockedCount: unlocked.count, totalCount: catalog.count)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                let secret = catalog.filter(\.isSecret)
                let limited = catalog.filter { !$0.isSecret && $0.limitedEditionEventId != nil }
                let regular = catalog.filter { !$0.isSecret && $0.limitedEditionEventId == nil }
                let limitedUnlocked = limited.filter { unlocked[$0.id] != nil }.count
                let secretUnlocked = secret.filter { unlocked[$0.id] != nil }.count

                ForEach(AchievementCategory.allCases, id: \.self) { category in
                    let items = regular.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(title(for: category)) {
                            badgeGrid(items, unlocked: unlocked)
                        }
                    }
                }

                if !limited.isEmpty {
                    Section {
                        badgeGrid(limited, unlocked: unlocked)
                    } header: {
                        Text("Limited edition \(limitedUnlocked)/\(limited.count)")
                    }
                }

                if !secret.isEmpty {
                    Section {
                        badgeGrid(secret, unlocked: unlocked)
                    } header: {
                        // The scroll target is the header, so "Secret x/15"
                        // lands at the top instead of just above it.
                        Text("Secret \(secretUnlocked)/\(secret.count)")
                            .id(Self.secretGroupId)
                    }
                }
            }
            .task {
                guard focus == .secrets, !didFocus else { return }
                didFocus = true
                // Give the List a moment to lay out its rows before scrolling.
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation(reduceMotion ? nil : .easeInOut) {
                    proxy.scrollTo(Self.secretGroupId, anchor: .top)
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

    @ViewBuilder
    private func badgeGrid(_ items: [AchievementDefinition], unlocked: [String: Date]) -> some View {
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

    private func title(for category: AchievementCategory) -> String {
        switch category {
        case .streak: return String(localized: "Streaks", comment: "Achievements group header.")
        case .level: return String(localized: "Levels", comment: "Achievements group header.")
        case .volume: return String(localized: "Logging Volume", comment: "Achievements group header: badges for the number of entries logged.")
        case .variety: return String(localized: "Variety", comment: "Achievements group header: badges for different foods.")
        case .challenges: return String(localized: "Challenges")
        case .dailyChallenges: return String(localized: "Daily Challenges", comment: "Achievements group header.")
        case .goalHitting: return String(localized: "Goal Hitting", comment: "Achievements group header: badges for days a nutrition goal was met.")
        case .extreme: return String(localized: "Extreme Days", comment: "Achievements group header: badges for very high-calorie days.")
        case .funnyFacts: return String(localized: "Fun Facts", comment: "Achievements group header: playful lifetime-calorie comparisons.")
        case .calendar: return String(localized: "Calendar", comment: "Achievements group header: date-based badges.")
        case .meta: return String(localized: "Completionist", comment: "Achievements group header: badges for unlocking other badges.")
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
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.6)
                    Text(verbatim: "\(unlockedCount)/\(totalCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            Text("achievements unlocked", comment: "Under the achievements completion ring (percent and count above it).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .card()
        .padding(.horizontal, Theme.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(unlockedCount) of \(totalCount) achievements unlocked, \(percent) percent", comment: "VoiceOver: the achievements completion ring."))
    }
}

// MARK: - Grid badge

private struct AchievementBadgeView: View {
    let definition: AchievementDefinition
    let unlockedDate: Date?

    private var isUnlocked: Bool { unlockedDate != nil }
    /// A locked secret badge: "???", no symbol, no rarity (D9).
    private var isHiddenSecret: Bool { definition.isSecret && !isUnlocked }

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            BadgeMedallion(symbol: isHiddenSecret ? "questionmark" : definition.badgeSymbol, rarity: definition.rarity, isLocked: !isUnlocked, size: 60)
            Text(isHiddenSecret ? "???" : definition.title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(isUnlocked ? .primary : .secondary)
                .lineLimit(2)
            if let unlockedDate {
                Text(unlockedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text(isHiddenSecret ? "???" : definition.rarity.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text("Opens achievement details"))
    }

    private var accessibilityLabel: String {
        if isHiddenSecret {
            return String(localized: "Secret achievement, locked", comment: "Accessibility label of a locked secret achievement tile (title hidden).")
        }
        if let unlockedDate {
            let date = unlockedDate.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "\(definition.title), \(definition.rarity.displayName) achievement, unlocked \(date)", comment: "VoiceOver: an unlocked badge tile. Title, rarity (adjective; Czech agrees with \"odznak\"), unlock date.")
        } else {
            return String(localized: "\(definition.title), locked, \(definition.rarity.displayName) achievement. \(definition.subtitle)", comment: "VoiceOver: a locked badge tile. Title, rarity (adjective; Czech agrees with \"odznak\"), how to earn it.")
        }
    }
}

// MARK: - Detail sheet

private struct AchievementDetailSheet: View {
    let definition: AchievementDefinition
    let unlockedDate: Date?

    @Environment(\.dismiss) private var dismiss

    private var isUnlocked: Bool { unlockedDate != nil }
    private var isHiddenSecret: Bool { definition.isSecret && !isUnlocked }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    BadgeMedallion(symbol: isHiddenSecret ? "questionmark" : definition.badgeSymbol, rarity: definition.rarity, isLocked: !isUnlocked, size: 120)
                        .padding(.top, Theme.Spacing.md)

                    VStack(spacing: Theme.Spacing.xs) {
                        Text(isHiddenSecret ? "???" : definition.title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(isHiddenSecret ? "???" : definition.rarity.displayName)
                            .font(.caption.weight(.semibold))
                            .textCase(.uppercase)
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                    }

                    Text(isHiddenSecret
                         ? String(localized: "A secret achievement. Keep logging to reveal it.", comment: "Detail sheet text of a locked secret achievement.")
                         : definition.subtitle)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    if let unlockedDate {
                        Label(String(localized: "Unlocked \(unlockedDate.formatted(date: .abbreviated, time: .omitted))", comment: "Badge detail: the unlock date."), systemImage: "checkmark.circle.fill")
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

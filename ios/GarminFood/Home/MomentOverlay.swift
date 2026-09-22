// MomentOverlay.swift
//
// Presents `GamificationEngine.pendingMoments` -- the level-up / streak
// milestone / challenge-completion "moments" that design.md D5 and the
// levels/challenges specs require to be a real animated event with haptic
// feedback, not a silently-updated number. Before this file existed the
// engine enqueued moments and nothing ever showed them.
//
// One moment at a time, from the front of the queue; `dismissCurrentMoment()`
// advances it. With Reduce Motion on, the same card appears with a plain
// opacity change and no scale/bounce (levels spec: "an equivalent
// non-animated confirmation SHALL still be shown"), and the haptic still
// fires -- haptics are not motion.
//
// The card's icon is a `BadgeMedallion` (not a plain glyph) for every
// moment kind, so a level-up genuinely shows its tier's rarity/art
// prominently (owner ask: "improve the gamification... tiers") rather than
// just a bare number -- `LevelTiers.tier(forLevel:)` already carries a
// title/flavor/rarity/symbol per tier (LevelTier.swift), this just finally
// puts all four on screen together.

import SwiftUI
import Gamification

struct MomentOverlay: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var shown: GamificationMoment?

    var body: some View {
        ZStack {
            if let moment = shown {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .accessibilityHidden(true)

                MomentCard(moment: moment, animated: animated, onDone: dismiss)
                    .transition(animated
                        ? .scale(scale: 0.86).combined(with: .opacity)
                        : .opacity)
            }
        }
        .animation(animated ? .spring(response: 0.45, dampingFraction: 0.78) : .easeInOut(duration: 0.15), value: shown)
        // Only when a moment APPEARS: the trigger also changes to nil on
        // dismiss, which used to buzz a second time.
        .sensoryFeedback(.success, trigger: shown) { _, new in
            new != nil && Haptics.isEnabled
        }
        .onChange(of: environment.gamificationEngine.pendingMoments.first) { _, next in
            if shown == nil { shown = next }
        }
        .onAppear { shown = environment.gamificationEngine.pendingMoments.first }
    }

    /// Movement only when both the system (Reduce Motion) and the user's
    /// celebrations preference allow it. The card itself always appears
    /// (levels spec: an equivalent non-animated confirmation).
    private var animated: Bool {
        !reduceMotion && environment.preferences.celebrationsEnabled
    }

    private func dismiss() {
        shown = nil
        environment.gamificationEngine.dismissCurrentMoment()
        // Chain straight into the next one, if a single log produced two.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            shown = environment.gamificationEngine.pendingMoments.first
        }
    }
}

private struct MomentCard: View {
    let moment: GamificationMoment
    let animated: Bool
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var medallionSize: CGFloat = 84

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            BadgeMedallion(symbol: medallionSymbol, rarity: medallionRarity, isLocked: false, size: medallionSize)
                .symbolEffect(.bounce, options: .nonRepeating, value: animated ? moment : nil)

            VStack(spacing: 2) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                if let tierTitle {
                    Text(tierTitle)
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .kerning(0.6)
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Keep going", action: onDone)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.xl, style: .continuous))
        .padding(Theme.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }

    /// The badge glyph for whatever this moment is -- a level-up shows its
    /// tier's own escalating symbol (`LevelTier.badgeSymbol`), everything
    /// else keeps the glyph it always had.
    private var medallionSymbol: String {
        switch moment {
        case .levelUp(let level): return LevelTiers.tier(forLevel: level).badgeSymbol
        case .streakMilestone: return "flame.fill"
        case .challengeCompleted: return "target"
        case .dailyChallengeCompleted: return "checkmark.circle.fill"
        case .achievementUnlocked(_, let badgeSymbol, _): return badgeSymbol
        }
    }

    /// Which `BadgeMedallion` colour ramp this moment's badge renders in.
    /// Level-up and achievement unlocks carry a real rarity already;
    /// streak milestones derive one from the same thresholds
    /// `AchievementRarity` uses for streak achievements, so a 500-day
    /// streak moment visibly outshines a 7-day one. Challenge completions
    /// have no natural difficulty tier of their own (every template is
    /// equally "one challenge"), so they stay at a modest, consistent grade
    /// rather than inventing one.
    private var medallionRarity: AchievementRarity {
        switch moment {
        case .levelUp(let level): return LevelTiers.tier(forLevel: level).rarity
        case .streakMilestone(let days): return AchievementRarity.derive(from: .streakAtLeast(days: days))
        case .challengeCompleted, .dailyChallengeCompleted: return .uncommon
        case .achievementUnlocked(_, _, let rarity): return rarity
        }
    }

    private var title: String {
        switch moment {
        case .levelUp(let level): return "Level \(level)"
        case .streakMilestone(let days): return "\(days)-day streak"
        case .challengeCompleted(let name, _): return name
        case .dailyChallengeCompleted(let name, _): return name
        case .achievementUnlocked(let name, _, _): return name
        }
    }

    /// A prominent second line under the title for a level-up only -- the
    /// tier name (owner ask: "show the tier name... prominently, not just
    /// a number"). Nil for every other moment kind, which has no tier
    /// concept of its own.
    private var tierTitle: String? {
        guard case .levelUp(let level) = moment else { return nil }
        return LevelTiers.tier(forLevel: level).title
    }

    private var detail: String {
        switch moment {
        case .levelUp(let level): return LevelTiers.tier(forLevel: level).flavor
        case .streakMilestone(let days): return "\(days) days in a row. That's a habit now."
        case .challengeCompleted(_, let xp): return "Challenge done. +\(xp) XP."
        case .dailyChallengeCompleted(_, let xp): return "Today's challenge done. +\(xp) XP."
        case .achievementUnlocked: return "New achievement unlocked."
        }
    }
}

#Preview("MomentCard -- level up") {
    MomentCard(moment: .levelUp(newLevel: 91), animated: true, onDone: {})
}

#Preview("MomentCard -- achievement") {
    MomentCard(moment: .achievementUnlocked(title: "Century Club", badgeSymbol: "fork.knife", rarity: .epic), animated: true, onDone: {})
}

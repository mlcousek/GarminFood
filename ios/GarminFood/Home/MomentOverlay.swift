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

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 44

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(Theme.flameGradient)
                .symbolEffect(.bounce, options: .nonRepeating, value: animated ? moment : nil)

            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

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

    private var symbol: String {
        switch moment {
        case .levelUp: return "arrow.up.circle.fill"
        case .streakMilestone: return "flame.fill"
        case .challengeCompleted: return "checkmark.seal.fill"
        }
    }

    private var title: String {
        switch moment {
        case .levelUp(let level): return "Level \(level)"
        case .streakMilestone(let days): return "\(days)-day streak"
        case .challengeCompleted(let name, _): return name
        }
    }

    private var detail: String {
        switch moment {
        case .levelUp(let level): return "\(LevelTiers.tier(forLevel: level).title) -- consistency is paying off."
        case .streakMilestone(let days): return "\(days) days in a row. That's a habit now."
        case .challengeCompleted(_, let xp): return "Challenge done. +\(xp) XP."
        }
    }
}

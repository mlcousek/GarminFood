// SecretsSlotView.swift
//
// add-secret-achievements design D4: the Progress-tab card for the secret
// achievements -- a keyhole, "Secrets 3/15" and one pip per secret --
// linking to the Achievements screen scrolled to its Secret group
// (`AchievementsView(focus: .secrets)`, which renders the "???" tiles).
// Replaces the add-gamification-signals stub; the host
// (`ProgressSlotHost`) is untouched.
//
// Thin, and deliberately title-free: the card only ever shows COUNTS, so a
// locked secret's real title can never be rendered or read by VoiceOver
// from here (design D1). The count is `SecretAchievementsFeature
// .foundCount` (Gamification, unit-tested) over the engine's unlock state,
// so it needs no async reload -- it updates whenever `unlockedAchievements`
// does. The keyhole is drawn (no SF Symbol is a keyhole) in theme tokens.
//
// Depends on: AppEnvironment, FeatureHost, SecretAchievementsFeature,
// AchievementsView. Depended on by: ProgressSlotHost.

import SwiftUI
import Gamification

@MainActor
struct SecretsSlotView: View {
    @Environment(AppEnvironment.self) private var environment

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    private var foundCount: Int {
        SecretAchievementsFeature.foundCount(
            unlockedBadgeIds: Set(environment.gamificationEngine.unlockedAchievements.keys)
        )
    }

    private var totalCount: Int { SecretAchievementsFeature.secretCount }

    var body: some View {
        Group {
            if featureHost?.feature(SecretAchievementsFeature.self) != nil {
                NavigationLink {
                    AchievementsView(focus: .secrets)
                } label: {
                    card(found: foundCount, total: totalCount)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func card(found: Int, total: Int) -> some View {
        let allFound = total > 0 && found >= total
        let tint = allFound ? Theme.success : Theme.accent

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "key.fill")
                    .foregroundStyle(Theme.accent)
                Text("Secrets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Text(verbatim: "\(found)/\(total)")
                    .font(.headline.monospacedDigit())
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: Theme.Spacing.md) {
                KeyholeBadge(tint: tint)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("\(found) of \(total) secrets found")
                        .font(.subheadline.weight(.semibold))
                    (allFound ? Text("Every secret found!") : Text("Some habits reveal hidden badges."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index < found ? tint : Theme.stroke)
                        .frame(maxWidth: .infinity)
                        .frame(height: 6)
                }
            }
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(found) of \(total) secrets found"))
        .accessibilityHint(Text("Opens the secret achievements"))
        .accessibilityAddTraits(.isButton)
    }
}

/// A keyhole in a tinted disc: the card's "something is hidden here" mark.
private struct KeyholeBadge: View {
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                VStack(spacing: -side * 0.04) {
                    Circle()
                        .fill(tint)
                        .frame(width: side * 0.26, height: side * 0.26)
                    KeyholeStem()
                        .fill(tint)
                        .frame(width: side * 0.22, height: side * 0.26)
                }
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

/// The keyhole's tapered slot: narrow at the top, wider at the bottom.
private struct KeyholeStem: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

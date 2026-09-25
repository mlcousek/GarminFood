// BingoSlotView.swift
//
// add-weekly-bingo design D8: the Progress-tab card for this week's bingo
// -- a 3x3 mini grid (filled dot = done, star = the free centre), the
// number of completed lines, squares done out of 9 and days left in the
// week -- linking to `BingoCardView`. Replaces the add-gamification-signals
// stub; the host (`ProgressSlotHost`) is untouched.
//
// Thin: the card comes from `WeeklyBingoFeature.currentCard()`
// (Gamification, unit-tested) and is reloaded whenever the feature host
// publishes a new bingo summary. Before the feature's first run this week
// the card shows a short "appears after your next log" line instead.
//
// Depends on: AppEnvironment, FeatureHost, WeeklyBingoFeature, BingoCardView,
// BingoStats, Theme.
// Depended on by: ProgressSlotHost.

import SwiftUI
import FoodLogCore
import Gamification

@MainActor
struct BingoSlotView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var card: BingoCardStatus?

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        // A VStack, not a Group: `.task` on a Group whose only child is a
        // false `if` never runs (see SeasonalBannerSlot).
        VStack(spacing: 0) {
            if featureHost?.feature(WeeklyBingoFeature.self) != nil {
                NavigationLink {
                    BingoCardView()
                } label: {
                    content
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: featureHost?.summaries[WeeklyBingoFeature.id]) {
            await reload()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: WeeklyBingoFeature.symbol)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("Weekly Bingo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }

            if let card {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    BingoMiniGrid(card: card)
                        .accessibilityHidden(true)
                    BingoStats(
                        card: card,
                        daysLeft: WeeklyBingoFeature.daysLeft(week: card.week, today: NutritionDate.todayString(), calendar: .current)
                    )
                    Spacer(minLength: 0)
                }
            } else {
                Text("Your bingo card appears after your next log.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the bingo card"))
    }

    private func reload() async {
        guard let feature = featureHost?.feature(WeeklyBingoFeature.self) else { return }
        card = await feature.currentCard()
    }
}

/// The hub card's 3x3 dot grid.
private struct BingoMiniGrid: View {
    let card: BingoCardStatus
    @ScaledMetric(relativeTo: .caption) private var dot: CGFloat = 14

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        dotView(row * 3 + column)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dotView(_ index: Int) -> some View {
        let square: BingoSquareStatus? = index < card.squares.count ? card.squares[index] : nil
        if let square, square.isFree {
            Image(systemName: "star.fill")
                .font(.system(size: dot * 0.8))
                .foregroundStyle(Theme.accent)
                .frame(width: dot, height: dot)
        } else if let square, square.isDone {
            Circle()
                .fill(Theme.accent)
                .frame(width: dot, height: dot)
        } else {
            Circle()
                .strokeBorder(Theme.stroke, lineWidth: 1.5)
                .frame(width: dot, height: dot)
        }
    }
}

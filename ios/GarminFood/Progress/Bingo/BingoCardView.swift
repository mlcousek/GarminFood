// BingoCardView.swift
//
// add-weekly-bingo design D8: the full weekly-bingo screen -- this week's
// card as a large grid (completed lines stroked across it), lines / squares
// / days left, what a line and a full card pay, a sheet per square with its
// rule, difficulty, the data it is judged from and the day it was done, and
// a horizontally paged list of the previous weeks' cards (up to 11 more,
// the store keeps 12 weeks).
//
// Thin: cards come from `WeeklyBingoFeature.currentCard()`/`pastCards()`
// (Gamification, unit-tested) and are reloaded whenever the feature host
// publishes a new bingo summary; this screen never evaluates anything.
//
// Depends on: AppEnvironment, FeatureHost, WeeklyBingoFeature, BingoGrid,
// BingoFormat, SectionHeader, Theme.
// Depended on by: BingoSlotView.

import SwiftUI
import FoodLogCore
import Gamification

/// A tapped square, identified across cards (index alone repeats per week).
struct BingoSquareSelection: Identifiable {
    let week: WeekKey
    let square: BingoSquareStatus

    var id: String { "\(week.rawValue)-\(square.index)" }
}

@MainActor
struct BingoCardView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var current: BingoCardStatus?
    @State private var past: [BingoCardStatus] = []
    @State private var selection: BingoSquareSelection?

    private var featureHost: FeatureHost? { environment.gamificationEngine.featureHost }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if let current {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text(verbatim: BingoFormat.weekRange(current.week))
                            .font(.sectionHeader)
                            .foregroundStyle(.secondary)
                        BingoGrid(card: current, size: .large, animateLines: true) { square in
                            selection = BingoSquareSelection(week: current.week, square: square)
                        }
                        BingoStats(card: current, daysLeft: daysLeft(current))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                } else {
                    Text("Your bingo card appears after your next log.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                }

                Text("Squares tick themselves from what you log. Each line earns \(XPAward.bingoLine) XP; a full card earns \(XPAward.bingoFullCard) XP and a streak freeze.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !past.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(title: String(localized: "Past cards"))
                        pastCardsPager
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle(Text("Weekly Bingo"))
        .sheet(item: $selection) { selection in
            BingoSquareSheet(selection: selection)
        }
        .task(id: featureHost?.summaries[WeeklyBingoFeature.id]) {
            await reload()
        }
    }

    private var pastCardsPager: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: Theme.Spacing.md) {
                ForEach(past) { card in
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(verbatim: BingoFormat.weekRange(card.week))
                            .font(.sectionHeader)
                            .foregroundStyle(.secondary)
                        BingoGrid(card: card, size: .compact) { square in
                            selection = BingoSquareSelection(week: card.week, square: square)
                        }
                        BingoStats(card: card, daysLeft: nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
    }

    private func daysLeft(_ card: BingoCardStatus) -> Int {
        WeeklyBingoFeature.daysLeft(week: card.week, today: NutritionDate.todayString(), calendar: .current)
    }

    private func reload() async {
        guard let feature = featureHost?.feature(WeeklyBingoFeature.self) else { return }
        current = await feature.currentCard()
        past = await feature.pastCards()
    }
}

/// "Lines: 2 · Squares: 5/9 · Days left: 3" as separate, wrapping items.
struct BingoStats: View {
    let card: BingoCardStatus
    /// `nil` for a finished (past) card.
    let daysLeft: Int?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.md) { items }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { items }
        }
        .font(.subheadline.monospacedDigit())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var items: some View {
        Text("Lines: \(card.lines.count)")
        Text("Squares: \(card.doneCount)/9")
        if let daysLeft {
            Text("Days left: \(daysLeft)")
        } else if card.isFull {
            Text("Full card")
                .foregroundStyle(Theme.accent)
        }
    }
}

/// One square's rule, difficulty, data source and completion day.
private struct BingoSquareSheet: View {
    let selection: BingoSquareSelection
    @Environment(\.dismiss) private var dismiss

    private var square: BingoSquareStatus { selection.square }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if let task = square.task {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: task.symbol)
                                .font(.title2)
                                .foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            Text(verbatim: task.title)
                                .font(.title3.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)

                        Text(verbatim: task.detail)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)

                        if let day = square.completedDay {
                            Label {
                                Text("Done on \(BingoFormat.longDay(day))")
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.success)
                            }
                        } else {
                            Label {
                                Text("Not done yet")
                            } icon: {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Label {
                            Text(verbatim: BingoFormat.difficulty(task.difficulty))
                        } icon: {
                            Image(systemName: "dial.medium")
                                .foregroundStyle(.secondary)
                        }

                        ForEach(BingoFormat.dataSources(task.requirement), id: \.self) { line in
                            Text(verbatim: line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
            }
            .background(Theme.groupedBackground)
            .navigationTitle(Text(verbatim: BingoFormat.weekRange(selection.week)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

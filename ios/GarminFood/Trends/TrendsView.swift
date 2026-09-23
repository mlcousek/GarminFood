// TrendsView.swift
//
// The Trends screen (add-trends-and-insights): a ~30-day macro trend
// (calories/protein/carbs/fat, actual vs. goal, from ONE new Garmin read --
// `GarminClient.calorieSummaryDaily`, see `MacroTrendLoader`) plus a purely
// local hydration streak + daily-total trend (`FoodLogCore.HydrationHistory
// .streak`, no network at all). Reached from the Progress tab (see
// `TrendsSummaryCard` in ProgressViews.swift), same "card summarizes, tap
// opens the detail screen" shape every other Progress entry point uses.
//
// Reads `environment.trendsLoader` (fetched on `.task`/pull-to-refresh,
// never on app foreground -- see that loader's own header for why) and
// `environment.hydrationLoader.entries` (already refreshed elsewhere;
// hydration's own trend math is pure and local, so nothing extra is
// fetched for it here).
//
// add-day-notes: tagged days from `environment.dayNoteStore` (local, no
// network) are drawn as emoji markers on every daily chart; tapping one
// opens `DayNoteRevealSheet` (see DayNoteChartMarkers.swift).

import SwiftUI
import FoodLogCore

@MainActor
struct TrendsView: View {
    @Environment(AppEnvironment.self) private var environment

    /// The effective water goal (Garmin's unless overridden in Settings,
    /// sync-weight-hydration-with-garmin D5). The streak/trend below still
    /// sums only drinks logged in this app: Garmin's per-day totals are
    /// fetched for today only, not for past days.
    private var hydrationGoalML: Double { environment.hydrationLoader.goalML }

    /// Matches `HydrationTrendChartView`'s reasonable phone-width range
    /// (task brief: "last ~14-30 days"); 21 keeps the bar chart legible on
    /// a phone screen without crowding, roughly 3 weeks of habit data.
    private let hydrationDaysBack = 21

    @State private var noteMarkers: [DayNoteChartMarker] = []
    @State private var revealedNote: DayNote?

    var body: some View {
        let macroLoader = environment.trendsLoader
        let hydrationEntries = environment.hydrationLoader.entries

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                macroSection(loader: macroLoader)
                hydrationSection(entries: hydrationEntries)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await macroLoader.refresh() }
        .task { await loadDayNotes() }
        .refreshable {
            await macroLoader.refresh()
            await environment.hydrationLoader.refresh()
            await loadDayNotes()
        }
        .sheet(item: $revealedNote) { note in
            DayNoteRevealSheet(note: note)
        }
    }

    // MARK: - Macros

    @ViewBuilder
    private func macroSection(loader: MacroTrendLoader) -> some View {
        let hasAnyMacroData = loader.days.contains {
            $0.calories != nil || $0.proteinG != nil || $0.carbsG != nil || $0.fatG != nil
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Macros, last 30 days")

            if loader.isLoading && loader.days.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.lg)
            } else if loader.loadFailed && loader.days.isEmpty {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Couldn't load trends",
                    message: "Pull to refresh to try again."
                )
                .card()
            } else if !hasAnyMacroData {
                EmptyStateView(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No data yet",
                    message: "Log a few days of food to see your macro trends here."
                )
                .card()
            } else {
                VStack(spacing: Theme.Spacing.md) {
                    MacroLineChartView(title: "Calories", unit: "kcal", tint: Theme.accent, days: loader.days, actual: { $0.calories }, goal: { $0.calorieGoal }, noteMarkers: noteMarkers, onSelectNote: { revealedNote = $0 })
                    MacroLineChartView(title: "Protein", unit: "g", tint: Theme.protein, days: loader.days, actual: { $0.proteinG }, goal: { $0.proteinGoalG }, noteMarkers: noteMarkers, onSelectNote: { revealedNote = $0 })
                    MacroLineChartView(title: "Carbs", unit: "g", tint: Theme.carbs, days: loader.days, actual: { $0.carbsG }, goal: { $0.carbsGoalG }, noteMarkers: noteMarkers, onSelectNote: { revealedNote = $0 })
                    MacroLineChartView(title: "Fat", unit: "g", tint: Theme.fat, days: loader.days, actual: { $0.fatG }, goal: { $0.fatGoalG }, noteMarkers: noteMarkers, onSelectNote: { revealedNote = $0 })
                }
                .card()
            }
        }
    }

    // MARK: - Hydration

    @ViewBuilder
    private func hydrationSection(entries: [HydrationEntry]) -> some View {
        let points = hydrationTrendPoints(entries: entries)
        let streak = HydrationHistory.streak(for: entries, goalML: hydrationGoalML)

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Water, last \(hydrationDaysBack) days")
            HStack(spacing: Theme.Spacing.sm) {
                StatTile(value: "\(streak)", label: "Day streak", systemImage: "flame.fill", tint: Theme.carbs)
                StatTile(value: hydrationGoalML.formattedML, label: "ml goal", systemImage: "target", tint: Theme.carbs)
            }
            HydrationTrendChartView(points: points, goalML: hydrationGoalML, noteMarkers: noteMarkers, onSelectNote: { revealedNote = $0 })
                .card()
        }
    }

    /// Local only (`DayNoteStore`), so it's cheap to re-read every time the
    /// screen appears -- a note written on Today since the last visit shows
    /// up straight away.
    private func loadDayNotes() async {
        let notes = await environment.dayNoteStore.all()
        noteMarkers = DayNoteChartMarker.markers(from: notes)
    }

    /// `hydrationDaysBack` local-midnight days ending today, oldest first --
    /// pure local computation over `environment.hydrationLoader.entries`,
    /// no network call. Deliberately plain `Calendar.current`/local midnight
    /// rather than `NutritionDayBoundary`: hydration has no Garmin nutrition
    /// day concept of its own (`HydrationHistory.total` already buckets by
    /// plain calendar day, matching how a person thinks about "today's
    /// water" -- see that function's own doc comment), so this stays
    /// consistent with it rather than introducing a second day boundary.
    private func hydrationTrendPoints(entries: [HydrationEntry], calendar: Calendar = .current) -> [HydrationTrendPoint] {
        let today = calendar.startOfDay(for: Date())
        return (0..<hydrationDaysBack).reversed().compactMap { offset -> HydrationTrendPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return HydrationTrendPoint(date: day, totalML: HydrationHistory.total(for: entries, on: day, calendar: calendar))
        }
    }
}

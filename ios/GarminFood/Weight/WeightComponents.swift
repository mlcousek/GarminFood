// WeightComponents.swift
//
// Small, composable views for the weight feature (config.yaml's "small,
// composable views" principle) -- the hero (current weight + trend, shared
// between WeightView and ProgressViews.swift's summary card), a Swift
// Charts line/point chart, and one history row. Visual language matches the
// rest of the app: Theme tokens, `.card()`, the same macro/streak type
// scale -- nothing new invented here, per config.yaml's "small, consistent
// design system... reused everywhere" principle.

import SwiftUI
import Charts
import FoodLogCore
import GarminKit

// MARK: - Hero

/// The big "current weight" number plus a trend badge vs the previous
/// entry. Used both at the top of `WeightView` and (in a more compact form)
/// as `WeightSummaryCard`'s content on the Progress tab.
struct WeightHeroCard: View {
    let latest: WeightEntry?
    let previous: WeightEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Current weight")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(latest.weightKg.formattedKg)
                        .font(.heroNumber)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("kg")
                        .font(.heroUnit)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Text("Logged \(latest.loggedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let delta = WeightHistory.delta(latest: latest, previous: previous) {
                        WeightDeltaBadge(delta: delta)
                    }
                }
            } else {
                Text("No weigh-ins yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Log your weight to start tracking it here and syncing it to Garmin.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "+1.5 kg" / "-0.8 kg" since the previous entry. Deliberately neutral
/// (`.secondary`, no success/warning colour): unlike a calorie goal, this
/// app has no weight GOAL to judge a direction against, so up vs down is
/// information, not a pass/fail the way `TodaySummary.GoalState` is.
struct WeightDeltaBadge: View {
    let delta: Double

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(accessibilityText)
    }

    /// Within 50g either way reads as "no real change" rather than forcing
    /// an arrow on essentially-zero noise.
    private var symbol: String {
        if delta > 0.05 { return "arrow.up.right" }
        if delta < -0.05 { return "arrow.down.right" }
        return "arrow.right"
    }

    private var text: String { String(format: "%.1f kg", abs(delta)) }

    private var accessibilityText: String {
        if delta > 0.05 { return "up \(text) since last time" }
        if delta < -0.05 { return "down \(text) since last time" }
        return "unchanged since last time"
    }
}

// MARK: - Chart

/// A simple line + point chart of recent weigh-ins. `entries` MUST be
/// oldest-first (the reverse of `WeightStore.all()`'s own newest-first
/// order) so Swift Charts draws left-to-right chronologically.
struct WeightChartView: View {
    let entries: [WeightEntry]

    var body: some View {
        Chart(entries, id: \.id) { entry in
            LineMark(
                x: .value("Date", entry.loggedAt),
                y: .value("Weight", entry.weightKg)
            )
            .foregroundStyle(Theme.accent)
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Date", entry.loggedAt),
                y: .value("Weight", entry.weightKg)
            )
            .foregroundStyle(Theme.accent)
            .symbolSize(24)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weight trend")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        guard let first = entries.first, let last = entries.last else { return "No data" }
        return "From \(first.weightKg.formattedKg) to \(last.weightKg.formattedKg) kilograms over \(entries.count) entries"
    }
}

// MARK: - History row

/// One row in the History list -- name/date/note plus a sync-state glyph,
/// with swipe-to-delete (and swipe-to-retry when delivery failed), mirroring
/// `SyncQueueView`'s `QueueEntryRow` shape.
struct WeightRow: View {
    let entry: WeightEntry
    let syncState: OutboxEntryState?
    let onDelete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(entry.weightKg.formattedKg)
                        .font(.foodTitle)
                    Text("kg")
                        .font(.foodSubtitle)
                        .foregroundStyle(.secondary)
                }
                Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.foodSubtitle)
                    .foregroundStyle(.secondary)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            statusIcon
        }
        .padding(.vertical, Theme.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            if syncState == .failed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch syncState {
        case .pending:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        case .sent, .none:
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        var label = "\(entry.weightKg.formattedKg) kilograms, \(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))"
        if let note = entry.note, !note.isEmpty { label += ", \(note)" }
        switch syncState {
        case .pending: label += ", waiting to sync"
        case .failed: label += ", sync failed"
        case .sent, .none: break
        }
        return label
    }
}

// MARK: - Formatting

extension Double {
    /// "75.5" / "80" -- rounded to one decimal place, with no trailing
    /// ".0" for a whole number, mirroring `MealPresetEditorView`'s own
    /// `formattedQuantity` convention for a user-facing numeric value.
    var formattedKg: String {
        let rounded = (self * 10).rounded() / 10
        return rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}

#Preview("WeightHeroCard") {
    WeightHeroCard(
        latest: WeightEntry(weightKg: 75.5, loggedAt: Date()),
        previous: WeightEntry(weightKg: 76.8, loggedAt: Date().addingTimeInterval(-86_400))
    )
    .card()
    .padding()
}

#Preview("WeightRow") {
    List {
        WeightRow(entry: WeightEntry(weightKg: 75.5, loggedAt: Date(), note: "Morning"), syncState: .sent, onDelete: {}, onRetry: {})
        WeightRow(entry: WeightEntry(weightKg: 76, loggedAt: Date()), syncState: .pending, onDelete: {}, onRetry: {})
        WeightRow(entry: WeightEntry(weightKg: 77.2, loggedAt: Date()), syncState: .failed, onDelete: {}, onRetry: {})
    }
}

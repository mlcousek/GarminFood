// WeightComponents.swift
//
// Small, composable views for the weight feature (config.yaml's "small,
// composable views" principle) -- the hero (current weight + trend, shared
// between WeightView, the Today card and ProgressViews.swift's summary
// card), the goal bar, a Swift Charts line/point chart, and one history
// row. Visual language matches the rest of the app: Theme tokens,
// `.card()`, the same macro/streak type scale -- nothing new invented here,
// per config.yaml's "small, consistent design system... reused everywhere"
// principle.
//
// sync-weight-hydration-with-garmin: every view here now takes FoodLogCore's
// `WeighInDisplayEntry` (a row of the merged Garmin + local history,
// `WeightHistoryMerge`) instead of the app's own `WeightEntry`, since a
// weigh-in from a scale or Garmin Connect has no `WeightEntry` at all. The
// goal bar (`WeightGoalBar`) renders FoodLogCore's `WeightGoalProgress`
// (design.md D5) -- no goal maths here.

import SwiftUI
import Charts
import FoodLogCore
import GarminKit

// MARK: - Hero

/// The big "current weight" number plus a trend badge vs the previous
/// entry, and -- when a goal exists -- the goal bar beneath. Used at the
/// top of `WeightView` and inside `TodayWeightCard`.
struct WeightHeroCard: View {
    let latest: WeighInDisplayEntry?
    let previous: WeighInDisplayEntry?
    var progress: WeightGoalProgress? = nil
    /// Shows the quiet "couldn't refresh" caption (design.md "Fallback
    /// when routes break").
    var refreshFailed: Bool = false

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
                        .heroNumberFont()
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
                if let progress {
                    WeightGoalBar(progress: progress)
                        .padding(.top, Theme.Spacing.xs)
                }
            } else {
                Text("No weigh-ins yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Log your weight here or on a Garmin scale -- it shows up in both places.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if refreshFailed {
                GarminRefreshFailedCaption()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "Couldn't refresh from Garmin" -- the quiet failure caption shared by the
/// weight and water cards. Auth failures never land here (they have the
/// loud banner); this is for a network or server hiccup, while the card
/// keeps showing the last good values.
struct GarminRefreshFailedCaption: View {
    var body: some View {
        Label("Couldn't refresh from Garmin. Showing the last values.", systemImage: "icloud.slash")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// "+1.5 kg" / "-0.8 kg" since the previous entry. Deliberately neutral
/// (`.secondary`, no success/warning colour): up vs down is information
/// here; how it relates to the goal is the goal bar's job.
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

// MARK: - Goal (design.md D5)

/// start -> current -> target as a bar, kg to go, and an ETA at the current
/// trend when the trend points at the target. Everything shown comes from
/// `WeightGoalProgress`; this view only formats it.
struct WeightGoalBar: View {
    let progress: WeightGoalProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .tint(progress.isReached ? Theme.success : Theme.accent)
                HStack {
                    if let start = progress.startKg {
                        Text("\(start.formattedKg) kg")
                    }
                    Spacer()
                    Text("Goal \(progress.targetKg.formattedKg) kg")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            } else {
                Text("Goal \(progress.targetKg.formattedKg) kg")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(summary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(progress.isReached ? Theme.success : .primary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        if progress.isReached {
            return "Goal reached"
        }
        var text = "\(progress.kgToGo.formattedKg) kg to go"
        if let eta = progress.eta {
            text += " · about \(eta.formatted(.dateTime.day().month(.abbreviated).year()))"
            if progress.etaSource == .garminPlan {
                text += " at Garmin's planned rate"
            }
        }
        return text
    }
}

// MARK: - Chart

/// A simple line + point chart of recent weigh-ins. `rows` MUST be
/// oldest-first (the reverse of the merged history's newest-first order)
/// so Swift Charts draws left-to-right chronologically.
struct WeightChartView: View {
    let rows: [WeighInDisplayEntry]
    var targetKg: Double? = nil

    var body: some View {
        Chart {
            ForEach(rows) { row in
                LineMark(
                    x: .value("Date", row.loggedAt),
                    y: .value("Weight", row.weightKg)
                )
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.catmullRom)
                PointMark(
                    x: .value("Date", row.loggedAt),
                    y: .value("Weight", row.weightKg)
                )
                .foregroundStyle(Theme.accent)
                .symbolSize(24)
            }
            if let targetKg {
                RuleMark(y: .value("Goal", targetKg))
                    .foregroundStyle(Theme.success.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
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
        guard let first = rows.first, let last = rows.last else { return "No data" }
        return "From \(first.weightKg.formattedKg) to \(last.weightKg.formattedKg) kilograms over \(rows.count) entries"
    }
}

// MARK: - History row

/// One row in the History list -- weight/date/note/source plus a sync-state
/// glyph, with swipe-to-delete (and swipe-to-retry when an add or a delete
/// failed), mirroring `SyncQueueView`'s `QueueEntryRow` shape.
struct WeightRow: View {
    let row: WeighInDisplayEntry
    let onDelete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(row.weightKg.formattedKg)
                        .font(.foodTitle)
                    Text("kg")
                        .font(.foodSubtitle)
                        .foregroundStyle(.secondary)
                }
                Text(row.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.foodSubtitle)
                    .foregroundStyle(.secondary)
                if let note = row.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if row.syncState == .deleteFailed {
                    Text("Couldn't delete in Garmin")
                        .font(.caption)
                        .foregroundStyle(Theme.warning)
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
            if canRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var canRetry: Bool {
        switch row.syncState {
        case .failed, .deleteFailed: return row.outboxEntryId != nil
        case .synced, .pending: return false
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch row.syncState {
        case .pending:
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed, .deleteFailed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.warning)
        case .synced:
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        var label = "\(row.weightKg.formattedKg) kilograms, \(row.loggedAt.formatted(date: .abbreviated, time: .shortened))"
        if let note = row.note, !note.isEmpty { label += ", \(note)" }
        switch row.syncState {
        case .pending: label += ", waiting to sync"
        case .failed: label += ", sync failed"
        case .deleteFailed: label += ", delete in Garmin failed"
        case .synced: break
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
        return NumberDisplay.quantity(rounded, fractionDigits: 1)
    }
}

// MARK: - Previews

private func previewRow(_ kg: Double, hoursAgo: Double, state: WeighInSyncState = .synced) -> WeighInDisplayEntry {
    WeighInDisplayEntry(
        source: .local(WeightEntry(weightKg: kg, loggedAt: Date().addingTimeInterval(-hoursAgo * 3_600))),
        syncState: state,
        outboxEntryId: nil
    )
}

#Preview("WeightHeroCard") {
    WeightHeroCard(
        latest: previewRow(83.9, hoursAgo: 1),
        previous: previewRow(84.4, hoursAgo: 25),
        progress: WeightGoalProgress.compute(
            goal: EffectiveWeightGoal(targetKg: 76, startKg: 86, origin: .garmin),
            currentKg: 83.9,
            recentWeighIns: [],
            now: Date()
        )
    )
    .card()
    .padding()
}

#Preview("WeightRow") {
    List {
        WeightRow(row: previewRow(75.5, hoursAgo: 1), onDelete: {}, onRetry: {})
        WeightRow(row: previewRow(76, hoursAgo: 2, state: .pending), onDelete: {}, onRetry: {})
        WeightRow(row: previewRow(77.2, hoursAgo: 3, state: .failed), onDelete: {}, onRetry: {})
    }
}

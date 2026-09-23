// HydrationComponents.swift
//
// Small, composable views for the hydration feature -- same idiom as
// WeightComponents.swift: a hero (today's total, shared between
// HydrationView and ProgressViews.swift's summary card), a quick-add chip
// row, and one history row. Nothing new invented here.
//
// "How much of today's target have I had" is the whole point of a
// hydration screen every competitor (Yazio, Kalorické tabulky) shows.
// Since sync-weight-hydration-with-garmin the total is Garmin's day total
// plus undelivered local drinks (FoodLogCore `HydrationDayTotal`), and the
// goal is Garmin's `goalInML` unless overridden in Settings -> Goals
// (`HydrationLoader.goal`). The old per-device `@AppStorage`
// "hydrationDailyGoalML" preference is no longer read anywhere.

import SwiftUI
import FoodLogCore
import GarminKit

// MARK: - Hero

struct HydrationHeroCard: View {
    let todayTotalML: Double
    let goalML: Double
    /// Shows the quiet "couldn't refresh" caption.
    var refreshFailed: Bool = false

    private var fraction: Double {
        guard goalML > 0 else { return 0 }
        return min(todayTotalML / goalML, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Today")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(0.6)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(todayTotalML.formattedML)
                    .font(.heroNumber)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("ml")
                    .font(.heroUnit)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction)
                .tint(Theme.carbs)
            Text(goalML > 0 ? "Goal \(goalML.formattedML) ml" : "No goal set")
                .font(.caption)
                .foregroundStyle(.secondary)
            if refreshFailed {
                GarminRefreshFailedCaption()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Quick add

/// One-tap logging for the amounts people actually reach for -- a glass, a
/// bottle, a large bottle. Calls straight through to `onAdd`, no sheet, no
/// confirmation: same "commit instantly" reasoning as the rest of this
/// app's logging actions (HydrationLogCoordinator.swift's header).
struct HydrationQuickAddRow: View {
    let onAdd: (Double) -> Void
    let onCustom: () -> Void

    private let presets: [Double] = [100, 250, 500]

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(presets, id: \.self) { amount in
                Button {
                    onAdd(amount)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "drop.fill")
                            .font(.subheadline)
                        Text("\(Int(amount))")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.bordered)
                .tint(Theme.carbs)
                .accessibilityLabel("Add \(Int(amount)) milliliters")
            }
            Button(action: onCustom) {
                VStack(spacing: 2) {
                    Image(systemName: "plus")
                        .font(.subheadline)
                    Text("Custom")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add a custom amount")
        }
    }
}

// MARK: - History row

/// One row in the History list -- mirrors `WeightRow` exactly (amount/date,
/// sync-state glyph, swipe-to-delete, swipe-to-retry on a failed delivery).
struct HydrationRow: View {
    let entry: HydrationEntry
    let syncState: OutboxEntryState?
    let onDelete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(entry.valueInML.formattedML)
                        .font(.foodTitle)
                    Text("ml")
                        .font(.foodSubtitle)
                        .foregroundStyle(.secondary)
                }
                Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.foodSubtitle)
                    .foregroundStyle(.secondary)
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
        // `.createdAwaitingDelete` is food-outbox-only (add-log-entry-
        // editing); a drink never reaches it.
        case .sent, .createdAwaitingDelete, .none:
            EmptyView()
        }
    }

    private var accessibilityLabel: String {
        var label = "\(entry.valueInML.formattedML) milliliters, \(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))"
        switch syncState {
        case .pending: label += ", waiting to sync"
        case .failed: label += ", sync failed"
        case .sent, .createdAwaitingDelete, .none: break
        }
        return label
    }
}

// MARK: - Formatting

extension Double {
    /// "250" / "1,500" -- whole-number milliliters, no decimals, mirroring
    /// `formattedKg`'s "no trailing noise" convention for this unit.
    var formattedML: String {
        String(Int(self.rounded()))
    }
}

#Preview("HydrationHeroCard") {
    HydrationHeroCard(todayTotalML: 1250, goalML: 2000)
        .card()
        .padding()
}

#Preview("HydrationRow") {
    List {
        HydrationRow(entry: HydrationEntry(valueInML: 250, loggedAt: Date()), syncState: .sent, onDelete: {}, onRetry: {})
        HydrationRow(entry: HydrationEntry(valueInML: 500, loggedAt: Date()), syncState: .pending, onDelete: {}, onRetry: {})
        HydrationRow(entry: HydrationEntry(valueInML: 100, loggedAt: Date()), syncState: .failed, onDelete: {}, onRetry: {})
    }
}

// SupplementInsightsView.swift
//
// add-supplements task 3.4: how the stack is going -- an adherence
// calendar of the last five weeks (tap a day to open and edit it, design
// D14), per-product adherence over 7 and 30 days, the stock overview (days
// left at the planned rate) and the cost per day and month.
//
// Every number comes from FoodLogCore (`SupplementChecklist`,
// `SupplementAdherence`, `StockProjection`), each day checked against the
// schedule in effect that day.
//
// Depends on: SupplementsController, SupplementDayView. Depended on by:
// SupplementsView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementInsightsView: View {
    @Environment(AppEnvironment.self) private var environment

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        List {
            Section {
                AdherenceCalendar()
            } header: {
                Text("Last 5 weeks")
            } footer: {
                Text("Tap a day to open it.", comment: "Supplement insights: under the adherence calendar.")
            }

            Section {
                let week = supplements.adherence(lastDays: 7, productId: nil)
                let month = supplements.adherence(lastDays: 30, productId: nil)
                AdherenceRow(title: String(localized: "Whole stack"), week: week, month: month)
                ForEach(supplements.stack) { product in
                    AdherenceRow(
                        title: product.name,
                        week: supplements.adherence(lastDays: 7, productId: product.id),
                        month: supplements.adherence(lastDays: 30, productId: product.id)
                    )
                }
            } header: {
                Text("Taken as planned")
            }

            Section {
                ForEach(supplements.stack) { product in
                    StockRow(product: product)
                }
            } header: {
                Text("Stock and cost")
            } footer: {
                Text("Set a pack's size, price and what's left in My stack.", comment: "Supplement insights: under stock and cost.")
            }
        }
        .navigationTitle("Insights")
    }
}

private struct AdherenceRow: View {
    let title: String
    let week: SupplementAdherence
    let month: SupplementAdherence

    var body: some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("7 days: \(percentText(week))", comment: "Supplement adherence over the last 7 days. %@ = a percentage or a dash.")
                Text("30 days: \(percentText(month))", comment: "Supplement adherence over the last 30 days. %@ = a percentage or a dash.")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func percentText(_ adherence: SupplementAdherence) -> String {
        guard let percent = adherence.percent else { return "–" }
        return (Double(percent) / 100).formatted(.percent.precision(.fractionLength(0)))
    }
}

private struct StockRow: View {
    @Environment(AppEnvironment.self) private var environment
    let product: SupplementProduct

    var body: some View {
        let supplements = environment.supplements
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: product.name)
            HStack {
                if let remaining = supplements.remainingServings(product) {
                    Text("Servings left: \(SupplementFormat.servings(remaining))", comment: "Supplement stock: servings remaining. %@ = a number (may be fractional, so no plural).")
                } else {
                    Text("Stock not set")
                }
                Spacer()
                if let daysLeft = supplements.daysLeft(product) {
                    Text("\(daysLeft) days left", comment: "My stack: stock lasts this many more days at the planned rate. Plural.")
                        .foregroundStyle(daysLeft <= StockProjection.defaultRestockLeadDays ? Theme.warning : Color.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let cost = supplements.cost(product) {
                Text("\(cost.perDay.formatted(.currency(code: cost.currency))) a day · \(cost.perMonth.formatted(.currency(code: cost.currency))) a month", comment: "Supplement cost at the planned rate: per day, then per 30 days.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Five weeks of days as coloured dots; tapping one opens that day.
private struct AdherenceCalendar: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let supplements = environment.supplements
        let today = supplements.today
        let start = SupplementDate.adding(-34, to: today) ?? today
        let days = SupplementDate.days(from: start, through: today)
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 7)

        LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
            ForEach(days, id: \.self) { day in
                NavigationLink {
                    SupplementDayView(day: day)
                } label: {
                    DayDot(day: day, status: supplements.status(on: day), isToday: day == today)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct DayDot: View {
    let day: String
    let status: SupplementDayStatus
    let isToday: Bool

    var body: some View {
        let number = SupplementDay.date(day).map { Calendar.current.component(.day, from: $0) } ?? 0
        Text(verbatim: "\(number)")
            .font(.caption2.monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(fill, in: Circle())
            .overlay {
                if isToday {
                    Circle().stroke(Theme.accent, lineWidth: 2)
                }
            }
            .foregroundStyle(status == .complete ? Theme.onAccent : Color.primary)
            .accessibilityElement()
            // VoiceOver reads the full date and the day's status.
            .accessibilityLabel(Text(verbatim: SupplementDay.date(day)?.formatted(date: .complete, time: .omitted) ?? day))
            .accessibilityValue(Text(verbatim: SupplementStatusBadge.title(for: status)))
    }

    private var fill: Color {
        switch status {
        case .complete: return Theme.success
        case .partial: return Theme.warning.opacity(0.35)
        case .missed: return Color.secondary.opacity(0.15)
        case .neutral: return Color.clear
        }
    }
}

/// One past (or today's) day, opened from the calendar: the same checklist
/// as the main screen, for that day.
@MainActor
struct SupplementDayView: View {
    @Environment(AppEnvironment.self) private var environment
    let day: String

    var body: some View {
        let supplements = environment.supplements
        let checklist = supplements.checklist(on: day)
        let editable = supplements.editability(of: day) == .editable
        List {
            Section {
                HStack {
                    Text(verbatim: SupplementDay.title(day, today: supplements.today))
                        .font(.headline)
                    Spacer()
                    SupplementStatusBadge(status: checklist.status)
                }
            }
            if checklist.entries.isEmpty {
                Text("Nothing planned for this day.", comment: "Supplements screen: the selected day has no planned items.")
                    .foregroundStyle(.secondary)
            }
            ForEach(checklist.slots, id: \.key) { slot in
                SupplementChecklistSection(slot: slot, day: day, checklist: checklist, isEditable: editable)
            }
        }
        .navigationTitle(SupplementDay.title(day, today: supplements.today))
        .navigationBarTitleDisplayMode(.inline)
    }
}

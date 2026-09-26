// SupplementsView.swift
//
// add-supplements D11/D14, task 3.2: the Supplements screen, reached from
// the Today card and the Progress row (not a tab). Top to bottom:
// - the day: a date picker from today back 365 days (D14 -- past days are
//   evaluated against the schedule in effect then), with the day's status;
// - the checklist for that day, one section per slot, with "Take all";
// - extra doses logged that day, and "Log an extra dose";
// - the day's limit warnings (calm, amber, D6);
// - links to My stack, Totals and limits, Insights, Evidence and Reminder
//   times; the disclaimer last.
//
// Thin: all state and actions are `SupplementsController`; ticking is
// local-first (no network, CLAUDE.md).
//
// Depends on: SupplementsController, SupplementChecklistSection,
// ExtraDoseSheet, SupplementStackView, SupplementLimitsView,
// SupplementInsightsView, SupplementEvidenceListView,
// SupplementReminderTimesView. Depended on by: SupplementsTodayCard,
// ProgressViews (entry row).

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementsView: View {
    @Environment(AppEnvironment.self) private var environment
    /// The day shown; `nil` = today (follows midnight).
    @State private var selectedDay: String?
    @State private var isAddingExtra = false

    private var supplements: SupplementsController { environment.supplements }
    private var day: String { selectedDay ?? supplements.today }

    var body: some View {
        let controller = supplements
        let checklist = controller.checklist(on: day)
        let editable = controller.editability(of: day) == .editable

        List {
            daySection(checklist)

            if controller.plan.products.isEmpty {
                Section {
                    NavigationLink {
                        SupplementStackView()
                    } label: {
                        Label("Add your first supplement", systemImage: "plus.circle.fill")
                    }
                }
            } else if checklist.entries.isEmpty {
                Section {
                    Text("Nothing planned for this day.", comment: "Supplements screen: the selected day has no planned items.")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(checklist.slots, id: \.key) { slot in
                SupplementChecklistSection(slot: slot, day: day, checklist: checklist, isEditable: editable)
            }

            extrasSection(editable: editable)

            let warnings = controller.warnings(on: day)
            if !warnings.isEmpty {
                Section {
                    // By position: one ingredient can have both a daily
                    // and a single-dose warning.
                    ForEach(Array(warnings.enumerated()), id: \.offset) { item in
                        LimitWarningRow(warning: item.element)
                    }
                } header: {
                    Text("Over your limits")
                }
            }

            Section {
                NavigationLink {
                    SupplementStackView()
                } label: {
                    Label("My stack", systemImage: "square.stack.3d.up")
                }
                NavigationLink {
                    SupplementLimitsView(day: day)
                } label: {
                    Label("Totals and limits", systemImage: "gauge.with.dots.needle.33percent")
                }
                NavigationLink {
                    SupplementInsightsView()
                } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
                NavigationLink {
                    SupplementEvidenceListView()
                } label: {
                    Label("Evidence", systemImage: "book.closed")
                }
                NavigationLink {
                    SupplementReminderTimesView()
                } label: {
                    Label("Reminder times", systemImage: "bell")
                }
            } footer: {
                Text(verbatim: EvidenceCatalog.disclaimer)
            }
        }
        .navigationTitle("Supplements")
        .task { await controller.reload() }
        .refreshable { await controller.reload() }
        .sheet(isPresented: $isAddingExtra) {
            NavigationStack {
                ExtraDoseSheet(day: day)
            }
        }
        .alert(
            "Couldn't save",
            isPresented: Binding(get: { supplements.errorMessage != nil }, set: { if !$0 { supplements.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(supplements.errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private func daySection(_ checklist: SupplementChecklist) -> some View {
        Section {
            DatePicker(
                selection: Binding(
                    get: { SupplementDay.date(day) ?? Date() },
                    set: { date in
                        let key = SupplementDay.key(date)
                        selectedDay = key == supplements.today ? nil : key
                    }
                ),
                in: (SupplementDay.date(supplements.earliestDay) ?? Date())...(SupplementDay.date(supplements.today) ?? Date()),
                displayedComponents: .date
            ) {
                Text("Day")
            }
            HStack {
                Text(verbatim: SupplementDay.title(day, today: supplements.today))
                    .font(.headline)
                Spacer()
                SupplementStatusBadge(status: checklist.status)
            }
            .accessibilityElement(children: .combine)
        } footer: {
            if day != supplements.today {
                Text("Ticks on past days count for your streak and history. After 7 days they no longer earn XP.", comment: "Supplements screen: footer when a past day is selected (design D14).")
            }
        }
    }

    private func extrasSection(editable: Bool) -> some View {
        let extras = supplements.records(on: day).filter { $0.kind == .extra }
        return Section {
            ForEach(extras) { record in
                HStack {
                    Text(verbatim: supplements.product(record.productId)?.name ?? String(localized: "Removed product"))
                    Spacer()
                    Text(verbatim: "× " + SupplementFormat.servings(record.servings))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .swipeActions {
                    if editable {
                        Button(role: .destructive) {
                            Task { await supplements.removeRecord(record) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            if editable && !supplements.plan.products.isEmpty {
                Button {
                    isAddingExtra = true
                } label: {
                    Label("Log an extra dose", systemImage: "plus")
                }
            }
        } header: {
            if !extras.isEmpty {
                Text("Extra doses")
            }
        }
    }
}

/// "Stack done" / "Partly" / "Missed" / "Nothing planned" for a day.
struct SupplementStatusBadge: View {
    let status: SupplementDayStatus

    var body: some View {
        Label {
            Text(Self.title(for: status))
        } icon: {
            Image(systemName: symbol)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
    }

    static func title(for status: SupplementDayStatus) -> String {
        switch status {
        case .complete: return String(localized: "Stack done", comment: "Supplements: every planned item of the day was taken.")
        case .partial: return String(localized: "Partly done", comment: "Supplements: some planned items of the day were taken.")
        case .missed: return String(localized: "Not taken", comment: "Supplements: nothing planned was taken that day.")
        case .neutral: return String(localized: "Nothing planned", comment: "Supplements: no item was planned that day.")
        }
    }

    private var symbol: String {
        switch status {
        case .complete: return "checkmark.seal.fill"
        case .partial: return "circle.lefthalf.filled"
        case .missed: return "circle"
        case .neutral: return "minus.circle"
        }
    }

    private var color: Color {
        switch status {
        case .complete: return Theme.success
        case .partial: return Theme.warning
        case .missed, .neutral: return .secondary
        }
    }
}

/// One calm, amber row: an ingredient over its limit (design D6).
struct LimitWarningRow: View {
    let warning: LimitWarning

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: EvidenceCatalog.name(of: warning.ingredient))
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let amount = SupplementFormat.amount(warning.amount, unit: warning.unit)
        let limit = SupplementFormat.amount(warning.limit, unit: warning.unit)
        switch warning.kind {
        case .daily:
            return String(localized: "\(amount) today, above your limit of \(limit).", comment: "Supplements warning: a day's total over the upper limit. First %@ = the total, second = the limit.")
        case .singleDose:
            return String(localized: "\(amount) in one dose, above \(limit) per dose.", comment: "Supplements warning: a single dose over the per-dose limit (caffeine).")
        }
    }
}

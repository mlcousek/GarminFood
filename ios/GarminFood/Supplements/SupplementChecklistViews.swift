// SupplementChecklistViews.swift
//
// add-supplements task 3.2: the pieces of a day's checklist -- one section
// per time slot (tick each item, "Take all") -- and the sheet for an
// off-plan extra dose, which shows a calm, non-blocking notice when the dose
// would take a day's total over a limit (design D6: the dose is logged
// either way; no push notification).
//
// Ticks commit to `SupplementIntakeStore` through `SupplementsController`
// with no network wait. A day outside the editable range (future, or more
// than 365 days back) is read-only.
//
// Depends on: SupplementsController, FoodLogCore (SupplementChecklist,
// SupplementFormat, SupplementLimits). Depended on by: SupplementsView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementChecklistSection: View {
    @Environment(AppEnvironment.self) private var environment
    let slot: TimeSlot
    let day: String
    let checklist: SupplementChecklist
    let isEditable: Bool

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        let entries = checklist.entries(in: slot)
        let isComplete = checklist.isComplete(slot)

        Section {
            ForEach(entries, id: \.item) { entry in
                SupplementChecklistRow(
                    entry: entry,
                    product: supplements.product(entry.item.productId),
                    isEditable: isEditable
                ) { taken in
                    Task { await supplements.setTaken(entry, taken: taken, on: day) }
                }
            }
            if isEditable && !isComplete && entries.count > 1 {
                Button {
                    Task { await supplements.takeAll(slot, on: day) }
                } label: {
                    Label("Take all", systemImage: "checkmark.circle")
                }
            }
        } header: {
            HStack {
                Label(slot.displayName, systemImage: slot.symbolName)
                Spacer()
                if isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.success)
                        .accessibilityLabel(Text("Done"))
                }
            }
        }
    }
}

/// One planned item: a round checkmark button, the product and its dose.
struct SupplementChecklistRow: View {
    let entry: SupplementChecklist.Entry
    let product: SupplementProduct?
    let isEditable: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!entry.isTaken)
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: entry.isTaken ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(entry.isTaken ? Theme.success : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: product?.name ?? String(localized: "Removed product"))
                        .strikethrough(entry.isTaken, color: .secondary)
                        .foregroundStyle(.primary)
                    if let summary = product?.summaryLine, !summary.isEmpty {
                        Text(verbatim: summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let suffix = entry.item.servingsSuffix {
                    Text(verbatim: suffix)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .accessibilityElement(children: .combine)
        .accessibilityValue(entry.isTaken ? Text("Taken") : Text("Not taken"))
        .accessibilityAddTraits(entry.isTaken ? .isSelected : [])
    }
}

/// An off-plan dose: pick a product and servings; a notice appears when it
/// would go over a limit, but logging is never blocked.
@MainActor
struct ExtraDoseSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let day: String
    @State private var productId: UUID?
    @State private var servings: Double = 1

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        let products = supplements.plan.products
        let selected = productId.flatMap { supplements.product($0) }
        let notice = selected.map { supplements.extraDoseNotice($0, servings: servings, on: day) } ?? []

        Form {
            Picker("Supplement", selection: $productId) {
                Text("Choose…").tag(UUID?.none)
                ForEach(products) { product in
                    Text(verbatim: product.name).tag(Optional(product.id))
                }
            }
            Stepper(value: $servings, in: 0.5...20, step: 0.5) {
                HStack {
                    Text("Servings")
                    Spacer()
                    Text(verbatim: SupplementFormat.servings(servings))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if !notice.isEmpty {
                Section {
                    ForEach(Array(notice.enumerated()), id: \.offset) { item in
                        LimitWarningRow(warning: item.element)
                    }
                } footer: {
                    Text("You can still log it. This is information, not medical advice.", comment: "Extra dose sheet: under the over-limit notice.")
                }
            }
        }
        .navigationTitle("Extra dose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Log") {
                    guard let productId else { return }
                    Task {
                        await supplements.addExtra(productId, servings: servings, on: day)
                        dismiss()
                    }
                }
                .disabled(productId == nil)
            }
        }
        .onAppear {
            if productId == nil { productId = supplements.stack.first?.id ?? products.first?.id }
        }
    }
}

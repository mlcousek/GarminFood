// SupplementsTodayCard.swift
//
// add-supplements D4, task 3.6: Today's supplements card
// (`TodayCardID.supplements`), after the meals. Two variants from the
// layout editor:
// - `slot` (default): the current slot -- the next one due by clock time,
//   else the first not done -- with a tick per item and "Take all"; once
//   everything today is taken it collapses to "Stack done";
// - `day`: every slot today as a compact pill (tap one to take the slot).
// Tapping the header opens the Supplements screen.
//
// Always today's date, whatever day the Today screen is showing: the card
// is about what to take now. Ticking commits locally, with no network
// (CLAUDE.md). It only renders while the feature is on with a product
// (`TodayCardID.baseAvailability`).
//
// Depends on: SupplementsController, SupplementsView, AppearanceKit
// (SupplementsVariant). Depended on by: TodayView.

import SwiftUI
import FoodLogCore
import AppearanceKit

@MainActor
struct SupplementsTodayCard: View {
    @Environment(AppEnvironment.self) private var environment
    let variant: SupplementsVariant
    let onOpen: () -> Void

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        let today = supplements.today
        let checklist = supplements.checklist(on: today)

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Button(action: onOpen) {
                HStack {
                    Label("Supplements", systemImage: "pills")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens your supplements"))

            if checklist.entries.isEmpty {
                Text("Nothing planned today.", comment: "Today supplements card: nothing due today.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if checklist.status == .complete {
                Label("Stack done", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.success)
            } else {
                switch variant {
                case .slot:
                    slotBody(checklist)
                case .day:
                    dayBody(checklist)
                }
            }
        }
        .card()
        .task { if !supplements.hasLoaded { await supplements.reload() } }
    }

    @ViewBuilder
    private func slotBody(_ checklist: SupplementChecklist) -> some View {
        if let slot = supplements.currentSlot(in: checklist) {
            let entries = checklist.entries(in: slot)
            Text(verbatim: slot.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(entries, id: \.item) { entry in
                SupplementChecklistRow(
                    entry: entry,
                    product: supplements.product(entry.item.productId),
                    isEditable: true
                ) { taken in
                    Task { await supplements.setTaken(entry, taken: taken, on: checklist.day) }
                }
            }
            if entries.filter({ !$0.isTaken }).count > 1 {
                Button {
                    Task { await supplements.takeAll(slot, on: checklist.day) }
                } label: {
                    Label("Take all", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
            }
        }
    }

    private func dayBody(_ checklist: SupplementChecklist) -> some View {
        // Wraps onto more lines at large text sizes.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.xs) { pills(checklist) }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) { pills(checklist) }
        }
    }

    @ViewBuilder
    private func pills(_ checklist: SupplementChecklist) -> some View {
        ForEach(checklist.slots, id: \.key) { slot in
            let done = checklist.isComplete(slot)
            Button {
                if !done { Task { await supplements.takeAll(slot, on: checklist.day) } }
            } label: {
                Label(slot.displayName, systemImage: done ? "checkmark.circle.fill" : slot.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(done ? Theme.success.opacity(0.18) : Theme.accent.opacity(0.12), in: Capsule())
                    .foregroundStyle(done ? Theme.success : Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: slot.displayName))
            .accessibilityValue(done ? Text("Taken") : Text("Not taken"))
            .accessibilityHint(done ? Text(verbatim: "") : Text("Takes everything in this slot"))
        }
    }
}

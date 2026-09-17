// MealDetailView.swift
//
// One meal in full (meal-dashboard spec): consumed vs Garmin's suggested
// target, every nutrient Garmin returned, the foods, adding straight into
// this meal, and deleting an entry after confirming.
//
// Deleting a synced entry calls DELETE /nutrition-service/food/logs/{date},
// modelled on garmin_mcp and not yet exercised by this project, so a
// failure keeps the entry listed and says why (design D5).

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct MealDetailView: View {
    let mealType: MealType

    @Environment(AppEnvironment.self) private var environment
    @State private var catalogContext: LogContext?
    @State private var pendingDelete: MealEntry?
    @State private var deleteError: String?
    @State private var deletingId: String?

    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 96

    var body: some View {
        let dayLog = environment.dayLog
        let section = dayLog.dashboard.section(for: mealType)

        List {
            if let section {
                Section {
                    summary(section)
                }

                Section("Foods") {
                    if section.entries.isEmpty {
                        EmptyStateView(
                            systemImage: mealType.symbolName,
                            title: "Nothing logged",
                            message: "Add a food to \(mealType.displayName.lowercased()) to see it here."
                        )
                    } else {
                        ForEach(section.entries) { entry in
                            MealEntryRow(entry: entry)
                                .opacity(deletingId == entry.id ? 0.4 : 1)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        pendingDelete = entry
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        pendingDelete = entry
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                if section.nutrients.count > 4 {
                    Section("Nutrients") {
                        ForEach(section.nutrients.filter { $0.kind != .calories }) { nutrient in
                            NutrientRow(nutrient: nutrient)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(mealType.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    catalogContext = LogContext(mealType: mealType, date: dayLog.selectedDate)
                } label: {
                    Label("Add food", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(item: $catalogContext) { context in
            FoodCatalogView()
                .environment(\.logContext, context)
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete \(entry.name)", role: .destructive) {
                delete(entry)
            }
        } message: { entry in
            Text(entry.isSynced
                 ? "It will also be removed from Garmin Connect."
                 : "It hasn't reached Garmin yet, so it's only removed from this phone.")
        }
        .alert(
            "Couldn't delete",
            isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .refreshable {
            await dayLog.refresh()
        }
    }

    private func summary(_ section: MealSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.lg) {
                ProgressRing(
                    fraction: section.totals.calories.fraction ?? 0,
                    lineWidth: 10,
                    tint: section.totals.calories.state.tint(base: Theme.accent)
                ) {
                    VStack(spacing: 0) {
                        Text("\(Int(section.totals.calories.consumed.rounded()))")
                            .font(.system(.title2, design: .rounded).weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text("kcal")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(Theme.Spacing.xs)
                }
                .frame(width: ringSize, height: ringSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(mealType.displayName) calories")
                .accessibilityValue(targetText(section.totals.calories))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(targetText(section.totals.calories))
                        .font(.headline)
                    if let window = section.window {
                        Label(window.displayText, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Suggested by Garmin Connect")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            MacroBar(title: "Carbs", progress: section.totals.carbs, unit: "g", tint: Theme.carbs)
            MacroBar(title: "Protein", progress: section.totals.protein, unit: "g", tint: Theme.protein)
            MacroBar(title: "Fat", progress: section.totals.fat, unit: "g", tint: Theme.fat)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func targetText(_ calories: MacroProgress) -> String {
        let consumed = Int(calories.consumed.rounded())
        guard let goal = calories.goal else { return "\(consumed) kcal, no target" }
        return "\(consumed) of \(Int(goal.rounded())) kcal"
    }

    private func delete(_ entry: MealEntry) {
        deletingId = entry.id
        Task {
            defer { deletingId = nil }
            do {
                try await environment.delete(entry)
                Haptics.success()
            } catch {
                deleteError = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

private struct NutrientRow: View {
    let nutrient: NutrientAmount

    var body: some View {
        HStack {
            Text(nutrient.kind.displayName)
                .font(nutrient.kind.isSubNutrient ? .subheadline : .body)
                .foregroundStyle(nutrient.kind.isSubNutrient ? .secondary : .primary)
                .padding(.leading, nutrient.kind.isSubNutrient ? Theme.Spacing.md : 0)
            Spacer()
            Text("\(nutrient.value.formatted(.number.precision(.fractionLength(0...1)))) \(nutrient.kind.unit)")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MealDetailView.swift
//
// One meal in full (meal-dashboard spec): consumed vs Garmin's suggested
// target, every nutrient Garmin returned, the foods, adding straight into
// this meal, and deleting an entry after confirming.
//
// add-log-entry-editing: each food row swipes to Edit / Delete (trailing)
// and Duplicate (leading), long-presses to Edit / Move / Duplicate /
// Delete, and "Copy from…" re-logs a past day's meal -- all through the
// shared `EntryEditor` (EntryEditing.swift), same as the Today cards.
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
    @State private var editor = EntryEditor()

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
                                .entryActions(entry, editor: editor)
                        }
                    }
                }

                if section.nutrients.count > 4 {
                    // This is Garmin's own daily/meal aggregate -- it has no
                    // vitaminB1...omega6 fields to show even after
                    // implement-micronutrients (2026-09-22), since Garmin's
                    // API genuinely doesn't return them (MealDashboard.
                    // nutrients' header comment). A food's fuller Open Food
                    // Facts panel is shown per-food instead, on
                    // LogEntryConfirmView's nutrition section, at the point
                    // it's actually known.
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
                    editor.copyTarget = CopyMealTarget(mealType: mealType)
                } label: {
                    Label("Copy from…", systemImage: "doc.on.doc")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    catalogContext = LogContext(mealType: mealType, date: dayLog.selectedDate)
                } label: {
                    Label("Add food", systemImage: "plus.circle.fill")
                }
            }
        }
        .navigationDestination(item: $catalogContext) { context in
            FoodCatalogView(logContext: context)
        }
        .entryEditing(editor)
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
                        Text("\(section.totals.calories.consumed.wholeNumberText)")
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
        let consumed = calories.consumed.wholeNumberText
        guard let goal = calories.goal else { return "\(consumed) kcal, no target" }
        return "\(consumed) of \(goal.wholeNumberText) kcal"
    }
}

// `NutrientRow` moved to DesignSystem/Components.swift (implement-micronutrients,
// 2026-09-22) so `LogEntryConfirmView`'s new per-serving nutrition section
// can reuse it too.

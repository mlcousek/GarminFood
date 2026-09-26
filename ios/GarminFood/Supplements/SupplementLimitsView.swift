// SupplementLimitsView.swift
//
// add-supplements task 3.3 (design D6): the day's total per ingredient
// across every product (planned and extra, in canonical units), each
// against its limit, with calm amber rows when over; and the limit editor --
// your own target and upper limit, the default with its source, and "Reset
// to default". Endurance athletes often need more sodium or magnesium, so
// the default is a starting point, not a rule.
//
// Where the EU sets no upper limit, the row says so, with the US figure
// labelled as US where one exists (D6). Totals, effective limits and
// warnings all come from FoodLogCore (`IngredientTotals`,
// `SupplementLimits`); this view lays them out.
//
// Depends on: SupplementsController, FoodLogCore (SupplementLimits,
// EvidenceCatalog, SupplementFormat). Depended on by: SupplementsView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementLimitsView: View {
    @Environment(AppEnvironment.self) private var environment
    let day: String

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        let totals = supplements.totals(on: day)
        let warned = Set(supplements.warnings(on: day).map(\.ingredient))

        List {
            Section {
                if totals.ingredients.isEmpty {
                    Text("Nothing taken on this day yet.", comment: "Totals: empty day.")
                        .foregroundStyle(.secondary)
                }
                ForEach(totals.ingredients, id: \.self) { ingredient in
                    TotalRow(
                        ingredient: ingredient,
                        amount: totals.amount(of: ingredient),
                        limit: supplements.effectiveLimit(ingredient),
                        isOver: warned.contains(ingredient)
                    )
                }
            } header: {
                Text(verbatim: SupplementDay.title(day, today: supplements.today))
            } footer: {
                if !totals.unconverted.isEmpty {
                    Text("Some amounts use a unit that can't be added up here (for example IU for something other than vitamin D), so they're left out.", comment: "Totals footer: ingredients whose units couldn't be converted.")
                }
            }

            Section {
                ForEach(supplements.limitIngredients, id: \.self) { ingredient in
                    NavigationLink {
                        LimitEditorView(ingredient: ingredient)
                    } label: {
                        LimitSummaryRow(limit: supplements.effectiveLimit(ingredient))
                    }
                }
            } header: {
                Text("Your limits")
            } footer: {
                Text(verbatim: EvidenceCatalog.disclaimer)
            }
        }
        .navigationTitle("Totals and limits")
    }
}

private struct TotalRow: View {
    let ingredient: IngredientID
    let amount: Double
    let limit: EffectiveLimit
    let isOver: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: EvidenceCatalog.name(of: ingredient))
                Spacer()
                Text(verbatim: SupplementFormat.amount(amount, unit: limit.unit))
                    .monospacedDigit()
                    .foregroundStyle(isOver ? Theme.warning : Color.primary)
            }
            if let upper = limit.upperLimit, upper > 0 {
                ProgressView(value: min(amount / upper, 1))
                    .tint(isOver ? Theme.warning : Theme.accent)
                Text("Limit \(SupplementFormat.amount(upper, unit: limit.unit))", comment: "Totals row: the upper limit in use. %@ = amount with unit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: EvidenceCatalog.noEUUpperLimitText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct LimitSummaryRow: View {
    let limit: EffectiveLimit

    var body: some View {
        HStack {
            Text(verbatim: EvidenceCatalog.name(of: limit.ingredient))
            Spacer()
            Text(verbatim: limit.upperLimit.map { SupplementFormat.amount($0, unit: limit.unit) } ?? "–")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if limit.isOverridden {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel(Text("Your own limit"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Your own target and upper limit for one ingredient, with the default and
/// its source.
@MainActor
struct LimitEditorView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let ingredient: IngredientID
    @State private var targetText = ""
    @State private var upperText = ""

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        let limit = supplements.effectiveLimit(ingredient)
        let card = EvidenceCatalog.card(for: ingredient)
        let unit = ingredient.canonicalUnit.symbol

        Form {
            Section {
                row(String(localized: "Daily target"), text: $targetText, unit: unit)
                row(String(localized: "Upper limit"), text: $upperText, unit: unit)
            } footer: {
                Text("Endurance athletes often use more sodium or magnesium. Discuss your own limits with a professional.", comment: "Limit editor footer.")
            }

            Section {
                if let value = limit.defaultUpperLimit {
                    LabeledContent(String(localized: "Default"), value: SupplementFormat.amount(value, unit: limit.unit))
                } else {
                    Text(verbatim: EvidenceCatalog.noEUUpperLimitText)
                }
                if let us = card?.limit.usFigure {
                    LabeledContent(String(localized: "US figure"), value: SupplementFormat.amount(us, unit: limit.unit))
                }
                if let note = card?.limitNote {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let source = card?.limit.source {
                    Link(destination: source.url) {
                        Label(source.title, systemImage: "link")
                    }
                }
                if limit.isOverridden {
                    Button("Reset to default", role: .destructive) {
                        Task {
                            await supplements.resetLimit(ingredient)
                            dismiss()
                        }
                    }
                }
            } header: {
                Text("Default and source")
            }
        }
        .navigationTitle(EvidenceCatalog.name(of: ingredient))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await supplements.setLimit(LimitOverride(
                            ingredient: ingredient,
                            target: SupplementProductEditorView.number(targetText),
                            upperLimit: SupplementProductEditorView.number(upperText)
                        ))
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            let override = supplements.overrides[ingredient]
            targetText = override?.target.map { SupplementFormat.servings($0) } ?? ""
            upperText = override?.upperLimit.map { SupplementFormat.servings($0) } ?? ""
        }
    }

    private func row(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            TextField(text: text, prompt: Text("Default")) { Text(verbatim: title) }
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(verbatim: unit).foregroundStyle(.secondary)
        }
    }
}

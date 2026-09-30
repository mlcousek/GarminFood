// SupplementStackView.swift
//
// add-supplements task 3.2 ("My stack") and D10's adding paths: the
// products planned from today on, each with its schedule summary and stock,
// then the products taken out of the stack (their history stays, D10), and
// two ways to add one -- from the built-in catalog (prefilled label and a
// suggested slot) or your own. Barcode prefill (wave 5) plugs in here.
//
// Taking a product out of the stack sets its schedule to "none" from today
// (past days keep theirs, design D3); deleting removes it and its schedule
// history for good, after a confirmation.
//
// The catalog lists real branded products (SupplementCatalog.branded, with
// the quality facts their maker states and the page they were read from)
// above the generic entries (add-custom-ingredients-and-owner-supplements).
//
// Depends on: SupplementsController, SupplementProductEditorView,
// FoodLogCore (SupplementCatalog, SupplementCatalog+Branded). Depended on by: SupplementsView,
// SupplementsSettingsRow (onboarding).

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementStackView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var editing: SupplementEditorRequest?
    @State private var productToDelete: SupplementProduct?

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        List {
            Section {
                if supplements.stack.isEmpty {
                    Text("Nothing in your stack yet.", comment: "My stack: empty.")
                        .foregroundStyle(.secondary)
                }
                ForEach(supplements.stack) { product in
                    Button {
                        editing = .existing(product.id)
                    } label: {
                        StackRow(product: product)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button {
                            Task { await supplements.removeFromStack(product.id) }
                        } label: {
                            Label("Stop taking", systemImage: "pause.circle")
                        }
                        .tint(Theme.warning)
                    }
                }
            } header: {
                Text("My stack")
            }

            Section {
                NavigationLink {
                    SupplementCatalogPicker { catalogProduct in
                        editing = .catalog(catalogProduct.id)
                    }
                } label: {
                    Label("Add from the catalog", systemImage: "list.bullet.rectangle")
                }
                Button {
                    editing = .custom
                } label: {
                    Label("Add your own", systemImage: "square.and.pencil")
                }
            }

            if !supplements.retired.isEmpty {
                Section {
                    ForEach(supplements.retired) { product in
                        Button {
                            editing = .existing(product.id)
                        } label: {
                            StackRow(product: product)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button(role: .destructive) {
                                productToDelete = product
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Not taking now")
                } footer: {
                    Text("Their history stays. Open one to plan it again.", comment: "My stack: footer under products no longer planned.")
                }
            }
        }
        .navigationTitle("My stack")
        .sheet(item: $editing) { request in
            NavigationStack {
                SupplementProductEditorView(request: request)
            }
        }
        .confirmationDialog(
            "Delete this supplement and its history?",
            isPresented: Binding(get: { productToDelete != nil }, set: { if !$0 { productToDelete = nil } }),
            titleVisibility: .visible,
            presenting: productToDelete
        ) { product in
            Button("Delete", role: .destructive) {
                Task { await supplements.deleteProduct(product.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Ticks you already logged stay in your history, but they'll show as a removed product.", comment: "Confirming deleting a supplement product.")
        }
    }
}

/// What the product editor opens with.
enum SupplementEditorRequest: Identifiable, Hashable {
    case existing(UUID)
    case catalog(String)
    case custom

    var id: String {
        switch self {
        case .existing(let id): return "existing." + id.uuidString
        case .catalog(let id): return "catalog." + id
        case .custom: return "custom"
        }
    }
}

/// A stack row: name, dose summary, and stock when set.
private struct StackRow: View {
    @Environment(AppEnvironment.self) private var environment
    let product: SupplementProduct

    var body: some View {
        let supplements = environment.supplements
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: product.name)
            if !product.summaryLine.isEmpty {
                Text(verbatim: product.summaryLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let daysLeft = supplements.daysLeft(product) {
                Text("\(daysLeft) days left", comment: "My stack: stock lasts this many more days at the planned rate. Plural.")
                    .font(.caption)
                    .foregroundStyle(daysLeft <= StockProjection.defaultRestockLeadDays ? Theme.warning : Color.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The built-in products, each with its label: real branded products
/// first (add-custom-ingredients-and-owner-supplements -- their label,
/// the quality facts their maker states and where it was read), then the
/// generic ones.
struct SupplementCatalogPicker: View {
    let onPick: (CatalogProduct) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !SupplementCatalog.branded.isEmpty {
                Section {
                    ForEach(SupplementCatalog.branded) { product in
                        row(product)
                    }
                } header: {
                    Text("Brand products")
                } footer: {
                    Text("Amounts as the product page states them on the date shown. Check them against your pack; recipes change.", comment: "Supplement catalog: footer under the branded products.")
                }
            }
            Section {
                ForEach(SupplementCatalog.all) { product in
                    row(product)
                }
            } header: {
                Text("Common supplements")
            }
        }
        .navigationTitle("Catalog")
    }

    private func row(_ product: CatalogProduct) -> some View {
        Button {
            onPick(product)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: product.name)
                    .foregroundStyle(.primary)
                if let label = product.label {
                    Text(verbatim: label.brand)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: ([product.servingDescription] + product.ingredients.map { line($0) }).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let label = product.label {
                    if !label.quality.isEmpty {
                        Text(verbatim: label.quality.map(\.text).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    if let details = label.labelDetails {
                        Text(verbatim: details)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("Label from \(label.sourceURL.host() ?? label.sourceURL.absoluteString), checked \(Self.day(label.verifiedOn))", comment: "Supplement catalog: where a branded product's label was read and when. %1$@ = website, %2$@ = date.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Zinc 15 mg (bisglycinate)": a branded row shows its form too.
    private func line(_ row: IngredientAmount) -> String {
        let base = SupplementFormat.ingredientLine(row)
        guard let form = row.form, !form.isEmpty else { return base }
        return base + " (" + form + ")"
    }

    /// `yyyy-MM-dd` as a short local date; the raw text if it doesn't parse.
    private static func day(_ text: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withFullDate]
        parser.timeZone = .current
        guard let date = parser.date(from: text) else { return text }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

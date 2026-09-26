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
// Depends on: SupplementsController, SupplementProductEditorView,
// FoodLogCore (SupplementCatalog). Depended on by: SupplementsView,
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

/// The built-in products, each with its label.
struct SupplementCatalogPicker: View {
    let onPick: (CatalogProduct) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(SupplementCatalog.all) { product in
            Button {
                onPick(product)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: product.name)
                        .foregroundStyle(.primary)
                    Text(verbatim: ([product.servingDescription] + product.ingredients.map { SupplementFormat.ingredientLine($0) }).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .navigationTitle("Catalog")
    }
}

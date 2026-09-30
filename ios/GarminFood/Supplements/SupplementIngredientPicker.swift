// SupplementIngredientPicker.swift
//
// add-custom-ingredients-and-owner-supplements: choosing an ingredient for
// a product row. Replaces the product editor's old Picker, which listed
// only the 15 ingredients with an evidence card -- the owner could not
// enter a label with anything else ("I cannot add a custom ingredient and
// it was not in the suggestions").
//
// A searchable list: the user's own ingredients, then every known one
// (evidence-card ingredients and the label-only extras of
// IngredientCatalog), matched in English and Czech with diacritics
// ignored. When nothing has exactly the typed name, "Add “…” as your own
// ingredient" opens `CustomIngredientEditor` (name, unit incl. IU and ml,
// optional form), which saves it to the plan file at once, so it is
// found by the next search even if this product is never saved.
//
// Ranking, folding and duplicate names are FoodLogCore's
// (IngredientSearch, SupplementPlanStore.saveCustomIngredient) and tested
// there; this file only lays them out.
//
// Depends on: SupplementsController, FoodLogCore (IngredientSearch,
// CustomIngredient, DoseUnit). Depended on by: SupplementProductEditorView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementIngredientPicker: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    /// The row's current ingredient, checkmarked.
    var selected: IngredientID?
    let onPick: (IngredientChoice) -> Void

    @State private var query = ""
    @State private var isCreating = false

    private var supplements: SupplementsController { environment.supplements }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let choices = IngredientSearch.choices(for: query, custom: supplements.customIngredients)
        let own = choices.filter(\.isCustom)
        let known = choices.filter { !$0.isCustom }
        List {
            Section {
                if IngredientSearch.canCreate(query, custom: supplements.customIngredients) {
                    Button {
                        isCreating = true
                    } label: {
                        Label {
                            Text("Add “\(trimmedQuery)” as your own ingredient", comment: "Ingredient picker: create a custom ingredient with the typed name. %@ = the name.")
                        } icon: {
                            Image(systemName: "plus.circle")
                        }
                    }
                } else if trimmedQuery.isEmpty {
                    Button {
                        isCreating = true
                    } label: {
                        Label("Create your own ingredient", systemImage: "plus.circle")
                    }
                }
            } footer: {
                Text("Not in the list? Type its name and add it as your own.", comment: "Ingredient picker: footer under the create button.")
            }

            if !own.isEmpty {
                Section {
                    ForEach(own) { choice in row(choice) }
                } header: {
                    Text("Your ingredients")
                }
            }
            if !known.isEmpty {
                Section {
                    ForEach(known) { choice in row(choice) }
                } header: {
                    Text("Known ingredients")
                }
            }
        }
        .searchable(text: $query, prompt: Text("Search ingredients"))
        .navigationTitle("Choose ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .navigationDestination(isPresented: $isCreating) {
            CustomIngredientEditor(initialName: trimmedQuery) { saved in
                onPick(IngredientChoice(id: saved.id, name: saved.name, unit: saved.unit, isCustom: true, hasEvidence: false))
                dismiss()
            }
        }
    }

    private func row(_ choice: IngredientChoice) -> some View {
        Button {
            onPick(choice)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: choice.name)
                        .foregroundStyle(.primary)
                    if !choice.hasEvidence {
                        Text(choice.isCustom ? "Your own · no evidence card" : "Label only · no evidence card", comment: "Ingredient picker: this ingredient has no evidence card, so no limits or ranges are checked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(verbatim: choice.unit.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if choice.id == selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(choice.id == selected ? .isSelected : [])
    }
}

/// Creates a custom ingredient: its name, the unit its totals add up in
/// (mg, µg, g, IU or ml) and, optionally, the form printed on the label.
@MainActor
struct CustomIngredientEditor: View {
    @Environment(AppEnvironment.self) private var environment
    let onSaved: (CustomIngredient) -> Void

    @State private var name: String
    @State private var unit: DoseUnit = .mg
    @State private var form = ""
    @State private var isSaving = false

    init(initialName: String, onSaved: @escaping (CustomIngredient) -> Void) {
        self.onSaved = onSaved
        _name = State(initialValue: initialName)
    }

    private var canSave: Bool {
        !isSaving && CustomIngredient.make(name: name, unit: unit) != nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Unit", selection: $unit) {
                    ForEach(DoseUnit.pickable, id: \.self) { unit in
                        Text(verbatim: unit.symbol).tag(unit)
                    }
                }
                TextField(text: $form, prompt: Text("e.g. citrate, malate, MK-7", comment: "Custom ingredient editor: placeholder of the optional form field.")) {
                    Text("Form (optional)")
                }
                .textInputAutocapitalization(.never)
            } footer: {
                Text("Totals for this ingredient add up in the unit you pick. It stays on this phone and the search finds it next time.", comment: "Custom ingredient editor: footer.")
            }
        }
        .navigationTitle("New ingredient")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        isSaving = true
                        let saved = await environment.supplements.createCustomIngredient(name: name, unit: unit, form: form)
                        isSaving = false
                        if let saved { onSaved(saved) }
                    }
                }
                .disabled(!canSave)
            }
        }
    }
}

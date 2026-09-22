// MealPresetEditorView.swift
//
// The meal-preset editor: name, an ordered list of ingredients (each a
// food+serving+quantity, added via `FoodCatalogView(mode: .pickIngredient)`
// -- see that file's header), and a running nutrition total. Mirrors
// `CustomFoodEditorView`'s shape (task 15.1's precedent) but for N
// ingredients instead of one backing food.
//
// Also handles EDITING an existing preset (`existing:`), not just creating
// one -- there is no separate "edit" screen, per config.yaml's "small,
// composable views" principle: one form, two entry points.

import SwiftUI
import FoodLogCore

@MainActor
struct MealPresetEditorView: View {
    var existing: MealPreset?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var ingredients: [MealPresetIngredient]
    @State private var note: String
    @State private var isPresentingIngredientPicker = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    init(existing: MealPreset? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _ingredients = State(initialValue: existing?.ingredients ?? [])
        _note = State(initialValue: existing?.note ?? "")
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty
    }

    private var totals: MealPreset.Totals {
        MealPreset(id: UUID(), name: name, ingredients: ingredients).totals()
    }

    var body: some View {
        Form {
            Section("Meal") {
                TextField("Name (e.g. \"Breakfast bowl\")", text: $name)
            }

            Section {
                ForEach($ingredients) { $ingredient in
                    IngredientRow(ingredient: $ingredient)
                }
                .onDelete { ingredients.remove(atOffsets: $0) }

                Button {
                    isPresentingIngredientPicker = true
                } label: {
                    Label("Add ingredient", systemImage: "plus")
                }
            } header: {
                Text("Ingredients")
            } footer: {
                if ingredients.isEmpty {
                    Text("Add at least one ingredient -- each one logs as its own entry when you log this meal.")
                }
            }

            if !ingredients.isEmpty {
                Section("Total") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        MacroBadge(value: totals.calories, unit: " kcal", accessibleUnit: "kilocalories")
                    }
                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text("\(Int(totals.carbs.rounded())) g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(Int(totals.protein.rounded())) g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Fat")
                        Spacer()
                        Text("\(Int(totals.fat.rounded())) g").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Note") {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if let saveErrorMessage {
                Section {
                    Text(saveErrorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(existing == nil ? "New Meal" : "Edit Meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!isValid || isSaving)
            }
        }
        .sheet(isPresented: $isPresentingIngredientPicker) {
            NavigationStack {
                FoodCatalogView(mode: .pickIngredient(onPick: { food, serving, customFoodDraft in
                    ingredients.append(MealPresetIngredient(food: food, serving: serving, quantity: 1, customFoodDraft: customFoodDraft))
                }))
            }
        }
    }

    private func save() async {
        guard isValid else { return }
        isSaving = true
        defer { isSaving = false }

        let preset = MealPreset(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            ingredients: ingredients,
            note: note.isEmpty ? nil : note,
            createdAt: existing?.createdAt ?? Date()
        )

        do {
            try await environment.mealPresetStore.upsert(preset)
            dismiss()
        } catch {
            saveErrorMessage = "Couldn't save this meal. Try again."
        }
    }
}

/// One ingredient row: name/serving, and an editable quantity multiplier
/// (same meaning as everywhere else in this app -- a multiplier of the
/// shown serving, e.g. `1.5` x "100 g").
private struct IngredientRow: View {
    @Binding var ingredient: MealPresetIngredient

    @State private var quantityText: String = ""

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.food.name)
                    .font(.foodTitle)
                Text(ingredient.serving.displayLabel)
                    .font(.foodSubtitle)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.sm)
            TextField("1", text: $quantityText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)
                .onChange(of: quantityText) { _, newValue in
                    if let value = Double(newValue), value > 0 {
                        ingredient.quantity = value
                    }
                }
            Text("×")
                .foregroundStyle(.secondary)
            if let calories = ingredient.calories {
                MacroBadge(value: calories, unit: " kcal", accessibleUnit: "kilocalories")
            }
        }
        .onAppear {
            if quantityText.isEmpty {
                quantityText = ingredient.quantity.formattedQuantity
            }
        }
    }
}

private extension Double {
    var formattedQuantity: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(Int(self)) : String(format: "%.2f", self)
    }
}

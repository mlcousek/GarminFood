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
import GarminKit

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
    @State private var garminCustomMealId: Int?
    @State private var garminSyncedAt: Date?
    @State private var isSyncingToGarmin = false
    @State private var isConfirmingGarminSync = false
    @State private var garminSyncErrorMessage: String?

    init(existing: MealPreset? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _ingredients = State(initialValue: existing?.ingredients ?? [])
        _note = State(initialValue: existing?.note ?? "")
        _garminCustomMealId = State(initialValue: existing?.garminCustomMealId)
        _garminSyncedAt = State(initialValue: existing?.garminSyncedAt)
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

            if existing != nil, !ingredients.isEmpty {
                Section {
                    if let garminSyncedAt {
                        Label("Synced to Garmin \(garminSyncedAt.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if ingredients.contains(where: { $0.customFoodDraft != nil }) {
                        Text("This meal includes a custom food, which can't be synced to Garmin yet -- only real catalog/matched foods can.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            isConfirmingGarminSync = true
                        } label: {
                            if isSyncingToGarmin {
                                ProgressView()
                            } else {
                                Text(garminCustomMealId == nil ? "Sync to Garmin (experimental)" : "Re-sync to Garmin (experimental)")
                            }
                        }
                        .disabled(isSyncingToGarmin)
                    }
                    if let garminSyncErrorMessage {
                        Text(garminSyncErrorMessage).foregroundStyle(.red).font(.footnote)
                    }
                } header: {
                    Text("Garmin")
                } footer: {
                    Text("Creates this meal as a real, named meal in your Garmin account (an experimental, unconfirmed route -- see openspec/changes/sync-meal-presets-to-garmin). Logging this preset already works fully without this; this only makes Garmin's own app show it as one grouped meal too.")
                }
                .confirmationDialog(
                    "Send \(ingredients.count) ingredient\(ingredients.count == 1 ? "" : "s") to Garmin as \"\(name)\"?",
                    isPresented: $isConfirmingGarminSync,
                    titleVisibility: .visible
                ) {
                    Button("Sync") { Task { await syncToGarmin() } }
                } message: {
                    Text("This is an experimental, unconfirmed Garmin route -- it may fail. If it succeeds, it creates a new meal in your Garmin account; it never deletes or replaces anything there.")
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
            createdAt: existing?.createdAt ?? Date(),
            garminCustomMealId: garminCustomMealId,
            garminSyncedAt: garminSyncedAt
        )

        do {
            try await environment.mealPresetStore.upsert(preset)
            dismiss()
        } catch {
            saveErrorMessage = "Couldn't save this meal. Try again."
        }
    }

    /// The one explicit, user-triggered call to `GarminClient.
    /// createCustomMeal` for this preset -- never invoked automatically.
    /// Genuinely experimental: the route's request/response shape is
    /// unconfirmed (see `CreateCustomMealRequest`'s doc comment in
    /// GarminKit), so a failure here is expected as a real possibility, not
    /// a bug -- it's surfaced plainly and changes nothing else about the
    /// preset (logging it already works fully without this).
    private func syncToGarmin() async {
        guard let existing else { return }
        isSyncingToGarmin = true
        garminSyncErrorMessage = nil
        defer { isSyncingToGarmin = false }

        let items = ingredients.map { ingredient in
            CustomMealItemInput(
                foodId: ingredient.food.id,
                servingId: ingredient.serving.id,
                source: ingredient.food.source == .fatSecret ? "FATSECRET" : "GARMIN",
                // The quantity MULTIPLIER, matching `FoodLogWriteBody.Item.
                // servingQty`'s confirmed meaning on the food-log write --
                // NOT `serving.numberOfUnits * quantity` (the serving's own
                // absolute size is separate and already implied by
                // `servingId`).
                numberOfUnits: ingredient.quantity
            )
        }

        do {
            let result = try await environment.garminClient.createCustomMeal(name: name, items: items)
            garminCustomMealId = result.customMealId
            garminSyncedAt = Date()
            let preset = MealPreset(
                id: existing.id,
                name: name.trimmingCharacters(in: .whitespaces),
                ingredients: ingredients,
                note: note.isEmpty ? nil : note,
                createdAt: existing.createdAt,
                garminCustomMealId: garminCustomMealId,
                garminSyncedAt: garminSyncedAt
            )
            try? await environment.mealPresetStore.upsert(preset)
        } catch {
            DiagnosticsLog.log(.warning, category: "MealPresetEditorView", "createCustomMeal failed for preset=\(name): \(error)")
            garminSyncErrorMessage = "Couldn't sync to Garmin: this route is experimental and may not be supported. \(error)"
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

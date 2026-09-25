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
//
// add-standalone-mode D5 (task 3.4): in standalone mode ingredients may be
// of any origin (the ingredient picker already routes an Open Food Facts
// product straight to its serving picker there), the Garmin section ("Sync
// to Garmin") is hidden, and an ingredient that would stop the preset from
// being logged in the current mode (`MealPreset.blockingIngredients(in:)`)
// is named under the list. Garmin mode behaves as before.

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
        draftPreset.totals()
    }

    /// The preset as currently edited, for the pure FoodLogCore rules.
    private var draftPreset: MealPreset {
        MealPreset(id: existing?.id ?? UUID(), name: name, ingredients: ingredients)
    }

    private var dataMode: DataMode { environment.dataMode }

    /// Ingredients that stop this preset from being logged in the current
    /// mode, named in the list's footer (never silently skipped at log time).
    private var blockingIngredientsMessage: String? {
        let blocking = draftPreset.blockingIngredients(in: dataMode)
        guard !blocking.isEmpty else { return nil }
        let names = blocking.map(\.food.name).formatted(.list(type: .and))
        switch dataMode {
        case .standalone:
            return String(
                localized: "No calorie value: \(names). Remove it or add it as a custom food with its calories, or this meal can't be logged.",
                comment: "Meal editor, standalone mode. %@ is a list of ingredient names."
            )
        case .garminConnected:
            return String(
                localized: "Needs a Garmin match before this meal can be logged to Garmin: \(names).",
                comment: "Meal editor, Garmin mode. %@ is a list of ingredient names."
            )
        }
    }

    /// The Garmin-sync confirmation title. The count is its own plural
    /// phrase ("3 ingredients" / "3 suroviny"), never an `== 1 ?` suffix.
    private var garminSyncConfirmationTitle: String {
        let count = String(localized: "\(ingredients.count) ingredients", comment: "Number of ingredients in a saved meal. Plural.")
        return String(
            localized: "Send \(count) to Garmin as \"\(name)\"?",
            comment: "Confirmation title. First %@ is a counted phrase like '3 ingredients', second the meal's name."
        )
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
                } else if let blockingIngredientsMessage {
                    Text(blockingIngredientsMessage)
                        .foregroundStyle(Theme.danger)
                }
            }

            if !ingredients.isEmpty {
                Section("Total") {
                    HStack {
                        Text("Calories")
                        Spacer()
                        MacroBadge.calories(totals.calories)
                    }
                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text("\(totals.carbs.wholeNumberText) g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(totals.protein.wholeNumberText) g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Fat")
                        Spacer()
                        Text("\(totals.fat.wholeNumberText) g").foregroundStyle(.secondary)
                    }
                }
            }

            // add-standalone-mode: Garmin-only, hidden in standalone mode.
            if existing != nil, !ingredients.isEmpty, dataMode == .garminConnected {
                Section {
                    if let garminSyncedAt {
                        Label("Synced to Garmin \(garminSyncedAt.formatted(.relative(presentation: .named)))", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !draftPreset.offersGarminSync(in: dataMode) {
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
                                if garminCustomMealId == nil {
                                    Text("Sync to Garmin (experimental)")
                                } else {
                                    Text("Re-sync to Garmin (experimental)")
                                }
                            }
                        }
                        .disabled(isSyncingToGarmin)
                    }
                    if let garminSyncErrorMessage {
                        Text(garminSyncErrorMessage).foregroundStyle(Theme.danger).font(.footnote)
                    }
                } header: {
                    Text("Garmin")
                } footer: {
                    // User-facing: the route's design notes live in
                    // openspec/changes/sync-meal-presets-to-garmin.
                    Text("Creates this meal as a real, named meal in your Garmin account, using an experimental, unconfirmed Garmin route. Logging this meal already works fully without it; this only makes Garmin's own app show it as one grouped meal too.")
                }
                .confirmationDialog(
                    garminSyncConfirmationTitle,
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
                    Text(saveErrorMessage).foregroundStyle(Theme.danger)
                }
            }
        }
        .navigationTitle(existing == nil ? String(localized: "New Meal") : String(localized: "Edit Meal"))
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
                FoodCatalogView(mode: .pickIngredient(onPick: { food, serving, customFoodDraft, quantity in
                    ingredients.append(MealPresetIngredient(food: food, serving: serving, quantity: quantity, customFoodDraft: customFoodDraft))
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
            saveErrorMessage = String(localized: "Couldn't save this meal. Try again.")
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
            garminSyncErrorMessage = String(
                localized: "Couldn't sync to Garmin: this route is experimental and may not be supported. \(error.localizedDescription)",
                comment: "Error under the experimental meal sync. %@ is the underlying error's description."
            )
        }
    }
}

/// One ingredient row: name/serving, and an editable quantity. The stored
/// `ingredient.quantity` is a multiplier of the shown serving (same meaning
/// as everywhere else in this app, e.g. `1.5` x "100 g"), but for a serving
/// with a known gram/ml size it is TYPED in grams by default
/// (amount-in-grams) -- the same `ServingQuantityInput` rules and
/// remembered `AppPreferences.quantityInputMode` as `ServingQuantityField`,
/// in a compact row layout: tapping the "g"/"×" label switches the mode.
/// Text that isn't a valid amount is ignored (the last valid quantity
/// stays), as before.
private struct IngredientRow: View {
    @Binding var ingredient: MealPresetIngredient

    @Environment(AppEnvironment.self) private var environment
    @State private var quantityText: String = ""
    /// The text this row last wrote itself and the exact quantity it stands
    /// for, so re-showing a quantity never nudges it by display rounding.
    @State private var writtenText: String?
    @State private var writtenQuantity: Double?

    private var input: ServingQuantityInput { ServingQuantityInput(serving: ingredient.serving) }
    private var mode: QuantityInputMode { input.resolvedMode(environment.preferences.quantityInputMode) }

    private var unitLabel: String {
        if mode == .amount, let size = input.size { return size.unit.symbol }
        return "×"
    }

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
            TextField(mode == .amount ? "100" : "1", text: $quantityText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .onChange(of: quantityText) { _, newValue in
                    if newValue == writtenText {
                        if let writtenQuantity, writtenQuantity != ingredient.quantity {
                            ingredient.quantity = writtenQuantity
                        }
                        return
                    }
                    // `DecimalInput` inside: accepts the Czech comma ("0,5").
                    if let value = input.quantity(fromText: newValue, mode: mode) {
                        ingredient.quantity = value
                    }
                }
            if input.offersModeChoice {
                Button(unitLabel) {
                    environment.preferences.quantityInputMode = mode == .amount ? .servings : .amount
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(mode == .amount ? String(localized: "Grams or millilitres. Switch to servings") : String(localized: "Servings. Switch to grams or millilitres"))
            } else {
                Text(unitLabel)
                    .foregroundStyle(.secondary)
            }
            if let calories = ingredient.calories {
                MacroBadge.calories(calories)
            }
        }
        .onAppear {
            if quantityText.isEmpty {
                writeQuantityText()
            }
        }
        .onChange(of: mode) { _, _ in
            writeQuantityText()
        }
    }

    private func writeQuantityText() {
        let value = ingredient.quantity
        let text = input.text(forQuantity: value, mode: mode, decimalSeparator: Locale.current.decimalSeparator ?? ".")
        writtenText = text
        writtenQuantity = value
        quantityText = text
    }
}

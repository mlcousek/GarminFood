// CustomFoodEditorView.swift
//
// The custom-food editor (task 15.1, food-catalog spec's "Creating a custom
// food" scenario): name, serving unit, quantity, and the macro fields a
// logged entry needs. Per design.md D4's fallback path (implemented in
// `CustomFoodDraft`, see FoodLogCore/CustomFood.swift's header for why),
// saving REQUIRES picking the closest existing Garmin food -- without one,
// there is nothing this project can ever hand to `Outbox`, so the form
// can't be submitted until that choice is made, and this is stated plainly
// in the UI rather than discovered only after tapping Save.

import SwiftUI
import FoodLogCore

@MainActor
struct CustomFoodEditorView: View {
    var prefillNote: String?

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brandName = ""
    @State private var servingUnit = "serving"
    @State private var numberOfUnits = "1"
    @State private var calories = ""
    @State private var carbs = ""
    @State private var protein = ""
    @State private var fat = ""
    @State private var sugar = ""
    @State private var sodium = ""
    @State private var note = ""

    @State private var backingFood: Food?
    @State private var backingServing: Serving?
    @State private var backingMultiplier = "1"
    @State private var isPresentingBackingFoodPicker = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    /// Every number here goes through `DecimalInput.parse` (FoodLogCore), so
    /// a Czech decimal comma ("0,5") is accepted rather than rejected.
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedPositive(numberOfUnits) != nil
            && backingFood != nil
            && backingServing != nil
            && parsedPositive(backingMultiplier) != nil
            && macroFieldsAreValid
    }

    /// A macro field may be left empty (the nutrient is then unknown, not
    /// zero), but anything typed must be a real, non-negative number --
    /// otherwise it used to be dropped silently on save.
    private var macroFieldsAreValid: Bool {
        [calories, carbs, protein, fat, sugar, sodium].allSatisfy { text in
            text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || macroValue(text) != nil
        }
    }

    /// A serving size or multiplier: positive and within `LogQuantity`'s
    /// bound, so the serving label and the backing amount stay sane.
    private func parsedPositive(_ text: String) -> Double? {
        guard let value = DecimalInput.parse(text), LogQuantity.isValid(value) else { return nil }
        return value
    }

    private func macroValue(_ text: String) -> Double? {
        guard let value = DecimalInput.parse(text), value >= 0 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $name)
                TextField("Brand (optional)", text: $brandName)
                TextField("Serving unit (e.g. \"bowl\", \"slice\")", text: $servingUnit)
                TextField("Number of units", text: $numberOfUnits)
                    .keyboardType(.decimalPad)
            }

            Section("Nutrition (per serving)") {
                macroField("Calories (kcal)", text: $calories)
                macroField("Carbs (g)", text: $carbs)
                macroField("Protein (g)", text: $protein)
                macroField("Fat (g)", text: $fat)
                macroField("Sugar (g)", text: $sugar)
                macroField("Sodium (mg)", text: $sodium)
            }

            Section {
                Button {
                    isPresentingBackingFoodPicker = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Closest match in Garmin")
                                .foregroundStyle(.primary)
                            if let backingFood, let backingServing {
                                Text("\(backingFood.name) · \(backingServing.displayLabel)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Required — pick one")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.warning)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                if backingFood != nil {
                    HStack {
                        Text("Quantity multiplier")
                        Spacer()
                        TextField("1", text: $backingMultiplier)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }
            } header: {
                Text("Since custom-food creation isn't confirmed possible via Garmin's private API yet, this food will actually be logged as the Garmin food you pick here, scaled by the multiplier.")
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
        .navigationTitle("New Custom Food")
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
        .sheet(isPresented: $isPresentingBackingFoodPicker) {
            NavigationStack {
                FoodCatalogView(mode: .pickBackingFood(onPick: { food, serving in
                    backingFood = food
                    backingServing = serving
                }))
            }
        }
        .onAppear {
            if let prefillNote, note.isEmpty {
                note = prefillNote
            }
        }
    }

    /// `title` is a `LocalizedStringKey`, so each literal call site
    /// ("Carbs (g)") is a catalog key.
    @ViewBuilder
    private func macroField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
        }
    }

    private func save() async {
        guard isValid, let backingFood, let backingServing, let quantity = parsedPositive(numberOfUnits), let multiplier = parsedPositive(backingMultiplier) else { return }
        isSaving = true
        defer { isSaving = false }

        let draft = CustomFoodDraft(
            name: name.trimmingCharacters(in: .whitespaces),
            brandName: brandName.isEmpty ? nil : brandName,
            servingUnit: servingUnit.isEmpty ? "serving" : servingUnit,
            numberOfUnits: quantity,
            calories: macroValue(calories),
            carbs: macroValue(carbs),
            protein: macroValue(protein),
            fat: macroValue(fat),
            sugar: macroValue(sugar),
            sodium: macroValue(sodium),
            backingFoodId: backingFood.id,
            backingFoodName: backingFood.name,
            backingServingId: backingServing.id,
            backingQuantityMultiplier: multiplier,
            note: note.isEmpty ? nil : note,
            backingRegionCode: backingFood.regionCode,
            backingLanguageCode: backingFood.languageCode
        )

        do {
            try await environment.customFoodStore.upsert(draft)
            await environment.foodCache.upsert([draft.asFood()])
            dismiss()
        } catch {
            saveErrorMessage = String(localized: "Couldn't save this custom food. Try again.")
        }
    }
}

// No #Preview here: this view requires a live `AppEnvironment` injected via
// `.environment(_:)` (it owns real GarminKit/FoodLogCore state -- Keychain,
// an outbox file, etc.), which isn't something worth constructing just for
// a preview that can't actually be opened and inspected in this project
// today anyway (design.md's "no Mac" constraint -- see the top-level
// report for what genuinely could and couldn't be verified).

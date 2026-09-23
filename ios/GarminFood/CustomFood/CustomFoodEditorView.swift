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

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && Double(numberOfUnits) != nil
            && backingFood != nil
            && backingServing != nil
            && Double(backingMultiplier) != nil
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
                    Text(saveErrorMessage).foregroundStyle(.red)
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

    @ViewBuilder
    private func macroField(_ title: String, text: Binding<String>) -> some View {
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
        guard let backingFood, let backingServing, let quantity = Double(numberOfUnits), let multiplier = Double(backingMultiplier) else { return }
        isSaving = true
        defer { isSaving = false }

        let draft = CustomFoodDraft(
            name: name.trimmingCharacters(in: .whitespaces),
            brandName: brandName.isEmpty ? nil : brandName,
            servingUnit: servingUnit.isEmpty ? "serving" : servingUnit,
            numberOfUnits: quantity,
            calories: Double(calories),
            carbs: Double(carbs),
            protein: Double(protein),
            fat: Double(fat),
            sugar: Double(sugar),
            sodium: Double(sodium),
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
            saveErrorMessage = "Couldn't save this custom food. Try again."
        }
    }
}

// No #Preview here: this view requires a live `AppEnvironment` injected via
// `.environment(_:)` (it owns real GarminKit/FoodLogCore state -- Keychain,
// an outbox file, etc.), which isn't something worth constructing just for
// a preview that can't actually be opened and inspected in this project
// today anyway (design.md's "no Mac" constraint -- see the top-level
// report for what genuinely could and couldn't be verified).

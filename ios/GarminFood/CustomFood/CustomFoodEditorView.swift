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
//
// add-standalone-mode D5 (task 3.3), gated on the effective data mode so
// Garmin mode looks and behaves exactly as before:
//   - standalone: no "closest Garmin food" section at all -- the food is
//     logged as itself -- and calories are required instead (a food without
//     them can't be logged there, see NutritionCompleteness). A barcode field
//     appears, pre-filled when opened from an unknown scan (task 3.5).
//   - Garmin mode, `existing:` a food created without Garmin (after a mode
//     switch): the same form, pre-filled, with the backing picker required
//     -- "Needs a Garmin match" on the confirm screen opens this. Saving
//     keeps the food's id, so its usage history and favorites stay attached.

import SwiftUI
import FoodLogCore

@MainActor
struct CustomFoodEditorView: View {
    /// Edit this food instead of creating a new one (same id on save).
    var existing: CustomFoodDraft?
    var prefillNote: String?
    /// add-standalone-mode D5: a catalog product that can't be logged
    /// (no calories) starts a custom food under its own name and brand.
    var prefillName: String?
    var prefillBrand: String?
    /// add-standalone-mode 3.5: an unknown scanned barcode (standalone).
    var prefillBarcode: String?
    /// Called with the saved food, before the sheet dismisses.
    var onSaved: ((CustomFoodDraft) -> Void)?

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
    @State private var barcode = ""
    @State private var didPrefill = false

    @State private var backing: BackingChoice?
    @State private var backingMultiplier = "1"
    @State private var isPresentingBackingFoodPicker = false
    @State private var isSaving = false
    @State private var saveErrorMessage: String?

    /// The Garmin food+serving a custom food logs as in Garmin mode: picked
    /// here, or carried over from `existing` (whose serving label isn't
    /// stored, hence optional).
    private struct BackingChoice {
        let foodId: String
        let foodName: String
        let servingId: String
        let servingLabel: String?
        let regionCode: String?
        let languageCode: String?
    }

    private var isStandalone: Bool { environment.dataMode == .standalone }

    /// Every number here goes through `DecimalInput.parse` (FoodLogCore), so
    /// a Czech decimal comma ("0,5") is accepted rather than rejected.
    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              parsedPositive(numberOfUnits) != nil,
              macroFieldsAreValid
        else { return false }
        if isStandalone {
            // Logged as itself: its own calories are what count.
            return macroValue(calories) != nil
        }
        return backing != nil && parsedPositive(backingMultiplier) != nil
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

            if isStandalone {
                Section {
                    macroField("Calories (kcal)", text: $calories)
                    macroField("Carbs (g)", text: $carbs)
                    macroField("Protein (g)", text: $protein)
                    macroField("Fat (g)", text: $fat)
                    macroField("Sugar (g)", text: $sugar)
                    macroField("Sodium (mg)", text: $sodium)
                } header: {
                    Text("Nutrition (per serving)")
                } footer: {
                    Text(String(localized: "Calories are required; leave anything else you don't know empty."))
                }

                Section {
                    TextField(String(localized: "Barcode (optional)"), text: $barcode)
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())
                } footer: {
                    Text(String(localized: "Scanning this barcode later finds this food."))
                }
            } else {
                Section("Nutrition (per serving)") {
                    macroField("Calories (kcal)", text: $calories)
                    macroField("Carbs (g)", text: $carbs)
                    macroField("Protein (g)", text: $protein)
                    macroField("Fat (g)", text: $fat)
                    macroField("Sugar (g)", text: $sugar)
                    macroField("Sodium (mg)", text: $sodium)
                }

                garminBackingSection
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
        .navigationTitle(existing == nil ? String(localized: "New Custom Food") : String(localized: "Edit Custom Food"))
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
                    backing = BackingChoice(
                        foodId: food.id,
                        foodName: food.name,
                        servingId: serving.id,
                        servingLabel: serving.displayLabel,
                        regionCode: food.regionCode,
                        languageCode: food.languageCode
                    )
                }))
            }
        }
        .onAppear(perform: prefillOnce)
    }

    /// Garmin mode only: the closest Garmin food this custom food logs as.
    private var garminBackingSection: some View {
        Section {
            Button {
                isPresentingBackingFoodPicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Closest match in Garmin")
                            .foregroundStyle(.primary)
                        if let backing {
                            if let servingLabel = backing.servingLabel {
                                Text("\(backing.foodName) · \(servingLabel)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(backing.foodName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
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
            if backing != nil {
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

    /// Fills the form once: from `existing` when editing, then any prefill
    /// the caller passed (never over something already typed).
    private func prefillOnce() {
        guard !didPrefill else { return }
        didPrefill = true
        if let existing {
            name = existing.name
            brandName = existing.brandName ?? ""
            servingUnit = existing.servingUnit
            numberOfUnits = Self.text(existing.numberOfUnits)
            calories = existing.calories.map(Self.text) ?? ""
            carbs = existing.carbs.map(Self.text) ?? ""
            protein = existing.protein.map(Self.text) ?? ""
            fat = existing.fat.map(Self.text) ?? ""
            sugar = existing.sugar.map(Self.text) ?? ""
            sodium = existing.sodium.map(Self.text) ?? ""
            note = existing.note ?? ""
            barcode = existing.barcode ?? ""
            backingMultiplier = Self.text(existing.backingQuantityMultiplier)
            if let foodId = existing.backingFoodId, let servingId = existing.backingServingId, existing.hasGarminBacking {
                backing = BackingChoice(
                    foodId: foodId,
                    foodName: existing.backingFoodName ?? foodId,
                    servingId: servingId,
                    servingLabel: nil,
                    regionCode: existing.backingRegionCode,
                    languageCode: existing.backingLanguageCode
                )
            }
        }
        if let prefillNote, note.isEmpty {
            note = prefillNote
        }
        if let prefillName, name.isEmpty {
            name = prefillName
        }
        if let prefillBrand, brandName.isEmpty {
            brandName = prefillBrand
        }
        if let prefillBarcode, barcode.isEmpty {
            barcode = prefillBarcode
        }
    }

    /// A stored number back into the text field ("0.5", "280").
    private static func text(_ value: Double) -> String {
        NumberDisplay.quantity(value, fractionDigits: 2)
    }

    private func save() async {
        guard isValid, let quantity = parsedPositive(numberOfUnits) else { return }
        // Garmin mode needs its backing; standalone keeps whatever an
        // existing food already had (it is never shown or changed there).
        if !isStandalone, backing == nil { return }
        let multiplier = isStandalone
            ? (existing?.backingQuantityMultiplier ?? 1)
            : (parsedPositive(backingMultiplier) ?? 1)
        isSaving = true
        defer { isSaving = false }

        let trimmedBarcode = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = CustomFoodDraft(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            brandName: brandName.isEmpty ? nil : brandName,
            servingUnit: servingUnit.isEmpty ? "serving" : servingUnit,
            numberOfUnits: quantity,
            calories: macroValue(calories),
            carbs: macroValue(carbs),
            protein: macroValue(protein),
            fat: macroValue(fat),
            fiber: existing?.fiber,
            sugar: macroValue(sugar),
            saturatedFat: existing?.saturatedFat,
            sodium: macroValue(sodium),
            createdAt: existing?.createdAt ?? Date(),
            backingFoodId: backing?.foodId,
            backingFoodName: backing?.foodName,
            backingServingId: backing?.servingId,
            backingQuantityMultiplier: multiplier,
            note: note.isEmpty ? nil : note,
            backingRegionCode: backing?.regionCode,
            backingLanguageCode: backing?.languageCode,
            barcode: trimmedBarcode.isEmpty ? nil : trimmedBarcode
        )

        do {
            try await environment.customFoodStore.upsert(draft)
            await environment.foodCache.upsert([draft.asFood()])
            onSaved?(draft)
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

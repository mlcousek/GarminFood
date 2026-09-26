// SupplementProductEditorView.swift
//
// add-supplements task 3.2: add or edit one product -- the label (name,
// brand, form, serving, ingredients with amounts and units, magnesium's
// form), when to take it (`SupplementScheduleEditor`), the pack (servings,
// price, stock on hand) and certifications the user checked themselves
// (design D7: a manual badge with a date; the app never claims one).
//
// A catalog product opens prefilled with its label and suggested slot
// (`CatalogProduct.makeProduct`/`suggestedSchedule`); every amount stays
// editable, since labels differ between brands. Schedule changes apply from
// today on (design D3); saving without touching the schedule leaves it as
// it is. Setting the stock records today as the pack's start
// (`SupplementProduct.setStock`, D14), so earlier ticks don't drain it.
//
// Depends on: SupplementsController, SupplementScheduleEditor, FoodLogCore
// (SupplementProduct, IngredientAmount, SupplementCatalog).
// Depended on by: SupplementStackView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementProductEditorView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let request: SupplementEditorRequest

    @State private var product: SupplementProduct?
    @State private var schedule = ScheduleDraft()
    @State private var originalSchedule = ScheduleDraft()
    @State private var isInStack = true
    @State private var stockText = ""
    @State private var originalStockText = ""
    @State private var packText = ""
    @State private var priceText = ""
    @State private var isScanning = false
    @State private var isLookingUp = false
    @State private var lookupMessage: String?

    private var supplements: SupplementsController { environment.supplements }

    var body: some View {
        Form {
            if let binding = Binding($product) {
                labelSection(binding)
                ingredientsSection(binding)

                Section {
                    Toggle("Planned", isOn: $isInStack)
                } footer: {
                    Text("Turn off to stop taking it from today. Past days keep their plan.", comment: "Supplement editor: the Planned toggle.")
                }
                if isInStack {
                    SupplementScheduleEditor(draft: $schedule, hasTrainingData: environment.dataMode != .standalone)
                }

                packSection(binding)
                certificationSection(binding)

                Section {
                    TextField("Notes", text: Binding(
                        get: { binding.wrappedValue.notes ?? "" },
                        set: { binding.wrappedValue.notes = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
    }

    private var title: String {
        switch request {
        case .existing: return String(localized: "Edit supplement")
        case .catalog, .custom: return String(localized: "New supplement")
        }
    }

    private var canSave: Bool {
        guard let product else { return false }
        return !product.name.trimmingCharacters(in: .whitespaces).isEmpty && (!isInStack || !schedule.slots.isEmpty)
    }

    // MARK: - Sections

    private func labelSection(_ product: Binding<SupplementProduct>) -> some View {
        Section {
            TextField("Name", text: product.name)
            TextField("Brand", text: Binding(
                get: { product.wrappedValue.brand ?? "" },
                set: { product.wrappedValue.brand = $0.isEmpty ? nil : $0 }
            ))
            Picker("Form", selection: Binding(
                get: { product.wrappedValue.form ?? .capsule },
                set: { product.wrappedValue.form = $0 }
            )) {
                ForEach([ProductForm.capsule, .tablet, .powder, .liquid, .gummy], id: \.self) { form in
                    Text(Self.formName(form)).tag(form)
                }
            }
            TextField("Serving (e.g. 2 capsules)", text: Binding(
                get: { product.wrappedValue.servingDescription ?? "" },
                set: { product.wrappedValue.servingDescription = $0.isEmpty ? nil : $0 }
            ))
            barcodeRow(product)
        } header: {
            Text("Label")
        } footer: {
            if let lookupMessage {
                Text(verbatim: lookupMessage)
            }
        }
        .sheet(isPresented: $isScanning) {
            NavigationStack {
                Group {
                    if BarcodeScannerAvailability.isSupported, BarcodeScannerAvailability.isAvailable {
                        BarcodeScannerRepresentable { code in
                            isScanning = false
                            product.wrappedValue.barcode = code
                            Task { await lookUp(code, into: product) }
                        }
                        .ignoresSafeArea()
                    } else {
                        Text("The camera can't scan barcodes on this device. Type the number instead.", comment: "Supplement editor: scanner unavailable.")
                            .padding()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isScanning = false }
                    }
                }
            }
        }
    }

    /// add-supplements 5.3: the barcode, a scan button, and "Look up",
    /// which prefills what the label databases know. The user confirms
    /// every amount (design D7); a miss just means typing it in.
    private func barcodeRow(_ product: Binding<SupplementProduct>) -> some View {
        HStack {
            TextField("Barcode", text: Binding(
                get: { product.wrappedValue.barcode ?? "" },
                set: { product.wrappedValue.barcode = $0.isEmpty ? nil : $0 }
            ))
            .keyboardType(.numberPad)
            Button {
                isScanning = true
            } label: {
                Image(systemName: "barcode.viewfinder")
            }
            .accessibilityLabel(Text("Scan barcode"))
            Button {
                guard let code = product.wrappedValue.barcode else { return }
                Task { await lookUp(code, into: product) }
            } label: {
                if isLookingUp {
                    ProgressView()
                } else {
                    Text("Look up")
                }
            }
            .disabled(isLookingUp || (product.wrappedValue.barcode ?? "").count < 8)
        }
        .buttonStyle(.borderless)
    }

    private func lookUp(_ code: String, into product: Binding<SupplementProduct>) async {
        isLookingUp = true
        defer { isLookingUp = false }
        guard let result = await supplements.barcodeLookup.lookup(code) else {
            lookupMessage = String(localized: "Not found in the label databases. Type the label in.", comment: "Supplement editor: barcode lookup found nothing (or no connection).")
            return
        }
        // Fill only what's still empty; the user's own text wins.
        if product.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty {
            product.wrappedValue.name = result.name
        }
        if product.wrappedValue.brand == nil { product.wrappedValue.brand = result.brand }
        if product.wrappedValue.servingDescription == nil { product.wrappedValue.servingDescription = result.servingDescription }
        if product.wrappedValue.ingredients.isEmpty { product.wrappedValue.ingredients = result.ingredients }
        if case .custom = product.wrappedValue.source {
            product.wrappedValue.source = .barcode(result.provider.rawValue)
        }
        lookupMessage = result.ingredients.isEmpty
            ? String(localized: "Name and brand filled in. Copy the amounts from your label.", comment: "Supplement editor: barcode lookup found the product but no amounts.")
            : String(localized: "Filled in from the label database. Check every amount against your label.", comment: "Supplement editor: barcode lookup found amounts (US database).")
    }

    private func ingredientsSection(_ product: Binding<SupplementProduct>) -> some View {
        Section {
            ForEach(product.wrappedValue.ingredients.indices, id: \.self) { index in
                // Rows are addressed by index and keep their own text state,
                // so they are rebuilt whenever the list changes length --
                // otherwise deleting a row leaves the next one showing the
                // deleted row's amount.
                IngredientRowEditor(row: product.ingredients[index])
                    .id("\(index)-\(product.wrappedValue.ingredients.count)")
            }
            .onDelete { offsets in
                product.wrappedValue.ingredients.remove(atOffsets: offsets)
            }
            Button {
                product.wrappedValue.ingredients.append(IngredientAmount(ingredient: .magnesium, amount: nil, unit: IngredientID.magnesium.canonicalUnit))
            } label: {
                Label("Add ingredient", systemImage: "plus")
            }
        } header: {
            Text("Per serving")
        } footer: {
            Text("Copy the amounts from your label. They drive the totals, limits and label score.", comment: "Supplement editor: footer under the ingredient rows.")
        }
    }

    private func packSection(_ product: Binding<SupplementProduct>) -> some View {
        Section {
            numberField("Servings per pack", text: $packText)
            numberField("Price per pack", text: $priceText, suffix: product.wrappedValue.effectiveCurrency)
            numberField("Servings left now", text: $stockText)
        } header: {
            Text("Pack and stock")
        } footer: {
            Text("With stock set, GarminFood counts it down as you tick and reminds you a week before it runs out.", comment: "Supplement editor: footer under pack and stock.")
        }
    }

    private func certificationSection(_ product: Binding<SupplementProduct>) -> some View {
        Section {
            ForEach([CertificationBody.nsfCertifiedForSport, .informedSport, .koelnerListe], id: \.self) { body in
                Toggle(isOn: Binding(
                    get: { product.wrappedValue.certifications?.contains { $0.body == body } ?? false },
                    set: { isOn in
                        var list = product.wrappedValue.certifications ?? []
                        list.removeAll { $0.body == body }
                        if isOn { list.append(Certification(body: body, checkedOn: supplements.today)) }
                        product.wrappedValue.certifications = list.isEmpty ? nil : list
                    }
                )) {
                    Text(verbatim: SupplementCertificationLinks.name(body))
                }
            }
        } header: {
            Text("Certification you checked")
        } footer: {
            Text("Certification is per batch. Tick one only after finding your product on the certifier's own site (Evidence › Verify certification).", comment: "Supplement editor: footer under the manual certification toggles.")
        }
    }

    private func numberField(_ title: LocalizedStringKey, text: Binding<String>, suffix: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(text: text, prompt: Text(verbatim: "–")) { Text(title) }
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            if let suffix {
                Text(verbatim: suffix).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Load and save

    private func load() {
        guard product == nil else { return }
        switch request {
        case .existing(let id):
            guard let existing = supplements.product(id) else { return }
            product = existing
            let current = supplements.plan.schedule(of: id, on: supplements.today)
            isInStack = current != nil
            schedule = current.map { ScheduleDraft($0) } ?? ScheduleDraft()
            stockText = supplements.remainingServings(existing).map { Self.text($0) } ?? ""
            packText = existing.packServings.map { Self.text($0) } ?? ""
            priceText = existing.pricePerPack.map { Self.text($0) } ?? ""
        case .catalog(let id):
            guard let catalog = SupplementCatalog.product(id: id) else { return }
            product = catalog.makeProduct()
            schedule = ScheduleDraft(catalog.suggestedSchedule)
        case .custom:
            product = SupplementProduct(name: "", form: .capsule, ingredients: [], source: .custom)
            schedule = ScheduleDraft(SupplementSchedule(slots: [.morning]))
        }
        originalSchedule = schedule
        originalStockText = stockText
        if case .existing = request {} else {
            // A new product always writes its schedule.
            originalSchedule = ScheduleDraft(slots: [], servingsPerSlot: 0)
        }
    }

    private func save() async {
        guard var product else { return }
        product.name = product.name.trimmingCharacters(in: .whitespaces)
        product.packServings = Self.number(packText)
        product.pricePerPack = Self.number(priceText)
        let wasInStack: Bool = {
            if case .existing(let id) = request { return supplements.plan.schedule(of: id, on: supplements.today) != nil }
            return false
        }()
        let newSchedule = isInStack ? schedule.schedule(anchor: supplements.today) : nil
        let scheduleChanged = isInStack != wasInStack || (isInStack && schedule != originalSchedule)
        await supplements.save(product, schedule: newSchedule, updateSchedule: scheduleChanged)
        if stockText != originalStockText, let stock = Self.number(stockText) {
            await supplements.setStock(product.id, servingsOnHand: stock)
        }
        dismiss()
    }

    // MARK: - Formatting

    static func formName(_ form: ProductForm) -> String {
        switch form {
        case .capsule: return String(localized: "Capsule")
        case .tablet: return String(localized: "Tablet")
        case .powder: return String(localized: "Powder")
        case .liquid: return String(localized: "Liquid")
        case .gummy: return String(localized: "Gummy")
        default: return form.rawValue
        }
    }

    static func text(_ value: Double) -> String {
        SupplementFormat.servings(value)
    }

    /// Reads "2,5" and "2.5" alike.
    static func number(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

/// One ingredient row: which ingredient, the amount and unit, and for
/// magnesium its form (the EU limit applies to some salts, design D2).
private struct IngredientRowEditor: View {
    @Binding var row: IngredientAmount
    @State private var amountText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Picker("Ingredient", selection: $row.ingredient) {
                ForEach(IngredientID.builtIn, id: \.self) { ingredient in
                    Text(verbatim: EvidenceCatalog.name(of: ingredient)).tag(ingredient)
                }
            }
            HStack {
                TextField(text: $amountText, prompt: Text("Amount")) { Text("Amount") }
                    .keyboardType(.decimalPad)
                    .onChange(of: amountText) { _, text in
                        row.amount = SupplementProductEditorView.number(text)
                    }
                Picker("Unit", selection: $row.unit) {
                    ForEach(units, id: \.self) { unit in
                        Text(verbatim: unit.symbol).tag(unit)
                    }
                }
                .labelsHidden()
            }
            if row.ingredient == .magnesium {
                Picker("Form", selection: Binding(
                    get: { row.form ?? "" },
                    set: { row.form = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Not stated").tag("")
                    ForEach([MagnesiumForm.citrate, .bisglycinate, .oxide, .malate, .lactate, .chloride, .carbonate, .glycerophosphate, .threonate, .aspartate], id: \.rawValue) { form in
                        Text(verbatim: form.rawValue).tag(form.rawValue)
                    }
                }
            }
        }
        .onAppear {
            amountText = row.amount.map { SupplementFormat.servings($0) } ?? ""
        }
        .onChange(of: row.ingredient) { _, ingredient in
            // A new ingredient starts in its own unit (IU only for vitamin D).
            if !units.contains(row.unit) { row.unit = ingredient.canonicalUnit }
        }
    }

    private var units: [DoseUnit] {
        row.ingredient == .vitaminD ? [.ug, .iu, .mg] : [.g, .mg, .ug]
    }
}

// ServingQuantityField.swift
//
// The quantity input shared by the log confirm screen and the Edit entry
// sheet (amount-in-grams). Owner report 2026-09-24: for a "100g" x 1
// serving the field wanted "1,5" for 150 g, while a "g" x 100 serving took
// "150" -- the same 100 g of food, two input conventions. This field lets
// any serving with a known gram/ml size be typed in g/ml ("150"), with a
// "g | Servings" switch remembered in `AppPreferences.quantityInputMode`;
// a 1 g/1 ml serving is always typed in grams (the multiplier already is
// the gram amount); a serving with no metric size ("1 medium") stays
// servings-only, as before.
//
// All conversion/validation is `ServingQuantityInput` (FoodLogCore,
// unit-tested in ServingAmountTests); this view only holds the text. The
// bound `quantity` is ALWAYS the multiplier sent to Garmin as `servingQty`
// (`nil` while the text is not a valid amount), so no caller's confirm/save
// path changes. Parsing goes through `DecimalInput`, so the Czech decimal
// comma works, and updates on every keystroke so the caller's kcal preview
// is live (a `TextField(value:format:)` only committed on Return).
//
// The meal-preset ingredient row uses the same `ServingQuantityInput`
// rules in its own compact layout (MealPresetEditorView.swift).

import SwiftUI
import FoodLogCore

@MainActor
struct ServingQuantityField: View {
    /// The serving `quantity` multiplies; `nil` = unknown (servings only).
    let serving: Serving?
    /// The multiplier of `serving`; `nil` while the text isn't a valid one.
    @Binding var quantity: Double?
    var isFocused: FocusState<Bool>.Binding
    /// Shown after "×" in servings mode when `serving` is unknown (the Edit
    /// sheet's read-back description).
    var fallbackServingLabel: String? = nil
    /// +/- buttons (10 g, or half a serving).
    var showsStepper: Bool = false

    @Environment(AppEnvironment.self) private var environment
    @State private var text = ""
    /// The text this view last wrote itself and the exact quantity it
    /// stands for -- so re-showing a stored quantity (e.g. Garmin's float32
    /// 0.699999988) never nudges it by the display rounding.
    @State private var writtenText: String?
    @State private var writtenQuantity: Double?
    @State private var didLoad = false

    private var input: ServingQuantityInput { ServingQuantityInput(serving: serving) }
    private var mode: QuantityInputMode { input.resolvedMode(environment.preferences.quantityInputMode) }
    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    private var servingLabel: String? { serving?.displayLabel ?? fallbackServingLabel }

    var body: some View {
        Group {
            if input.offersModeChoice {
                Picker("Enter as", selection: modeBinding) {
                    Text(input.size?.unit.symbol ?? "g").tag(QuantityInputMode.amount)
                    Text("Servings").tag(QuantityInputMode.servings)
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text(mode == .amount ? "Amount" : "Quantity")
                Spacer()
                TextField(mode == .amount ? "100" : "1", text: $text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    .focused(isFocused)
                    .frame(minWidth: 60)
                    .accessibilityLabel(accessibilityLabel)
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsStepper {
                    Stepper("Adjust amount", onIncrement: { step(by: 1) }, onDecrement: { step(by: -1) })
                        .labelsHidden()
                }
            }
            // On the always-present row, not the Group: a Group's modifiers
            // are applied to EACH of its rows inside a Form.
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                show(quantity)
            }
            .onChange(of: serving) { _, _ in
                show(quantity)
            }
            .onChange(of: text) { _, newValue in
                if newValue == writtenText {
                    quantity = writtenQuantity
                } else {
                    quantity = input.quantity(fromText: newValue, mode: mode)
                }
            }

            if quantity == nil {
                // The caller's confirm/save button is disabled meanwhile,
                // so say why -- in the unit being typed.
                Text(input.invalidMessage(mode: mode))
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            } else if let caption {
                // The conversion made explicit: builds trust that the right
                // number is what actually reaches Garmin.
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Pieces

    private var suffix: String {
        if mode == .amount, let size = input.size { return size.unit.symbol }
        return servingLabel.map { "× \($0)" } ?? "×"
    }

    private var accessibilityLabel: String {
        if mode == .amount, let size = input.size {
            return size.unit == .grams ? "Amount in grams" : "Amount in millilitres"
        }
        return "Number of servings"
    }

    /// "= 1.5 × 100g" while typing grams, "= 150 g" while typing servings;
    /// nothing when there's no conversion to show.
    private var caption: String? {
        guard let quantity, input.offersModeChoice else { return nil }
        switch mode {
        case .amount:
            guard let servingLabel else { return nil }
            return "= \(quantity.formattedQuantity) × \(servingLabel)"
        case .servings:
            return input.amountLabel(forQuantity: quantity).map { "= \($0)" }
        }
    }

    private var modeBinding: Binding<QuantityInputMode> {
        Binding(
            get: { mode },
            set: { newMode in
                let current = quantity
                environment.preferences.quantityInputMode = newMode
                show(current)
            }
        )
    }

    // MARK: Actions

    /// Writes `value` into the field in the current mode (or clears it).
    private func show(_ value: Double?) {
        guard let value else {
            writtenText = nil
            writtenQuantity = nil
            text = ""
            quantity = nil
            return
        }
        let newText = input.text(forQuantity: value, mode: mode, decimalSeparator: decimalSeparator)
        writtenText = newText
        writtenQuantity = value
        text = newText
        quantity = value
    }

    /// 10 g/ml per tap when typing an amount, half a serving otherwise --
    /// ignored past `LogQuantity`'s bounds.
    private func step(by direction: Double) {
        let current = quantity ?? writtenQuantity ?? 1
        let next: Double
        if mode == .amount, let size = input.size {
            next = size.quantity(forAmount: size.amount(forQuantity: current) + direction * 10)
        } else {
            next = current + direction * 0.5
        }
        guard LogQuantity.isValid(next) else { return }
        show(next)
    }
}

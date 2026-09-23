// AddHydrationSheet.swift
//
// The custom-amount entry form, reached from HydrationView's "Custom" quick-
// add button or its + toolbar item -- mirrors AddWeightSheet's shape (a
// `Form`, a save action gated on a validity check) but adds preset chips
// inside the sheet too, since a sheet opened from the + toolbar item has no
// amount pre-filled the way a hero-row tap would. Saving calls
// `HydrationLogCoordinator.logHydration` through `AppEnvironment
// .hydrationLogged()`, which commits locally and enqueues for delivery
// BEFORE this sheet dismisses -- no network `await` anywhere in this file,
// per the project's zero-network-wait constraint.

import SwiftUI
import FoodLogCore

@MainActor
struct AddHydrationSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = "250"
    @State private var loggedAt = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var amountFieldFocused: Bool

    private let presets: [Double] = [100, 250, 500]

    private var amountValue: Double? {
        guard let value = DecimalInput.parse(amountText), value > 0, value < 5000 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section("Amount") {
                HStack {
                    TextField("e.g. 250", text: $amountText)
                        .keyboardType(.numberPad)
                        .focused($amountFieldFocused)
                    Text("ml")
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(presets, id: \.self) { preset in
                        Button("\(Int(preset))") {
                            amountText = String(Int(preset))
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.carbs)
                    }
                }
                DatePicker("When", selection: $loggedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Water")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(amountValue == nil || isSaving)
            }
        }
        .onAppear { amountFieldFocused = true }
    }

    private func save() async {
        guard let amountValue else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await environment.hydrationLogCoordinator.logHydration(
                valueInML: amountValue,
                loggedAt: loggedAt
            )
            await environment.hydrationLogged()
            dismiss()
        } catch {
            errorMessage = "Couldn't save this entry. Try again."
        }
    }
}

// No #Preview here: this view requires `AppEnvironment` via `@Environment`,
// same reason AddWeightSheet.swift has none.

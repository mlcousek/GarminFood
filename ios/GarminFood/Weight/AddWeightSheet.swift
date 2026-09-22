// AddWeightSheet.swift
//
// The weigh-in entry form -- mirrors `MealPresetEditorView`'s shape (a
// `Form` with a title, a save action gated on a validity check, and an
// inline error message) but far simpler: one number, one optional date/time
// (for backdating a missed weigh-in), one optional note. Saving calls
// `WeightLogCoordinator.logWeight` through `AppEnvironment.weightLogged()`,
// which commits locally and enqueues for delivery BEFORE this sheet
// dismisses -- there is no network `await` anywhere in this file, per the
// project's zero-network-wait constraint.

import SwiftUI
import FoodLogCore

@MainActor
struct AddWeightSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var loggedAt = Date()
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var weightFieldFocused: Bool

    /// Accepts either "." or "," as the decimal separator (a Czech keyboard
    /// defaults to a comma on the decimal pad) -- same normalization
    /// `MealPresetEditorView`'s quantity field implicitly avoids needing
    /// only because a quantity multiplier is usually a whole number; a body
    /// weight virtually never is.
    private var weightValue: Double? {
        let normalized = weightText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value < 500 else { return nil }
        return value
    }

    var body: some View {
        Form {
            Section("Weight") {
                HStack {
                    TextField("e.g. 75.5", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($weightFieldFocused)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }
                DatePicker("When", selection: $loggedAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            }

            Section("Note") {
                TextField("Optional note", text: $note, axis: .vertical)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Add Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(weightValue == nil || isSaving)
            }
        }
        .onAppear { weightFieldFocused = true }
    }

    private func save() async {
        guard let weightValue else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await environment.weightLogCoordinator.logWeight(
                weightKg: weightValue,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
                loggedAt: loggedAt
            )
            await environment.weightLogged()
            dismiss()
        } catch {
            errorMessage = "Couldn't save this weigh-in. Try again."
        }
    }
}

// No #Preview here: this view requires `AppEnvironment` via `@Environment`,
// which has no default and would crash a Previews canvas without a real
// instance to inject -- same reason TodayView/ProfileView/SettingsView/
// MealPresetEditorView (all `AppEnvironment`-dependent screens) have none
// either, per Components.swift's header ("no Xcode Previews canvas actually
// running for this project today").

// DataModeSection.swift
//
// Settings -> "Data": where this install keeps its food log, and the
// explicit, confirmed switch between Garmin-connected and standalone
// ("on this phone only") mode (add-standalone-mode D10, task 5.4).
//
// A self-contained Section, the first one on the Data screen that
// `add-data-safety` builds (DataSettingsView).
//
// - Garmin -> standalone: refused while a drain is running ("Finishing
//   sync, try again in a moment"). With undelivered food entries the user
//   picks "Deliver first" (only when signed in) or "Keep on this phone",
//   which converts them into local entries (`UndeliveredFoodConversion`).
//   The Garmin token is kept.
// - Standalone -> Garmin: completes only after a successful sign-in; the
//   local food log stays on the phone and isn't uploaded.
// Every confirmation says what happens to the data.
//
// Thin: the switching lives in AppEnvironment (`switchToStandalone`,
// `deliverBeforeSwitching`, `switchToGarminIfSignedIn`).
//
// Depends on: AppEnvironment, GarminSignInSheet. Depended on by: DataSettingsView.

import SwiftUI
import FoodLogCore

@MainActor
struct DataModeSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isConfirmingStandalone = false
    @State private var isConfirmingGarmin = false
    @State private var isPresentingSignIn = false
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        let mode = environment.dataMode

        Section {
            HStack {
                Text("Food log")
                Spacer()
                Text(mode == .standalone ? String(localized: "On this phone only") : String(localized: "Garmin Connect"))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if mode == .standalone {
                Button(String(localized: "Connect Garmin instead…")) {
                    isConfirmingGarmin = true
                }
                .disabled(isWorking)
            } else {
                Button(String(localized: "Keep food on this phone only…")) {
                    if environment.isDraining {
                        message = String(localized: "Finishing sync, try again in a moment.")
                    } else {
                        isConfirmingStandalone = true
                    }
                }
                .disabled(isWorking)
            }
            if environment.preferences.forceStandaloneMode {
                Text("The testing switch in Diagnostics is on, so this phone runs on its own anyway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Data")
        } footer: {
            Text(mode == .standalone
                 ? String(localized: "Your food, goals, weight and water are stored only on this phone. Nothing is sent to Garmin.")
                 : String(localized: "Your food goes to Garmin Connect. Switching keeps everything on this phone instead."))
        }
        .confirmationDialog(
            String(localized: "Keep your food on this phone only?"),
            isPresented: $isConfirmingStandalone,
            titleVisibility: .visible
        ) {
            let undelivered = environment.undeliveredFoodEntryCount
            if undelivered > 0 {
                if environment.authState.state == .authenticated {
                    Button(String(localized: "Deliver first")) {
                        Task { await deliverFirst() }
                    }
                }
                Button(String(localized: "Keep on this phone")) {
                    Task { await switchToStandalone(keep: true) }
                }
            } else {
                Button(String(localized: "Switch")) {
                    Task { await switchToStandalone(keep: false) }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(standaloneMessage)
        }
        .confirmationDialog(
            String(localized: "Connect Garmin?"),
            isPresented: $isConfirmingGarmin,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Sign in and switch")) {
                Task { await switchToGarmin() }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text("After you sign in, new food goes to Garmin Connect. The food log on this phone stays here and isn't uploaded; you'll see it again if you switch back. Weight and water logged here stay on this phone too.")
        }
        .sheet(isPresented: $isPresentingSignIn, onDismiss: {
            Task { await finishGarminSwitch() }
        }) {
            GarminSignInSheet()
        }
        .alert(
            String(localized: "Data"),
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var standaloneMessage: String {
        let undelivered = environment.undeliveredFoodEntryCount
        let base = String(localized: "New food, weight and water stay on this phone and nothing is sent to Garmin. Your Garmin history isn't copied. You stay signed in, so switching back is quick.")
        guard undelivered > 0 else { return base }
        return base + "\n\n" + String(localized: "\(undelivered) food entries haven't reached Garmin yet. Deliver them first, or keep them on this phone.")
    }

    private func deliverFirst() async {
        isWorking = true
        defer { isWorking = false }
        await environment.deliverBeforeSwitching()
        if environment.undeliveredFoodEntryCount > 0 {
            message = String(localized: "Some entries still haven't reached Garmin. You can keep them on this phone instead.")
        } else {
            await switchToStandalone(keep: false)
        }
    }

    private func switchToStandalone(keep: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await environment.switchToStandalone(keepUndelivered: keep)
            if let result, result.leftInGarmin > 0 {
                message = String(localized: "\(result.leftInGarmin) entries were already on their way to Garmin and stay there.")
            }
        } catch AppEnvironment.ModeSwitchError.syncInProgress {
            message = String(localized: "Finishing sync, try again in a moment.")
        } catch {
            message = error.localizedDescription
        }
    }

    private func switchToGarmin() async {
        isWorking = true
        defer { isWorking = false }
        let switched = await environment.switchToGarminIfSignedIn()
        if !switched {
            isPresentingSignIn = true
        }
    }

    private func finishGarminSwitch() async {
        isWorking = true
        defer { isWorking = false }
        let switched = await environment.switchToGarminIfSignedIn()
        if !switched {
            message = String(localized: "Not signed in, so nothing changed. Your food stays on this phone.")
        }
    }
}

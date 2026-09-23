// SettingsView.swift
//
// profile-and-settings spec: the Garmin connection (with sign out), Garmin's
// nutrition plan shown read-only (changed in Garmin Connect, never here, per
// the spec's own words), the sync queue, preferences that persist, and
// About.

import SwiftUI
import GarminKit

@MainActor
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isPresentingSignIn = false
    @State private var isConfirmingSignOut = false

    var body: some View {
        @Bindable var preferences = environment.preferences

        Form {
            Section("Garmin account") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
                if environment.authState.state == .authenticated {
                    Button("Sign out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                } else {
                    Button("Sign in to Garmin") {
                        isPresentingSignIn = true
                    }
                }
            }

            Section {
                nutritionRow("Calorie goal", value: calorieGoalText)
                nutritionRow("Carbs", value: macroText(environment.profile.settings?.macroGoals?.carbs))
                nutritionRow("Protein", value: macroText(environment.profile.settings?.macroGoals?.protein))
                nutritionRow("Fat", value: macroText(environment.profile.settings?.macroGoals?.fat))
                ForEach(environment.dayLog.latestWindows.sorted { $0.mealType.rawValue < $1.mealType.rawValue }, id: \.mealType) { window in
                    nutritionRow(window.mealType.displayName, value: window.displayText)
                }
            } header: {
                Text("Nutrition plan")
            } footer: {
                if environment.profile.settingsFailed {
                    Text("Couldn't load from Garmin.")
                } else {
                    Text("Set in Garmin Connect. GarminFood only displays it.")
                }
            }

            // sync-weight-hydration-with-garmin 3.5 (GoalsSettingsSection.swift).
            GoalsSettingsSection()

            Section {
                NavigationLink {
                    SyncQueueView()
                } label: {
                    HStack {
                        Label("Sync queue", systemImage: "arrow.triangle.2.circlepath")
                        Spacer()
                        if environment.undeliveredCount > 0 {
                            Text("\(environment.undeliveredCount)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Theme.warning, in: Capsule())
                        }
                    }
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Reminders", systemImage: "bell.badge")
                }
                NavigationLink {
                    DiagnosticsLogView()
                } label: {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
                NavigationLink {
                    AppIconPickerView()
                } label: {
                    Label("App Icon", systemImage: "app.badge")
                }
            }

            Section("Preferences") {
                Toggle("Haptic feedback", isOn: $preferences.hapticsEnabled)
                Toggle("Celebration animations", isOn: $preferences.celebrationsEnabled)
                Toggle("Default meal from Garmin's schedule", isOn: $preferences.useGarminMealWindows)
                Toggle("Search Czech foods only", isOn: $preferences.czechOnlySearch)
            }
            .onChange(of: preferences.hapticsEnabled) {
                environment.preferencesChanged()
            }

            // redesign-fasting-schedule 2.1 (FastingSettingsSection.swift).
            FastingSettingsSection()

            // add-offline-czech-food-index 3.5 (OfflineIndexSettingsSection.swift).
            OfflineIndexSettingsSection()

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(versionText)
                        .foregroundStyle(.secondary)
                }
                // add-offline-czech-food-index D5: OFF data (live search and
                // the offline database) is ODbL-licensed and must be credited.
                Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                    Label("Open Food Facts (ODbL)", systemImage: "leaf")
                }
                Link(destination: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!) {
                    Label("Open Database License 1.0", systemImage: "doc.text")
                }
            } header: {
                Text("About")
            } footer: {
                Text("GarminFood logs food in two taps and syncs it to Garmin Connect. Czech product data © Open Food Facts contributors, available under the Open Database License (ODbL).")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingSignIn) {
            GarminSignInSheet()
        }
        .confirmationDialog(
            "Sign out of Garmin?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                Task { await environment.signOut() }
            }
        } message: {
            Text("Entries waiting to sync stay queued and send once you sign in again.")
        }
    }

    private var statusText: String {
        switch environment.authState.state {
        case .authenticated: return "Connected"
        case .needsSignIn: return "Sign-in expired"
        case .signedOut: return "Not connected"
        }
    }

    private var calorieGoalText: String {
        guard let goal = environment.profile.settings?.calorieGoal else { return "—" }
        return "\(goal.wholeNumberText) kcal"
    }

    private func macroText(_ grams: Double?) -> String {
        guard let grams else { return "—" }
        return "\(grams.wholeNumberText) g"
    }

    private func nutritionRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

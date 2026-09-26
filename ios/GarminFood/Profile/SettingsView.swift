// SettingsView.swift
//
// profile-and-settings spec: the Garmin connection (with sign out), Garmin's
// nutrition plan shown read-only (changed in Garmin Connect, never here, per
// the spec's own words), the sync queue, preferences that persist, and
// About.
//
// add-standalone-mode 5.2: in standalone mode every Garmin-only row is
// hidden -- the Garmin account section, Garmin's read-only plan (replaced
// by the local editable one), the sync queue and "Default meal from
// Garmin's schedule" -- and About no longer says it syncs to Garmin.

import SwiftUI
import UIKit
import GarminKit

@MainActor
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @State private var isPresentingSignIn = false
    @State private var isConfirmingSignOut = false

    /// add-localization 6.5 / design.md D1: the app follows the iOS
    /// language and has no in-app picker; iOS itself offers Settings ›
    /// GarminFood › Language once the app declares en + cs. This row shows
    /// the language in use and opens that page -- the only way to pin
    /// English on a Czech phone (or the reverse).
    private var languageRow: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        } label: {
            HStack {
                Label("Language", systemImage: "globe")
                    .foregroundStyle(.primary)
                Spacer()
                Text(currentLanguageName)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityHint("Opens GarminFood's page in iOS Settings, where the app's language can be changed")
    }

    /// The localization iOS picked for this app ("Čeština", "English"),
    /// named in that same language.
    private var currentLanguageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let locale = Locale(identifier: code)
        return locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) ?? code
    }

    var body: some View {
        @Bindable var preferences = environment.preferences
        let isStandalone = environment.dataMode == .standalone

        Form {
            if !isStandalone {
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
            }

            // add-data-safety D6: backups, export/import, and (add-
            // standalone-mode 5.4) where the food log lives with the mode
            // switch -- all on the Data screen.
            Section {
                NavigationLink {
                    DataSettingsView()
                } label: {
                    Label("Data", systemImage: "externaldrive")
                }
            }

            // add-standalone-mode 4.3: standalone's plan is the local,
            // editable goal; Garmin mode keeps Garmin's read-only plan.
            if isStandalone {
                LocalNutritionPlanSection()
            } else {
                garminNutritionPlan
            }

            // sync-weight-hydration-with-garmin 3.5 (GoalsSettingsSection.swift).
            GoalsSettingsSection()

            Section {
                if !isStandalone {
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
                // add-themes-and-layout R6: theme, style, custom accent and the
                // app icon grid all live on this one page.
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
                languageRow
            }

            Section("Preferences") {
                Toggle("Haptic feedback", isOn: $preferences.hapticsEnabled)
                Toggle("Celebration animations", isOn: $preferences.celebrationsEnabled)
                if !isStandalone {
                    Toggle("Default meal from Garmin's schedule", isOn: $preferences.useGarminMealWindows)
                }
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
                if isStandalone {
                    Text("GarminFood logs food in two taps and keeps it on this phone. Czech product data © Open Food Facts contributors, available under the Open Database License (ODbL).")
                } else {
                    Text("GarminFood logs food in two taps and syncs it to Garmin Connect. Czech product data © Open Food Facts contributors, available under the Open Database License (ODbL).")
                }
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

    /// Garmin's nutrition plan, read-only (Garmin mode only).
    private var garminNutritionPlan: some View {
        Section {
            nutritionRow(String(localized: "Calorie goal"), value: calorieGoalText)
            nutritionRow(String(localized: "Carbs"), value: macroText(environment.profile.settings?.macroGoals?.carbs))
            nutritionRow(String(localized: "Protein"), value: macroText(environment.profile.settings?.macroGoals?.protein))
            nutritionRow(String(localized: "Fat"), value: macroText(environment.profile.settings?.macroGoals?.fat))
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
    }

    private var statusText: String {
        switch environment.authState.state {
        case .authenticated: return String(localized: "Connected")
        case .needsSignIn: return String(localized: "Sign-in expired")
        case .signedOut: return String(localized: "Not connected")
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

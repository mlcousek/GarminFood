// AppearanceSettingsView.swift
//
// Settings -> Appearance ("Vzhled"), the one page for all customization
// (add-themes-and-layout design.md R6, tasks 2.4-2.6). Sections, in order:
//   1. theme gallery (live mini previews)
//   2. Light / Dark / System (R7: one global choice; disabled, with a note,
//      for a single-scheme theme)
//   3. app icon grid + "Match app icon to theme"
//   4. customization: custom accent, card style, corners, density, number
//      font, gradient header, macro colors
//   5. layout: Today, Log Food and Progress each open LayoutEditorSheet
//      (waves 3-4), plus the start tab picker (task 4.3)
//   6. share / import a theme code (wave 5, ThemeShareSection)
//   7. reset
// Every change writes through ThemeStore / LayoutStore immediately and
// applies live. "Reset all appearance" resets the layouts too (design.md
// Migration Plan: it is the one way back to both defaults).
//
// Depends on ThemeStore and LayoutStore (via AppEnvironment) and
// AppearanceKit's option enums. Reached from SettingsView.

import SwiftUI
import AppearanceKit

@MainActor
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmsReset = false
    /// The screen whose layout editor is open, if any.
    @State private var editingLayoutScreen: LayoutScreen?

    private var store: ThemeStore { environment.themeStore }
    private var layoutStore: LayoutStore { environment.layoutStore }

    var body: some View {
        Form {
            if store.showsResetNotice {
                Section {
                    Label("Your saved look couldn't be read and was reset.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                }
            }
            if layoutStore.showsResetNotice {
                Section {
                    Label("Your saved layout couldn't be read and was reset.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warning)
                }
            }

            Section {
                ThemeGalleryView(store: store)
            } header: {
                Text("Theme")
            } footer: {
                // D13: widgets can't read the app's settings (no App Group).
                Text("Widgets don't change with the app's theme. Touch and hold a widget, then Edit Widget, to pick its theme.")
            }

            appearanceSection

            AppIconGridSection(store: store)

            AccentColorSection(store: store)

            fineTuneSection

            layoutSection

            ThemeShareSection(store: store)

            Section {
                Button("Reset all appearance", role: .destructive) {
                    confirmsReset = true
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset all appearance settings?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                store.resetAll()
                layoutStore.resetAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your theme, style and screen layouts go back to their defaults.")
        }
        .sheet(isPresented: isEditingLayout) {
            if let screen = editingLayoutScreen {
                // Only what Settings can know: fasting on/off. Log again / Log
                // a meal depend on Today's loaded shelves, and the Log Food
                // shelves on the catalog's, so they read as available here.
                LayoutEditorSheet(screen: screen) { id in
                    guard screen == .today, let card = TodayCardID(rawValue: id) else { return .available }
                    return TodayCardID.baseAvailability(card, preferences: environment.preferences)
                }
            }
        }
        .onDisappear {
            if store.showsResetNotice { store.dismissResetNotice() }
            if layoutStore.showsResetNotice { layoutStore.dismissResetNotice() }
        }
    }

    // MARK: Layout (design.md D9)

    @ViewBuilder
    private var layoutSection: some View {
        Section {
            layoutRow(.today, systemImage: "fork.knife", value: layoutStore.currentTodayPreset?.displayName ?? String(localized: "Custom"))
            layoutRow(.logFood, systemImage: "magnifyingglass", value: layoutSummary(.logFood))
            layoutRow(.progress, systemImage: "chart.bar", value: layoutSummary(.progress))
        } header: {
            Text("Layout")
        } footer: {
            Text("Reorder, hide and restyle the cards. You can also open this from the menu on Today.")
        }

        // Task 4.3: honored at launch; a widget or link still opens where
        // it points (AppRouter).
        Section {
            Picker("Start on", selection: startTabBinding) {
                Text("Today").tag(StartTab.today)
                Text("Progress").tag(StartTab.progress)
            }
        } header: {
            Text("Start tab")
        } footer: {
            Text("Applies the next time the app opens. Widgets and links still open where they point.")
        }
    }

    private func layoutRow(_ screen: LayoutScreen, systemImage: String, value: String) -> some View {
        Button {
            editingLayoutScreen = screen
        } label: {
            HStack {
                Label(screen.title, systemImage: systemImage)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityHint("Opens the layout editor")
    }

    /// "Default" or "Custom" for the screens without presets.
    private func layoutSummary(_ screen: LayoutScreen) -> String {
        layoutStore.config.isDefaultLayout(screen)
            ? String(localized: "Default", comment: "Settings -> Appearance -> Layout: a screen whose layout was never changed.")
            : String(localized: "Custom")
    }

    private var isEditingLayout: Binding<Bool> {
        Binding(
            get: { editingLayoutScreen != nil },
            set: { if !$0 { editingLayoutScreen = nil } }
        )
    }

    private var startTabBinding: Binding<StartTab> {
        let layoutStore = self.layoutStore
        return Binding(
            get: { layoutStore.config.resolvedStartTab },
            set: { layoutStore.setStartTab($0) }
        )
    }

    // MARK: Appearance (R7)

    @ViewBuilder
    private var appearanceSection: some View {
        let supported = store.theme.supportedSchemes
        Section {
            Picker("Appearance", selection: binding(\.appearance)) {
                Text("System").tag(AppearanceMode.system)
                Text("Light").tag(AppearanceMode.light)
                Text("Dark").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .disabled(supported.count == 1)
        } footer: {
            if supported == [.dark] {
                Text("This theme is dark only.")
            } else if supported == [.light] {
                Text("This theme is light only.")
            }
        }
    }

    // MARK: Fine-tune (D6)

    private var fineTuneSection: some View {
        Section {
            Picker("Card style", selection: binding(\.style.cardStyle)) {
                Text("Filled").tag(CardStyleOption.filled)
                Text("Elevated").tag(CardStyleOption.elevated)
                Text("Outlined").tag(CardStyleOption.outlined)
                Text("Glass").tag(CardStyleOption.glass)
            }
            Picker("Corners", selection: binding(\.style.cornerShape)) {
                Text("Sharp").tag(CornerShapeOption.sharp)
                Text("Standard").tag(CornerShapeOption.standard)
                Text("Round").tag(CornerShapeOption.round)
            }
            Picker("Density", selection: binding(\.style.density)) {
                Text("Comfortable").tag(DensityOption.comfortable)
                Text("Compact").tag(DensityOption.compact)
            }
            Picker("Number font", selection: binding(\.style.numberFont)) {
                Text("Rounded").tag(NumberFontOption.rounded)
                Text("Default").tag(NumberFontOption.default)
                Text("Serif").tag(NumberFontOption.serif)
                Text("Monospaced").tag(NumberFontOption.monospaced)
            }
            Toggle("Gradient header", isOn: binding(\.style.gradientHeader))
            Picker("Macro colors", selection: binding(\.macroSet)) {
                Text("Theme colors").tag(MacroSetOption.theme)
                Text("Legible").tag(MacroSetOption.legible)
                Text("Colour-blind safe").tag(MacroSetOption.colorBlindSafe)
            }
        } header: {
            Text("Fine-tune")
        } footer: {
            Text("Colour-blind safe colors are also used whenever Differentiate Without Color is on.")
        }
    }

    // MARK: Helpers

    private func binding<Value>(_ keyPath: WritableKeyPath<AppearanceSettings, Value>) -> Binding<Value> {
        let store = self.store
        return Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in store.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}

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
//   5. layout: "Customize layout" -- Coming soon (waves 3-4)
//   6. share / import a theme code (wave 5, ThemeShareSection)
//   7. reset
// Every change writes through ThemeStore immediately and applies live.
//
// Depends on ThemeStore (via AppEnvironment) and AppearanceKit's option
// enums. Reached from SettingsView.

import SwiftUI
import AppearanceKit

@MainActor
struct AppearanceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var confirmsReset = false

    private var store: ThemeStore { environment.themeStore }

    var body: some View {
        Form {
            if store.showsResetNotice {
                Section {
                    Label("Your saved look couldn't be read and was reset.", systemImage: "exclamationmark.triangle")
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

            Section {
                HStack {
                    Label("Customize layout", systemImage: "rectangle.3.group")
                    Spacer()
                    Text("Coming soon")
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } header: {
                Text("Layout")
            }

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
            Button("Reset", role: .destructive) { store.resetAll() }
            Button("Cancel", role: .cancel) {}
        }
        .onDisappear {
            if store.showsResetNotice { store.dismissResetNotice() }
        }
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

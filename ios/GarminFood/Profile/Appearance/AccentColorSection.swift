// AccentColorSection.swift
//
// Settings -> Appearance: the custom accent (add-themes-and-layout D5, task
// 2.4). The raw pick is stored (`AppearanceSettings.customAccent`); fitting
// to the contrast policy happens at resolve time per scheme
// (AccentAdjuster), so this section only shows the outcome: a note when the
// color was adjusted for light or dark mode, and a warning when it sits too
// close to a macro color (`AccentAdjuster.collidingMacro`).
//
// Depends on ThemeStore, AppearanceKit. Used by AppearanceSettingsView.

import SwiftUI
import UIKit
import AppearanceKit

@MainActor
struct AccentColorSection: View {
    let store: ThemeStore

    /// Curated picks that read well in most themes (all fitted anyway).
    private static let swatches: [UInt32] = [
        0x15808C, 0xF56B4A, 0x2F74C8, 0x7A52C7, 0xC2255C, 0x2E7D4F, 0xD9480F, 0x3A3A3C
    ]

    private var customAccent: RGBA? { store.settings.customAccent }

    var body: some View {
        Section {
            Toggle("Custom accent color", isOn: Binding(
                get: { customAccent != nil },
                set: { isOn in
                    store.update { settings in
                        settings.customAccent = isOn ? AppearanceKit.RGBA(hex: 0x15808C) : nil
                    }
                }
            ))

            if let accent = customAccent {
                ColorPicker("Accent color", selection: Binding(
                    get: { Color(uiColor: ThemePalette.uiColor(accent)) },
                    set: { color in
                        store.update { $0.customAccent = Self.rgba(from: color) }
                    }
                ), supportsOpacity: false)

                swatchRow(selected: accent)

                ForEach(notes(for: accent), id: \.self) { note in
                    Label(note, systemImage: "wand.and.stars")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let warning = collisionWarning() {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                }
            }
        } header: {
            Text("Accent color")
        }
    }

    private func swatchRow(selected: RGBA) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(Self.swatches, id: \.self) { hex in
                let rgba = AppearanceKit.RGBA(hex: hex)
                Button {
                    store.update { $0.customAccent = rgba }
                } label: {
                    Circle()
                        .fill(Color(uiColor: ThemePalette.uiColor(rgba)))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(rgba.hexString == selected.hexString ? 0.8 : 0), lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rgba.hexString)
                .accessibilityAddTraits(rgba.hexString == selected.hexString ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    /// "Adjusted for light/dark mode" per scheme the active theme shows in.
    private func notes(for accent: RGBA) -> [String] {
        store.theme.supportedSchemes.compactMap { scheme in
            let palette = store.resolved(store.theme, scheme: scheme)
            guard palette.adjustedRoles.contains(.accent) else { return nil }
            switch scheme {
            case .light: return String(localized: "Adjusted for light mode to stay readable.")
            case .dark: return String(localized: "Adjusted for dark mode to stay readable.")
            }
        }
    }

    private func collisionWarning() -> String? {
        let scheme = store.theme.supportedSchemes.first ?? .light
        let palette = store.resolved(store.theme, scheme: scheme)
        guard let role = AccentAdjuster.collidingMacro(in: palette) else { return nil }
        switch role {
        case .carbs: return String(localized: "Looks like the carbs color. Bars may be harder to tell apart.")
        case .protein: return String(localized: "Looks like the protein color. Bars may be harder to tell apart.")
        case .fat: return String(localized: "Looks like the fat color. Bars may be harder to tell apart.")
        case .water: return String(localized: "Looks like the water color. Bars may be harder to tell apart.")
        default: return nil
        }
    }

    /// SwiftUI color -> stored sRGB pick (extended-range values clamped).
    static func rgba(from color: Color) -> RGBA {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return RGBA(red: Double(red), green: Double(green), blue: Double(blue)).clamped
    }
}

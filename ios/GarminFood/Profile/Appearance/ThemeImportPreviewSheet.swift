// ThemeImportPreviewSheet.swift
//
// Import theme (add-themes-and-layout design.md D11, task 5.5): what a
// pasted code or an opened `garminfood://theme?c=…` link leads to. It
// decodes the code with AppearanceKit's `ThemeShareCode` and shows the
// theme's gallery tile, what doesn't carry over (a newer build's theme or
// values), and Apply / Cancel. Nothing is ever applied without this
// preview and an explicit Apply; an unreadable code only says so and
// changes nothing (spec "Invalid code").
//
// Presented by ThemeShareSection (Paste) and ContentView (the link, via
// AppRouter.pendingThemeImport). Applies through
// ThemeStore.applyImported(_:).

import SwiftUI
import AppearanceKit

/// A code waiting for the import preview (`.sheet(item:)`).
struct ThemeImportRequest: Identifiable, Equatable {
    let id = UUID()
    /// The pasted text or the link's `c` value; decoded by the sheet.
    let code: String
}

@MainActor
struct ThemeImportPreviewSheet: View {
    let code: String

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var store: ThemeStore { environment.themeStore }

    private var result: Result<ThemeShareCode.Import, ThemeShareCode.Failure> {
        ThemeShareCode.decode(pasted: code, scheme: GarminFoodDeepLink.scheme)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch result {
                case .success(let imported):
                    preview(imported)
                case .failure(let failure):
                    ContentUnavailableView {
                        Label("Couldn't read the code", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(Self.message(for: failure))
                    }
                }
            }
            .navigationTitle("Import theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Preview

    private func preview(_ imported: ThemeShareCode.Import) -> some View {
        let settings = imported.settings
        let spec = ThemeCatalog.themeOrDefault(id: settings.themeID)
        return Form {
            Section {
                HStack(spacing: Theme.Spacing.md) {
                    ThemePreviewTile(palette: palette(for: settings, spec: spec), isSelected: false)
                        .frame(width: 120)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(spec.displayName)
                            .font(.headline)
                        if settings.customAccent != nil {
                            Text("Custom accent color")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
            } header: {
                Text("Theme")
            } footer: {
                Text("Applying replaces your theme, accent color, style and macro colors.")
            }

            if !imported.warnings.isEmpty {
                Section {
                    ForEach(imported.warnings, id: \.self) { warning in
                        Label(Self.message(for: warning), systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }

            Section {
                PrimaryButton(title: "Apply") {
                    store.applyImported(settings)
                    dismiss()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
    }

    /// The imported look as it would show here: its own macro set and
    /// accent, this phone's accessibility settings, and its Light/Dark
    /// choice (else the system's) unless the theme has only one scheme.
    private func palette(for settings: AppearanceSettings, spec: ThemeSpec) -> ResolvedPalette {
        let requested = store.previewScheme(for: settings.appearance, environmentScheme: colorScheme)
        return PaletteResolver.resolve(
            theme: spec,
            requestedScheme: spec.effectiveScheme(for: requested),
            macroSet: settings.macroSet,
            customAccent: settings.customAccent,
            increasedContrast: store.increasedContrast,
            differentiateWithoutColor: store.differentiateWithoutColor
        )
    }

    // MARK: Text

    static func message(for warning: ThemeShareCode.Warning) -> String {
        switch warning {
        case .unknownTheme(let id):
            return String(localized: "This code uses a theme this version doesn't have (\(id)). The rest of its settings apply on Classic Coral.")
        case .ignoredUnknownValues:
            return String(localized: "Some settings in this code aren't supported by this version and keep their defaults.")
        }
    }

    static func message(for failure: ThemeShareCode.Failure) -> String {
        switch failure {
        case .notAShareCode:
            return String(localized: "That isn't a GarminFood theme code. Nothing was changed.")
        case .unsupportedVersion:
            return String(localized: "This code comes from a newer version of GarminFood. Update the app to import it. Nothing was changed.")
        case .tooLong, .corrupted:
            return String(localized: "The code is incomplete or damaged. Copy it again. Nothing was changed.")
        }
    }
}

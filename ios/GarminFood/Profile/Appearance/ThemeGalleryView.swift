// ThemeGalleryView.swift
//
// The first section of Settings -> Appearance (add-themes-and-layout R6,
// task 2.4): a grid of live mini previews, one per built-in theme, each
// drawn with *that* theme's resolved palette (background, card, a small
// ring in the accent, the three macro bars), not the active one. So the
// user sees Increase Contrast / colour-blind-safe / custom-accent effects
// in the preview before picking.
//
// Previews use plain (non-dynamic) colors from `ThemePalette.previewColor`
// resolved for the scheme the theme would actually show in: the user's
// Light/Dark choice, else the SYSTEM scheme (not the one the active theme
// forces -- a dark-only active theme must not preview Ocean in dark), or the
// theme's only scheme.
//
// Depends on ThemeStore (selection, resolution). Used by
// AppearanceSettingsView; `ThemePreviewTile` also by ThemeImportPreviewSheet.

import SwiftUI
import UIKit
import AppearanceKit

@MainActor
struct ThemeGalleryView: View {
    let store: ThemeStore
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.md)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
            ForEach(ThemeCatalog.all) { spec in
                let isSelected = spec.id == store.theme.id
                Button {
                    store.selectTheme(spec.id)
                } label: {
                    VStack(spacing: Theme.Spacing.xs) {
                        ThemePreviewTile(palette: palette(for: spec), isSelected: isSelected)
                        Text(spec.displayName)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spec.displayName)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func palette(for spec: ThemeSpec) -> ResolvedPalette {
        let requested = store.previewScheme(for: store.settings.appearance, environmentScheme: colorScheme)
        return store.resolved(spec, scheme: spec.effectiveScheme(for: requested))
    }
}

extension ThemeStore {
    /// The scheme a dual-scheme theme is previewed in for `appearance`: the
    /// user's Light/Dark choice, else the system's. `environmentScheme` is
    /// the view's `colorScheme`, which is the system's only while nothing
    /// is forced: `.preferredColorScheme` overrides the whole window, so
    /// under a single-scheme active theme the screen's own traits are read.
    func previewScheme(for appearance: AppearanceMode, environmentScheme: ColorScheme) -> ThemeColorScheme {
        switch appearance {
        case .light: return .light
        case .dark: return .dark
        case .system: break
        }
        guard forcedColorScheme != nil else {
            return environmentScheme == .dark ? .dark : .light
        }
        let screenStyle = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen.traitCollection.userInterfaceStyle }
            .first ?? .light
        return screenStyle == .dark ? .dark : .light
    }
}

/// A miniature Today: background, one card with a ring and three macro bars.
struct ThemePreviewTile: View {
    let palette: ResolvedPalette
    let isSelected: Bool

    private func color(_ role: ThemeRole) -> Color {
        ThemePalette.previewColor(palette, role)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color(.background))
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(color(.accent), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        bar(.carbs, 0.8)
                        bar(.protein, 0.55)
                        bar(.fat, 0.35)
                    }
                }
                Capsule()
                    .fill(color(.accent))
                    .frame(height: 10)
                    .overlay(
                        Capsule()
                            .fill(color(.onAccent))
                            .frame(width: 20, height: 3)
                    )
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color(.surface))
            )
            .padding(8)
        }
        .frame(height: 84)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color.secondary.opacity(0.25), lineWidth: isSelected ? 3 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.onAccent, Theme.accent)
                    .padding(4)
            }
        }
    }

    private func bar(_ role: ThemeRole, _ fraction: CGFloat) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color(role))
                .frame(width: proxy.size.width * fraction)
        }
        .frame(height: 4)
    }
}

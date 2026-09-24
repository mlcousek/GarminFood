// AppIconGridSection.swift
//
// Settings -> Appearance, section 3 (add-themes-and-layout R5/R6): the app
// icon grid that used to be its own screen (AppIconPickerView, add-app-icon-
// picker), plus the "Match app icon to theme" toggle (default on). The icon
// can still be picked independently of the theme here.
//
// `UIApplication.setAlternateIconName` (via AppIconSwitcher) is the only way
// to change a Home Screen icon; iOS shows its own confirmation alert. There
// is no simulator here -- CI's xcodebuild only proves this compiles, not
// that the loose PNGs / Info.plist keys resolve on a device.
//
// Depends on AppIconOption / AppIconSwitcher and ThemeStore.

import SwiftUI
import UIKit

@MainActor
struct AppIconGridSection: View {
    @Bindable var store: ThemeStore
    @State private var selected: AppIconOption = AppIconSwitcher.current
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: Theme.Spacing.md)]

    var body: some View {
        Section {
            Toggle("Match app icon to theme", isOn: $store.matchesAppIcon)
            LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                ForEach(AppIconOption.allCases) { option in
                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            thumbnail(for: option)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                                        .strokeBorder(selected == option ? Theme.accent : Color.clear, lineWidth: 3)
                                )
                            Text(option.title)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selected == option ? [.isButton, .isSelected] : [.isButton])
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        } header: {
            Text("App icon")
        } footer: {
            Text("With matching on, picking a theme also switches the Home Screen icon.")
        }
        .onAppear { selected = AppIconSwitcher.current }
        // A theme pick with matching on switches the icon behind our back.
        .onChange(of: store.settings.themeID) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                selected = AppIconSwitcher.current
            }
        }
        .alert(
            "Couldn't change the app icon",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func thumbnail(for option: AppIconOption) -> some View {
        if let uiImage = UIImage(named: option.previewImageName) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 56, height: 56)
        }
    }

    private func select(_ option: AppIconOption) {
        // Not `option != selected`: a removed icon still on the Home Screen
        // shows as "GF Teal" selected, and tapping it must still switch.
        // `set` itself skips an icon that is already showing.
        AppIconSwitcher.set(option) { error in
            if let error {
                errorMessage = error.localizedDescription
            } else {
                selected = option
            }
        }
    }
}

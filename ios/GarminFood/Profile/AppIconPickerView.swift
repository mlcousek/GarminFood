// AppIconPickerView.swift
//
// Reached from Settings (add-app-icon-picker) -- a plain list of the 6
// `AppIconOption`s, each with its real preview thumbnail and a checkmark on
// whichever is currently active. Tapping one calls `UIApplication.
// setAlternateIconName`, which is the ONLY way to change a Home Screen icon
// on iOS -- there is no local preview/simulator to verify this renders
// correctly; CI's `xcodebuild` only confirms it compiles, not that the
// loose PNG files/Info.plist keys actually resolve on a real device (see
// project.yml's own comment on that same gap).

import SwiftUI
import UIKit

@MainActor
struct AppIconPickerView: View {
    @State private var selected: AppIconOption = AppIconPickerView.currentOption()
    @State private var errorMessage: String?

    var body: some View {
        List(AppIconOption.allCases) { option in
            Button {
                select(option)
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    thumbnail(for: option)
                    Text(option.title)
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected == option {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(option.title)
            .accessibilityAddTraits(selected == option ? [.isSelected] : [])
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
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
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 52, height: 52)
        }
    }

    private func select(_ option: AppIconOption) {
        guard option != selected else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "This device doesn't support alternate app icons."
            return
        }
        UIApplication.shared.setAlternateIconName(option.alternateIconName) { error in
            Task { @MainActor in
                if let error {
                    errorMessage = error.localizedDescription
                } else {
                    selected = option
                }
            }
        }
    }

    /// `UIApplication.shared.alternateIconName` is `nil` for the default
    /// icon; matched back to its `AppIconOption` by raw value, falling back
    /// to `.default` for a name this enum doesn't recognise (e.g. a stale
    /// value from a build that has since removed an icon).
    private static func currentOption() -> AppIconOption {
        guard let name = UIApplication.shared.alternateIconName else { return .default }
        return AppIconOption(rawValue: name) ?? .default
    }
}

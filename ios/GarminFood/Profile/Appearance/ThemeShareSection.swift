// ThemeShareSection.swift
//
// Settings -> Appearance, "Share" (add-themes-and-layout design.md D11,
// task 5.5): "Share theme" opens ThemeShareSheet (code, link, QR) for the
// current look; "Import theme" is a system `PasteButton` -- which, unlike
// reading `UIPasteboard` in code, never triggers the "Allow Paste" prompt --
// leading to ThemeImportPreviewSheet. The `garminfood://theme` link and its
// QR code reach the same preview through AppRouter/ContentView.
//
// Each sheet hangs off its own row, not the Section: inside a Form a
// container's modifiers are applied to every row.
//
// Depends on ThemeStore and AppearanceKit's ThemeShareCode. Used by
// AppearanceSettingsView.

import SwiftUI
import AppearanceKit

@MainActor
struct ThemeShareSection: View {
    let store: ThemeStore

    @State private var isSharing = false
    @State private var importRequest: ThemeImportRequest?

    var body: some View {
        Section {
            Button {
                isSharing = true
            } label: {
                Label("Share theme", systemImage: "square.and.arrow.up")
            }
            .sheet(isPresented: $isSharing) {
                ThemeShareSheet(code: ThemeShareCode.encode(store.settings))
            }

            HStack {
                Text("Import theme")
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        importRequest = ThemeImportRequest(code: text)
                    }
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
            }
            .sheet(item: $importRequest) { request in
                ThemeImportPreviewSheet(code: request.code)
            }
        } header: {
            Text("Share")
        } footer: {
            Text("Share your look as a code, link or QR code. Importing always shows a preview first.")
        }
    }
}

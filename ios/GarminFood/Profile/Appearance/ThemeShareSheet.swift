// ThemeShareSheet.swift
//
// Share theme (add-themes-and-layout design.md D11, task 5.5): the current
// look as a `GFT1.` code (AppearanceKit's `ThemeShareCode`), its
// `garminfood://theme?c=…` link, and a QR code of that link drawn with
// CoreImage's `CIQRCodeGenerator` -- scanning it with the iPhone Camera
// opens the link, which lands in the import preview (AppRouter). The code
// holds appearance settings only, never food or personal data.
//
// The QR image is black modules on white (CoreImage's output, not theme
// colors): scanners need the contrast whatever theme is active.
//
// Presented by ThemeShareSection.

import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import AppearanceKit

@MainActor
struct ThemeShareSheet: View {
    let code: String

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    @State private var didCopy = false

    private var link: URL? {
        ThemeShareCode.link(for: code, scheme: GarminFoodDeepLink.scheme)
    }

    /// What the share sheet sends: one line of instructions, the code and
    /// the link, each on its own line so either can be copied on its own.
    private var shareText: String {
        var lines = [
            String(localized: "My GarminFood look. Paste the code in Settings > Appearance > Import theme, or open the link on your iPhone."),
            code
        ]
        if let link { lines.append(link.absoluteString) }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    if let qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                            .accessibilityLabel("QR code with the theme link")
                    }

                    Text("Scan the QR code with the iPhone Camera, or send the code. It contains only appearance settings, never food or personal data.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text(code)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .padding(Theme.Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

                    ShareLink(item: shareText) {
                        Label("Share code", systemImage: "square.and.arrow.up")
                            .foregroundStyle(Theme.onAccent)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)

                    Button {
                        UIPasteboard.general.string = code
                        didCopy = true
                    } label: {
                        Group {
                            if didCopy {
                                Label("Copied", systemImage: "checkmark")
                            } else {
                                Label("Copy code", systemImage: "doc.on.doc")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle("Share theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if let link { qrImage = ThemeQRCode.image(for: link.absoluteString) }
            }
        }
    }
}

/// A QR code image of `text`, scaled up without smoothing.
enum ThemeQRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

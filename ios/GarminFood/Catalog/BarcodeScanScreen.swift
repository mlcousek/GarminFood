// BarcodeScanScreen.swift
//
// Hosts `BarcodeScannerRepresentable`, resolves a scanned code against
// Garmin (food-catalog spec's UPC-A/EAN-13 and "cannot be resolved"
// scenarios), and reports back one of: a resolved `Food`, an unresolved
// code (caller offers custom-food creation, design.md D3's fallback), or a
// cancellation. Degrades to a plain "not available" screen on unsupported
// hardware/OS rather than presenting a broken camera view (task 14.3).
//
// `polish-barcode-scanning` (2026-09-22) added the three pieces of UI
// `BarcodeScanner.swift`'s own header names as the gap: a real viewfinder
// overlay (`BarcodeViewfinderOverlay` below -- purely decorative, VisionKit
// still scans the full camera frame regardless, see that type's own doc
// comment), a success haptic fired from `handleScan` the moment a camera
// scan is reported, and a manual digit-entry fallback
// (`ManualBarcodeEntrySheet`) for when the camera genuinely can't read a
// code -- a real usability path, not decoration, given
// docs/garmin-food-log-contract.md's owner-confirmed finding that even
// Garmin's own native scanner fails on Czech barcodes. The manual path
// reuses `handleScan`/`BarcodeResolution.resolve` unchanged; only the entry
// method differs.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct BarcodeScanScreen: View {
    let onResolved: (Food) -> Void
    let onUnresolved: (String) -> Void
    let onCancel: () -> Void

    @Environment(AppEnvironment.self) private var environment
    @State private var isResolving = false
    @State private var resolutionErrorMessage: String?
    @State private var isPresentingManualEntry = false

    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScannerAvailability.isSupported, BarcodeScannerAvailability.isAvailable {
                    ZStack {
                        BarcodeScannerRepresentable(onScan: { code in handleScan(code, isFromCamera: true) })
                            .ignoresSafeArea()

                        BarcodeViewfinderOverlay()
                            .ignoresSafeArea()

                        VStack {
                            Spacer()
                            Button {
                                isPresentingManualEntry = true
                            } label: {
                                Label("Enter barcode manually", systemImage: "keyboard")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, Theme.Spacing.xl)
                        }

                        if isResolving {
                            ProgressView("Looking up…")
                                .padding(Theme.Spacing.md)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                        }

                        if let resolutionErrorMessage {
                            VStack {
                                Spacer()
                                Text(resolutionErrorMessage)
                                    .font(.footnote)
                                    .padding(Theme.Spacing.sm)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                    .padding(.bottom, Theme.Spacing.lg)
                            }
                        }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "barcode.viewfinder",
                        title: "Scanner unavailable",
                        message: "Barcode scanning isn't supported on this device or OS version. Search by name instead, or note that Garmin's barcode coverage for Czech products is limited anyway."
                    )
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .sheet(isPresented: $isPresentingManualEntry) {
                ManualBarcodeEntrySheet { code in
                    isPresentingManualEntry = false
                    handleScan(code, isFromCamera: false)
                }
            }
        }
    }

    /// `isFromCamera` gates the success haptic: a manual submission isn't a
    /// "scan" in the sense task's haptic requirement means (VisionKit
    /// reading a code off the camera feed), so it doesn't buzz on submit --
    /// the resolution outcome (resolved/unresolved/error) is communicated
    /// the same way for both paths regardless.
    private func handleScan(_ code: String, isFromCamera: Bool) {
        guard !isResolving else { return }
        if isFromCamera { Haptics.success() }
        isResolving = true
        resolutionErrorMessage = nil
        Task {
            defer { isResolving = false }
            do {
                if let food = try await BarcodeResolution.resolve(scannedCode: code, using: environment.garminClient) {
                    onResolved(food)
                } else {
                    onUnresolved(code)
                }
            } catch {
                // A network/auth failure resolving the barcode is NOT the
                // same as "no product for this code" (food-catalog spec's
                // distinct "cannot be resolved" scenario) -- surface it and
                // let the user retry the scan, rather than silently
                // treating a transient failure as "offer a custom food".
                resolutionErrorMessage = "Couldn't look that up right now. Try again."
            }
        }
    }
}

// MARK: - Viewfinder overlay

/// The camera-framing overlay: a centered rounded-rect cutout with corner
/// brackets, a dimmed surround, and an instruction label. Purely visual --
/// `DataScannerViewController` scans its full camera frame regardless of
/// this box (its `regionOfInterest` is deliberately left unset to match),
/// so this must never be read as "scanning is restricted to here," only as
/// "this is the recommended spot to aim." `.allowsHitTesting(false)` so it
/// never steals VisionKit's own tap-to-scan/pinch-to-zoom gestures.
private struct BarcodeViewfinderOverlay: View {
    private let frameSize = CGSize(width: 260, height: 160)
    private let cornerLength: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let frame = CGRect(
                x: (proxy.size.width - frameSize.width) / 2,
                y: (proxy.size.height - frameSize.height) / 2 - Theme.Spacing.xl,
                width: frameSize.width,
                height: frameSize.height
            )

            ZStack {
                Color.black.opacity(0.45)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()

                ViewfinderCorners(cornerLength: cornerLength, cornerRadius: Theme.Radius.md)
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)

                Text("Point your camera at a barcode")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(.black.opacity(0.55), in: Capsule())
                    .position(x: frame.midX, y: frame.maxY + Theme.Spacing.xl)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Four L-shaped corner brackets around a `cornerRadius`-rounded rectangle,
/// each arm `cornerLength` long -- one `Shape` so a single `.stroke(...)`
/// draws all four with matching line caps, rather than four separate
/// overlaid views each needing their own stroke style kept in sync.
private struct ViewfinderCorners: Shape {
    let cornerLength: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        func corner(at point: CGPoint, dx: CGFloat, dy: CGFloat) {
            path.move(to: CGPoint(x: point.x, y: point.y + dy * cornerLength))
            path.addLine(to: CGPoint(x: point.x, y: point.y + dy * cornerRadius))
            path.addQuadCurve(to: CGPoint(x: point.x + dx * cornerRadius, y: point.y), control: point)
            path.addLine(to: CGPoint(x: point.x + dx * cornerLength, y: point.y))
        }

        corner(at: CGPoint(x: rect.minX, y: rect.minY), dx: 1, dy: 1)
        corner(at: CGPoint(x: rect.maxX, y: rect.minY), dx: -1, dy: 1)
        corner(at: CGPoint(x: rect.minX, y: rect.maxY), dx: 1, dy: -1)
        corner(at: CGPoint(x: rect.maxX, y: rect.maxY), dx: -1, dy: -1)

        return path
    }
}

// MARK: - Manual entry fallback

/// The camera-can't-read-it escape hatch (`polish-barcode-scanning`):
/// a plain digit field gated by `FoodLogCore.ManualBarcodeEntry.
/// looksPlausible` so an obviously-wrong entry (empty, a phone number, a
/// food name typed into the wrong box) never spends a network round trip.
/// Submitting hands the typed code back to the caller unchanged -- it goes
/// through the exact same `BarcodeResolution.resolve` call the camera path
/// uses, per this change's "same resolution logic, just skip the camera."
private struct ManualBarcodeEntrySheet: View {
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var isFieldFocused: Bool

    private var isPlausible: Bool { ManualBarcodeEntry.looksPlausible(code) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Barcode digits", text: $code)
                        .keyboardType(.numberPad)
                        .font(.title3.monospacedDigit())
                        .focused($isFieldFocused)
                } footer: {
                    Text("Type the digits printed under the barcode -- usually 8 to 14 numbers.")
                }
            }
            .navigationTitle("Enter barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Trimmed here, not just for the plausibility check above --
                    // `BarcodeResolution.resolve`/`BarcodeNormalization` do no
                    // whitespace handling of their own, so an untrimmed value
                    // that passed `looksPlausible` (which trims) would silently
                    // fail every candidate and read back as "unresolved".
                    Button("Look Up") { onSubmit(code.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        .disabled(!isPlausible)
                }
            }
            .onAppear { isFieldFocused = true }
        }
    }
}

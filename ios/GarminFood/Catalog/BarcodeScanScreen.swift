// BarcodeScanScreen.swift
//
// Hosts `BarcodeScannerRepresentable`, resolves a scanned code against
// Garmin (food-catalog spec's UPC-A/EAN-13 and "cannot be resolved"
// scenarios), and reports back one of: a resolved `Food`, an unresolved
// code (caller offers custom-food creation, design.md D3's fallback), or a
// cancellation. Degrades to a plain "not available" screen on unsupported
// hardware/OS rather than presenting a broken camera view (task 14.3).

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

    var body: some View {
        NavigationStack {
            Group {
                if BarcodeScannerAvailability.isSupported, BarcodeScannerAvailability.isAvailable {
                    ZStack {
                        BarcodeScannerRepresentable(onScan: handleScan)
                            .ignoresSafeArea()

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
        }
    }

    private func handleScan(_ code: String) {
        guard !isResolving else { return }
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

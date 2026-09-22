// BarcodeScanner.swift
//
// The `DataScannerViewController` wrapper (task 14.1). VisionKit requires
// UIKit, which is exactly why this lives in the app target and not
// FoodLogCore (that package's own header comment: no UIKit/SwiftUI import
// anywhere). Barcode scanning is DEPRIORITIZED (design.md D3), and this
// wrapper stays deliberately minimal functionally -- no manual zoom controls
// beyond VisionKit's own pinch-to-zoom, no region-of-interest restriction.
// `polish-barcode-scanning` (2026-09-22) closed the gap worth closing here:
// `BarcodeScanScreen.swift` now draws a real viewfinder overlay on top of
// this view and fires a success haptic the moment `onScan` below reports a
// payload. A torch/flashlight toggle was investigated for that same change
// and deliberately NOT added -- `DataScannerViewController` has no
// documented public API for it (this wrapper never touches a raw
// `AVCaptureDevice`; VisionKit owns the capture session internally and
// doesn't expose one). Guessing at an unconfirmed member is exactly the
// mistake `add-glanceable-surfaces` tasks.md 17.3 already made once
// (`controlWidgetActionHint`) and had to revert after CI's real compiler
// rejected it -- not repeating that here.
//
// Scoped to exactly the symbologies task 14.1 and the food-catalog spec
// name: EAN-13, EAN-8, UPC-E, Code 128, ITF-14, GS1 DataBar. UPC-A has no
// distinct `VNBarcodeSymbology` case -- it arrives here AS an EAN-13 with a
// leading zero (design.md D3), which `BarcodeNormalization`
// (FoodLogCore) handles, not this file.

import SwiftUI
import VisionKit
import Vision

/// `nil` cases mean "can't scan on this device/OS" -- task 14.3's "degrades
/// to 'unavailable' messaging on unsupported hardware rather than crashing."
/// `@MainActor` because `DataScannerViewController.isSupported`/`.isAvailable`
/// are themselves main-actor-isolated.
@MainActor
enum BarcodeScannerAvailability {
    static var isSupported: Bool { DataScannerViewController.isSupported }
    static var isAvailable: Bool { DataScannerViewController.isAvailable }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    private static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .itf14, .gs1DataBar]

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.symbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !context.coordinator.hasStarted else { return }
        context.coordinator.hasStarted = true
        try? uiViewController.startScanning()
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        private var hasReportedScan = false
        var hasStarted = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        // Deliberately no haptic call in this delegate method: whether
        // `DataScannerViewControllerDelegate`'s requirements are themselves
        // main-actor-isolated isn't confirmed (unlike the class's own
        // `isSupported`/`isAvailable`, called out above), and this project
        // has no local compiler to find out which way that guess would
        // break. `BarcodeScanScreen.handleScan` -- provably `@MainActor`
        // since the whole view is -- fires `Haptics.success()` instead, the
        // moment this delegate reports a payload via `onScan` below.
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReportedScan, let first = addedItems.first else { return }
            guard case let .barcode(barcode) = first, let payload = barcode.payloadStringValue else { return }
            hasReportedScan = true
            onScan(payload)
        }
    }
}

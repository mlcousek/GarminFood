// BarcodeScanner.swift
//
// The `DataScannerViewController` wrapper (task 14.1). VisionKit requires
// UIKit, which is exactly why this lives in the app target and not
// FoodLogCore (that package's own header comment: no UIKit/SwiftUI import
// anywhere). Barcode scanning is DEPRIORITIZED (design.md D3) -- this is a
// correct, functional wrapper, not a polished one: no custom highlight UI,
// no manual torch/zoom controls beyond VisionKit's own built-ins.
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

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasReportedScan, let first = addedItems.first else { return }
            guard case let .barcode(barcode) = first, let payload = barcode.payloadStringValue else { return }
            hasReportedScan = true
            onScan(payload)
        }
    }
}

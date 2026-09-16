// ScanBarcodeControl.swift
//
// The barcode-scan Control (design.md D3, tasks.md 17.5). Its action is
// `OpenBarcodeScannerIntent` (../../Shared/OpenBarcodeScannerIntent.swift,
// dual target membership -- see that file's header) -- this Control declares
// the UI and `kind` only; the actual "open the app into the scanner" logic
// lives entirely in the shared intent.

import SwiftUI
import WidgetKit
import AppIntents

@available(iOS 18.0, *)
struct ScanBarcodeControl: ControlWidget {
    static let kind = "com.mlcousek.garminfood.widget.control.scan"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenBarcodeScannerIntent()) {
                Label("Scan Barcode", systemImage: "barcode.viewfinder")
            }
        }
        .displayName("Scan Barcode")
        .description("Opens GarminFood directly into the barcode scanner -- a camera session can't run inside a Control (design.md D3). This is the one flow in this project that is honestly three taps, not two.")
    }
}

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
        // Same key as the intent's description (add-localization 5.2). A
        // camera session can't run inside a Control (design.md D3), so this
        // is the one flow in this project that is honestly three taps, not two.
        .description("Opens GarminFood directly into the barcode scanner.")
    }
}

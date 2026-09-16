// OpenBarcodeScannerIntent.swift
//
// The barcode-scan Control's action (design.md D3, tasks.md 17.5): opens the
// app directly into `BarcodeScanScreen` (ios/GarminFood/Catalog/) rather than
// attempting to scan inline, because a camera capture session cannot run
// inside a widget/Control extension's archived-view rendering context, and
// the 30MB extension memory ceiling would be hit immediately regardless
// (design.md D3).
//
// Conforms to `OpenIntent` per design.md D3 / tasks.md 17.5's explicit
// instruction ("OpenIntent, target membership spanning app + extension"),
// rather than the simpler `openAppWhenRun = true` on a plain `AppIntent`
// seen elsewhere in community sample code -- `OpenIntent` conformance
// implies `openAppWhenRun` on its own, and is the API this project's own
// design doc names. `target` is required by the protocol but there is only
// ever one thing to open here, so it's an `AppEnum` with a single case
// rather than a full `AppEntity` + `EntityQuery` pair, which would be
// needless machinery for "open the one screen this app has."
//
// DUAL TARGET MEMBERSHIP (project.yml comment, matching this file's home in
// `Shared/`, already compiled into both `GarminFood` and
// `GarminFoodWidgetExtension`): the extension needs this TYPE to declare
// `ScanBarcodeControl` (GarminFoodWidget/Controls/ScanBarcodeControl.swift);
// the app needs it too, because `perform()` actually executes in the app's
// own process once the system foregrounds it there.
//
// `.alwaysAllowed` mirrors the quick-pick logging Controls
// (QuickPickLoggingIntents.swift) for the same reason: the fastest path to
// scanning something should not require unlocking first. See that file's
// header for the same genuinely-unconfirmed Face-ID-prompt caveat -- it
// applies here identically, and is not repeated in full below.

import AppIntents

enum ScannerDestination: String, AppEnum {
    case scanner

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "GarminFood Screen"
    static var caseDisplayRepresentations: [ScannerDestination: DisplayRepresentation] = [
        .scanner: DisplayRepresentation(title: "Barcode Scanner")
    ]
}

struct OpenBarcodeScannerIntent: OpenIntent {
    static var title: LocalizedStringResource = "Scan Barcode"
    static var description = IntentDescription("Opens GarminFood directly into the barcode scanner.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Screen")
    var target: ScannerDestination

    init() {
        self.target = .scanner
    }

    init(target: ScannerDestination) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Only meaningful the moment this genuinely executes in the app's
        // own process (see AppNavigationBridge.swift's header) -- which is
        // exactly what `OpenIntent` conformance is for.
        AppNavigationBridge.shared.request(.barcodeScanner)
        return .result()
    }
}

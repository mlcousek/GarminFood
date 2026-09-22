## Why

`BarcodeScanner.swift`'s own header comment says it plainly: barcode
scanning is a "correct, functional wrapper, not a polished one: no custom
highlight UI, no manual torch/zoom controls beyond VisionKit's own
built-ins." The flow itself already works end-to-end -- `FoodCatalogView`'s
toolbar button, the widget's `ScanBarcodeControl`, resolution, and the
unresolved-code fallback into custom-food creation are all wired and
untouched by this change. What's missing is the polish: the screen presents
a bare, full-bleed camera feed with no framing, gives no feedback the
instant a code is actually read, and offers no way forward when the camera
genuinely can't read a code -- which, per
`docs/garmin-food-log-contract.md`'s owner-confirmed finding, is a real
failure mode for Czech barcodes even in Garmin's own official app, not a
hypothetical edge case.

## What Changes

- Add a centered rounded-rect viewfinder overlay (`BarcodeViewfinderOverlay`)
  on `BarcodeScanScreen`: corner brackets, a dimmed surround, and an
  instruction label. Purely visual -- `DataScannerViewController`'s own scan
  region is unaffected (its `regionOfInterest` is deliberately left unset to
  match, so the overlay never claims to restrict where scanning happens).
- Add success haptic feedback (`Haptics.success()`, the app's existing
  shared helper) fired from `BarcodeScanScreen.handleScan` the instant a
  camera scan is reported, before resolution begins.
- Add a manual barcode-entry fallback (`ManualBarcodeEntrySheet`): a button
  opens a small digit-entry sheet, gated by a new pure helper,
  `FoodLogCore.ManualBarcodeEntry.looksPlausible`, and reuses the exact same
  `BarcodeResolution.resolve(scannedCode:using:)` call the camera path
  already uses -- same resolution logic, only the entry method differs.
- Investigated a torch/flashlight toggle for `DataScannerViewController` and
  did **not** add one -- see Non-goals.

## Capabilities

### Modified Capabilities

- `food-catalog` -- the existing "Barcode scanning resolves a scanned
  product to a Garmin food" requirement and its scenarios are unchanged
  (same resolution logic, same UPC-A/EAN-13 normalisation, same
  unresolved-code fallback). This change adds one new, additive requirement
  to that capability: a manual entry method that reaches the identical
  resolve/unresolve behaviour without a camera. See
  `specs/food-catalog/spec.md` in this change for the delta.

## Non-goals

- **A torch/flashlight toggle.** `DataScannerViewController` has no
  documented public API for controlling the flashlight -- unlike a raw
  `AVCaptureDevice` (which this project's wrapper never touches; VisionKit
  owns the capture session internally). Guessing at an unconfirmed member
  is exactly the mistake `add-glanceable-surfaces` tasks.md 17.3 already
  made once (`controlWidgetActionHint`, reverted after CI's real compiler
  rejected it) -- not repeating that here. Revisit only if a confirmed API
  surfaces (e.g. verified in real Xcode once the owner has access, or a
  future SDK release documents one).
- **Restricting the camera's actual scan region to the viewfinder box.**
  `DataScannerViewController.regionOfInterest` could in principle be set to
  match the overlay, but that changes scan *behavior*, not just its
  presentation, and risks making the scanner miss a barcode that's readable
  but outside the drawn box on an unfamiliar screen size/orientation. Out of
  scope for a presentation-focused change; the overlay is explicitly
  documented as a visual aid only, not a restriction.
- **Manual entry's own barcode checksum validation.** `ManualBarcodeEntry.
  looksPlausible` is a length/digit-only gate (8-14 digits, matching this
  project's scanned symbologies), not a real EAN/UPC check-digit validator --
  a checksum failure would still be worth trying against Garmin's search
  route, and building one is unrelated scope.
- **Any change to `BarcodeResolution`, `BarcodeNormalization`, the toolbar
  entry point in `FoodCatalogView`, or the widget Control wiring
  (`ScanBarcodeControl`/`AppNavigationBridge`).** All confirmed already
  working end-to-end before this change; none of it is touched.

## Impact

Affected surfaces: `ios/GarminFood/Catalog/BarcodeScanScreen.swift`
(viewfinder overlay, manual-entry sheet, haptic call, `handleScan` gains an
`isFromCamera` parameter), `ios/GarminFood/Catalog/BarcodeScanner.swift`
(header comment only -- documents the haptic now living in
`BarcodeScanScreen` and the torch investigation), and
`ios/FoodLogCore/Sources/FoodLogCore/BarcodeResolution.swift` (adds
`ManualBarcodeEntry`, a pure validation helper, with unit tests in
`BarcodeResolutionTests.swift`). No changes to `GarminKit`, no new Garmin
routes, no changes to `AppEnvironment`/`AppServices`.

**Depends on**: `add-food-log-core` (the barcode flow this change polishes)
and `add-glanceable-surfaces` (the widget Control entry point into this same
screen, left untouched).

**Unblocks**: nothing further planned.

## 1. Viewfinder overlay

- [x] 1.1 Add `BarcodeViewfinderOverlay` (private view in
      `BarcodeScanScreen.swift`): a centered rounded-rect cutout (dimmed
      surround via a `blendMode(.destinationOut)` + `compositingGroup()`
      punch-through, not a `.mask`), corner brackets drawn as a single
      `Shape` (`ViewfinderCorners`), and an instruction label
      ("Point your camera at a barcode"). `.allowsHitTesting(false)` so it
      never intercepts VisionKit's own tap/pinch gestures.
- [x] 1.2 Confirm `DataScannerViewController.regionOfInterest` is left
      unset -- the overlay is presentation-only, per Non-goals. Documented
      in the overlay's own doc comment so a future editor doesn't
      "helpfully" wire the two together.
- [ ] 1.3 **Needs a real device or Xcode Previews to actually verify** (no
      Mac available here): the overlay's frame position, sizing at phone
      vs. larger-screen widths, and legibility of the dimmed/bracket
      contrast in both light and dark camera feeds. Left unchecked rather
      than assumed correct.

## 2. Success haptic

- [x] 2.1 `BarcodeScanScreen.handleScan` gains an `isFromCamera: Bool`
      parameter and calls the app's existing shared `Haptics.success()`
      (not a raw `UINotificationFeedbackGenerator` call) when true, so the
      user's haptics-enabled preference (`AppPreferences.hapticsEnabled` via
      `Haptics.isEnabled`) is respected automatically, matching every other
      haptic call site in the app.
- [x] 2.2 Fired from `BarcodeScanScreen` (provably `@MainActor`, since the
      whole view is), not from `BarcodeScannerRepresentable.Coordinator`'s
      `DataScannerViewControllerDelegate` conformance -- that type's actor
      isolation isn't confirmed one way or the other (unlike
      `DataScannerViewController.isSupported`/`.isAvailable`, which the
      existing header comment already documents as main-actor-isolated),
      and there's no local compiler here to find out which way a wrong
      guess would break. Documented in both files' header comments.

## 3. Manual entry fallback

- [x] 3.1 Add `FoodLogCore.ManualBarcodeEntry.looksPlausible(_:)`
      (`BarcodeResolution.swift`): a pure, trimmed length (8-14 digits) +
      digits-only gate, matching this project's scanned symbologies
      (EAN-8 through ITF-14). Not a real checksum validator -- see
      proposal.md's Non-goals.
- [x] 3.2 Unit tests in `BarcodeResolutionTests.swift`: shortest/longest
      valid lengths, surrounding-whitespace tolerance, too-short, too-long,
      empty, and non-digit input. Same no-mocks pattern as the file's
      existing `BarcodeNormalization`/`BarcodeResolution` tests.
- [x] 3.3 Add `ManualBarcodeEntrySheet` (private view in
      `BarcodeScanScreen.swift`): a `Form` with a number-pad `TextField`,
      gated "Look Up" button, reached via a new "Enter barcode manually"
      button over the camera feed. Submission trims the typed code before
      handing it to `handleScan` -- `BarcodeResolution`/`BarcodeNormalization`
      do no whitespace handling of their own, so an untrimmed value that
      passed the (trimming) plausibility check would otherwise silently
      fail every resolution candidate.
- [x] 3.4 Manual submission reuses `handleScan`/`BarcodeResolution.resolve`
      unchanged -- `isFromCamera: false` only skips the success haptic
      (task 2.1); resolution, the loading state, the error message, and the
      resolved/unresolved callbacks are identical to the camera path.

## 4. Torch toggle (investigated, not built)

- [x] 4.1 Checked `DataScannerViewController`'s documented public API
      surface for a torch/flashlight control. Found none -- this wrapper
      never holds a reference to the underlying `AVCaptureDevice`
      (VisionKit owns the capture session internally), and no
      `DataScannerViewController` member for torch control could be
      confirmed. Not added, per proposal.md's Non-goals and
      `add-glanceable-surfaces` tasks.md 17.3's precedent (a guessed
      `ControlWidgetButton` member that CI's real compiler rejected).

## 5. Documentation

- [x] 5.1 Updated header comments in `BarcodeScanScreen.swift` and
      `BarcodeScanner.swift` to describe what changed and why, matching
      this project's "every `.swift` file explains why it exists" style.
- [x] 5.2 This change's own proposal.md/tasks.md/specs delta.

## 6. Verification

- [ ] 6.1 **CARRIED, needs CI.** No local Swift/Xcode toolchain (no Mac) --
      push this branch and let `.github/workflows/build.yml` run `swift
      test` for `FoodLogCore` (task 3.2's new tests) and `xcodebuild` for
      the app target. That is the real correctness signal for the SwiftUI
      changes, which cannot be compiled locally.
- [ ] 6.2 **CARRIED, needs a real device.** Sideload via AltStore and
      confirm: the overlay looks right on an actual camera feed, the haptic
      fires on a real scan, manual entry resolves/fails the same way a
      camera scan would, and the "Enter barcode manually" button doesn't
      overlap the instruction label or get clipped by the safe area on the
      owner's actual iPhone.

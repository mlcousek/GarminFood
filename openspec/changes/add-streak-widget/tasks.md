## 1. Streak-themed Home Screen widget

- [x] 1.1 Build `GarminFoodStreakWidget.swift`: `TimelineEntry`
      (date-only) + `TimelineProvider` returning a single entry with
      `Timeline(..., policy: .never)` -- same "nothing to ever refresh
      towards" reasoning as `GarminFoodHomeWidget.swift`, copied into this
      file's own header comment adapted to this widget.
- [x] 1.2 `systemSmall` layout: flame SF Symbol (`flame.fill`) + "Log
      today" caption, `Theme.flameGradient` background via
      `.containerBackground(for: .widget)`.
- [x] 1.3 `systemMedium` layout: larger flame + two lines of copy ("Keep
      your streak going" / "Log today"), same background, switched on
      `\.widgetFamily`.
- [x] 1.4 `widgetURL(GarminFoodDeepLink.logFoodURL)` -- reuses the
      existing `.logFood` deep-link action; no new `Action` case added.
- [x] 1.5 Accessibility: `.accessibilityElement(children: .combine)` +
      `.accessibilityLabel`/`.accessibilityHint`, matching
      `GarminFoodHomeWidgetView`'s pattern.
- [x] 1.6 `#Preview(as: .systemSmall)` and `#Preview(as: .systemMedium)`.

## 2. Registration

- [x] 2.1 Add `GarminFoodStreakWidget()` to `GarminFoodWidgetBundle.swift`,
      alongside the existing `GarminFoodHomeWidget()`.

## 3. Verification

- [ ] 3.1 **Requires CI (no local Xcode/Swift toolchain -- "no Mac"
      constraint).** Push a branch/PR so `.github/workflows/build.yml` runs
      `xcodebuild` for the widget extension target and confirms this new
      file compiles and the bundle registers cleanly.
- [ ] 3.2 **Requires a real device (Controls/widgets aren't meaningfully
      exercised in the Simulator per this project's prior experience).**
      Confirm both `.systemSmall` and `.systemMedium` variants render
      correctly in the widget gallery, and that tapping either opens the
      app straight into the food catalog. Not verifiable in this
      environment -- flagged, not claimed done.

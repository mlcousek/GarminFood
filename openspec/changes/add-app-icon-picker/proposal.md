## Why

The app's only icon has always been a bare "GF" wordmark on an orange gradient — no attribution, and no variety. The owner asked for the wordmark to actually say who made it ("GF by Jirka", not just "GF") and for a small set of alternate icons the app itself lets you switch between, the same way many personal/indie apps do.

## What Changes

- Redesign the primary icon (`Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`) to add the "by Jirka" tagline under the existing "GF" wordmark — same gradient, same asset-catalog wiring, image content only.
- Add 5 alternate icons — Streak (ember/flame gradient, matching the app's own streak UI palette), Macro (a carbs/protein/fat tri-color diagonal, matching `Theme.carbs`/`Theme.protein`/`Theme.fat`), Midnight (dark, for anyone who wants a low-key Home Screen tile), Mint (a green/`Theme.success`-toned variant), and Pastel (a light, soft variant) — all carrying the same "GF by Jirka" wordmark for a consistent identity across every option.
- Add an "App Icon" row in Settings (`AppIconPickerView`, listed alongside Sync Queue/Reminders/Diagnostics) that lists all 6 options with a live thumbnail and a checkmark on whichever is active, calling `UIApplication.setAlternateIconName` on selection.
- The 5 alternates are registered as classic, loose-file `CFBundleAlternateIcons` entries in `project.yml` (`@2x`/`@3x` PNGs in a new `GarminFood/AppIcons/` folder), NOT as additional asset-catalog imagesets — this is the older but far better-documented and more reliably-confirmed mechanism `setAlternateIconName` has used since iOS 10.3, chosen deliberately over the newer (but less uniformly documented) single-size-asset-catalog alternate-icon convenience, since there is no local Xcode to catch a wrong guess and CI's `xcodebuild` would not catch an Info.plist key/structure mistake either (it only confirms the app compiles, not that icon-switching actually works on device).

## Capabilities

### New Capabilities

- `app-icon-picker` — the Settings-reachable alternate-icon picker and its 5 alternate icon assets.

### Modified Capabilities

None (the primary icon's image content changes; its own asset-catalog wiring, `CFBundleIconName`, does not).

## Non-goals

- **iPad-sized alternate icons.** This target is iPhone-only (`TARGETED_DEVICE_FAMILY: "1"` in `project.yml`) — no `~ipad` icon variants are needed or added.
- **A Settings-driven live preview of the Home Screen itself.** The picker shows each option's own icon thumbnail; it does not attempt to mock up the actual Home Screen (not something `UIApplication`'s API supports anyway).
- **Syncing the chosen icon anywhere.** Purely a local `UIApplication` preference, like the OS itself treats it — no Garmin involvement, no new store.

## Impact

Affected surfaces: `ios/GarminFood/Assets.xcassets/AppIcon.appiconset/` (primary icon image only), a new `ios/GarminFood/AppIcons/` folder (10 loose PNGs, 5 icons × `@2x`/`@3x`), `ios/GarminFood/Profile/` (two new files: `AppIconOption.swift`, `AppIconPickerView.swift`), `ios/GarminFood/Profile/SettingsView.swift` (one new row), and `ios/project.yml` (`CFBundleIcons`/`CFBundleAlternateIcons`).

**Depends on**: nothing — self-contained.

**Unblocks**: nothing further planned.

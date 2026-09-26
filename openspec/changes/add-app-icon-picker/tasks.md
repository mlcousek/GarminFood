## 1. Icon assets

- [x] 1.1 Redesigned the primary icon (accent → accentDeep gradient, unchanged) to add a "by Jirka" tagline under "GF"; replaced `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` in place (same filename, same `Contents.json`, image content only).
- [x] 1.2 Generated 5 alternate 1024×1024 designs (Streak: ember→accentDeep diagonal; Macro: carbs→protein→fat tri-band diagonal with a soft rounded backing panel behind the wordmark for legibility over the light mid-band; Midnight: dark charcoal with coral text; Mint: `Theme.success`-toned green; Pastel: light cream/peach with dark-coral text), each carrying the same "GF" + "by Jirka" wordmark. Generated via a throwaway Python/Pillow script (no ImageMagick/rsvg-convert available on this machine; Pillow was) — fully opaque RGB, no transparency, no manually-rounded corners (iOS applies its own mask).
- [x] 1.3 Downsampled each alternate to `@2x` (120×120) and `@3x` (180×180) PNGs (Lanczos resample) and placed them as loose files at `GarminFood/AppIcons/<Name>@2x.png`/`@3x.png` — NOT in the asset catalog. iPhone-only target, so no `~ipad` sizes.

## 2. Registration

- [x] 2.1 Added `CFBundleIcons`/`CFBundleAlternateIcons` to `project.yml`'s `GarminFood` target `info.properties`, one entry per alternate with `CFBundleIconFiles: [<Name>]` + `UIPrerenderedIcon: false`. Left `CFBundleIconName: AppIcon` (the primary icon's own asset-catalog wiring) untouched and did not add a `CFBundlePrimaryIcon` entry — confirmed via research that the two mechanisms coexist without conflict (primary via `CFBundleIconName`, alternates via `CFBundleAlternateIcons`), rather than guessing.
- [x] 2.2 Validated the resulting `project.yml` parses as well-formed YAML (loaded with PyYAML and printed the `CFBundleIcons` subtree) before committing — no local XcodeGen to actually run `xcodegen generate` against it.

## 3. Picker UI

- [x] 3.1 `AppIconOption` (`Profile/AppIconOption.swift`): 6 cases (`.default` + 5 alternates), raw value doubling as both the `setAlternateIconName` argument and the exact `project.yml` `CFBundleAlternateIcons` key, plus a title and a `UIImage(named:)`-compatible preview image name for each.
- [x] 3.2 `AppIconPickerView` (`Profile/AppIconPickerView.swift`): a `List` of all 6 options, each with a real thumbnail (`UIImage(named:)`, which resolves both the loose alternate-icon files and the asset-catalog primary icon by name) and a checkmark on the currently-active one (`UIApplication.shared.alternateIconName`, `nil` → `.default`). Tapping a row calls `setAlternateIconName`, with an alert on failure and a `supportsAlternateIcons` guard.
- [x] 3.3 Added an "App Icon" row to `SettingsView`, alongside the existing Sync Queue/Reminders/Diagnostics rows.

## 4. Verification

- [x] 4.1 **CARRIED, needs CI.** No local Swift/Xcode toolchain — push this branch and let `.github/workflows/build.yml`'s `xcodebuild` confirm the app target (including the new Info.plist keys and loose bundle resources) actually builds. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.2 **CARRIED, needs a real device.** Sideload via AltStore and confirm: all 6 icons actually appear correctly in the system's icon-change confirmation prompt (iOS shows its own system alert on `setAlternateIconName`, not just this app's UI), the Home Screen icon genuinely changes, the picker's checkmark tracks the real active icon after a relaunch, and none of the wordmarks look clipped/misaligned on an actual device screen (only ever previewed here as raw PNGs, never in Xcode's icon-composer/simulator).

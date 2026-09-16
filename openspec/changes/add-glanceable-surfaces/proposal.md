## Why

This is the change that actually delivers "widget on the lock screen and on the desktop" — but the honest version of that request, not the literal one. Apple's own documentation states that Lock Screen *widget* buttons are inert while the device is locked: "the system doesn't perform actions unless a person authenticates and unlocks their device." The interactive lock-screen affordance that Apple ships for exactly this purpose is a **Control** (iOS 18+) — the same API surfaces in Control Center, in either Lock Screen bottom-button slot, and on the Action Button, from one implementation. Home Screen widgets and Siri shortcuts round out the fast-entry surface; a Live Activity is deliberately excluded, because its 8-hour active cap cannot represent a 24-hour running total.

## What Changes

- Add **Controls** (`ControlWidgetButton`) bound to the user's top quick-pick foods, placeable in Control Center, on the Lock Screen, and on the Action Button, using `authenticationPolicy = .alwaysAllowed` so they are permitted to fire without unlocking (whether that survives the app-foregrounding step their action also requires is unconfirmed — see design.md D1).
- Add a **Home Screen widget** (`systemSmall`) as a static, data-free "open the app" shortcut — icon, label, `widgetURL` only. **REVISED 2026-09-14**: the originally-planned `Gauge`-based calorie ring plus 2–4 interactive quick-add buttons is dropped entirely, not degraded — `add-garmin-auth-and-sync` task 6.4 confirmed there is no App Group or Keychain Sharing on this account, so a widget's own process has no channel to Garmin or to this app's local data, ever (design.md D2).
- Add a **static Lock Screen accessory widget** (`accessoryCircular`/`accessoryRectangular`) — the same static shortcut as the Home Screen widget, not interactive (because it cannot be while locked) and, per the same D2 revision, not showing a ring or any other data either.
- Add **App Shortcuts** (2–5, well under Apple's 10-shortcut cap) for Siri and Spotlight voice logging.
- Add a **barcode-scan Control** that opens the app directly into the scanner (`add-food-log-core`'s VisionKit flow), since a camera session cannot run inside a widget.
- Add **macOS availability for free**: the Home Screen widget appears on the Mac desktop via Continuity (macOS 14+/iOS 17+), requiring no separate build, provided the local store's file protection is `NSFileProtectionCompleteUntilFirstUserAuthentication`.

## Capabilities

### New Capabilities

- `lock-screen-and-controls` - the Control Center / Lock Screen / Action Button logging surface, and the static (data-free) Lock Screen shortcut.
- `home-screen-widget` - the static, data-free "open the app" shortcut on the Home Screen and, via Continuity, the Mac desktop.
- `siri-and-shortcuts` - voice and Spotlight-driven logging through App Intents.

### Modified Capabilities

None.

## Non-goals

- **A Live Activity for the daily total.** Explicitly rejected — ActivityKit's 8-hour active / 12-hour total lifetime cannot represent a running 24-hour count. A bounded-session Live Activity (e.g. a fasting timer) is out of scope entirely for this project.
- **A watchOS app.** A watch Control and complication are worth a future change once the phone-side flow is proven; not built here.
- **A native macOS widget extension.** Continuity gives Mac availability for free; a native target is only worth it if the phone being nearby becomes a real limitation, which is unverified.
- **Push-based instant widget updates.** iOS 26 `WidgetPushHandler`/`ControlPushHandler` require APNs, which requires a paid developer account this project does not have. Widgets rely on the free reload budget plus the guaranteed free reload after any button tap.

## Impact

Affected surfaces: a widget extension target (Home Screen widgets + Lock Screen accessories), a Control definition (possibly living in the same extension bundle), and the App Shortcuts provider in the main app target.

**Depends on**: `add-garmin-auth-and-sync` (an intent needs to authenticate and enqueue while the app isn't running) and `add-food-log-core` (a Control needs a food and serving to log against).

**Unblocks**: nothing further planned; this is the last app-side change. `add-companion-surfaces` runs in parallel, not after.

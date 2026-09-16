## Context

The single most consequential fact from platform research (2026-09-14): Lock Screen widget buttons are documented as inert while locked. Apple's own words — "On a locked device, buttons and toggles are inactive — the system doesn't perform actions unless a person authenticates and unlocks their device." A design built around interactive Lock Screen *widgets* would ship a feature that silently does nothing until Face ID fires, four steps deep (wake → tap → authenticate → tap) instead of the two the whole project exists to deliver.

Apple's actual answer to "interactive thing on the lock screen" is a **Control** (`ControlWidget`, iOS 18+): one implementation, placeable in Control Center, either Lock Screen bottom-button slot, and the Action Button, with `IntentAuthenticationPolicy.alwaysAllowed` explicitly documented to permit running "at any time, including when the device is locked."

The other governing fact: Live Activities cap out at 8 hours active / 12 hours total displayed. A calorie total spans a calendar day. The two numbers do not fit together, and no configuration changes that.

**A third governing fact, settled 2026-09-14 by `add-garmin-auth-and-sync` task 6.4, changes what "glanceable" can mean here.** There is no App Group and no Keychain Sharing on this free-tier account (`errSecMissingEntitlement`/-34018, confirmed live). That is not just "the app and widget can't share a token" — it means WidgetKit's own refresh mechanism cannot get data from the app into a widget's process under any circumstance. `WidgetCenter.reloadTimelines()` does not hand the widget a value; it tells the widget to re-run its own `getTimeline()`, in its own isolated process, which has no channel back to anything the app knows. A widget can only display data it fetches itself, and it cannot authenticate to Garmin itself (no shared token, and no way to present a browser sign-in from inside a widget's non-interactive rendering context). The practical result: **a Home Screen or Lock Screen widget cannot show a real, Garmin-sourced number on this account — not eventually, not occasionally, not once.** This is the single biggest concession this free-tier plan makes against the original "glanceable ring" goal, and it is exactly what a paid Developer Program's App Groups would remove.

## Goals / Non-Goals

**Goals:**

- The fastest logging path requires no more than a tap-and-hold (Action Button) or a wake-and-tap (Lock Screen control slot), with a brief app-open flash to reach the app's own stored credential (see D1) rather than a fully invisible background action — no *manual* authentication step, but not zero visible transition either.
- A widget exists on the Home Screen and Lock Screen as a fast entry point (deep-link / quick-add shortcut), honestly scoped to what's achievable without App Groups — see D2.
- Voice logging exists for the small number of things worth saying out loud.

**Non-Goals:**

- Matching every Yazio surface. Three or four surfaces done well beat eight done thinly, especially against Apple's hard caps (10 App Shortcuts, a 30MB widget-extension memory ceiling).
- Sub-minute refresh. WidgetKit's per-instance daily budget (roughly 40-70 reloads across 24 hours) makes that unrealistic regardless of design; the free reload guaranteed after any button tap covers the case that actually matters.

## Decisions

### D1 — Controls, not Lock Screen widgets, are the primary interactive surface — but they briefly open the app, not run invisibly

Per the Context section, accessory widget buttons are non-functional while locked, full stop — that part of the original reasoning stands. `ControlWidgetButton` entries for the user's top quick-pick foods (from `add-food-log-core`'s local ranking) are placed in Control Center and offered for the Lock Screen and Action Button.

**Revised, 2026-09-14, after `add-garmin-auth-and-sync` task 6.4's Keychain result.** The original plan gave each Control's `AppIntent` `supportedModes = [.background]`, meaning `perform()` runs in the widget extension's own process — invisibly, no app-open. That no longer works: the extension process has no Garmin credential (no shared Keychain, confirmed), so it cannot make the API call at all from there. The intent must instead conform to `ForegroundContinuableIntent` (or use `supportedModes` including `.foreground(...)`), which runs `perform()` inside the **app's own process**, where the app's own Keychain-stored token is available. Tapping the Control now briefly opens the app to do the real work, rather than acting invisibly.

**Genuinely unconfirmed, flagged rather than assumed**: whether `authenticationPolicy = .alwaysAllowed` (permitting the intent to run while locked) still avoids a Face ID/passcode prompt once the implementation must also foreground the app — since visibly showing app content on a locked device is normally exactly what triggers the unlock prompt in the first place. This can only be settled by building it and testing on the real device; it is not something to claim either way without that test.

The Lock Screen accessory widget still exists, but now strictly as a **static shortcut** — an icon/label with a `widgetURL` tap-to-open, per D2. It carries no live number and needs no Garmin credential. Opening the app this way requires unlocking, the same as opening any app from a locked Home Screen.

### D2 — Widgets cannot show live Garmin data at all; they are static shortcuts, not displays

**Revised, 2026-09-14 — this is the largest concession in this change.** `add-garmin-auth-and-sync` task 6.4 confirmed no App Group and no Keychain Sharing exist on this account. WidgetKit's refresh mechanism (`WidgetCenter.reloadTimelines()`) does not hand a widget a value from the app — it tells the widget to re-run its own `getTimeline()` in its own isolated process, which has no channel to anything the app knows and cannot authenticate to Garmin on its own (no token, and no ability to present a browser sign-in from a widget's non-interactive rendering context). There is no version of this that "eventually" shows real data; it is a permanent structural limit on this account, not a caching lag.

Consequence: the Home Screen and Lock Screen widgets are redesigned as **static, data-free shortcuts** — an icon, a label, and a `widgetURL` (or an `OpenIntent`-based Control) that opens the app. No `TimelineProvider` fetches anything from Garmin; there is nothing for it to fetch that it could ever successfully retrieve. Any actual number the user wants to see requires opening the real app, where the app's own process (with its own Keychain token) can fetch it normally.

This is precisely the capability a paid Apple Developer Program membership would restore: App Groups would give the app a shared container to write a cached total into, which a widget's `TimelineProvider` could then read without needing its own Garmin credential at all. Recorded here as a concrete, specific reason to revisit that decision if the static-shortcut widget feels too limited in practice — not a vague "maybe pay eventually," but this exact, named capability.

### D3 — Barcode scanning is a Control that opens the app, never an in-widget action

`DataScannerViewController` needs a presented view controller and a live camera session — neither exists in a widget extension's archived-view rendering, and the 30MB extension memory ceiling would be hit immediately regardless. The scan action is a `ControlWidgetButton` whose intent conforms to `OpenIntent` (added to both the app and extension's target membership), launching the app directly into the scanner. This is the one flow in the project that is honestly three taps, not two, and that is stated plainly rather than glossed over.

### D4 — No Live Activity for the running total; reconsidered only for bounded sessions

Ruled out per Context. If a future need arises for something Live-Activity-shaped (a fasting-window countdown, a single meal-logging session), it is scoped to well under 8 hours and treated as a separate, later change — not retrofitted onto this one.

### D5 — App Shortcuts are few and specific

Apple hard-caps at 10 App Shortcuts per app (a compile-time error beyond that) and recommends 2-5. This project ships shortcuts for: log the top quick-pick food, log a specified food by name (parameterised), and open the scanner. Each phrase includes `\(.applicationName)` as required, and each completed log donates via `IntentDonationManager` so Siri Suggestions and Spotlight improve with use.

### D6 — macOS support rides Continuity, at zero additional engineering cost

Since macOS 14 + iOS 17, an iPhone's widgets appear as Mac widgets automatically, executing the intent back on the iPhone and returning an updated timeline — no separate macOS target. The one requirement is file protection: `NSFileProtectionComplete` on the local store would silently make the widget unavailable on the Mac, so the per-process store (per `add-garmin-auth-and-sync` D3) uses `NSFileProtectionCompleteUntilFirstUserAuthentication` throughout, a constraint already recorded there and reaffirmed here because this is the change it would otherwise silently break.

## Risks / Trade-offs

- **`authenticationPolicy = .alwaysAllowed` on a food-logging action means anyone holding the locked phone can log food** → accepted. The blast radius of a false log is "delete a food entry later," not account or payment access. Named explicitly so it is a decision, not an oversight. **Compounded by D1's revision**: since the actual network call now must foreground the app (no extension-side credential), it is genuinely unconfirmed whether `.alwaysAllowed` avoids a Face ID/passcode prompt at that point — untested until built on a real device.
- **No widget can ever show live Garmin data on this account (D2)** → not a bounded lag, a permanent structural limit. Accepted; widgets are redesigned as static open-the-app shortcuts. The named mitigation is not a technical one but a decision point: this is exactly what a paid Developer Program's App Groups would fix, and it's worth revisiting if the static shortcut proves unsatisfying in daily use.
- **The barcode Control genuinely needs three taps** → named in D3 rather than claimed away. Still faster than opening the Garmin Connect app and navigating to nutrition.

## Open Questions

1. **Does the Action Button binding require the user to have an iPhone 15 Pro or later?** Yes, per platform research — Controls on the Action Button need that hardware; Control Center and the Lock Screen slots work more broadly (iOS 18+, any device with those UI surfaces). Document this as a hardware-dependent bonus, not a baseline requirement.
2. **Can a `ControlWidgetButton`'s inline "Logged ✓" status remain accurate without a shared local store?** Tentatively yes via `controlWidgetStatus`, set from the intent's own immediate result rather than a later shared read. Verify empirically once Controls are built.

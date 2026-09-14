## Context

The single most consequential fact from platform research (2026-09-14): Lock Screen widget buttons are documented as inert while locked. Apple's own words — "On a locked device, buttons and toggles are inactive — the system doesn't perform actions unless a person authenticates and unlocks their device." A design built around interactive Lock Screen *widgets* would ship a feature that silently does nothing until Face ID fires, four steps deep (wake → tap → authenticate → tap) instead of the two the whole project exists to deliver.

Apple's actual answer to "interactive thing on the lock screen" is a **Control** (`ControlWidget`, iOS 18+): one implementation, placeable in Control Center, either Lock Screen bottom-button slot, and the Action Button, with `IntentAuthenticationPolicy.alwaysAllowed` explicitly documented to permit running "at any time, including when the device is locked."

The other governing fact: Live Activities cap out at 8 hours active / 12 hours total displayed. A calorie total spans a calendar day. The two numbers do not fit together, and no configuration changes that.

## Goals / Non-Goals

**Goals:**

- The fastest logging path requires no more than a tap-and-hold (Action Button) or a wake-and-tap (Lock Screen control slot), with no authentication step.
- The glanceable ring is visible on the Home Screen, the Lock Screen, and the Mac desktop, and always reflects Garmin's own total.
- Voice logging exists for the small number of things worth saying out loud.

**Non-Goals:**

- Matching every Yazio surface. Three or four surfaces done well beat eight done thinly, especially against Apple's hard caps (10 App Shortcuts, a 30MB widget-extension memory ceiling).
- Sub-minute refresh. WidgetKit's per-instance daily budget (roughly 40-70 reloads across 24 hours) makes that unrealistic regardless of design; the free reload guaranteed after any button tap covers the case that actually matters.

## Decisions

### D1 — Controls, not Lock Screen widgets, are the primary interactive surface

Per the Context section, this is not a stylistic choice — accessory widget buttons are non-functional while locked, full stop. `ControlWidgetButton` entries for the user's top quick-pick foods (from `add-food-log-core`'s local ranking) are placed in Control Center and offered for the Lock Screen and Action Button. Each carries `authenticationPolicy = .alwaysAllowed` and an `AppIntent` with `supportedModes = [.background]`, so tapping logs the food and returns without opening the app.

The Lock Screen accessory widget still exists, but strictly as a **read-only** ring (`accessoryCircular`, `vibrant`/`accented` rendering only — `fullColor` is unavailable in that family). It shows the number; it does not try to take the tap.

### D2 — The Home Screen widget's ring always reads fresh from Garmin

Per `garmin-sync`'s D3, there is no shared local aggregate to read (no App Group on the free tier). The widget's `TimelineProvider` calls the daily-summary route directly, with a cache of tens of seconds to respect the reload budget, and shows any of *its own* still-pending entries added provisionally on top, visually marked pending. A `Button(intent:)` tap on the widget's own quick-add tiles triggers the guaranteed free reload WidgetKit grants after any intent, so the ring updates instantly for a same-widget tap without touching the budget; cross-surface updates (logged from the Control, seen on the widget) rely on the normal reload cycle or the next app foreground.

### D3 — Barcode scanning is a Control that opens the app, never an in-widget action

`DataScannerViewController` needs a presented view controller and a live camera session — neither exists in a widget extension's archived-view rendering, and the 30MB extension memory ceiling would be hit immediately regardless. The scan action is a `ControlWidgetButton` whose intent conforms to `OpenIntent` (added to both the app and extension's target membership), launching the app directly into the scanner. This is the one flow in the project that is honestly three taps, not two, and that is stated plainly rather than glossed over.

### D4 — No Live Activity for the running total; reconsidered only for bounded sessions

Ruled out per Context. If a future need arises for something Live-Activity-shaped (a fasting-window countdown, a single meal-logging session), it is scoped to well under 8 hours and treated as a separate, later change — not retrofitted onto this one.

### D5 — App Shortcuts are few and specific

Apple hard-caps at 10 App Shortcuts per app (a compile-time error beyond that) and recommends 2-5. This project ships shortcuts for: log the top quick-pick food, log a specified food by name (parameterised), and open the scanner. Each phrase includes `\(.applicationName)` as required, and each completed log donates via `IntentDonationManager` so Siri Suggestions and Spotlight improve with use.

### D6 — macOS support rides Continuity, at zero additional engineering cost

Since macOS 14 + iOS 17, an iPhone's widgets appear as Mac widgets automatically, executing the intent back on the iPhone and returning an updated timeline — no separate macOS target. The one requirement is file protection: `NSFileProtectionComplete` on the local store would silently make the widget unavailable on the Mac, so the per-process store (per `add-garmin-auth-and-sync` D3) uses `NSFileProtectionCompleteUntilFirstUserAuthentication` throughout, a constraint already recorded there and reaffirmed here because this is the change it would otherwise silently break.

## Risks / Trade-offs

- **`authenticationPolicy = .alwaysAllowed` on a food-logging action means anyone holding the locked phone can log food** → accepted. The blast radius of a false log is "delete a food entry later," not account or payment access. Named explicitly so it is a decision, not an oversight.
- **Cross-surface consistency (Control logs, widget doesn't reflect it instantly)** → accepted per D2; bounded by the reload cycle and app-foreground drain, not indefinite.
- **The barcode Control genuinely needs three taps** → named in D3 rather than claimed away. Still faster than opening the Garmin Connect app and navigating to nutrition.
- **Free-tier reload budget is a hard ceiling this design cannot negotiate around** → the design leans on the *free* guaranteed reload after any intent, which is not budget-constrained, rather than fighting the timeline-reload budget for freshness.

## Open Questions

1. **Does the Action Button binding require the user to have an iPhone 15 Pro or later?** Yes, per platform research — Controls on the Action Button need that hardware; Control Center and the Lock Screen slots work more broadly (iOS 18+, any device with those UI surfaces). Document this as a hardware-dependent bonus, not a baseline requirement.
2. **Can a `ControlWidgetButton`'s inline "Logged ✓" status remain accurate without a shared local store?** Tentatively yes via `controlWidgetStatus`, set from the intent's own immediate result rather than a later shared read. Verify empirically once Controls are built.

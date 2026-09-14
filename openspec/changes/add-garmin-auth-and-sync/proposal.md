## Why

Garmin closed scripted login behind Cloudflare in March 2026, so the app can never take a username and password. It must borrow a session established in a real browser, hold the resulting long-lived token safely, and share it with a widget extension running in a different process. Separately, a food entry must reach Garmin without the user ever waiting on the network — which means a durable outbox, not a request. These concerns are inseparable: the outbox is what survives an expired token, and re-authentication is what drains it.

## What Changes

- Add a **browser-based token bootstrap**: the user signs in on Garmin's own page inside `ASWebAuthenticationSession`, and the app captures the resulting ticket and exchanges it for tokens. The app never sees the password.
- Add **Keychain storage with an access group** shared between the app, the widget extension and the Control, so an intent running headless can authenticate.
- Add **automatic OAuth2 refresh** by re-signing the OAuth1 exchange, plus a loud, actionable "sign in again" state when the OAuth1 token finally expires.
- Add a **durable outbox**: every food entry is written locally with an idempotency key and drained asynchronously. The UI never blocks on `connectapi.garmin.com`.
- Add **reconciliation**: after a successful drain, re-read the day's log from Garmin and resolve divergence, so a retry that silently succeeded twice does not leave a duplicate.
- Add **rate-limit discipline**: honour `Retry-After`, exponential backoff with jitter, and treat 429 as stop-and-resume.

## Capabilities

### New Capabilities

- `garmin-auth` - obtaining, storing, sharing and refreshing Garmin credentials without ever handling a password.
- `garmin-sync` - getting locally-recorded food entries into Garmin Connect reliably, exactly once, without ever blocking the user.

### Modified Capabilities

None.

## Non-goals

- **Discovering the write route.** Owned by `establish-garmin-nutrition-contract`; this change consumes its output and cannot start without it.
- **Multi-account or multi-user support.** One person, one Garmin account, permanently.
- **The food entry UI.** Owned by `add-food-log-core`; this change only receives entries and delivers them.
- **Widget and Control surfaces.** Owned by `add-glanceable-surfaces`. This change makes their intents able to authenticate; it does not build them.
- **Proxying through a server.** Explicitly rejected in design.md D1 — a backend would add a credential-custody problem this design does not otherwise have.

## Impact

Affected surfaces: a new `GarminKit` Swift package (auth, transport, per-process outbox), a Keychain access group shared with both extensions, and distribution via AltStore/SideStore's automatic resign rather than the App Store.

Ships on a free Apple Personal Team by owner decision (2026-09-14) — no $99/yr program for now. That rules out App Groups, so the app and its extensions do not share a file container; each process treats Garmin's own API as the source of truth for reads and keeps its own local write queue. See design.md D3 for the full consequence and D8 for the distribution mechanics.

**Depends on**: `establish-garmin-nutrition-contract`. The outbox cannot be built against an unknown write contract.

**Unblocks**: `add-glanceable-surfaces` (intents need a token), `add-companion-surfaces` (the vault bridge reuses the same route registry).

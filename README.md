# GarminFood

A personal iOS app for logging food in two taps, with Garmin Connect as the system of record — Control Center / Lock Screen / Action Button logging, a Home Screen + Mac desktop widget, and Siri, built against Garmin's private mobile API since no public write API for nutrition exists.

**This repository is a plan, not yet code.** Everything lives under `openspec/` as five ordered OpenSpec changes. Start there.

## Read this first

- [`openspec/config.yaml`](openspec/config.yaml) — project context, hard constraints, and everything established by live-probing the owner's Garmin account on 2026-09-14.
- Free-tier decision (2026-09-14): **no paid Apple Developer Program for now.** Ships on a free Personal Team via SideStore/AltStore's automatic resign, not manual weekly Xcode reinstalls (which would wipe local data). This removes App Groups from the architecture — see `add-garmin-auth-and-sync`'s design.md D3.

## The five changes, in order

1. **[`establish-garmin-nutrition-contract`](openspec/changes/establish-garmin-nutrition-contract/)** — read-only recon. Confirms the nutrition API is live, discovers the food-log write route by decompiling the Garmin Android client, and defines the project's stop condition if no write path exists. **Nothing else can start until this reaches its gate.**
2. **[`add-garmin-auth-and-sync`](openspec/changes/add-garmin-auth-and-sync/)** — browser-based token bootstrap (scripted login is dead since March 2026), Keychain-based credential sharing across the app/widget/Control, and a per-process durable outbox with reconciliation against Garmin.
3. **[`add-food-log-core`](openspec/changes/add-food-log-core/)** — the food catalog (search, favourites, barcode scanning, custom foods) and the confirm-and-log flow every fast-entry surface points at.
4. **[`add-glanceable-surfaces`](openspec/changes/add-glanceable-surfaces/)** — the actual widgets: Controls for Control Center/Lock Screen/Action Button, a Home Screen + Mac ring widget, a read-only Lock Screen accessory, and Siri shortcuts.
5. **[`add-companion-surfaces`](openspec/changes/add-companion-surfaces/)** — a small, independent fix to the existing Obsidian vault's `sync-nutrition.mjs`, which has been silently broken since it was written (calls a route confirmed to 404).

Changes 3, 4 and 5 all depend on 1 and 2, but not on each other in sequence — 5 can run any time after 1, in parallel with the iOS work.

## Tools (already built, already run against the live account)

- `tools/lib/garmin-auth.mjs` — OAuth1→OAuth2 exchange, lifted from the vault's working Node client.
- `tools/probe-garmin-nutrition.mjs` — the original fixed-table recon probe.
- `tools/discover-nutrition-routes.mjs` — wide route/parameter sweep; this is how `searchExpression` was found.
- `tools/garmin-get.mjs` — ad hoc authenticated GET against any path, for continuing discovery.

All four are read-only. Run them with `VAULT_ROOT` pointed at the Obsidian vault holding the Garmin tokens:

```
VAULT_ROOT="/path/to/vault" node tools/garmin-get.mjs '/nutrition-service/food/search?searchExpression=banana'
```

## Validating the plan

```
npm install -g @fission-ai/openspec
openspec validate --all --strict
```

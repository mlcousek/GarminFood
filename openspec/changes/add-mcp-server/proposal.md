## Why

The owner spends a lot of the day at his Windows PC with Claude open. He
wants to drive GarminFood from there in plain language: "log my usual
breakfast", "save tonight's dinner as a preset", "add the new magnesium
bisglycinate, 2 capsules every evening", "tick yesterday's creatine", "how
much protein am I short today?". Today every one of those needs the phone in
hand.

The hard part is not the MCP server. It is that the server runs on the PC
while **most of the app's state lives only on the phone**:

- Food log entries, custom foods, weigh-ins and water are in **Garmin
  Connect** (the system of record), reachable from Windows through the same
  private API the app uses. `tools/lib/garmin-auth.mjs` already signs in from
  this PC.
- Supplements, meal presets, favourites, collections, day notes, fasting,
  local goals, reminders, appearance, usage history (which drives streak and
  XP), gamification state and the standalone local food log exist **only as
  JSON files and `UserDefaults` inside the iPhone app sandbox**.
- A free Apple Personal Team has **no App Group, no iCloud container
  entitlement and no push** (`openspec/config.yaml`). Nothing on the PC can
  reach into the sandbox or wake the app.

This change plans how to bridge that gap honestly, and the MCP server on
top of it. It writes no implementation code.

## What Changes

- **A hybrid transport (design D1–D3).**
  - **Garmin-direct** for what Garmin already holds: food-log reads, daily
    totals and goals, weigh-ins and water, food search. Food-log **creates**
    use the one write route this project has confirmed on a real device
    (`PUT /nutrition-service/food/logs`, 2026-09-16), so they land in
    Garmin Connect (and on the watch) immediately, even while the phone is
    off.
  - **A file bridge** for everything that exists only on the phone: the
    owner picks one folder in iCloud Drive once, in the app, with the
    system document picker. The app keeps a security-scoped bookmark to it
    (no entitlement needed; **UNVERIFIED on this account, design D2**).
    iCloud for Windows syncs the same folder to the PC.
    - The MCP server writes **command files** into `inbox/`.
    - The app applies them on launch and foreground through the **same
      coordinators and stores the UI uses** (same validation, same XP, same
      outbox), idempotently by command id, and writes a **result** per
      command into `results/`.
    - The app exports a read-only **`state.json` snapshot** of its local
      state for MCP reads.
  - **Receipts join the two.** A food entry the MCP server logs straight to
    Garmin also drops a record-only `food.adopt` command into the bridge,
    so the next time the app runs it credits usage history, streak and XP
    for it without delivering it again (design D4).
- **An MCP server on the PC (design D5–D8)**: Node + TypeScript, stdio
  transport, in `tools/mcp/`, registered in Claude Desktop and Claude Code.
  - ~45 tools grouped by area: food log, catalog and custom foods, meal
    presets, favourites, notes, weight, water, fasting, goals, supplements,
    reminders, data, gamification reads, appearance, bridge status.
  - Every write tool defaults to **dry-run** and returns a preview;
    `confirm: true` performs it. Garmin writes whose contract is not
    confirmed are **off unless explicitly enabled** and marked as such.
  - Garmin auth failures and a stale bridge are **loud** (tool errors that
    say what to do), never an empty answer.
- **App side (design D9–D12)**: a new Settings → Data → "PC bridge"
  section (off by default), a `BridgeCommand` model and a pure
  `BridgeCommandApplier` in FoodLogCore, a snapshot builder, and a status
  view listing recent commands and failures (also logged to
  `DiagnosticsLog`).
- **A shared, versioned protocol** (`docs/bridge-protocol.md` + JSON
  Schema + fixture files) that both the Node tests and the Swift tests
  consume, so the two sides cannot drift silently.

## Capabilities

### New Capabilities

- `mcp-server` — the PC-side MCP server: tool surface, dry-run and
  confirmation, write gating, error reporting, configuration on Windows.
- `mcp-garmin-direct` — reading and writing Garmin Connect from the PC
  through the route registry, and the adopt-receipt that keeps the app's
  streak/XP consistent with direct writes.
- `app-command-bridge` — the in-app side: bridge folder setup, command
  inbox, apply through existing coordinators, results, state snapshot,
  status and failure reporting.

### Modified Capabilities

(none — the bridge calls existing coordinators and stores; their behaviour
does not change)

## Non-goals

- **Any new Garmin write route.** Only routes already in
  `docs/garmin-routes.json` are used. Unconfirmed ones
  (`createCustomFood`, `createCustomMeal`, `quickAdd`, food-log delete from
  the PC) stay behind an explicit opt-in flag, per the repo rule. Confirming
  them belongs to their own changes (`fix-custom-food-log-region`,
  `sync-meal-presets-to-garmin` follow-ups).
- **Real-time control of the phone.** Commands apply only when the app runs
  (design D3). No local-network server on the phone, no push, no paid Apple
  account. Revisit if the owner pays for the Developer Program (an App
  Group or CloudKit would change D2).
- **A hosted relay/server.** No third-party cloud beyond iCloud Drive,
  which the owner already uses.
- **Credentials over the bridge.** Garmin tokens never enter the bridge
  folder, and no command can sign in, sign out, or change data mode.
- **Standalone mode (the fiancée's phone).** The MCP server targets the
  owner's Garmin-connected install. Bridge commands work in either mode,
  but Garmin-direct tools refuse to run against a standalone install
  (design D4).
- **UI automation / screen control of the phone** and **barcode scanning
  from the PC** (camera-only; the PC gets text search and
  `food.lookupBarcode` against Open Food Facts instead).
- **Replacing the existing generic `garmin` MCP server** the owner already
  has configured. Whether to keep it enabled is an open question (design
  Q3).

## Impact

- New `tools/mcp/` npm package (TypeScript, `@modelcontextprotocol/sdk`,
  `zod`), reusing `tools/lib/garmin-auth.mjs`; a new CI workflow
  (`.github/workflows/mcp.yml`, ubuntu, `npm ci && npm test`).
- New `docs/bridge-protocol.md`, `docs/bridge-protocol/*.schema.json` and
  `docs/bridge-protocol/fixtures/` shared by both test suites.
- FoodLogCore: `Bridge/` (command model, pure applier, snapshot builder,
  results) with unit tests; GarminKit untouched.
- App: `GarminFood/Bridge/` (folder picker, bookmark, apply-on-foreground
  runner, status view), wired through `AppServices`/`AppEnvironment`;
  `DiagnosticsLog` category `bridge`.
- No new AltStore App ID (no new target).
- **Depends on**:
  - `add-data-safety` (store catalog, snapshot/export shape and the
    compatibility contract the snapshot follows);
  - `add-supplements`, `add-meal-presets` (archived),
    `add-log-entry-editing`, `add-day-notes`, `add-favorite-foods`,
    `redesign-fasting-schedule`, `sync-weight-hydration-with-garmin` — the
    coordinators and stores the bridge calls;
  - `docs/garmin-routes.json` as the gate for every Garmin call.
- **Unblocks**: an Obsidian-vault or scheduled-agent integration later
  (same protocol), and a future paid-account transport swap (App Group /
  CloudKit) behind the same command model.

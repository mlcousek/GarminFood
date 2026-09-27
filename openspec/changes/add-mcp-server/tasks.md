## 0. Before starting

- [ ] 0.1 Owner answers design Q1–Q8 (bridge folder path, default `via` for food, what to do with the existing generic `garmin` MCP server, one approved delete probe, trust boundary, Shortcuts automation, standalone scope, late-adopt XP). Record the answers in design.md.
- [ ] 0.2 Confirm iCloud for Windows is installed on the PC and syncing iCloud Drive; note the local path it uses.

## 1. Wave 1 — Spike: does the bridge folder work on this account? (device check, gates everything app-side)

- [ ] 1.1 Throwaway spike build (behind a hidden Settings → Diagnostics button, removed in 3.x): pick a folder with `.fileImporter(allowedContentTypes: [.folder])`, save the bookmark, write `spike.txt` with the time, list the folder's files.
- [ ] 1.2 On device: pick `iCloud Drive/GarminFood Bridge`; confirm `spike.txt` appears on the PC. Record the time it took.
- [ ] 1.3 Put a file in the folder on the PC; relaunch the app; confirm the listing shows it and it can be read (with `NSFileCoordinator` + `startDownloadingUbiquitousItem`). Record whether it first appeared as a not-downloaded placeholder.
- [ ] 1.4 Force-quit and relaunch: bookmark resolves without the picker. Then wait for (or trigger) an AltStore re-sign in place and check again. Record whether the bookmark was stale.
- [ ] 1.5 Write the results, dated, into design.md D2 (replace "UNVERIFIED" with what was observed). If 1.3 or 1.4 fails, apply the D2 fallback and re-scope waves 3–5 before continuing. CI green on the spike PR.

## 2. Wave 2 — MCP server skeleton + Garmin-direct reads (PC only, no device needed)

- [ ] 2.1 `tools/mcp/` package: `package.json` (`@modelcontextprotocol/sdk`, `zod`, `ajv`, `typescript`), `tsconfig.json`, `src/index.ts` (stdio server, logs to stderr only), `.gitignore` for `dist/` and `node_modules/`. Header comment in each file explaining why it exists, matching the repo's Swift header convention.
- [ ] 2.2 `src/garmin/registry.ts`: load `docs/garmin-routes.json`, look operations up by name, classify each write as confirmed / modelled / unconfirmed (design D7). Tests with a fixture registry, including "missing operation disables its tool".
- [ ] 2.3 `src/garmin/client.ts`: wraps `tools/lib/garmin-auth.mjs`; 401/403/missing token → typed auth error with the loud message; 429 → honour `Retry-After` and stop. Tests against a fake HTTP layer (no live calls in tests).
- [ ] 2.4 Read tools: `server.status`, `food.search`, `food.getDay`, `food.getRange`, `food.recent`, `weight.list`, `water.get`, `goals.get` (Garmin half), `food.lookupBarcode` (Open Food Facts product route already documented in `docs/openfoodfacts-product-route.md`). Each description names its route and `lastVerified`. Tests with recorded-shape fixtures (field names only, no personal values).
- [ ] 2.5 Manual check from the PC (read-only): run the server under Claude Desktop, ask for today's food log and this week's weight. Record that the answers match the Garmin Connect app.
- [ ] 2.6 Settle `deleteFoodLogEntries` per Q4. The app already calls it directly on every delete of a delivered entry, so first ask the owner whether in-app deletes removed the entry in Garmin Connect, and check the phone's diagnostics log for its status codes. If that is conclusive, record it, dated, in `docs/garmin-routes.json`. Otherwise, and **only with the owner's explicit approval**, run one probe with `tools/garmin-write-probe.mjs` on an entry logged for the purpose, and record the status code and the re-read result. If neither happens, the direct delete stays hidden.
- [ ] 2.7 `.github/workflows/mcp.yml` (ubuntu, Node 22): `npm ci && npm run build && npm test` for `tools/mcp/**`, `docs/bridge-protocol/**`, `docs/garmin-routes.json`. CI green.

## 3. Wave 3 — Protocol + app-side bridge core (FoodLogCore, unit-tested in CI)

- [ ] 3.1 `docs/bridge-protocol.md`, `command.schema.json`, `result.schema.json`, `state.schema.json` (protocolVersion 1), and one valid + at least one invalid fixture per command kind in `docs/bridge-protocol/fixtures/`.
- [ ] 3.1a Move mutation logic the bridge needs out of app-target controllers into FoodLogCore (design D9): `SupplementsController` (tick, take all, extra dose, remove intake, save product/schedule, remove/delete, stock, refill, slot reminder minute, limits), and the equivalent fasting, day-note, favourite, local-goal and preset editor actions. Behaviour-preserving; existing tests stay green, new tests for each moved method.
- [ ] 3.2 `FoodLogCore/Bridge/BridgeCommand.swift`: envelope, open `kind`, typed payloads, `.unknown` fallback. Tests decode every fixture; a coverage test fails on a kind without a fixture.
- [ ] 3.3 `BridgeLedger` store (applied ids, 90 days, unreadable-file contract, fixture per `docs/data-compatibility.md`). Tests: round-trip, quarantine, prune.
- [ ] 3.4 `BridgeCommandApplier` + `BridgeTargets` protocol: ordering, at-most-once, `notAfter`, `unsupported_protocol`, allow-list, `expectedUpdatedAt` conflicts, result construction. Tests with real stores on temp files for each spec scenario in `app-command-bridge`.
- [ ] 3.5 `LogEntryCoordinator.adoptDelivered(...)` (usage history + serving default, no outbox; idempotent by `logId`; no XP when > 7 days late per Q8). Tests: adopt twice → one usage event; outbox untouched; streak counts the entry's own day.
- [ ] 3.6 `BridgeSnapshotBuilder`: the `state.schema.json` projection from local stores; token-key scan test reusing the backup's secret-scan list; schema validation of the output in a Node test against a Swift-generated sample committed as a fixture.
- [ ] 3.7 CI green (`swift test` FoodLogCore, `mcp.yml`).

## 4. Wave 4 — App wiring, status and folder UX (app target; device check)

- [ ] 4.1 Remove the wave-1 spike. `GarminFood/Bridge/`: Settings → Data → PC bridge switch (off by default), folder picker, bookmark storage, "Folder access lost" state. en + cs strings.
- [ ] 4.2 `BridgeRunner`: run on launch, on `scenePhase == .active`, and on "Check now"; off the main actor; coordinated reads; atomic result/snapshot writes (temp + rename); command → `archive/` only after its result is written. `BridgeTargets` implemented by the real coordinators and stores from `AppServices`.
- [ ] 4.3 Bridge status view (last run, last snapshot, last 50 results), Today notice for rejected/failed commands, `DiagnosticsLog` category `bridge`.
- [ ] 4.4 Snapshot written after each run and at most every 5 minutes in the foreground.
- [ ] 4.5 CI green (app + widget build). Sideload; on device: enable the bridge, confirm `state.json` appears on the PC and passes `state.schema.json` validation (`node tools/mcp/dist/validate-state.js`).

## 5. Wave 5 — Bridge write tools (PC) + end-to-end device checks

- [ ] 5.1 `src/bridge/`: atomic command writer (`.tmp` → rename), result reader, snapshot reader with staleness, `bridge.status`/`result`/`cancel`. Tests on a temp folder, including "never modifies a written file".
- [ ] 5.2 Dry-run/confirm wrapper shared by every write tool (design D8), with preview text saying where and when the change lands.
- [ ] 5.3 Bridge tools: custom foods, presets (incl. `preset.createFromDay`), favourites, notes, local goals, fasting, supplements (add/update/archive product, schedule, tick, take all, extra dose, limits, refill, totals), reminders, `settings.get/set` (allow-listed keys), progress reads, `data.exportSnapshot`. Tests: each writes a command that validates against the schema and equals its fixture modulo id/time.
- [ ] 5.4 On device, one command at a time, then read the result back from the PC: add a supplement product, set its schedule, tick it for yesterday, create a preset from a Garmin day, add a day note, set a local goal, start and end a fast. Record each result status and any mismatch.
- [ ] 5.5 Conflict check on device: edit a supplement product on the phone after the PC read the snapshot, then send an update from the PC → result `conflict` with the current value.

## 6. Wave 6 — Garmin-direct food writes + adopt receipts

- [ ] 6.1 `food.log` / `food.logAgain` / `food.copyMeal` / `preset.log` with `via: "garmin"`: `mealsForDate` → `createFoodLogEntry` (confirmed 2026-09-16) → read back `logId` → `food.adopt` command. Stops at first failure and reports which items made it. Tests against the fake HTTP layer.
- [ ] 6.2 `via: "bridge"` variants of the same tools and of `food.editEntry`/`food.deleteEntry` (app `replace`/`deleteCommitted`). Refuse `via: "garmin"` when the snapshot says standalone.
- [ ] 6.3 Direct `food.editEntry`/`food.deleteEntry` (create-then-delete) exposed only when the registry records `deleteFoodLogEntries` as exercised (2.6).
- [ ] 6.4 `weight.add`, `weight.delete`, `water.add` (confirmed routes) with dry-run/confirm.
- [ ] 6.5 On device + PC: log one food from the PC with the phone off; confirm it appears in Garmin Connect immediately; open the app later and confirm the streak counts that day, the entry appears once in Today, and the sync queue is empty. Log a weigh-in and 250 ml of water from the PC and confirm the app shows both after refresh.

## 7. Wave 7 — Experimental writes (opt-in only) and docs

- [ ] 7.1 `garmin.createCustomFood`, `garmin.createCustomMeal`, `food.quickAdd` behind `GARMINFOOD_MCP_EXPERIMENTAL_WRITES`, descriptions prefixed "EXPERIMENTAL — unconfirmed Garmin route", full request/response logged. Tests: hidden by default. **No task here sends one to the live account**; confirming any of them belongs to its own change, which must update `docs/garmin-routes.json` first.
- [ ] 7.2 `tools/mcp/README.md`: install, build, Claude Desktop config (`%APPDATA%\Claude\claude_desktop_config.json`) and `claude mcp add` command, env vars, what each tool does and when it lands, troubleshooting (token expired, bridge stale, placeholder files).
- [ ] 7.3 Update root `README.md` and `CLAUDE.md` Architecture with `tools/mcp/` and `FoodLogCore/Bridge/`.

## 8. Wave 8 — Optional: apply without opening the app (only if Q6 = yes)

- [ ] 8.1 `ApplyBridgeInboxIntent` (App Intent, no UI) calling `BridgeRunner`; device check that a Shortcuts time-of-day automation runs it with the phone locked and that the bookmark and iCloud reads work from that context. Record the result in design.md.
- [ ] 8.2 Also run `BridgeRunner` inside the existing `BackgroundRefresh` task when it fires; never rely on it.

## Context

The owner wants Claude on his Windows PC to do anything he can do in the
app. This design starts from where each piece of data actually lives,
because that decides what a PC process can reach at all.

What was checked, read-only, on 2026-09-27 in this repository (no live
Garmin call was made for this change):

- `docs/garmin-routes.json` (last full sweep 2026-09-14, entries up to
  2026-09-23): which Garmin routes are confirmed, modelled, or guessed.
- `FoodLogCore/Backup/StoreCatalog.swift`: the list of every persisted
  store file, its area and whether it is backed up.
- `LogEntryCoordinator`, `CustomFood.swift`, `MealPreset.swift`,
  `Supplements/`, `GamificationEngine`, `FeatureHost`,
  `DayLogDigest.swift`: which actions are Garmin writes and which are
  local, and what drives streak and XP.
- `tools/lib/garmin-auth.mjs`, `tools/garmin-get.mjs`,
  `tools/garmin-write-probe.mjs`: the Node tooling that already talks to
  Garmin from this PC with the vault's OAuth1 token.
- The owner's Claude setup already has a generic Garmin MCP server
  configured (tools such as `log_food`, `create_custom_food`,
  `delete_food_log`, `get_nutrition_daily_food_log`). It knows nothing about
  this app's local state.

Three facts shape everything below:

1. **Streak and XP come from the app's own usage history, not from
   Garmin.** `GamificationEngine` builds `loggedDays` from local
   `UsageEvent`s recorded at confirm time
   (`LogEntryCoordinator.confirm` → `usageHistory.record`). Garmin
   day-log digests feed only the signal-based features (bingo, collections,
   records). So a food entry written straight to Garmin by any PC tool —
   including the existing generic Garmin MCP — shows up in the calorie
   totals but **never counts toward the streak or XP**.
2. **Custom foods and meal presets are local.** A custom food is a local
   `CustomFoodDraft` backed by an existing Garmin food and a multiplier;
   Garmin-side custom food creation (`createCustomFood`) is gated and
   unconfirmed. Meal presets are local `MealPreset`s; pushing one to
   Garmin (`createCustomMeal`) is a guessed body, never sent.
3. **Everything else that is not food, weight or water is phone-only**:
   supplements, notes, fasting, local goals, favourites, collections,
   reminders, appearance, all gamification state. Some of it is in
   `UserDefaults` (`AppPreferences`: feature switches, local goals,
   appearance, fasting schedule), not in JSON files.

## Feature inventory

Surveyed read-only on 2026-09-27 from the SwiftUI views under
`ios/GarminFood/`, the coordinators and stores in `FoodLogCore`,
`Gamification` and `GarminKit`, and `StoreCatalog`. All file paths are
under the app's Application Support. **Garmin** means Garmin Connect through
a private route. **Local** means a JSON store or `UserDefaults`
(`preferences.*`, `goals.*`, `notifications.*`, `appearance.v1`,
`layout.v1`, `dataMode.v1`, `profile.localDisplayName`). Garmin tokens on
the phone are in the Keychain.

The MCP path column uses these codes:

- **G**: Garmin-direct from the PC.
- **B**: a bridge command, applied when the app next opens.
- **S**: read from `state.json`.
- **X**: an experimental Garmin write, hidden unless enabled (D7).
- **—**: not offered.

"Domain only" means the method exists but no view calls it today.

| Area | Action (UI entry point) | Code path today | Data lives in | R/W | MCP |
|---|---|---|---|---|---|
| Food log | Search foods: own, Garmin, OFF, offline Czech index (`Catalog/FoodCatalogView`, `SearchResultsSection`) | `FoodSearchEngine.search` | Garmin `foodSearch`; Local `custom-foods.json`, `favorite-foods.json`, `food-cache.json`, `usage-history.json`, `OfflineIndex/`; OFF | R | G + S (own foods) + OFF |
| | Scan a barcode (`Catalog/BarcodeScanScreen`, Control, Shortcut) | `BarcodeResolution` / `StandaloneBarcodeResolution` | Garmin `food/search/barCode`, OFF, offline index | R | — camera; `food.lookupBarcode` takes a typed code |
| | Match an OFF product to a Garmin food (`MatchConfirmationView`) | search + `FoodProvenanceStore.record` | Local `food-provenance.json` | R/W | G search, then B `food.log` with provenance |
| | Confirm a catalog food (`LogEntry/LogEntryConfirmView`) | `ModeRoutingFoodLogging.confirm` → `LogEntryCoordinator.confirm` (`Outbox.logFood`, usage history, serving default) → `GamificationEngine.handleLogConfirmed` | Local `GarminKit/outbox-app.json` → Garmin `createFoodLogEntry`; standalone: `FoodLog/<yyyy-MM>.json` | W | G + adopt, or B |
| | Log a custom food (confirm screen) | `confirmCustomFood` (sent as its backing Garmin food × multiplier) | `custom-foods.json` → outbox → Garmin | W | B `food.logCustom` |
| | Quick pick / Usual / Recent / Favourites shelves, "Log again" on Today, Siri and Controls intents | `QuickPick.rank`, `MealUsualRanker`, `RecentRanker` → `confirm` | `usage-history.json`, `food-cache.json` | R then W | S + G `recentFoods`; write as `food.log` |
| | Quick add by calories | not implemented in the app (only listed for Garmin-made quick-adds) | Garmin `quickAddFoodLogEntry` (documented, never exercised) | W | X `food.quickAdd` |
| | Log a meal preset (`MealPreset/MealPresetConfirmView`) | `confirmMealPreset`, one entry per ingredient | `meal-presets.json` → outbox | W | G + adopts, or B |
| | Copy a meal from another day (`MealDetailView` "Copy from…") | `copyMealPlan` + `coordinator.copyMeal` | Garmin `dailyFoodLog` → outbox | R/W | G + adopts, or B |
| | Edit amount / move to another meal (`Today/EntryEditing`) | `coordinator.edit` → outbox entry with `replaces` (create, then delete) | Garmin | W | B (G after task 2.6) |
| | Duplicate | `coordinator.duplicate` (`duplicateOf`) | Garmin | W | G + adopt, or B |
| | Delete an entry | `deleteCommitted` (a **direct** Garmin `DELETE food/logs/{date}`, not queued), or `deletePending` | Garmin / outbox | W | B (G after task 2.6) |
| | Day view: totals, meals, macros, day navigation (`Today/TodayView`, `MealDetailView`) | `DayLogLoader`, `MealDashboard` | Garmin `dailyFoodLog`, `mealsForDate`, `dailyWellnessSummary`; Local `day-log-digests.json`, `goal-status.json` | R | G |
| | Sync queue: retry, cancel, discard (`Profile/SyncQueueView`) | `Outbox.retry/cancelQueued`, weight/hydration equivalents | 3 outbox files (not backed up) | R/W | S read only; writes — |
| Custom foods | New / edit, with a "closest Garmin match" backing in Garmin mode (`CustomFood/CustomFoodEditorView`) | `CustomFoodStore.upsert` + `FoodCacheStore.upsert` | Local `custom-foods.json` only | W | B (backing chosen with G search) |
| | Delete | `CustomFoodStore.delete` (domain only) | Local | W | B |
| | "Create in Garmin" (OFF match flow) | `GarminClient.createCustomFood` (direct, unconfirmed body) | Garmin `PUT customFood` | W | X |
| Meal presets | New / edit (`MealPreset/MealPresetEditorView`) | `MealPresetStore.upsert` | Local `meal-presets.json` | W | B, plus `preset.createFromDay` (reads G) |
| | Delete (shelf context menu) | `MealPresetStore.delete` | Local | W | B |
| | "Sync to Garmin (experimental)" | `GarminClient.createCustomMeal` (guessed body, never sent) | Garmin `POST customMeal` | W | X |
| Favourites | Toggle the star (search rows, shelves) | `FavoriteFoodStore.toggle` | Local `favorite-foods.json` (the Garmin favourite route has no evidence) | W | B (`favorite.set` is idempotent, not a toggle) |
| Day notes | Write, edit or clear a note and its tags (`Today/DayNoteCard`) | `DayNoteStore.save(day:text:tags:)`; empty text and no tags deletes it | Local `day-notes.json` | W | B |
| Weight | Add a weigh-in (`Weight/AddWeightSheet`) | `WeightLogCoordinator.logWeight` → weight outbox → `addWeighIn` | Garmin (the truth since `sync-weight-hydration-with-garmin`); Local `weight-entries.json` while pending | W | G |
| | Delete a weigh-in (`WeightView`) | `WeightLogCoordinator.delete` → `weighInDelete` | Garmin | W | G |
| | History, goal progress, refresh | `WeightLoader`, `GarminHealthSync` | Garmin `getWeighIns`/`weighInsDayView`, `nutritionSettings`; `goals.weight.*` | R | G + S |
| Water | Add a drink, quick or custom (`Hydration/AddHydrationSheet`, Today) | `HydrationLogCoordinator.logHydration` → `addHydration` | Garmin day total; Local `hydration-entries.json` while pending | W | G |
| | Remove a drink (a negative correction once delivered) | `removeHydration` | Garmin | W | G (`water.add` with negative ml) |
| | Day total, goal, "Use Garmin's goal" | `HydrationLoader`; `goals.water.overrideML` | Garmin `hydrationDaily`; UserDefaults | R/W | G + S; override: B `settings.set` |
| Fasting | On/off, "fast from/until" (`Fasting/FastingSettingsSection`) | `AppPreferences` fasting setters + re-plan | UserDefaults `preferences.fasting.*` | W | B `fasting.setSchedule` |
| | Card, kept/broken history (`FastingHomeCard`, `FastingHistoryView`) | `FastingSchedule`, `FastingLogMoments` over usage history | Local (derived) | R | S |
| Goals | Garmin calorie and macro goals (read-only in the app; no write route exists) | `nutritionSettings` | Garmin | R | G |
| | Local weight goal and start weight (`Profile/GoalsSettingsSection`) | `goals.weight.overrideKg/startKg` | UserDefaults | W | B `settings.set` |
| | Standalone nutrition plan (`Goals/LocalGoalEditorView`) | `LocalGoalStore.save` (history by `effectiveFrom`) | Local `local-goals.json` | W | B `goals.setLocal` |
| | Goal calculator (saves nothing) | `GoalCalculator` | none | R | — (Claude can reason directly) |
| Supplements | Turn on the feature, with starter picks (`SupplementsSettingsSection`) | `preferences.supplements.enabled`; `SupplementsController.save` | UserDefaults; `supplement-plan.json` | W | B |
| | Add / edit a product: catalog, custom, barcode, certifications (`SupplementProductEditorView`) | `save` → `SupplementPlanStore.upsertProduct`; `barcodeLookup` | `supplement-plan.json`, `supplement-barcode-cache.json`; OFF/DSLD | W | B (barcode: typed code, looked up on the PC) |
| | Schedule: slots, patterns, cycles (`SupplementScheduleEditor`) | `SupplementPlanStore.setSchedule(_:for:from:)` | `supplement-plan.json` | W | B |
| | Tick / untick, Take all, any past day up to 365 days (`SupplementChecklistViews`, Today card) | `setTaken` → `recordPlanned`/`removePlanned`; `takeAll` | `SupplementIntake/<yyyy-MM>.json` | W | B |
| | Notification "Taken" | `SupplementSlotTaking.take` (idempotent) | same | W | B (`supplement.takeAll`) |
| | Extra dose, with the limit notice | `addExtra`, `extraDoseNotice` | same | W | B |
| | Remove an intake record | `removeRecord` | same | W | B |
| | Limits: override / reset (`SupplementLimitsView`) | `limitsStore.setOverride` / `reset` | `supplement-limits.json` | W | B |
| | Stock on hand; remove from stack; delete product (`SupplementStackView`) | `setStock`, `removeFromStack`, `deleteProduct` | `supplement-plan.json` | W | B |
| | Refill | `refill` (domain only) | `supplement-plan.json` | W | B |
| | Reminder time per slot (`SupplementReminderTimesView`) | `setReminderMinute` | `supplement-plan.json` | W | B |
| | Totals, warnings, adherence, cost, days left, label score, evidence cards | pure FoodLogCore (`StockProjection`, `LabelScore`, `EvidenceCatalog`) | plan + intake + built-in catalog | R | S (+ catalog JSON) |
| Reminders | Meal, streak, daily-challenge, fasting-end and fasting-start reminders: on/off and times (`Profile/NotificationSettingsView`) | `AE.set…Reminder` → `NotificationPreferencesStore` → `NotificationScheduler.sync` | UserDefaults `notifications.*` | W | B (re-plan runs on apply) |
| | Grant notification permission | system prompt | iOS | W | — |
| Data safety | Back up now; restore a snapshot; cancel a pending restore (`Profile/DataSettingsView`) | `BackupVault` via `DataSafetyController` | Local `Backups/` | W | — restore; S shows the last snapshot |
| | Export / import one file (`fileExporter` / `fileImporter`) | `makeExportContainer` / `readImport` → staged restore | `GarminFood-backup-yyyy-MM-dd.json` | R/W | B `data.exportSnapshot` drops a copy; import — |
| Data mode | Choose or switch mode, deliver-before-switch, "Copy last 90 days from Garmin" (`Onboarding`, `DataModeSection`) | `AE.chooseDataMode`, `switchToStandalone`, `GarminHistoryImport.run` | UserDefaults `dataMode.v1`; outbox; `FoodLog/` | W | — (S shows the mode) |
| Account | Garmin sign in / out (`GarminSSOWebView`, `AuthBannerView`) | `GarminAuthSession`, `TokenProvider` | Keychain | W | — never |
| Diagnostics | View, copy, clear the log; force-standalone test toggle (`DiagnosticsLogView`) | `DiagnosticsLog` | Local `GarminKit/diagnostics-log.json` | R/W | — (bridge failures come back as results) |
| | Offline index: download now, allow cellular | `OfflineIndexLoader`; `preferences.offlineIndex.allowsCellular` | Local `OfflineIndex/`; GitHub release | W | B `settings.set` (cellular only) |
| Gamification | Streak and freezes, level/XP, weekly and daily challenges, goal history, achievements, bingo, boss, journeys, records, collections, seasonal, sport and body, secrets, supplement streak (`Progress/*`, Today slots) | `GamificationEngine`, `FeatureHost`; computed from **local usage history** plus Garmin digests and the activity cache | Local `Gamification/*.json`, `Gamification/features/<id>/*.json`, `usage-history.json`, `day-log-digests.json` | R (the only write is a side effect of logging) | S |
| | Dismiss a celebration moment (`Home/MomentOverlay`) | `dismissCurrentMoment` | in memory | W | — |
| Trends | Calorie, macro and water trends; day-note markers (`Trends/TrendsView`) | `MacroTrendLoader` | Garmin `calorieSummaryDaily`; Local notes and water | R | G + S |
| Appearance | Theme, accent, reset (`Profile/Appearance/*`) | `ThemeStore.selectTheme/update/resetAll` | UserDefaults `appearance.v1` | W | B `settings.set` |
| | Share a theme code / import a `GFT1.` code | `ThemeShareCode`, `ThemeStore.applyImported` | `appearance.v1` | R/W | S shows the code; B `appearance.applyThemeCode` |
| | Card layout for Today, Log Food and Progress; start tab (`Layout/LayoutEditorSheet`) | `LayoutStore.move/setVisible/setVariant/apply/reset/setStartTab` | UserDefaults `layout.v1` | W | B `settings.set` (`layout.*`) |
| | App icon, "match app icon" | `setAlternateIconName` (shows a system alert) | iOS; `appearance.matchAppIcon` | W | — |
| | Haptics, celebrations, Garmin meal windows, Czech-only search, quantity input mode | `AppPreferences` | UserDefaults `preferences.*` | W | B `settings.set` |
| | Language | follows iOS; the row opens iOS Settings | iOS | — | — |
| Profile | Local display name; Garmin social profile | `profile.localDisplayName`; `socialProfile` | UserDefaults / Garmin | R/W | B / G |

In total there are about 60 actions:

- 12 go Garmin-direct.
- 33 become bridge writes.
- 8 are snapshot reads only.
- 11 are deliberately not offered: sign-in, data-mode switch, restore/import, notification permission, diagnostics, barcode camera, app icon, language, sync-queue writes, dismissing a moment, and the goal calculator.

Three actions exist only in the domain layer today: custom-food delete, supplement refill and favourite remove. The bridge can offer them because it calls the domain, not the view.

## Options for reaching phone-only state

| | (a) Garmin-only | (b) iCloud Drive file bridge | (c1) Manual export/import | (c2) Shortcuts automation | (c3) Server on the phone | (c4) Hosted relay |
|---|---|---|---|---|---|---|
| Covers | Food log, weight, water, Garmin goals, food search | Everything the UI can do on local data | Reads (backup file); writes only as a full restore | Triggers (b) without opening the app | Everything, live | Everything |
| Latency to phone | Immediate in Garmin; app sees it on next Garmin read | Next app launch/foreground (+ iCloud sync, typically seconds to minutes) | Manual, minutes | Scheduled times | Live while app is open | Next app open |
| Needs paid account/entitlement | No | No — document picker + bookmark (**UNVERIFIED on this account**) | No | No | No, but Local Network permission | No |
| Works with phone off/asleep | Yes | Queues; applies later | No | No | No | Queues |
| Keeps streak/XP right | **No** (see fact 1) unless receipts (D4) | Yes (same coordinators) | n/a | Yes | Yes | Yes |
| New attack surface | None beyond existing tokens | A synced folder the owner controls | None | None | Open port on the phone | A third-party server holding personal data |
| Build/verify cost | Low (Node only, CI on ubuntu) | Medium (Swift + Node + device test) | Low | Low, if (b) exists | High; iOS suspends sockets in background | High; hosting + auth |
| Verdict | Use for food/weight/water | **Use for phone-only data** | Keep as read fallback only | Optional later wave | Rejected | Rejected |

Notes on the rejected or partial options:

- **(c1) Manual export/import.** `add-data-safety` already exports one
  `.json` container of every data file. The MCP server can read one as a
  fallback snapshot. As a write path it is unsafe: import is a whole-app
  staged restore with a safety snapshot, not a merge, so a PC-edited backup
  would roll back anything done on the phone since the export.
- **(c2) Shortcuts personal automation.** Since iOS 17 a time-of-day
  personal automation can run an App Intent without asking. An
  `ApplyBridgeInboxIntent` (the app already ships App Intents in
  `GarminFood/Shortcuts/`) run a few times a day would apply commands
  without the owner opening the app. Whether an intent running in the
  background can resolve the bookmark and read a not-yet-downloaded iCloud
  file is **UNVERIFIED**. Planned as an optional wave, not a dependency.
- **(c3) A local HTTP server on the phone.** iOS suspends the app's
  sockets shortly after it leaves the foreground, so it only works while
  the app is open on the same Wi-Fi, needs a Local Network prompt, and
  opens a port that must be authenticated. It adds almost nothing over
  (b), which also applies on open.
- **(c4) A hosted relay** (a small server, a gist, a private repo) would
  put personal health data on a third party and needs its own auth. iCloud
  Drive is already the owner's own storage. Rejected.
- **`BGAppRefreshTask`** (already used by `BackgroundRefresh.swift` for
  outbox delivery) could also apply the inbox opportunistically, but iOS
  decides when it runs, if ever, for a sideloaded app. Treated as a bonus,
  never relied on.
- **Garmin as a message bus** (hiding commands in Garmin fields such as a
  custom food name) is rejected outright: it writes junk into the system of
  record and depends on unconfirmed routes.

## Decisions

### D1 — Hybrid: Garmin-direct for Garmin data, file bridge for phone data

- **Garmin-direct** for everything Garmin already holds and the app reads
  back from Garmin: food-log reads, food search, daily totals, Garmin
  goals (`nutritionSettings`), weigh-ins and water. Since
  `sync-weight-hydration-with-garmin`, Garmin is the truth for weight and
  water in the app, so a weigh-in or drink written by the PC shows up in
  the app after its next refresh.
- **Bridge** for everything that exists only on the phone.
- **Food logging offers both**, chosen per call with `via`:
  - `via: "garmin"` (default in Garmin mode): immediate in Garmin Connect
    and on the watch, plus an adopt receipt (D4) for streak/XP.
  - `via: "bridge"`: the app logs it at next open through
    `LogEntryCoordinator`, exactly like a tap. The only option in
    standalone mode, and the right one for local custom foods whose
    backing target the app resolves.
- Why not bridge-only: food is what the owner logs most, and waiting for
  the phone to be opened before calories appear in Garmin defeats the
  point of logging from the PC. Why not Garmin-only: it covers maybe a
  third of the inventory and silently breaks the streak (fact 1).

### D2 — The bridge folder: a user-picked iCloud Drive folder, remembered by bookmark

- On the phone: Settings → Data → PC bridge → "Choose folder" opens
  SwiftUI `.fileImporter(allowedContentTypes: [.folder])` (the app already
  uses `.fileImporter` for backups; `UIDocumentPickerViewController` only if
  the SwiftUI one can't return a folder).
  The owner creates or picks `iCloud Drive/GarminFood Bridge`. The app
  calls `startAccessingSecurityScopedResource()`, saves
  `url.bookmarkData()` in its own container, and resolves it on each run.
- On the PC: iCloud for Windows syncs the same folder, typically to
  `C:\Users\<user>\iCloudDrive\GarminFood Bridge\`. That path is
  `GARMINFOOD_BRIDGE_DIR`.
- **Why this should work without an entitlement (plausible, UNVERIFIED on
  this account):** the iCloud entitlement is only needed for an app's own
  ubiquity container. Access to a folder the user picks in the document
  picker is granted by the system through a security-scoped URL, and Apple
  documents persisting that access with a bookmark ("Providing access to
  directories"). This is the same mechanism as the `fileExporter` /
  `fileImporter` path `add-data-safety` already relies on, which needs no
  entitlement. Three things must be checked on the device before anything
  else is built (task 1.x):
  1. the bookmark survives an app relaunch **and an AltStore 7-day
     re-sign in place**;
  2. files written on the PC appear on the phone when the app reads the
     folder (iCloud may show them as not-yet-downloaded placeholders; the
     app must use `NSFileCoordinator` and
     `FileManager.startDownloadingUbiquitousItem(at:)` and handle
     "not downloaded yet" as "try again later", not as an error);
  3. files the app writes (`results/`, `state.json`) appear on the PC.
- **Fallback if (1) fails** (bookmark doesn't survive re-sign): ask for
  the folder again after each re-sign, loudly (spec: "Folder access
  lost"). **Fallback if (2) fails:** the bridge still works in the other
  direction (snapshot to PC), and writes fall back to Garmin-direct only;
  the owner is told which tools are unavailable.
- No App Group, iCloud container, CloudKit or push is used. If the owner
  ever pays for the Developer Program, the transport can be swapped for an
  app-owned iCloud container without changing the command model.

### D3 — Consistency model: an ordered, idempotent, eventually-applied command log

- **Folder layout**: `inbox/` (PC writes), `results/` (app writes),
  `archive/` (app moves applied commands here), `state.json` (app
  writes), `README.txt` (app writes once: what the folder is).
- **Command envelope**: `{ protocolVersion, commandId (UUID),
  createdAt, notAfter?, issuedBy: "garminfood-mcp/<version>", kind,
  payload, preconditions? }`. File name
  `<createdAt ISO basic>-<commandId>.json` so a directory listing sorts in
  creation order.
- **Apply rules**: ascending `createdAt`; one command at a time; an
  applied-id ledger (`bridge-ledger.json`, 90 days) makes every command
  at-most-once even when iCloud duplicates a file or the app dies mid-run;
  results are written before the command is archived, so a crash between
  the two re-writes the same result instead of applying twice.
- **Latency**: a command applies at the next app launch or foreground,
  after iCloud has synced both ways. Every bridge tool says so in its
  reply. Nothing on the PC ever waits for the phone.
- **Conflicts**: the phone is the authority for phone-only data.
  - Commands name targets by stable id (product id, preset id, note date),
    never by list position.
  - Update commands carry `preconditions.expectedUpdatedAt` from the
    snapshot the PC read. If the target changed on the phone since, the
    command is rejected with `conflict` and the current value is in the
    result, so Claude can re-read and retry. Create/append commands
    (tick, log, add note text) have no precondition.
  - Ticks and intake are already idempotent by (date, product, slot) in
    `SupplementIntakeStore`, so a tick from the PC and a tap on the phone
    for the same slot give one record.
- **Expiry**: `food.log` via bridge sets `notAfter` to the end of the
  target nutrition day + 48 h by default, so a command that sat in iCloud
  for a week doesn't surprise the owner. Configuration commands have no
  expiry.
- **Local-first is kept**: applying a command calls the same
  zero-network-wait confirm paths; Garmin delivery still happens only via
  `Outbox.drain`.

### D4 — Adopt receipts keep streak and XP right for direct Garmin logs

- The server sets `logTimestamp` to its own send time, like the app
  does with its outbox entry's `createdAt` (the app's Reconciliation uses
  that equality as its de-facto idempotency marker), and never retries a
  create whose outcome is unknown without first re-reading the day.
- After a direct `createFoodLogEntry` succeeds, the server reads the day
  back (`dailyFoodLog`) to find the new `logId`, then writes a
  `food.adopt` command with the entry's food id, serving, quantity, meal,
  date and `logTimestamp`.
- The app applies it with a new record-only path: `usageHistory.record`
  (and `servingDefaults.setDefault`) with the Garmin log time, then
  `GamificationEngine.handleLogConfirmed`. It does **not** touch the
  outbox, so there is nothing to deliver and nothing for Reconciliation to
  treat as a duplicate (Reconciliation only acts on this phone's own
  queued entries).
- Idempotent twice over: by `commandId`, and by `logId` (an adopt of a
  `logId` already adopted is `applied` with no effect).
- Late credit is fine: `StreakEngine.loggedDays` buckets events by their
  timestamp's nutrition day, so an entry logged at 12:30 and adopted at
  18:00 counts for its own day. XP for an entry adopted more than 7 days
  after its date follows the same late-entry rule supplements use (no XP),
  to avoid backfilling farms.
- Without a bridge the tool still logs to Garmin and says plainly that it
  won't count for the streak.
- The **existing generic Garmin MCP** writes without receipts. Design Q3
  asks the owner whether to disable its write tools.

### D5 — Where the server lives and what it is built with

- `tools/mcp/`, next to the Node tooling it reuses, as its own npm package
  (`package.json`, `tsconfig.json`, `src/`, `test/`). Not a new top-level
  folder: the repo's convention is that everything that runs on Windows
  lives under `tools/`.
- TypeScript compiled with `tsc` to `tools/mcp/dist/` (Node 22.12 is
  installed; type stripping is still behind a flag there, so a build step
  is the safer choice). `dist/` is git-ignored.
- Dependencies: `@modelcontextprotocol/sdk` (stdio transport), `zod`
  (input schemas → JSON Schema for the tool list), `ajv` (validate
  commands against `docs/bridge-protocol/*.schema.json`). Nothing else.
  Garmin auth is imported from `tools/lib/garmin-auth.mjs` unchanged.
- Tests: `node --test` on the compiled output, with a fake Garmin HTTP
  layer and a temp bridge folder. **No test calls the live Garmin API.** A
  new `.github/workflows/mcp.yml` runs them on `ubuntu-latest` for changes
  under `tools/mcp/**` or `docs/bridge-protocol/**`.

### D6 — Tool surface

Names use `area.verb`. "G" = Garmin-direct now; "B" = bridge, applies on
next app open; "S" = reads `state.json`; "X" = experimental, hidden
unless enabled (D7). Every write takes `confirm?: boolean` (D8) and
returns `{ preview | outcome, appliesWhen, commandId? }`.

| Tool | Path | Input (JSON Schema sketch) | Side effect |
|---|---|---|---|
| `server.status` | local | `{}` | none — token found?, bridge folder, snapshot age, experimental flags, phone-only actions list |
| `food.search` | G + local | `{ query: string, limit?: int≤50, sources?: ("garmin"\|"myFoods"\|"openFoodFacts")[] }` | none (Garmin `foodSearch`; custom foods/presets from S; OFF public API) |
| `food.lookupBarcode` | OFF | `{ barcode: string /^\d{8,14}$/ }` | none |
| `food.getDay` | G | `{ date: date }` | none (`dailyFoodLog` + `mealsForDate`) |
| `food.getRange` | G | `{ startDate: date, endDate: date (≤31 d) }` | none (`calorieSummaryDaily`) |
| `food.recent` | G + S | `{ limit?: int }` | none (`recentFoods`, usage history) |
| `food.log` | G (+B adopt) or B | `{ foodId, servingId, quantity: number>0, meal: enum, date?: date, source?: "GARMIN"\|"FATSECRET", via?: "garmin"\|"bridge", confirm? }` | G: PUT `food/logs` + `food.adopt` command; B: `food.log` command |
| `food.logCustom` | B | `{ customFoodId, quantity, meal, date?, confirm? }` | `food.logCustom` command (app resolves backing food) |
| `food.logAgain` | G or B | `{ fromDate, logId, meal?, date?, via?, confirm? }` | re-log of a read-back entry (same as Duplicate) |
| `food.copyMeal` | G or B | `{ fromDate, fromMeal, toDate?, toMeal?, logIds?: string[], via?, confirm? }` | N creates (+ adopts) or one `food.copyMeal` command |
| `food.editEntry` | G or B | `{ date, logId, quantity?, meal?, via?, confirm? }` | G: create new then delete old (D7 gate); B: `food.edit` command → app `replace` |
| `food.deleteEntry` | G or B | `{ date, logId, via?, confirm? }` | G: `deleteFoodLogEntries` (gated, D7); B: `food.delete` command |
| `food.quickAdd` | X | `{ name, calories, protein?, carbs?, fat?, meal, date?, confirm }` | `quickAddFoodLogEntry` — documented, never exercised |
| `customFood.list` | S | `{}` | none |
| `customFood.create` | B | `{ name, brand?, servingLabel, nutrients: {calories, protein?, carbs?, fat?, fiber?, sugar?, …}, backing: { foodId, servingId, multiplier } \| null, barcode?, confirm? }` | `customFood.create` command (local `CustomFoodDraft`) |
| `customFood.update` / `.delete` | B | `{ id, …fields, expectedUpdatedAt?, confirm? }` | command |
| `garmin.createCustomFood` | X | `{ name, nutrients, servingUnit, numberOfUnits, confirm }` | `createCustomFood` — unconfirmed body |
| `preset.list` | S | `{}` | none |
| `preset.create` | B | `{ name, defaultMeal?, ingredients: [{ foodId, servingId, quantity, source?, name, nutrientsSnapshot } \| { customFoodId, quantity }] (≥1), confirm? }` | command |
| `preset.createFromDay` | G→B | `{ date, meal, name, logIds?, confirm? }` | reads the day, then `preset.create` command |
| `preset.update` / `.delete` | B | `{ id, …, expectedUpdatedAt?, confirm? }` | command |
| `preset.log` | G (+adopts) or B | `{ id, meal?, date?, scale?: number, via?, confirm? }` | N creates + N adopts, or one `preset.log` command → `confirmMealPreset` |
| `garmin.createCustomMeal` | X | `{ presetId, confirm }` | `createCustomMeal` — guessed body, never sent |
| `favorite.list` / `.set` | S / B | `{ foodId, favorite: bool, confirm? }` | command (favourites are local; Garmin favourite route has no evidence) |
| `note.get` / `note.set` | S / B | `{ date, text?, tags?: string[], expectedUpdatedAt?, confirm? }` | command |
| `weight.list` | G | `{ startDate, endDate }` | none (`getWeighIns`) |
| `weight.add` | G | `{ kg: number 20–300, at?: datetime, confirm? }` | `addWeighIn` (confirmed 204, 2026-09-23) |
| `weight.delete` | G | `{ date, samplePk, confirm? }` | `weighInDelete` (confirmed 204, 2026-09-23) |
| `water.get` | G | `{ date }` | none (`hydrationDaily`) |
| `water.add` | G | `{ ml: int −3000…3000, date?, confirm? }` | `addHydration` (exercised on device, owner-confirmed) |
| `goals.get` | G + S | `{ date? }` | none (`nutritionSettings`; local goals from S) |
| `goals.setLocal` | B | `{ calories?, protein?, carbs?, fat?, fiber?, water?, targetWeightKg?, expectedUpdatedAt?, confirm? }` | command |
| `fasting.status` | S | `{}` | none |
| `fasting.setSchedule` | B | `{ enabled?: bool, fromMinute?: int 0–1439, untilMinute?: int 0–1439, confirm? }` | command → `preferences.fasting.*` + reminder re-plan (no manual start/stop exists since `redesign-fasting-schedule`) |
| `supplement.list` | S | `{ includeHistoryDays?: int≤90 }` | none |
| `supplement.catalog` | local | `{ query? }` | none (built-in catalog shipped as JSON in the protocol fixtures) |
| `supplement.addProduct` | B | `{ fromCatalog?: id, name, brand?, ingredients: [{ id, amount, unit, form? }], servingUnit, pack?: { size, price?, currency? }, confirm? }` | command |
| `supplement.updateProduct` / `.archiveProduct` | B | `{ productId, …, expectedUpdatedAt?, confirm? }` | command |
| `supplement.setSchedule` | B | `{ productId, slots: [{ slot, servings }], pattern: { kind: "daily"\|"everyNDays"\|"weekdays"\|"trainingDays"\|"cycle", … }, effectiveFrom?: date, confirm? }` | command |
| `supplement.tick` | B | `{ date, productId, slot, servings?: number>0, taken: bool, confirm? }` | command (idempotent per date/product/slot) |
| `supplement.takeAll` | B | `{ date, slot, confirm? }` | command |
| `supplement.logExtra` | B | `{ date, productId, servings, at?, confirm? }` | command |
| `supplement.setLimit` / `.resetLimit` | B | `{ ingredientId, target?, upperLimit?, confirm? }` | command |
| `supplement.refill` / `.setStock` | B | `{ productId, packs: number>0, price? }` / `{ productId, servingsOnHand: number≥0 }` + `confirm?` | command |
| `supplement.removeIntake` | B | `{ date, recordId, confirm? }` | command |
| `supplement.removeFromStack` / `.deleteProduct` | B | `{ productId, confirm? }` | command (delete is irreversible; preview says so) |
| `supplement.setSlotReminder` | B | `{ slot, minuteOfDay: int 0–1439 \| null, confirm? }` | command → re-plan on apply |
| `supplement.totals` | S | `{ date }` | none (computed in the snapshot) |
| `reminders.get` / `.set` | S / B | `{ kind, enabled?, time?, confirm? }` | command → re-plan on apply |
| `progress.summary` | S | `{}` | none — streak, freezes, level/XP, today's challenges, boss, bingo |
| `progress.achievements` / `.records` / `.journeys` / `.collections` | S | `{}` | none |
| `settings.get` / `settings.set` | S / B | `{ key: enum, value, confirm? }`. Allow-list: `haptics`, `celebrations`, `garminMealWindows`, `czechOnlySearch`, `quantityInputMode`, `offlineIndex.allowsCellular`, `fasting.enabled`, `supplements.enabled`, `goals.water.overrideML`, `goals.weight.overrideKg`, `goals.weight.startKg`, `profile.localDisplayName`, `appearance.theme`, `appearance.accent`, `layout.<screen>.cards`, `layout.startTab`. Never `dataMode.v1` or `developer.*` | command → `AppPreferences` / `ThemeStore` / `LayoutStore` |
| `appearance.applyThemeCode` | B | `{ code: string /^GFT1\./, confirm? }` | command → `ThemeStore.applyImported` (same validation as the in-app import) |
| `data.exportSnapshot` | B | `{ confirm? }` | asks the app to write a fresh `state.json` and a data-safety backup copy into the bridge folder |
| `bridge.status` / `bridge.result` / `bridge.cancel` | local | `{}` / `{ commandId }` / `{ commandId, confirm? }` | cancel deletes an unapplied command file |

`preset.log` and `food.copyMeal` with `via: "garmin"` send one create per
ingredient, like the app does (meal-presets D1), and stop at the first
failure, reporting which items made it.

### D7 — Garmin write gating follows the route registry, not the tool

| Registry status | Operations | MCP behaviour |
|---|---|---|
| Confirmed on this account | `createFoodLogEntry` (2026-09-16), `addWeighIn`, `weighInDelete` (204, 2026-09-23), `addHydration` (owner-confirmed on device) | Available; `confirm: true` required |
| Documented from a live-tested client, recorded as not exercised here | `deleteFoodLogEntries` — note the shipped app already calls it **directly** on every delete of a delivered entry (`deleteCommitted`), so it has very likely run on the device; the registry was never updated | Available only after task 2.6 records the evidence (the owner's own in-app deletes, checked in the diagnostics log, or one approved probe); until then hidden like X. `food.editEntry`/`deleteEntry` default to `via: "bridge"` meanwhile, where the app's own (already shipped) replace/delete path runs |
| Unconfirmed / guessed | `createCustomFood`, `createCustomMeal`, `quickAddFoodLogEntry`, `bulkCreateFoodLogEntries`, `calculateGoals` | Hidden unless `GARMINFOOD_MCP_EXPERIMENTAL_WRITES` names it; description starts "EXPERIMENTAL — unconfirmed Garmin route"; full request/response logged |
| No evidence | `favorite/food` POST, nutrition settings writes | Not implemented |

The server reads the registry at startup (spec: "Every Garmin call goes
through the route registry"), so a route moved to confirmed in the registry
is picked up without a code change to the gate.

### D8 — Safety model for writes

- **Dry-run by default.** Without `confirm: true` every write returns a
  preview and changes nothing. Claude Desktop also shows its own per-tool
  approval prompt; the dry-run makes the preview readable before that.
- **Bounded scope per call.** One day per food write, at most 20 entries
  per `copyMeal`/`preset.log`, no "delete all", no date ranges for writes.
- **Commands cannot reach credentials.** The command allow-list excludes
  sign-in/out, data mode, restore, store deletion, diagnostics clearing
  and notification permission. The app enforces the same list (spec
  "Forbidden command kind"), so a hand-written file in `inbox/` can't
  bypass the server.
- **Same warnings as the UI.** A `food.log` preview includes the
  fasting-window note and the supplement over-limit notice the app would
  show, computed from the snapshot. Neither blocks, as in the app.
- **Tokens never enter the bridge folder.** The PC reads the vault's token
  file as the existing tools do; the phone keeps its own. The snapshot
  goes through the same token-key scan the backup export already has.
- **Who can write to the inbox.** Anyone with the owner's iCloud account or
  the PC user account. That is the same trust boundary as the Garmin token
  file on the PC and the backup file in iCloud Drive. Not signing
  commands is a deliberate simplification (Q5).
- **Loud failures.** Garmin 401/403 → tool error "Garmin sign-in needed on
  this PC"; the app's own auth banner is independent and unchanged. Bridge
  rejections → diagnostics log + Today notice on the phone (spec) and
  `bridge.status` on the PC. A stale snapshot is always stated, never
  hidden.

### D9 — App side: a pure applier in FoodLogCore, a thin runner in the app

- `FoodLogCore/Bridge/`:
  - `BridgeCommand` (Codable envelope + `kind` as an open string with
    typed payloads; unknown kinds decode to `.unknown` instead of failing
    the file, per `docs/data-compatibility.md` rule 3);
  - `BridgeCommandApplier` — pure routing from a command to a
    `BridgeTargets` protocol (one method per kind), implemented in the app
    by the real coordinators and stores; unit-tested with the real stores
    on temp files, per the repo's test convention;
  - `BridgeLedger` (applied ids, 90 days; a store following the
    unreadable-file contract, with a fixture per `data-compatibility.md`);
  - `BridgeSnapshotBuilder` — pure, from the same local stores the backup
    reads, into the versioned `state.json` shape.
- `GarminFood/Bridge/`: folder picker + bookmark, `BridgeRunner` (launch,
  `scenePhase == .active`, "Check now"; coordinated reads; atomic writes;
  never on the main actor), status view, Today notice. Wired through
  `AppServices`/`AppEnvironment` like every store.
- **Some mutation logic lives in app-target controllers today**, not in
  FoodLogCore — e.g. `GarminFood/Supplements/SupplementsController.swift`
  (`setTaken`, `takeAll`, `addExtra`, `save`, `refill`, `setLimit`, …)
  and the fasting/notes/goal editors. The bridge must not re-implement it.
  Wave 3 first moves each such mutation into a FoodLogCore type that both
  the controller and `BridgeTargets` call (a behaviour-preserving
  refactor, covered by the existing tests plus new ones), which also makes
  it unit-testable — the repo's "push logic down" convention.
- `food.adopt` needs one new FoodLogCore entry point,
  `LogEntryCoordinator.adoptDelivered(...)` (usage history + serving
  default, no outbox). Everything else maps to an existing public method.

### D10 — One protocol document, tested from both sides

- `docs/bridge-protocol.md` (human), `docs/bridge-protocol/command.schema.json`,
  `result.schema.json`, `state.schema.json`, and
  `docs/bridge-protocol/fixtures/<kind>.json` (one valid example per
  command kind plus invalid ones).
- The Node tests validate the server's output against the schema and
  compare it with the fixtures. FoodLogCore tests decode every fixture
  through `BridgeCommand` and apply it with real stores. A fixture
  coverage test (like `testEveryPersistedFileHasAFixture`) fails when a
  kind has no fixture.
- `protocolVersion` starts at 1; additive changes keep it; a breaking
  change bumps it and the app refuses newer versions (spec).

### D11 — The snapshot is a projection, not a backup

`state.json` is a curated, documented projection (`state.schema.json`), not
the `add-data-safety` backup container, because the backup is a verbatim
copy of internal store formats (which may change under the compatibility
contract) and includes areas the PC doesn't need. The snapshot shape is
part of the protocol and versioned with it. `data.exportSnapshot` can
additionally drop a real backup file into the folder for the rare
"inspect everything" case.

### D12 — Claude Desktop and Claude Code configuration on Windows

`%APPDATA%\Claude\claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "garminfood": {
      "command": "node",
      "args": ["C:\\Git\\Projects\\GarminFood\\tools\\mcp\\dist\\index.js"],
      "env": {
        "VAULT_ROOT": "C:\\path\\to\\Jirkas_world",
        "GARMINFOOD_BRIDGE_DIR": "C:\\Users\\<user>\\iCloudDrive\\GarminFood Bridge"
      }
    }
  }
}
```

Claude Code: `claude mcp add garminfood --scope user -- node
C:\Git\Projects\GarminFood\tools\mcp\dist\index.js` with the same env.
`tools/mcp/README.md` documents both, plus `npm ci && npm run build`.
Paths are passed as arguments/env, never hard-coded, and the server logs to
stderr only (stdout is the MCP channel).

## Risks / Trade-offs

- **The bookmark or iCloud sync doesn't behave (D2).** → Verified on the
  device in wave 1 before any bridge feature is built; fallbacks named in
  D2. If both directions fail, the change shrinks to Garmin-direct tools +
  read-only snapshot via manual export.
- **iCloud for Windows sync is slow or pauses.** → Every bridge reply
  states that it applies on next app open; `bridge.status` shows overdue
  commands; results are the only proof of application.
- **Double logging** (the same meal logged via Garmin-direct and via the
  bridge, or by the generic Garmin MCP and this one). → One `via` per call,
  preview shows the day's existing entries for that meal, and Q3.
- **Private routes break.** → Registry-driven gate; failures name the
  route; fallback for food writes is `via: "bridge"` (the app's outbox
  retries later with the same route, but on the phone's schedule);
  fallback for reads is the snapshot's cached day digests.
- **Adopt credits an entry the owner then deletes in Garmin.** → Same as
  deleting an app-logged entry today: usage history keeps the event. Not
  worse than the status quo; noted, not solved.
- **Protocol drift between Swift and TypeScript.** → Shared schema and
  fixtures tested on both sides (D10).
- **Sensitive data in iCloud Drive.** → Same class of data as the backup
  export the owner already stores there; no tokens (D8).
- **A second, parallel write path makes bugs harder to trace.** → Every
  command and result is a file the owner can open; the diagnostics log has
  a `bridge` category; commands record `issuedBy`.

## Owner answers (2026-09-27)

- **Q1 — answered:** `iCloud Drive/GarminFood Bridge`. iCloud for Windows is
  installed and syncing; on the PC the folder is
  `C:\Users\jmlcousek\iCloudDrive\GarminFood Bridge` (created 2026-09-27).
- **Q2 — answered: through the phone.** Food logged from the PC goes to the
  app as a bridge command (`via: "bridge"` is the default and the only food
  path in the first release): the app logs it exactly like a tap, and its
  outbox delivers it to Garmin as it does today. Garmin-direct food writes
  (wave 6.1 `via: "garmin"`) are not built unless the owner asks later;
  `food.adopt` is only needed for them and is deferred with them.
- **Q3 — answered: keep** the existing generic `garmin` MCP server as it is,
  alongside this one. Its writes still give no streak credit; the docs say so.
- **Q4 — defaulted:** no probe. Food edits/deletes from the PC go through
  the bridge (the app's own delete path), so the direct delete stays hidden.
- **Q5 — defaulted:** the iCloud/PC account is the trust boundary
  (unsigned commands, allow-listed kinds, no credential access).
- **Q6 — defaulted:** no Shortcuts automation in the first release.
- **Q7 — defaulted:** owner-only for now.
- **Q8 — defaulted:** yes, no XP for items credited more than 7 days late.

Weight and water from the PC also go through the bridge (same reason as Q2),
unless the owner asks for Garmin-direct later.

## Open questions for the owner (original wording)

- **Q1** Which iCloud Drive path and folder name? (Default proposed:
  `iCloud Drive/GarminFood Bridge`.) Is iCloud for Windows already
  installed and syncing on this PC?
- **Q2** For food logs, should the default be `via: "garmin"` (instant in
  Garmin, streak credit when the app next opens) or `via: "bridge"`
  (everything identical to a tap, but nothing in Garmin until the phone
  opens the app)?
- **Q3** The existing generic `garmin` MCP server can already log and
  delete food in Garmin, without streak credit or this project's gating.
  Keep it enabled next to this one, disable its write tools, or remove it?
- **Q4** The app already deletes delivered entries with a direct
  `DELETE food/logs/{date}`. Have in-app deletes worked for you (entry gone
  in Garmin Connect)? If yes, that is enough to mark the route confirmed
  (task 2.6); if unsure, OK to spend one approved test write + delete from
  the PC? Until then, PC edits and deletes go through the bridge.
- **Q5** Is "anyone with your iCloud or PC account can queue commands" an
  acceptable trust boundary, or should commands be signed with a key
  shared once via the picker (more setup, more to break)?
- **Q6** Should the optional Shortcuts automation (c2) be built, and at
  what times (e.g. 07:00, 12:00, 18:00, 22:00)?
- **Q7** Should the fiancée's standalone install ever get the bridge, or
  is this owner-only? (Plan assumes owner-only for Garmin tools; bridge is
  mode-agnostic.)
- **Q8** Late adopt XP: no XP for entries adopted more than 7 days after
  their date (mirrors supplements) — agree?

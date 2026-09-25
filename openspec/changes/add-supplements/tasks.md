## 0. Before starting

- [ ] 0.1 `rebalance-xp-economy` merged (supplement XP is priced through its optional-source multiplier).
- [ ] 0.2 `add-weekly-boss-and-streak-freezes` merged (freeze pool); themes wave 3 merged (Today card registry, #78).
- [ ] 0.3 Confirm the design's open questions with the owner: default slot reminder times; sodium shown as mg with salt as secondary.

## 1. Wave 1 — Pure core (FoodLogCore, no UI)

- [x] 1.1 Models: `Ingredient` (ids, canonical units, magnesium form), `IngredientAmount`, `SupplementProduct`, `SupplementSchedule` (slots and patterns incl. cycles, `effectiveFrom` history), `IntakeRecord`. Optional Codable fields; tolerant decoding.
- [x] 1.2 `ScheduleEvaluator.due(on:plan:trainingDays:)`: every pattern, cycles across phase boundaries, schedule edits applying from their day forward. Tests for each spec scenario.
- [x] 1.3 Stack-complete / neutral / partial / missed day classification. Tests.
- [x] 1.4 `IngredientTotals` with IU→µg conversion and multi-ingredient products. Tests (the zinc 10 + 25 mg case, ZMA).
- [x] 1.5 `EvidenceCatalog` + `SupplementCatalog`: ingredient cards and default limits entered **from the source PDFs** (design D8 table; don't trust summaries), en + cs texts written for the app, sources and disclaimer. Test: every catalog product's ingredients have a card; every limit has a source.
- [x] 1.6 Limits: defaults + user overrides + reset; over-limit evaluation incl. "no EU UL" cases. Tests.
- [x] 1.7 `LabelScore` (transparency 40 / dose 40 / headroom 20) with an explained breakdown. Tests (proprietary blend, effective creatine dose).
- [x] 1.8 `StockProjection`: stock after ticks, days left under the current schedule, restock trigger once per pack; cost per day/month. Tests.
- [x] 1.9 Past-day logging (design D14): intake for any day up to 365 days back evaluated against that day's schedule; stock counts only intake on/after `stockSetOn`; late entries (> 7 days after their date) grant no XP. Tests.

## 2. Wave 2 — Stores and wiring

- [ ] 2.1 `SupplementPlanStore`, `SupplementIntakeStore` (month-sharded), `SupplementLimitsStore`: JSON actors, unreadable-file/quarantine contract, `save` loads first, idempotent intake writes keyed by (date, product, slot). Tests: round-trip, quarantine, old-file decode, idempotency.
- [ ] 2.2 Register the stores in `AppServices`/`AppEnvironment`; `AppPreferences.supplementsEnabled` (default false).
- [ ] 2.3 Standalone backup/export includes the supplement stores (`add-standalone-mode` data-backup). Test export → import round-trip.
- [ ] 2.4 Training-day input: read `ActivityCacheStore` (existing confirmed read-only route; no new Garmin route) + `race` day-note tags; standalone falls back to tags only.

## 3. Wave 3 — Screens

- [ ] 3.1 Settings row "Supplements" / "Doplňky stravy" + first-enable onboarding (pick from catalog → slots and reminders).
- [ ] 3.2 Supplements screen: Today checklist (tick, Take all, extra dose), past-day editing via date picker and adherence calendar (any day up to 365 days back), My stack, product editor (catalog / custom / ingredients / pack and price / certifications), schedule editor (slots, patterns, cycles).
- [ ] 3.3 Totals and limits view with warnings; limit editor with default and source shown, and reset.
- [ ] 3.4 Insights: adherence calendar and per-product 7/30-day %, stock overview, cost.
- [ ] 3.5 Evidence card view and label score breakdown; "Verify certification" links and the manual certified badge.
- [ ] 3.6 Today card `TodayCardID.supplements` with `slot` and `day` variants; availability = enabled and ≥ 1 product; extend the golden-order test (unchanged when disabled). Entry row on Progress.
- [ ] 3.7 All strings en + cs (Czech plurals for doses: kapsle/kapslí), `SpokenUnits` for VoiceOver, locale decimals, Dynamic Type, Reduce Motion, theme tokens only. Glossary additions (design D12).

## 4. Wave 4 — Reminders

- [ ] 4.1 `NotificationPlanning`: `.supplementSlot` (skipped once the slot is done) and `.supplementRestock` kinds, en + cs texts. Tests through the pure planner and the title/body diff.
- [ ] 4.2 Notification category with a "Taken" action; the delegate writes the slot's intake records in the background (idempotent); on a store error, open the app on the slot and log to `DiagnosticsLog`.
- [ ] 4.3 Disabling the feature removes pending supplement reminders (scheduler diff). Test through the planner.

## 5. Wave 5 — Barcode prefill

- [ ] 5.1 Probe (read-only) the Open Food Facts product endpoint `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json` with 3 real supplement barcodes (one Czech, one German, one US brand). Record the status code and payload shape (which fields hold name, brand, quantity; whether nutriments hold per-serving values) in `docs/supplement-data-sources.md`, dated.
- [ ] 5.2 Probe (read-only) DSLD `GET https://api.ods.od.nih.gov/dsld/v9/search-filter?q=<spaced UPC-A>` and `/label/{id}` for a US product. Record status, shape and observed rate-limit headers in the same doc.
- [ ] 5.3 `SupplementBarcodeLookup`: OFF → DSLD (only for 0-prefixed codes, converted to spaced UPC-A) → manual; local cache by barcode; no network on any confirm path. Tests with fixture JSON (no live network in tests).
- [ ] 5.4 Read the terms of use of NSF Certified for Sport, Informed Sport and Kölner Liste; link only to their public search pages; record the finding in the doc.

## 6. Wave 6 — Gamification

- [ ] 6.1 Feature `supplements` in the registry (grant keys `supplements.*`), reading a `SupplementSignals` digest passed in by the host; budget line in `XPBudget` (optional source, ~6 XP/day before the multiplier).
- [ ] 6.2 Supplement streak with neutral days; freeze planner extended to a shared pool across the food and supplement streaks (only streaks ≥ 3; at most one freeze per missed day per streak). Tests incl. both spec scenarios; food-streak results unchanged when supplements are off.
- [ ] 6.3 Badges (design D9) with rarities; challenges in rotation only while enabled with a plan; vitamin collection; creatine journey. Tests.
- [ ] 6.4 UI: streak and badges on the Supplements screen and in Achievements; en + cs.

## 7. Verify

- [ ] 7.1 `openspec validate add-supplements --strict`; `node tools/check-localizations.mjs`; `bash tools/lint-design-tokens.sh`.
- [ ] 7.2 CI green (`swift test` FoodLogCore, Gamification, AppearanceKit; app + widget build).
- [ ] 7.3 On device:
  - enable, add creatine from the catalog, add a custom ZMA, scan a Czech product;
  - tick the morning slot from the notification's "Taken" action on the lock screen;
  - check totals and the zinc warning, a limit override, stock days left and restock reminder;
  - disable and re-enable (data kept, no reminders while off);
  - the Czech texts and VoiceOver units read correctly.

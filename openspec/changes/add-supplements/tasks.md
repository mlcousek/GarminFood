## 0. Before starting

- [x] 0.1 `rebalance-xp-economy` merged (supplement XP is priced through its optional-source multiplier).
- [x] 0.2 `add-weekly-boss-and-streak-freezes` merged (freeze pool); themes wave 3 merged (Today card registry, #78).
- [x] 0.3 Confirm the design's open questions with the owner: default slot reminder times; sodium shown as mg with salt as secondary. **Defaulted, owner may override:** morning 08:00, evening 21:00, with-breakfast and pre-workout no reminder (manual, settable per slot); sodium in mg with salt (Na × 2.5) shown as secondary.

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

- [x] 2.1 `SupplementPlanStore`, `SupplementIntakeStore` (month-sharded), `SupplementLimitsStore`: JSON actors, unreadable-file/quarantine contract, `save` loads first, idempotent intake writes keyed by (date, product, slot). Tests: round-trip, quarantine, old-file decode, idempotency.
- [x] 2.2 Register the stores in `AppServices`/`AppEnvironment`; `AppPreferences.supplementsEnabled` (default false).
- [x] 2.3 Standalone backup/export includes the supplement stores (`add-standalone-mode` data-backup). Test export → import round-trip. **Covered by `add-data-safety`'s generic snapshot:** it copies the whole FoodLogCore data directory, and all three supplement stores live there (`supplement-plan.json`, `supplement-limits.json`, `SupplementIntake/<yyyy-MM>.json` under Application Support/FoodLogCore). The export → restore round-trip is tested there; supplement fixtures are added per `docs/data-compatibility.md` once `add-data-safety` merges.
- [x] 2.4 Training-day input: read `ActivityCacheStore` (existing confirmed read-only route; no new Garmin route) + `race` day-note tags; standalone falls back to tags only.

## 3. Wave 3 — Screens

- [x] 3.1 Settings row "Supplements" / "Doplňky stravy" + first-enable onboarding (pick from catalog → slots and reminders).
- [x] 3.2 Supplements screen: Today checklist (tick, Take all, extra dose), past-day editing via date picker and adherence calendar (any day up to 365 days back), My stack, product editor (catalog / custom / ingredients / pack and price / certifications), schedule editor (slots, patterns, cycles).
- [x] 3.3 Totals and limits view with warnings; limit editor with default and source shown, and reset.
- [x] 3.4 Insights: adherence calendar and per-product 7/30-day %, stock overview, cost.
- [x] 3.5 Evidence card view and label score breakdown; "Verify certification" links and the manual certified badge. *Links go only to each certifier's public search page (no query URLs) until 5.4 records their terms.*
- [x] 3.6 Today card `TodayCardID.supplements` with `slot` and `day` variants; availability = enabled and ≥ 1 product; extend the golden-order test (unchanged when disabled). Entry row on Progress.
- [x] 3.7 All strings en + cs (Czech plurals for doses: kapsle/kapslí), `SpokenUnits` for VoiceOver, locale decimals, Dynamic Type, Reduce Motion, theme tokens only. Glossary additions (design D12).

## 4. Wave 4 — Reminders

- [x] 4.1 `NotificationPlanning`: `.supplementSlot` (skipped once the slot is done) and `.supplementRestock` kinds, en + cs texts. Tests through the pure planner and the title/body diff.
- [x] 4.2 Notification category with a "Taken" action; the delegate writes the slot's intake records in the background (idempotent); on a store error, open the app on the slot and log to `DiagnosticsLog`. *On a store error it logs to DiagnosticsLog and posts a follow-up notification asking to open the app (a background action can't bring the app forward itself). Restock reminders are add-only (once per pack), so the diff can't cancel one before it fires.*
- [x] 4.3 Disabling the feature removes pending supplement reminders (scheduler diff). Test through the planner.

## 5. Wave 5 — Barcode prefill

- [x] 5.1 Probe (read-only) the Open Food Facts product endpoint `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json` with 3 real supplement barcodes (one Czech, one German, one US brand). Record the status code and payload shape (which fields hold name, brand, quantity; whether nutriments hold per-serving values) in `docs/supplement-data-sources.md`, dated.
- [x] 5.2 Probe (read-only) DSLD `GET https://api.ods.od.nih.gov/dsld/v9/search-filter?q=<spaced UPC-A>` and `/label/{id}` for a US product. Record status, shape and observed rate-limit headers in the same doc.
- [x] 5.3 `SupplementBarcodeLookup`: OFF → DSLD (only for 0-prefixed codes, converted to spaced UPC-A) → manual; local cache by barcode; no network on any confirm path. Tests with fixture JSON (no live network in tests).
- [x] 5.4 Read the terms of use of NSF Certified for Sport, Informed Sport and Kölner Liste; link only to their public search pages; record the finding in the doc.

## 6. Wave 6 — Gamification

- [x] 6.1 Feature `supplements` in the registry (grant keys `supplements.*`), reading a `SupplementSignals` digest passed in by the host; budget line in `XPBudget` (optional source, ~6 XP/day before the multiplier). Since `rebalance-xp-economy` (#83): pay through `XPBudget.optionalMultiplier(enabledOptionalSources:lines:)` + `scaledGrant(_:multiplier:)` (or `optionalGrantXP`), and at most about ONE grant per day (e.g. stack complete), because every grant is at least 1 XP and the cap is 0.5% of core. *Done: `SupplementsFeature` (registered last), the digest built by `FeatureHost.buildSupplementSignals` and passed in `FeatureContext.supplements`; one grant `supplements.stack.<day>` per stack-complete day in the 7-day grace window (on-time ticks only), scaled by `optionalGrantXP` (1 XP). The host scales an optional source's badge bonus the same way. A tick re-runs gamification.*
- [x] 6.2 Supplement streak with neutral days; freeze planner extended to a shared pool across the food and supplement streaks (only streaks ≥ 3; at most one freeze per missed day per streak). Tests incl. both spec scenarios; food-streak results unchanged when supplements are off. *Done: `SupplementStreak` (pure walk; no weekly grace, per the spec's missed-day scenario), `StreakFreezePlanner.planShared` (the earlier break gets the freeze, food first on a tie; `plan` delegates to it with no supplements, pinned by StreakFreezeTests + an equivalence test). A consumption now records its `streak` (absent = food; store v2 fixture; `gamification.features` schema 2). D10 "frozen in place" while off: `SupplementPause` records off/on ranges in `supplements.json` and reads paused days as neutral.*
- [x] 6.3 Badges (design D9) with rarities; challenges in rotation only while enabled with a plan; vitamin collection; creatine journey. Tests. *Done: 10 badges (`supplements.*`, category `.supplements`; Stack week = 7-day supplement streak, Full stack month = 30; Omega month = 30 days in a row; Alphabet counts vitamins AND minerals -- the app has only 5 vitamins; unearned ones hidden while off). 4 core challenge templates (`supp-*`, Czech in Catalog.strings) with static weight 0 -- outside "complete every challenge" and the mean-reward assumption -- offered (weight 3) only while the digest is active and, for slot rules, the slot was completed in the last 14 days; their XP is ordinary challenge XP (same single slot). Vitamin alphabet = 11 built-in vitamins/minerals; creatine journey 100 g / 500 g / 1 kg / 2.5 kg / 5 kg with scaled milestone grants. Creatine per day is kept in `supplements.json` beyond the 365-day digest.*
- [x] 6.4 UI: streak and badges on the Supplements screen and in Achievements; en + cs. *Done: `SupplementProgressSection` on the Supplements screen (streak + longest, badge strip, vitamin alphabet, creatine journey, link to Achievements); Achievements gets a "Supplements" group with the streak row. App strings in Localizable.xcstrings (inserted as text: main's catalog holds a duplicate "Achievements" key, so a parse/stringify round trip would rewrite it), package strings in en/cs .lproj.*

## 7. Verify

- [x] 7.1 `openspec validate add-supplements --strict`; `node tools/check-localizations.mjs`; `bash tools/lint-design-tokens.sh`. *All three pass locally after wave 6 (2026-09-26).*
- [ ] 7.2 CI green (`swift test` FoodLogCore, Gamification, AppearanceKit; app + widget build).
- [ ] 7.3 On device:
  - enable, add creatine from the catalog, add a custom ZMA, scan a Czech product;
  - tick the morning slot from the notification's "Taken" action on the lock screen;
  - check totals and the zinc warning, a limit override, stock days left and restock reminder;
  - disable and re-enable (data kept, no reminders while off);
  - the Czech texts and VoiceOver units read correctly.

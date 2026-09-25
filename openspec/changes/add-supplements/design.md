## Context

The owner is starting a supplement stack and wants the app to track it. This
design comes from a grilling session on 2026-09-25 (decisions below) and a
read-only research pass on the same day (D7). Garmin plays no part:
supplements are local, like weight/water notes in standalone mode. That
makes the feature identical in Garmin and standalone mode, and it must be
included in the standalone backup/export (`add-standalone-mode` data-backup
spec).

The closest existing pattern is **fasting**:
- off by default (`AppPreferences.fastingEnabled`);
- its own screen;
- reminders planned by the pure `NotificationPlanning` and diffed by
  `NotificationScheduler`;
- a Today card that shows only when enabled.

Supplements follows it.

### Owner decisions (2026-09-25)

| Topic | Decision |
|---|---|
| Tracking model | Plan + daily checklist; off-plan extras as one-off logs |
| Garmin | Local only |
| Rating | Evidence cards + upper-limit warnings + barcode prefill + external rating if possible (→ D7: not possible, label score + certification links instead) |
| Limits | User-editable targets and upper limits (endurance athletes need more) |
| Reminders | One per time slot, only if the slot isn't done |
| Entry data | Dose + unit per serving; multi-ingredient products; stock + reorder; schedule patterns incl. cycles and training days |
| Gamification | Streak + badges, challenges, collection/journey; XP must not speed up levelling (→ `rebalance-xp-economy`) |
| Streak rule | Stack complete = all planned items taken; unscheduled days neutral |
| Freezes | Shared pool with the food streak |
| Today card | Current-slot checklist and whole-day pills (two variants); tick any past day (up to 365 days back) from the screen |
| Adding | Built-in catalog, custom product, barcode scan |
| Surfaces | Notification "Taken" action only |
| Modes | Both Garmin and standalone |
| Safety | Informational + disclaimer |
| Disable | Hide everything, keep data, earned badges stay |
| Insights | Adherence history, ingredient totals, stock overview, cost |

## Decisions

### D1 — Module placement

- **FoodLogCore `Supplements/`** (pure models and logic):
  - `Ingredient`, `SupplementProduct`, `SupplementSchedule`,
    `SupplementPlan`, `IntakeRecord`;
  - `ScheduleEvaluator` (which items are due on a date);
  - `IngredientTotals`;
  - `LabelScore`;
  - `StockProjection`;
  - `SupplementCatalog` (built-in products and ingredients);
  - `EvidenceCatalog` (cards and limits).

  No SwiftUI, per the module rule.
- **Stores** (JSON actors, unreadable-file/quarantine contract, `save`
  lazily loads first, Optional fields):
  - `SupplementPlanStore` (products and schedules);
  - `SupplementIntakeStore` (month-sharded intake log, like
    `LocalFoodLogStore`);
  - `SupplementLimitsStore` (user overrides of targets and limits).

  All are registered in `AppServices`.
- **Gamification**: `Features/Supplements/` behind the
  `GamificationFeature` protocol, reading a `SupplementSignals` digest built
  in FoodLogCore. The Gamification package never imports the stores
  directly; the host passes the digest in, like `DaySignals`.
- **App**: `GarminFood/Supplements/` holds the screen, editors, insights,
  evidence card view and the Today card views.

### D2 — Data model

- **`Ingredient`**: a stable id (`creatine`, `magnesium`, `vitaminD`,
  `vitaminC`, `zinc`, `omega3EPA_DHA`, `vitaminB12`, `iron`, `selenium`,
  `vitaminB6`, `caffeine`, `betaAlanine`, `sodium`, `potassium`,
  `vitaminK2`, …) plus a canonical unit (`mg`, `µg`, `g`).
  - Vitamin D accepts IU and is converted at 40 IU = 1 µg; the conversion
    is stored with the product.
  - Magnesium records its **form** (citrate, bisglycinate, oxide…), because
    the EFSA supplemental limit applies to readily dissociable salts and
    oxide.
- **`SupplementProduct`**:
  - id, name, brand, optional barcode, and `form` (capsule, tablet, powder,
    liquid, gummy);
  - `servingDescription` (e.g. "2 capsules", "5 g scoop");
  - `ingredients: [IngredientAmount]` per serving;
  - optional `packServings`, `pricePerPack`, `currency` (default CZK),
    `certifications: [Certification]` (user-set) and a `notes` field;
  - `source`: `.catalog(id)`, `.custom`, `.barcode(provider)`.
- **`SupplementSchedule`**: `slots: [TimeSlot]` (morning, withBreakfast,
  preWorkout, evening, custom(name, time)), `servingsPerSlot`, and a
  `pattern`:
  - `.daily`;
  - `.everyNDays(n, anchor)`;
  - `.weekdays(Set)`;
  - `.trainingDays`;
  - `.cycle(phases: [(servings, days)], anchor, repeat)`, e.g. creatine
    loading 4×5 g for 7 days, then 1×5 g.
- **`IntakeRecord`**: date (the logged day, using `NutritionDayBoundary`),
  product id, slot, servings, `takenAt`, and `kind`: `.planned` or
  `.extra`.
- **Stack complete**: every planned item on a day has an intake record.

### D3 — Schedule evaluation (pure, fully tested)

`ScheduleEvaluator.due(on:plan:trainingDays:)` returns the planned items per
slot:
- Training days come from `ActivityCacheStore`, the same confirmed
  read-only activities route as sport & body, plus days tagged `race` in
  day notes.
- In standalone mode, with no activity data, `.trainingDays` falls back to
  race-tagged days only, and the editor shows a hint.
- Cycles are anchored to a start date and computed arithmetically, so there
  is no stored per-day state.
- Changing a schedule applies from today onward. Past checklists are
  evaluated against the schedule that was active that day, so the plan
  keeps an `effectiveFrom` history, like `LocalGoalStore`.

### D4 — Today card

- A new `TodayCardID.supplements` in AppearanceKit's card registry.
- Availability is "feature enabled and at least one product". The default
  placement is after the meals, so the existing order is unchanged for
  anyone who never enables it (the golden test is extended).
- Two variants:
  - **`slot`** (default): the next due slot, falling back to the first
    incomplete slot, with ticks and "Take all"; it collapses to
    "✓ Stack done";
  - **`day`**: all of today's slots as compact pills.
- Ticking is local-first: it commits to `SupplementIntakeStore` with no
  network, per the "zero-network-wait" rule.

### D5 — Reminders

- `NotificationPlanning` gains `.supplementSlot(slot)` and
  `.supplementRestock(product)` kinds.
- A slot reminder is planned for each slot with due items today and is
  skipped once the slot is complete. The existing re-plan on
  foreground/log/setting change plus the title/body diff (l10n 3.3b) handle
  this.
- **"Taken" action**: a `UNNotificationCategory` with a `TAKEN` action.
  - The app's notification delegate handles it in the background by
    writing intake records for that slot. The action carries the date and
    slot in `userInfo` and is idempotent.
  - No foreground launch is needed. If the store is unreadable because the
    device is locked, the action falls back to opening the app with the
    slot highlighted, and it is logged to `DiagnosticsLog`.
- **Restock**: a reminder when projected days left ≤ the user's lead time
  (default 7 days), at most once per product per pack.

### D6 — Totals, limits, warnings

- `IngredientTotals` sums a day's intake per ingredient across products
  (planned + extra) in canonical units.
- `SupplementLimitsStore` holds per-ingredient overrides of the target and
  upper limit. The defaults come from `EvidenceCatalog`.
- The editor shows the default, its source, and a "Reset to default"
  button, e.g. "Endurance athletes often use more sodium/magnesium —
  discuss with a professional".
- A **warning** appears when a day's total goes over the user's upper limit:
  - an amber row on the totals card and on the evidence card, with calm
    wording;
  - a non-blocking banner at confirm time when an extra dose would exceed
    it.

  No push notification.
- Limits with no UL (vitamin C in EFSA, omega-3) show "No EU upper limit
  set", with the US figure labelled as US where one exists.

### D7 — External rating research (probed 2026-09-25, read-only)

| Source | Result |
|---|---|
| Labdoor | No public API; licensing on request (paid) |
| ConsumerLab | ToS forbids automated access/API use |
| Examine.com | Data licensing only by request (examine.com/api-requests) |
| NSF Certified for Sport / Informed Sport / Kölner Liste | Free web search only; no API or data licence; certification is per batch |
| dTest.cz | Members-only results, no data access |
| SZPI / potravinynapranyri.cz | Only non-compliant products; no documented API |
| NIH ODS DSLD API (`https://api.ods.od.nih.gov/dsld/v9/`) | Keyless. `GET /search-filter?q=creatine&size=2` → **200**, `{hits:[{_id,_source:{fullName,brandName,allIngredients[],netContents,productType,offMarket}}], stats:{count:3957}}`. `GET /label/43261` → **200** with `upcSku` ("8 51780 00591 0"), `ingredientRows`, `servingSizes`. UPC search works only in the spaced UPC-A format; US market only (~215k labels); CC0. Rate limits (1k/h without key) per third-party docs, not confirmed |
| Open Food Facts (`/api/v2/search?categories_tags_en=dietary-supplements&countries_tags_en=czech-republic`) | **200**, `count: 383`, but polluted (protein drinks/bars). Of 100 sampled, target nutrients almost absent (vit D 3, Mg 5, Zn 6, omega-3 0, creatine 0); values per 100 g, not per dose. ODbL |

**Conclusion**: there is no usable free external rating, so the app doesn't
claim one. It provides instead:
- **`LabelScore`** (0–100, pure and explained), made of three parts:
  - label transparency, 40 points: every ingredient has an amount, the form
    is stated, and there are no proprietary blends;
  - dose against the evidence, 40 points: within the evidence card's
    effective range;
  - headroom, 20 points: the total at the planned dose stays under the
    user's upper limit.

  The screen shows the breakdown, never just a number.
- **Certification**: "Verify certification" deep links to the NSF, Informed
  Sport and Kölner Liste search pages (a URL with the product name where the
  site supports it, otherwise the search page), plus a badge the user sets
  manually with a date. Before shipping the links, the implementer reads
  each site's terms of use (task 5.4).

**Barcode chain**: the offline index doesn't apply, since it holds food, not
supplements. The order is:
1. **Open Food Facts** product endpoint (name and brand prefill);
2. **DSLD**, converting EAN-13 or UPC-A to the spaced UPC-A format, only
   for codes starting with 0 (US/Canada);
3. manual entry.

Ingredient amounts are always confirmed by the user. A successful lookup
result is cached locally by barcode. **Fallback** when either service breaks
or changes shape: manual entry. Neither is on a confirm path, so there is no
network wait.

### D8 — Evidence catalog (static, offline, en + cs)

Values below are checked against the source PDFs on 2026-09-25. The
implementer stores them **from the sources, not from summaries**; a web
summarizer returned wrong EFSA values during research.

| Ingredient | Default upper limit (adults) | Source |
|---|---|---|
| Vitamin D | 100 µg/day (4000 IU) | EFSA 2023 (UL summary v11, Aug 2025) |
| Vitamin C | no EU UL (US 2000 mg, labelled as US) | EFSA 2004 / NIH ODS |
| Zinc | 25 mg/day | SCF 2003 via EFSA summary |
| Magnesium (supplemental only) | 250 mg/day | EFSA; readily dissociable salts + MgO; food magnesium excluded |
| Vitamin B6 | 12 mg/day | EFSA 2023 |
| Iron | 40 mg/day "safe level" (not a UL) | EFSA 2024 |
| Selenium | 255 µg/day | EFSA 2023 |
| EPA+DHA | no UL; ≤ 5 g/day from supplements raises no safety concern | EFSA 2012 (doi 10.2903/j.efsa.2012.2815) |
| Creatine | 3 g/day unlikely to pose risk (EFSA 2004); typical 3–5 g/day, loading 0.3 g/kg/day for 5–7 days | EFSA AFC 2004; ISSN 2017 (doi 10.1186/s12970-017-0173-z) |
| Caffeine | 400 mg/day; 200 mg single dose | EFSA 2015 (doi 10.2903/j.efsa.2015.4102) |

- Each card has: what it's for (plain language), evidence strength
  (strong/moderate/limited), typical dose, timing and with-food notes (e.g.
  D3 with fat, magnesium in the evening, zinc apart from iron and calcium),
  the upper limit, sources with links, and the disclaimer.
- The texts are written for this app, with no copied prose. Attribution
  follows EFSA's reproduction terms ("source acknowledged") and NIH ODS
  credit.

### D9 — Gamification (feature id `supplements`)

- **Streak**: consecutive stack-complete days; days with nothing planned
  don't count and don't break it. It uses `StreakEngine` with
  `frozenDays`.
  - **Shared freeze pool**: a freeze earned from bingo or the boss protects
    whichever streak (food or supplements) breaks first. This holds only
    for streaks of 3+ days, the same rule as the food streak.
  - The freeze planner (owned by the boss feature) gains a second streak
    input and consumes at most one freeze per missed day, whichever streak
    that is.
- **Badges**: "First stack", "Stack week" (7 complete), "Creatine 30/100",
  "Sunshine" (60 D3 days Oct–Mar), "Omega month", "Full stack month",
  "Never ran out" (restocked before empty 3 times), "Alphabet"
  (5/10 distinct vitamins). Rarities follow the existing scheme.
- **Challenges**: 3–4 templates added to the rotation only while the feature
  is enabled and a plan exists, e.g. "Complete your stack 5 days this
  week" or "Take your evening slot before 22:00 three times".
- **Collection**: the "Vitamin alphabet" of distinct vitamins and minerals
  taken. **Journey**: creatine grams (e.g. 100 g → 1 kg → 5 kg milestones).
- **XP**: the budget line is ~6 XP/day before the optional multiplier
  (`rebalance-xp-economy` D4). Grant keys are `supplements.<…>`.
  - **Few, larger grants** (xp-economy decision, relayed 2026-09-25):
    optional sources are priced with `XPBudget.optionalMultiplier(...)` and
    `XPBudget.scaledGrant(_:multiplier:)`, capped so that all optional
    sources together add at most 0.5 % of core daily XP, and every grant is
    at least 1 XP. Many tiny grants would each round up to 1 XP and break
    that allowance, so supplements grants **one grant per stack-complete
    day plus milestone grants** (badges, journey steps), never one per
    tick.
- **Disabled feature**: when disabled, the feature doesn't evaluate. Earned
  badges stay, challenges leave the rotation, and the streak is frozen in
  place (it is neither lost nor extended).

### D10 — Enabling and disabling

- The `AppPreferences.supplementsEnabled` key defaults to `false`.
- Settings: a row "Supplements" / "Doplňky stravy" with a toggle and a
  short explainer.
- Enabling for the first time opens onboarding: add the first product from
  the catalog, then set slots and reminders.
- Disabling cancels supplement reminders, via the scheduler diff, and hides
  the screen, tab entry and card. The data is kept.

### D11 — Where the screen lives

Per the owner, there is a **new screen** reached from a Today card tap and
from a row on Progress. It is not a new tab by default: the start-tab and
tab settings live in themes wave 4, and supplements can become a tab there
later. The screen has sections for Today's checklist, My stack, Totals and
limits, Insights (adherence, stock, cost) and Evidence.

### D12 — Localization and accessibility

- All strings in English and Czech from day one.
- Czech plurals for doses, e.g. "1 kapsle / 2 kapsle / 5 kapslí".
- Units are spelled out for VoiceOver through the existing `SpokenUnits`.
- Decimals follow the locale ("2,5 g").
- Dynamic Type, Reduce Motion, and no hard-coded colours.
- Glossary additions: doplněk stravy, dávka, balení, horní limit, tolerable
  upper intake level → "horní přípustný limit".

### D13 — Testing

FoodLogCore tests use real stores on temp files:
- the schedule evaluator: every pattern, cycles across boundaries,
  `effectiveFrom` history;
- totals with multi-ingredient products and IU conversion;
- limits and warnings, including overrides and no-UL cases;
- the label score breakdown;
- stock projection and restock planning;
- intake idempotency, which matters for the notification action;
- store round-trip, quarantine and old-file decode.

Gamification tests: streak with neutral days and the shared freezes; badges;
challenges only when enabled; XP budget line present.

AppearanceKit: the golden Today order is unchanged when the feature is
disabled.

## Risks / Trade-offs

- **Health information is sensitive.** It is kept informational, sourced,
  calm and user-overridable, never prescriptive, with a visible disclaimer.
- **Barcode coverage for Czech supplements is poor.** Most products will
  need manual ingredient entry; the catalog and remembered custom products
  soften this.
- **Background notification actions on a free Apple account.** Actions
  don't need special entitlements, but the behaviour when the device is
  locked needs checking on the device (D5 fallback).
- **Scope is large.** The tasks are split into waves so each PR stays
  reviewable.

## Open Questions

- Units for electrolytes: sodium in mg only, or also a "salt" conversion
  (salt = Na × 2.5)? Default: mg, with salt shown as secondary.
- Default reminder times per slot: morning 08:00, evening 21:00, pre-workout
  none (manual). To be confirmed during implementation with the owner.

### D14 — Logging past days (owner request, 2026-09-25)

The owner wants to record intake "backwards": yesterday, a week ago, or a
month ago.

- **Where:** the Supplements screen has a date picker and a tappable
  adherence calendar. Selecting a past day opens that day's checklist,
  evaluated against the schedule in effect then (D3 `effectiveFrom`
  history). The picker range is today − 365 days … today. Future days are
  not editable.
- **Streak and history** are recomputed from the intake log on every
  evaluation, so a backfilled day can repair a broken streak. A freeze that
  was already consumed for that day stays consumed (no refund), which keeps
  the freeze pool simple and predictable.
- **Stock:** each product stores `stockSetOn` (the date its pack count was
  last set or refilled). Remaining stock counts only intake dated on or after
  that date, so backfilling a day before the current pack doesn't drain it.
- **XP:** to keep the pace promise and prevent history farming, intake
  recorded more than 7 days after its date counts for history, streaks,
  badges and statistics, but **grants no XP**. Grants are keyed by date, so
  re-entering a day never double-pays.
- **Tests:** backfill across a schedule change, streak repair, stock
  unaffected by pre-pack backfill, no XP for late entries older than 7 days,
  and the 365-day limit.

## Context

Read before writing this (2026-09-24, on `origin/main` @ 1004976):
`Gamification/Package.swift` (depends on FoodLogCore only, deliberately NOT
GarminKit), `ChallengeTemplates.swift` (13 hand-authored + 14 ladder
families = 226 templates), `ChallengeEngine.swift` (`progress(for:active:
events:goalStatuses:now:)`, `ChallengeRotation.pickNext` = `now % pool.count`
over non-recent ids), `ChallengeStore.swift` (`recentTemplateIds` capped at
3), `DailyChallengeEngine.swift` (djb2 + LCG `seededShuffle`),
`Achievements.swift` / `AchievementEngine.swift` (122 definitions, a two-pass
meta evaluation whose denominator is every non-meta definition),
`AchievementStore.swift` (`unlockedAt: [id: Date]`, id-agnostic),
`StreakEngine.swift` / `StreakHistory.swift`, `XPStore.swift`
(`recordChallengeCompletion(xp:)` is a generic "add N XP"),
`GamificationMoment.swift`, `NutritionDayBoundary.swift` (the engine uses
`loggedDateBoundaryHour = 0`, i.e. the logged calendar date),
`GamificationEngine.swift` (app; composes everything; calls
`garminClient.dailyFoodLog` for goal status), `ProgressViews.swift`,
`DayLogLoader.swift` (holds active kcal in memory only), FoodLogCore's
`UsageHistory.swift` (500-event cap; `mealType` optional since 2026-09-23),
`Food.swift` (`Serving` carries fibre and sugar), `FoodCache.swift`,
`OpenFoodFactsClient.swift` (OFF `Food.id` is the barcode; `brands` joined),
`GarminHealthCache.swift` (weigh-ins, hydration days, weight goal with
`startingWeightGrams`/`targetWeightGrams`), `FastingSchedule.swift`
(`FastingDayEvaluator`, `FastingDayResult`), `DayNote.swift` (tags: race,
training, celebration, sick, travel, party, restDay), `SearchText.swift`,
and `docs/garmin-routes.json`.

Two constraints shape everything below:

1. **Gamification must not import GarminKit.** FoodLogCore already exposes
   some GarminKit types in its public API (`GarminHealthSnapshot` holds
   `GarminWeighIn`, `HydrationDaily`), so the new signal types are plain
   FoodLogCore structs (numbers, strings, dates) that Gamification can read
   without naming a GarminKit type.
2. **Seven changes will be built in parallel after this one.** Anything they
   would all edit (the engine body, the catalog, the moment enum, the
   Progress screen) is edited once, here, and replaced by owned files.

## Goals / Non-Goals

**Goals:** a per-day signal model rich enough for every wave-2/3 rule in the
owner's list; deterministic, pure, unit-tested logic in the packages; zero new
network work on any confirm path; old JSON always decodes.

**Non-goals:** the features themselves; any Garmin write; routes that were
not probed (steps, sleep).

## Evidence (probes)

| Route | Method | Probed | Status | Shape observed |
|---|---|---|---|---|
| `/activitylist-service/activities/search/activities?startDate={yyyy-MM-dd}&endDate={yyyy-MM-dd}&limit={n}` | GET | 2026-09-24, owner's account, read-only | 200 | JSON array; 78 keys per item incl. `activityId`, `startTimeLocal` ("2026-09-23 19:22:08"), `startTimeGMT`, `activityType.typeKey` ("walking", "mobility", "running", …), `duration` (s, double), `calories`, `distance` (m). The probe tool truncates bodies at 20 KB, so use `limit` ≤ 20 per call. |
| `/usersummary-service/usersummary/daily?calendarDate={d}` | GET | 2026-09-23 (already recorded) | 200 | `activeKilocalories`, `bmrKilocalories`, `totalKilocalories` |
| `/nutrition-service/food/logs/{date}` | GET | 2026-09-14 (already recorded) | 200 | `dailyNutritionContent` (calories, protein, carbs, fat, **fiber, sugar**), `dailyNutritionGoals`, `loggedFoodsWithServingSizes[]` (logTimestamp, mealId, foodMetaData, nutritionContent) |
| `/userprofile-service/socialProfile` | GET | 2026-09-23 (already recorded) | 200 | `fullName` ("Jiří Mlčoušek") |
| hydration daily, weigh-ins, nutrition settings | GET | 2026-09-23 (already recorded) | 200 | already cached by `GarminHealthCacheStore` |

**Fallback for every one of them:** signals are built from local data first
(usage history + FoodCache macros + local hydration entries + day notes +
fasting schedule). A Garmin read only *enriches* a day. If a route breaks,
the affected fields are `nil` and the day's `availability` flags say so;
features whose rule needs that field simply don't evaluate (never a false
"failed"). Auth errors propagate to the existing loud auth banner; every
other read failure is logged to `DiagnosticsLog` (category `signals`) and
otherwise ignored.

## Decisions

### D1 — `FoodTag` is an open struct, not an enum

```swift
public struct FoodTag: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String          // "fish", "cuisine.italian", "colour.red"
}
extension FoodTag { public static let fish = FoodTag(rawValue: "fish") }
```

An enum would force every wave-2 change to edit the same file. With a
struct, each change declares its own tags in its own file
(`FoodTag+Seasonal.swift` declares `.goose`, `.carp`, `.lentils`, …). Tags
are persisted by raw value; unknown raw values decode fine.

**Core tags shipped here** (used by more than one later change):
`fruit, vegetable, fish, seafood, meat, redMeat, poultry, egg, dairy,
cheese, fermented, legume, nuts, wholeGrain, soup, coffee, tea,
sugaryDrink, alcohol, beer, sweets, pastry, pizza, pie, potato, knedlik`;
colours `colour.red|orange|yellow|green|purple|white`; cuisines
`cuisine.czech|italian|japanese|chinese|indian|mexican|thai|vietnamese|
greek|turkish|spanish|french|american|korean|middleEastern`; and
`czechBrand`.

### D2 — FoodTagger: keyword rules over `SearchText`, in FoodLogCore

```swift
public struct FoodTagRule: Sendable {
    public let tags: Set<FoodTag>
    public let anyPhrases: [String]      // folded+stemmed phrase match, e.g. "kysane zeli"
    public let anyBrands: [String]       // matched against the brand only
    public let excludePhrases: [String]  // e.g. "rybiz" (currant) must not be "ryba"
}
public struct FoodTagRuleSet: Sendable { public let id: String; public let rules: [FoodTagRule] }
public enum FoodTagger {
    public static func tags(name: String, brand: String?, barcode: String?,
                            ruleSets: [FoodTagRuleSet] = FoodTagRuleRegistry.all) -> Set<FoodTag>
}
```

- Name and brand are normalised once with `SearchText.foldedPhrase` and
  `CzechLightStemmer` (the same normalisation search uses — one definition of
  "the same word"). A phrase matches on whole-token boundaries, so "pivo"
  does not match "pivonka".
- Exclusions win over inclusions within a rule.
- `czechBrand`: the brand matches `CzechBrands.all` (Madeta, Kunín, Tatra,
  Olma, Hollandia, Pilos, Albert Quality, Penam, Opavia, Orion, Kofola,
  Mattoni, Relax, Hamé, Vitana, Jihlavanka, Kostelecké uzeniny, Choceňská
  mlékárna, Pribináček, Emco, Bonavita, Semix; Slovak brands such as Rajec
  are deliberately not on the list)
  **or** the barcode is a 13-digit EAN starting `859` (GS1 Czech prefix; a
  weaker signal because it marks the registrant, not the factory, so it is
  used only when the brand is unknown).
- Rule sets are registered in `FoodTagRuleRegistry.all`:
  `[.core, .seasonal, .collections, .sport]`. The last three ship **empty**
  here (stub files) and are filled by their owning change.
- Tagging is memoised per `foodId` in the builder (a food's name does not
  change), so a 500-event history tags ~150 distinct foods, not 500.

Macro-derived facts (e.g. "≥ 20 g protein", "≥ 30 g carbs") are **not**
tags; they are read from the entry's macros by predicates (D5), because
they depend on the logged quantity, not the food.

### D3 — Where each food's name, brand and barcode come from

Per entry, in priority order:

1. The cached **Garmin day-log digest** for that day (D4): `foodMetaData`
   name/brand and per-entry nutrition, as Garmin actually recorded them.
2. **FoodCacheStore** (`Food.name`, `Food.brandName`, `Serving` macros ×
   logged quantity, with the same serving math `LogQuantity`/`ServingAmount`
   already use for the confirm screen).
3. **FoodProvenanceStore** (new, tiny): `foodId → (barcode?, offBrand?)`,
   written when a food that came from Open Food Facts (whose `Food.id` *is*
   the barcode) is matched or turned into a custom food. This is a local
   JSON write that happens inside the existing match/create flow, after the
   user's action, and never adds a network await. Without it, the barcode is
   lost once an OFF product becomes a Garmin food.

An entry with no name anywhere gets no tags (it still counts as "an entry").

### D4 — Persisted caches (FoodLogCore, JSON-file actors, capped)

All use `PersistedStoreLoading`/quarantine semantics like every other store
(fix-silent-store-wipe), and every new field on an existing Codable type is
Optional.

- `DayLogDigestStore` — `[day: DayLogDigest]`, last **120** days. A
  `DayLogDigest` holds totals (calories, protein, carbs, fat, fiber?, sugar?),
  goals (calories, protein, carbs, fat), and entries
  (`foodId, name, brand?, timestamp?, mealType (plain String), calories?,
  protein?, carbs?, fat?, fiber?, sugar?`). Written by a small
  `DayLogDigest.init(log: DailyFoodLog)` adapter wherever the app already
  fetches a day log (`DayLogLoader`, `GamificationEngine.refreshGoalStatus`).
  No new request.
- `ActivityCacheStore` — `[day: DayActivity]`, last **120** days, where
  `DayActivity = (activeKcal: Double?, activities: [ActivitySummary]?,
  fetchedAt)` and `ActivitySummary = (id, typeKey, start: Date, durationS,
  calories?, distanceM?)`. `start` is parsed from `startTimeGMT` (UTC) so
  time-zone travel cannot shift the "before/after activity" windows;
  `startTimeLocal`'s date decides which day the activity belongs to.
- `FoodProvenanceStore` — see D3, capped at 2,000 foods.

### D5 — `DaySignals` and the pure builder

```swift
public struct DaySignals: Sendable, Equatable {
    public let day: String                     // yyyy-MM-dd, logged date
    public let date: Date                      // start of that day
    public let entries: [SignalEntry]          // sorted by time
    public let totals: MacroTotals             // garmin totals if digest exists, else summed local
    public let goals: MacroGoals?              // from digest, else nil
    public let goalStatus: DailyGoalStatus?    // the existing four booleans (Gamification type, mirrored as plain Bools here)
    public let waterML: Double?, waterGoalML: Double?
    public let activeKcal: Double?
    public let activities: [ActivitySummary]
    public let weighInKg: Double?              // last weigh-in of the day
    public let fasting: FastingOutcome?        // .kept / .broken / nil (not tracked, in progress)
    public let noteTags: Set<DayNoteTag>
    public let availability: SignalAvailability // hasGarminLog, hasWater, hasActivities, hasWeight, hasFasting
}
public struct SignalEntry: Sendable, Equatable {
    public let foodId: String, name: String?, brand: String?, barcode: String?
    public let tags: Set<FoodTag>
    public let timestamp: Date
    public let meal: SignalMeal                // breakfast/lunch/dinner/snack
    public let calories, protein, carbs, fat, fiber, sugar: Double?
}
public struct SignalsSnapshot: Sendable, Equatable {
    public let days: [String: DaySignals]      // window below
    public let today: String
    public let profile: ProfileSignals         // firstName?, weightGoal (startKg?, targetKg?)
}
public enum DaySignalsBuilder {
    public static func build(input: SignalsInput, today: Date, windowDays: Int = 42,
                             calendar: Calendar) -> SignalsSnapshot
}
```

- `SignalsInput` is a plain struct of arrays already loaded from the stores
  (events, foods, digests, activity days, hydration entries, health
  snapshot values, notes, fasting schedule), so the builder is a pure
  function and tested with literals.
- **Meal**: `UsageEvent.mealType` when present, else the digest's
  `mealId`-derived type, else `MealTimeBucket.bucket(for:)` (documented
  fallback; same hours as today).
- **Entry identity when both sources exist**: digest entries win for days
  that have a digest; local events whose timestamp is newer than the
  digest's `fetchedAt` are appended (they were logged after the fetch and
  are still in the outbox). Entry matching is by `foodId` + timestamp
  within ±120 s so an entry is never counted twice.
- **Window**: 42 days (6 weeks: bingo needs this week, boss needs 4 full
  past weeks). Features that need lifetime totals (journeys, records,
  collections) keep their own ledgers and process each day once (D8).
- **Water**: max(local hydration total, Garmin `valueInML`) for the day,
  goal from Garmin `goalInML` else the app's water goal preference, passed
  in by the app.
- **ProfileSignals.weightGoal**: the app's `EffectiveWeightGoal`
  (`GoalResolution`: local override, else Garmin nutrition settings
  `startingWeight`/`targetWeight`), passed in as plain kilograms.
- **ProfileSignals.firstName**: first whitespace-separated token of
  `socialProfile.fullName`, cached in `AppPreferences` by
  `GamificationSignalsSync` (so the widget-free, offline path still has it).

### D6 — `DayPredicate`: one shared rule vocabulary

Bingo squares, boss challenges and the new creative challenges are all
"a day (or a week) satisfies X". Instead of three rule languages:

```swift
public indirect enum DayPredicate: Sendable, Equatable, Codable {
    case hasTag(FoodTag)                          // any entry with tag
    case tagCountAtLeast(FoodTag, Int)            // entries with tag
    case anyTagCountAtLeast([FoodTag], Int)       // e.g. fruit+veg portions
    case distinctTagsAtLeast(prefix: String, Int) // e.g. "colour.", 5
    case noTag(FoodTag, minEntries: Int)          // logged ≥ minEntries, none tagged
    case tagInMeal(FoodTag, SignalMeal)
    case mealLogged(SignalMeal)
    case firstLogBefore(hour: Int, minute: Int)
    case lastLogBefore(hour: Int, minute: Int)
    case distinctFoodsAtLeast(Int)
    case goalMet(GoalMacro)
    case macroAtLeast(Macro, grams: Double)       // needs garminLog or local macros
    case macroAtMost(Macro, grams: Double, minEntries: Int)
    case waterGoalMet
    case hasActivity(minMinutes: Int)
    case proteinAfterActivity(grams: Double, withinMinutes: Int)
    case newFood                                  // food first seen this day (vs retained history)
    case newCzechBrand                            // czechBrand entry whose brand not seen before this day
    case all([DayPredicate]), any([DayPredicate])
    public var requirement: DataRequirement { … } // .none / .macros / .water / .activities / .weight
}
public struct WeekPredicate … // .daysSatisfying(DayPredicate, atLeast: Int) and .distinctTagsAcrossWeek(prefix:, atLeast:)
public enum SignalEvaluator { static func holds(_ p: DayPredicate, on: DaySignals, history: SignalsSnapshot) -> Bool }
```

`requirement` lets a feature skip a rule when the owner's data doesn't
support it (no water data in the last 14 days → no water square/boss/
challenge). Evaluation for a day whose data is missing returns `false`, and
eligibility checks happen *before* a rule is offered, so a rule is never
shown that cannot be satisfied.

### D7 — The plug-in seam

```swift
public protocol GamificationFeature: AnyObject, Sendable {   // implemented by actors
    nonisolated var featureId: String { get }                 // "bingo", "seasonal", …
    nonisolated var badges: [AchievementDefinition] { get }   // static, for the Achievements screen
    func update(_ context: FeatureContext) async -> FeatureUpdate
}
public struct FeatureContext: Sendable {
    public let snapshot: SignalsSnapshot
    public let now: Date, calendar: Calendar
    public let streak: StreakEngine.Status, level: Int
    public let unlockedBadgeIds: Set<String>
    public let isConfirmPath: Bool   // true when called right after a log confirm
}
public struct FeatureUpdate: Sendable {
    public var grants: [RewardGrant] = []          // idempotent (key-based)
    public var unlockBadgeIds: [String] = []
    public var moments: [FeatureMoment] = []
    public var summary: FeatureSummary? = nil      // title, subtitle, fraction, symbol for the hub card
}
public struct RewardGrant: Sendable { public let key: String; public let kind: Kind
    public enum Kind: Sendable { case xp(Int), streakFreeze } }
public struct FeatureMoment: Sendable, Equatable {
    public let featureId, title, message, symbol: String
    public let style: Style   // .celebration, .record, .secret, .event, .boss, .freeze
    public let xpAwarded: Int
}
```

- **Registration**: `GamificationFeatureRegistry.makeAll(directory:)` returns
  one instance per feature, in fixed order. This change pre-registers **all
  eight** features, each pointing at a **stub** type in its own file that
  returns an empty `FeatureUpdate` and no badges. A wave-2 change replaces
  its stub file's contents; it does not touch the registry.
- **Each feature owns its own JSON store(s)** under
  `GamificationStorage.directory()/features/<featureId>/`, using the same
  `loadPersistedJSON`/`ensureSafeToWrite` helpers.
- **`FeatureHost`** (app, `App/FeatureHost.swift`) is called by
  `GamificationEngine.refresh` and at the end of `handleLogConfirmed`. It
  builds the snapshot from the stores (local reads only), runs each feature,
  and applies results: grants via `RewardLedger`, badges via the existing
  `AchievementStore.unlock(ids:now:)` (plus `XPAward.achievementBonus` for
  each newly unlocked badge — exactly what the engine already does for core
  achievements), moments appended to `pendingMoments`. For each newly
  unlocked badge the host also queues the standard `.achievementUnlocked`
  moment — **except** secret badges, whose feature supplies its own
  `.secret` reveal moment (so a secret title is never shown twice, and never
  by generic code before the reveal). A feature that throws
  or misbehaves is caught, logged to `DiagnosticsLog`, and skipped; the rest
  still run.
- **Confirm path cost**: the host runs *after* the entry is committed to the
  outbox and after the existing gamification work, off the confirm action's
  critical path, with local reads only. No network call is ever made from
  `FeatureHost`.

### D8 — `RewardLedger`: rewards are idempotent by key

`RewardLedger` (Gamification, JSON actor) records every applied
`RewardGrant.key` with its kind and date. Applying a grant whose key is
already recorded is a no-op. XP is added through the existing
`XPStore.recordChallengeCompletion(xp:)` (a generic add). Freeze grants are
only recorded here (`freezeGrants: [(key, day)]`); `add-weekly-boss-and-
streak-freezes` reads them to compute the balance, so a full bingo card
earned before wave 3 ships is not lost. Keys are namespaced:
`"<featureId>.<what>.<period>"`, e.g. `bingo.line.2026-W39.row0`. The ledger
keeps keys forever (≈ 20 bytes × a few thousand per year — negligible).

Lifetime features (journeys, records, collections) must also be idempotent
per **day**: each keeps `processedThrough: String?` and a small
`openDays: [day: contribution]` for the last 3 days (late logs and deletes
can still change them); older days are sealed into running totals. That is
the only way to get true lifetime totals given the 500-event history cap.

### D9 — Badge model extensions (in `Achievements.swift`, this change only)

`AchievementDefinition` gains Optional-by-default fields (existing call
sites compile unchanged):

- `visibility: .normal | .secret` — secret badges show "???" and a lock
  until unlocked (count shown, titles hidden).
- `edition: .permanent | .limited(eventId: String)` — limited badges are
  shown with the event name and the years earned.
- `rarityOverride: AchievementRarity?` — feature badges have no
  `AchievementCondition` to derive rarity from.
- `featureId: String?` — which feature evaluates it.

`AchievementCondition` gains `.featureEvaluated` (never met by
`AchievementEngine`; features unlock these themselves).

**Meta denominator**: the completionist meta achievements keep counting only
the original core catalog (definitions whose condition is not
`.featureEvaluated`). Otherwise shipping 150 new badges would silently push
"unlock 50% of everything" further away for an owner who was close.

`BadgeRegistry.all` = `AchievementCatalog.all` + every registered feature's
`badges`, de-duplicated by id (a duplicate id is a test failure, not a
runtime choice). The Achievements screen and summary card switch to it.

Badge id namespaces: `achv-*` (existing), `bingo.*`, `event.*`,
`collection.*`, `journey.*`, `record.*`, `secret.*`, `sport.*`, `boss.*`,
`freeze.*`.

### D10 — XP budget for the new sources

Today's design assumes ~75 XP/day (expand-gamification-depth D1: level 84
at ~3 years). New constants in `XPAward+Features.swift`:

| Constant | XP |
|---|---|
| `bingoLine` | 25 |
| `bingoFullCard` | 150 |
| `seasonalEventCompleted` (per event per year) | 50 |
| `collectionDiscovery` (first time an entry is found) | 5 |
| `journeyMilestone` | 40 |
| `personalRecord` (max once per record per day) | 20 |
| `secretUnlocked` (on top of `achievementBonus`) | 50 |
| `sportBadge` (on top of `achievementBonus`) | 0 — the generic bonus is enough |
| `bossDefeatedBase` / `bossDefeatedPerTargetDay` | 150 / 25 |
| `creativeChallenge` (per template, see D11) | 60–160 |

Estimated average from new sources ≈ 220 XP/week ≈ +31 XP/day (bingo ~70,
boss ~110 at a 50 % win rate, records ~20, collections/journeys ~20). That
makes level 84 arrive after ~2.1 years instead of ~3. Accepted and called
out as an open question (keep, or nudge `LevelCurve.growthFactor` from
1.045 to 1.048 in a later change).

### D11 — Catalog trim: rotation weights, not deletion

`ChallengeRotationPolicy.weight(for: ChallengeTemplate) -> Int`:

- The 13 hand-authored templates: **2**.
- The new creative, signal-based templates (below): **3**.
- Ladder families: an explicit allowlist keeps **two tiers per family per
  axis** in rotation with weight **1** (a "medium" and a "hard" tier, e.g.
  `log-streak-10`, `log-streak-21`; `goal-days-protein-7`,
  `goal-days-protein-12`); every other ladder tier gets weight **0**.
- Templates whose `DataRequirement` is not satisfied by the last 14 days of
  signals get weight 0 for this pick.

`ChallengeRotation.pickNext` becomes a weighted deterministic pick (seeded by
`now` exactly like today, using the shared `DeterministicRandom` extracted
from `DailyChallengeSelection` — the daily-challenge code keeps its own copy
untouched so its picks do not change). `ChallengeStore.recentTemplateIds`
cap rises from 3 to 8. Weight-0 templates stay in `ChallengeCatalog.all`:
an active challenge whose template became weight 0 finishes normally; its
history and every earned badge keep working.

With 13×2 + 24×3 + ~28×1, creative templates are ≈ 57 % of picks and ladder
tiers ≈ 22 % (today: ladders are 94 %).

**`achv-all-challenges`** (`.allChallengesCompleted`): its denominator
becomes "templates with rotation weight > 0 under the policy's static
weights" — otherwise trimming would make it impossible. Distinct completed
ids already on disk still count.

**Creative long-running challenges** (new `ChallengeKind.signalDays(
DayPredicate, minDays: Int)` and `.signalWeek(WeekPredicate)`; window 7 days
unless noted; XP in brackets):

| id | Title | Rule |
|---|---|---|
| `sig-something-fishy` | Something Fishy | fish on 2 days (80) |
| `sig-five-a-day` | Five-a-Day Week | ≥ 5 fruit+veg entries on 4 days (120) |
| `sig-rainbow-week` | Rainbow Week | all 6 colours across the week (120) |
| `sig-czech-safari` | Czech Supermarket Safari | 3 different Czech brands (80) |
| `sig-fermentation-station` | Fermentation Station | fermented food on 4 days (100) |
| `sig-pulse-check` | Pulse Check | legumes on 3 days, 10-day window (90) |
| `sig-hydration-station` | Hydration Station | water goal on 5 days — needs water (110) |
| `sig-early-bird` | Early Bird Week | first log before 09:00 on 5 days (100) |
| `sig-kitchen-curfew` | Kitchen Curfew | last log before 20:00 on 5 logged days (110) |
| `sig-green-breakfast` | Green Breakfast Club | vegetable at breakfast on 3 days (90) |
| `sig-fibre-fanatic` | Fibre Fanatic | ≥ 30 g fibre on 4 days — needs macros (120) |
| `sig-sugar-detective` | Sugar Detective | ≤ 40 g sugar on 4 days with ≥ 3 entries — needs macros (120) |
| `sig-fuel-and-recover` | Fuel & Recover | ≥ 20 g protein within 60 min after 3 activities, 10-day window — needs activities (130) |
| `sig-active-on-target` | Active and On Target | an activity ≥ 30 min and the calorie goal on the same day, 3 days (110) |
| `sig-nut-job` | Nut Job | nuts on 4 days (70) |
| `sig-global-kitchen` | Global Kitchen | 4 different cuisines (90) |
| `sig-tea-time` | Tea Time | tea on 5 days (70) |
| `sig-soup-season` | Polévková sezóna | a soup on 4 days (80) |
| `sig-whole-grain-hero` | Whole Grain Hero | whole grain on 5 days (90) |
| `sig-egg-cellent` | Egg-cellent Week | eggs on 3 days (60) |
| `sig-no-soda` | Soda-Free Week | no sugary drink on 6 of 7 logged days, ≥ 2 entries/day (120) |
| `sig-colour-day` | Paint the Plate | ≥ 4 colours in one day, 2 days (90) |
| `sig-new-horizons` | New Horizons | 5 foods never logged before (90) |
| `sig-protein-breakfast` | Protein Breakfast | ≥ 20 g protein at breakfast on 4 days — needs macros (110) |

### D12 — UI scaffolding: slots

- `Progress/Slots/ProgressSlotHost.swift` renders, in a fixed order, one
  slot view per feature: `BossSlotView`, `BingoSlotView`,
  `SeasonalSlotView`, `JourneysSlotView`, `RecordsSlotView`,
  `CollectionsSlotView`, `SportBodySlotView`, `SecretsSlotView`. Each lives
  in its own file and ships as `EmptyView()` here. `ProgressHomeView`
  gains one line (`ProgressSlotHost()`) under the level card.
- `Today/Slots/TodaySlotHost.swift` hosts `SeasonalBannerSlot` and
  `BossBannerSlot` (both `EmptyView` stubs) above the meals list.
- A slot view reads `environment.gamificationEngine.featureHost` and asks
  for its own feature by type (`featureHost.feature(WeeklyBingoFeature.self)`)
  to call feature-specific async APIs for detail screens; the hub card can
  use the generic `FeatureSummary`.
- `MomentOverlay` renders the new `.feature(FeatureMoment)` case once,
  generically (symbol, title, message, XP, style colour + haptic), so no
  wave-2 change edits it.
- `AchievementsView` groups by category as today, adds a "Secret" group
  (count of `???` tiles) and "Limited edition" group, and reads
  `BadgeRegistry`.

### D13 — Testing

- `FoodTaggerTests` (golden): ≥ 120 fixtures, Czech and English, including
  traps ("rybíz" ≠ fish, "pivoňka" ≠ beer, "kuřecí" = poultry, "Kofola" =
  sugaryDrink + czechBrand, "Kofola bez cukru" ≠ sugaryDrink, "kysané zelí" =
  fermented + vegetable, "Hollandia Selský jogurt" = dairy + fermented +
  czechBrand, barcode "8594…" + unknown brand = czechBrand).
- `DaySignalsBuilderTests`: literal inputs → expected `DaySignals`
  (digest-vs-local precedence, ±120 s de-dup, meal fallback order, water
  max rule, activity day assignment by local date with GMT start).
- `DayPredicateTests`: one test per predicate case including the
  data-missing → false path.
- `RewardLedgerTests`: duplicate key is a no-op; XP added exactly once;
  freeze grants listed.
- `ChallengeRotationPolicyTests`: weights per family, allowlist size, weighted
  pick determinism, requirement filtering, `allChallengesCompleted`
  denominator.
- `BadgeRegistryTests`: no duplicate ids across core + stubs; meta
  denominator excludes `.featureEvaluated`.
- Codable back-compat tests: pre-change `ChallengeStore`,
  `AchievementStore` JSON fixtures decode.
- GarminKit: `GarminActivity` decodes a trimmed real payload fixture
  (78-key item cut to the used keys plus a few unknown ones).
- Real stores in temp directories, never mocks (project convention).

## Wave plan & file ownership

All paths are under `ios/` unless noted. "Owns" = creates or is the only
change allowed to edit. "May touch" = the *only* shared files the change
may edit; anything else shared needs a follow-up change.

**Wave 1 — `add-gamification-signals`** (this change; merges first)

- Owns (new): `FoodLogCore/Sources/FoodLogCore/Signals/{FoodTag, FoodTagRule,
  FoodTagger, FoodTagRules+Core, FoodTagRuleRegistry, CzechBrands,
  DaySignals, DaySignalsBuilder, DayLogDigest, ActivityCache,
  FoodProvenanceStore, ProfileSignals}.swift`; stubs
  `Signals/FoodTagRules+Seasonal.swift`, `Signals/FoodTagRules+Collections.swift`,
  `Signals/FoodTagRules+Sport.swift`;
  `GarminKit/Sources/GarminKit/GarminActivities.swift`;
  `Gamification/Sources/Gamification/Signals/{DayPredicate, WeekPredicate,
  SignalEvaluator, WeekKey, DeterministicRandom}.swift`;
  `Gamification/Sources/Gamification/Features/{GamificationFeature,
  GamificationFeatureRegistry, RewardLedger, BadgeRegistry,
  XPAward+Features, ChallengeRotationPolicy, ChallengeTemplates+Signals}.swift`;
  stubs `Features/WeeklyBingo/WeeklyBingoFeature.swift`,
  `Features/Seasonal/SeasonalEventsFeature.swift`,
  `Features/Collections/FoodCollectionsFeature.swift`,
  `Features/Journeys/JourneysFeature.swift`,
  `Features/Records/PersonalRecordsFeature.swift`,
  `Features/Secret/SecretAchievementsFeature.swift`,
  `Features/SportBody/SportAndBodyFeature.swift`,
  `Features/Boss/WeeklyBossFeature.swift`;
  `GarminFood/App/{FeatureHost, GamificationSignalsSync}.swift`;
  `GarminFood/Progress/Slots/*` and `GarminFood/Today/Slots/*` (host + stubs).
- May touch: `GarminClient.swift` (one read method), `Achievements.swift`,
  `AchievementEngine.swift`, `ChallengeTemplates.swift`
  (`ChallengeKind` cases, `all` concatenation), `ChallengeEngine.swift`,
  `ChallengeStore.swift`, `GamificationMoment.swift`,
  `GamificationEngine.swift`, `DayLogLoader.swift`, `Shared/AppServices.swift`,
  `App/AppEnvironment.swift`, `Home/MomentOverlay.swift`,
  `Progress/ProgressViews.swift`, `Progress/AchievementsView.swift`,
  `Today/TodayView.swift`, the OFF match/create call site (provenance
  write), `docs/garmin-routes.json`, `.github/workflows/build.yml` only if a
  new test target were needed (it is not).

**Wave 2 — parallel; each touches only its own files**

| Change | Owns (replaces stub / creates) | May touch (shared) |
|---|---|---|
| `add-weekly-bingo` | `Features/WeeklyBingo/*` (feature, `BingoCard`, `BingoTaskCatalog`, `BingoStore`), `Progress/Slots/BingoSlotView.swift`, `Progress/Bingo/*` | none |
| `add-seasonal-events` | `Features/Seasonal/*` (feature, `SeasonalCalendar` incl. computus, `CzechNameDays`, `SeasonalEventCatalog`, store), `Signals/FoodTagRules+Seasonal.swift`, `Signals/FoodTag+Seasonal.swift` (new), `Progress/Slots/SeasonalSlotView.swift`, `Today/Slots/SeasonalBannerSlot.swift`, `Progress/Seasonal/*` | none |
| `add-food-collections` | `Features/Collections/*`, `Signals/FoodTagRules+Collections.swift`, `Signals/FoodTag+Collections.swift` (new), `Progress/Slots/CollectionsSlotView.swift`, `Progress/Collections/*` | none |
| `add-journeys-and-records` | `Features/Journeys/*`, `Features/Records/*`, `Progress/Slots/{JourneysSlotView,RecordsSlotView}.swift`, `Progress/Journeys/*`, `Progress/Records/*` | none |
| `add-secret-achievements` | `Features/Secret/*`, `Progress/Slots/SecretsSlotView.swift` | none |
| `add-sport-and-body-achievements` | `Features/SportBody/*`, `Signals/FoodTagRules+Sport.swift`, `Signals/FoodTag+Sport.swift` (new), `Progress/Slots/SportBodySlotView.swift`, `Progress/SportBody/*` | none |

Tests: each change adds its own files under the package's `Tests/…Tests/`
named after its feature (`WeeklyBingo*Tests.swift`, …). No shared test
helper edits; each feature adds its own `*TestSupport.swift` if needed.

If a wave-2 change discovers it needs a new *core* `FoodTag`, a new
`DayPredicate` case or a new `SignalEntry` field, it does **not** edit the
foundation file in parallel: tags are declared in its own `FoodTag+X.swift`;
a predicate can be written as a feature-local function over `DaySignals`;
a missing signal field is raised as a follow-up. The one permitted
exception is a single appended line in `FoodTagRuleRegistry.all` or
`GamificationFeatureRegistry.makeAll` — and both already list every planned
slot, so it should not be needed.

**Wave 3 — `add-weekly-boss-and-streak-freezes`** (after wave 2 merges)

- Owns: `Features/Boss/*`, `Gamification/Sources/Gamification/StreakFreeze/*`,
  `Progress/Slots/BossSlotView.swift`, `Today/Slots/BossBannerSlot.swift`,
  `Progress/Boss/*`.
- May touch: `StreakEngine.swift`, `StreakHistory.swift` (frozen-day
  semantics), `GamificationEngine.swift` (pass frozen days into the two
  streak calls and run the freeze planner before them),
  `Progress/ProgressViews.swift` (`StreakDot` frozen colour, freeze count on
  the streak card and detail).

## Risks / Trade-offs

- **Keyword tagging is imperfect** (a "Rybí salát" is fish; "Salát s
  rybízem" is not). Mitigation: exclusions + a golden suite that grows with
  every mis-tag the owner reports; a wrong tag costs a bingo square, not
  data.
- **Signals are only as good as what's cached.** A day never opened in the
  app has no Garmin digest; its macros come from local servings only (still
  correct for entries made in this app). Features requiring `.macros` treat
  a day with any entry lacking macros as "unknown" for macro rules.
- **One more read on refresh** (activities, `limit=20`, last 14 days, at
  most once per 30 min). Rate-limit rules from config apply (429 → stop).
- **More moving parts on the confirm path.** The host runs after commit and
  never awaits the network, but its local work must stay fast: builder over
  42 days × ~15 entries is O(600) — well under a frame; a test asserts
  < 50 ms for a 42-day, 1,000-entry synthetic input in release mode.

## Open Questions

1. XP pacing (D10): accept ~+31 XP/day (level 84 in ~2.1 y), or retune the
   curve slightly in a later change?
2. Should the free-text day note (not just tags) be scanned for words like
   "závod" to infer a race day? Proposed: no — tags only, explicit is better.
3. Is the Czech-brand list right for the owner's actual shops (does he buy
   Pilos at Lidl, Albert Quality at Albert)? Easy to extend later.

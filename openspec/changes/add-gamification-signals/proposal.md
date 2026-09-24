## Why

The owner asked, in his own words: *"i would like to have better and more
creative gamification, better challenges and achievments like things from
real word and not only track breakfast in 5 days, next 6 days, next 7 days
etc... add creative ideas"*.

He is right about what the current system can see. Every challenge and
achievement today is evaluated from two inputs only: `UsageEvent`
(foodId/servingId/quantity/timestamp/day/optional meal type) and a
four-boolean `DailyGoalStatus`. Nothing in `Gamification` knows *what* was
eaten (fish? a strawberry? svíčková? a Kofola?), how much protein or fibre a
day actually had, how much water was drunk, whether a run happened, what the
scale said, or that the day was a race day. That is exactly why the catalog
grew into number ladders (`log-streak-2 … log-streak-30`,
`meal-breakfast-2 … meal-breakfast-14`): counting days is the only thing the
engine can do.

The owner chose to build nine creative features (weekly bingo, Czech
seasonal events, food collections, sport & body via Garmin, real-world
journeys, personal records, secret achievements, an adaptive weekly boss and
streak freezes), delivered in parallel waves. They all need the same missing
foundation: a per-day picture of *what happened* (the signals), a way to
classify foods into real-world categories (the tagger), and a plug-in seam so
seven features can be built at the same time without all editing
`GamificationEngine.swift` and `ChallengeTemplates.swift`.

## What Changes

- **FoodTagger** (FoodLogCore, pure): classifies a food from its name, brand
  and (when known) barcode into open-ended `FoodTag`s (fruit, vegetable, fish,
  fermented, coffee, sugary drink, cuisine.italian, colour.red, czechBrand, …)
  using a keyword/rule dictionary over `SearchText`'s folded, stemmed text.
  Golden-tested with Czech and English food names.
- **DaySignals** (FoodLogCore, pure value types + pure builder): one aggregate
  per nutrition-day — entries with tags, time and meal; macros including fibre
  and sugar when known; water and water goal; active kcal; Garmin activities;
  weigh-in; fasting result; day-note tags; plus data-availability flags.
- **Local caches for Garmin reads the app already makes or newly makes**
  (all READ-ONLY): a persisted digest of each fetched Garmin day log, active
  kcal per day, and a new activities read
  `GET /activitylist-service/activities/search/activities` (probed 200 on
  2026-09-24) recorded in `docs/garmin-routes.json`. Fetched on refresh, never
  on a confirm path.
- **Pluggable feature registry** (Gamification): a `GamificationFeature`
  protocol, a `FeatureHost` in the app that runs every registered feature once
  per refresh/confirm, an idempotent `RewardLedger` for XP and streak-freeze
  grants, a generic feature moment, and pre-created stub slots (one file per
  wave-2/3 change) so later changes own their files outright.
- **Model extensions every feature needs**: secret and limited-edition badge
  metadata, event windows, explicit rarity, a `BadgeRegistry` combining the
  existing 122 achievements with feature badges, XP constants for the new
  sources, and a shared `DayPredicate` library (bingo, boss and creative
  challenges all use it).
- **Challenge catalog trim + creative challenges**: rotation weights so the
  number-ladder families mostly leave rotation (definitions kept, so history
  and earned badges stay valid), plus ~24 new "real-world" long-running
  challenges built on `DayPredicate` ("Something Fishy", "Rainbow Week",
  "Czech Supermarket Safari", …).
- **Progress-tab and Today slot scaffolding**: an ordered slot host and one
  empty slot view per feature, so wave-2 UIs plug in without touching
  `ProgressViews.swift`.

## Capabilities

### New Capabilities

- `gamification-signals` - food tagging, per-day signals, cached Garmin reads
  for activities/active kcal/day-log digests, and the feature plug-in seam.

### Modified Capabilities

- `challenges` - rotation weights trim the number ladders; creative
  signal-based templates join the rotation.

## Non-goals

- The features themselves: bingo (`add-weekly-bingo`), seasonal events
  (`add-seasonal-events`), collections (`add-food-collections`), journeys and
  records (`add-journeys-and-records`), secrets (`add-secret-achievements`),
  sport & body (`add-sport-and-body-achievements`), boss and freezes
  (`add-weekly-boss-and-streak-freezes`). This change ships only empty stubs
  for them.
- Any Garmin write. Every route here is a read.
- Steps, sleep, HRV or other Garmin metrics without a confirmed route
  (no `10k steps` bingo square until such a route is probed and recorded).
- Removing or renaming any existing challenge, daily-challenge or achievement
  id (ids are persisted on disk).
- An ML/LLM classifier. Tagging is a hand-authored dictionary, testable and
  deterministic.

## Impact

Affected code: `FoodLogCore` (new `Signals/` folder), `GarminKit` (one new
read method + DTO), `Gamification` (new `Signals/`, `Features/` folders;
small edits to `Achievements.swift`, `ChallengeTemplates.swift`,
`ChallengeEngine.swift`, `ChallengeStore.swift`, `GamificationMoment.swift`),
app target (`App/FeatureHost.swift`, `App/GamificationSignalsSync.swift`, a
few lines in `GamificationEngine.swift`, `AppServices.swift`,
`AppEnvironment.swift`, `MomentOverlay.swift`, `ProgressViews.swift`,
`TodayView.swift`), `docs/garmin-routes.json`.

**Depends on**: `expand-gamification-depth` (shipped: achievements, daily
challenges, ladders), `rebuild-food-search` (shipped: `SearchText`,
`CzechLightStemmer`).

**Unblocks**: `add-weekly-bingo`, `add-seasonal-events`,
`add-food-collections`, `add-journeys-and-records`,
`add-secret-achievements`, `add-sport-and-body-achievements` (wave 2, in
parallel), then `add-weekly-boss-and-streak-freezes` (wave 3).

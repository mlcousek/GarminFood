## Why

On 2026-09-23 the owner confirmed on device that weigh-ins and drinks logged
in the app arrive in Garmin. But sync is one-way. A weigh-in from a scale or
the Garmin Connect app, or water logged on the watch or in Connect, never
shows up in GarminFood, because the app's own stores are treated as the only
truth. The owner wants Garmin to be the source of truth, with a weight goal
and Garmin's water goal on top.

Both read routes were live-probed on 2026-09-23 (see `docs/garmin-routes.json`):

- `GET /weight-service/weight/dayview/{date}` returns `dateWeightList[]`,
  with grams and a `samplePk` per sample.
- `GET /usersummary-service/usersummary/hydration/daily/{date}` returns
  `valueInML` (the day total) and `goalInML`.

The delete route `DELETE /weight-service/weight/{date}/byversion/{samplePk}`
was live-confirmed with the owner's approval: it returned 204 and the entry was
gone on re-read. The weight goal already sits in nutrition settings:
`targetWeightGoal` 76000 g, `startingWeight` 80400 g, `weightChangeType`
LOSS, `weightChangeRate` 250.

## What Changes

**Weight: Garmin is the truth.**

- The Weight screen and the home card show Garmin's weigh-ins for the visible
  range. Local entries that haven't synced are merged in and marked pending.
- A local entry that was delivered is de-duplicated against its Garmin sample
  by timestamp and value.
- A weigh-in from a scale or Connect appears after refresh.
- Deleting a weigh-in in the app deletes it in Garmin too. The delete goes
  through the durable outbox, not a blocking call.

**Hydration: Garmin's daily total is the truth.**

- The water card shows Garmin's `valueInML` plus local drinks that haven't
  been delivered yet.
- Removing a drink sends a negative delta. The log route is additive and
  allows negatives, per python-garminconnect.
- Garmin only returns a day total, not per-drink entries. So the app lists the
  drinks you logged in the app, while the total comes from Garmin.

**Goals: Garmin by default, with an override in the app.**

- The water goal is Garmin's `goalInML`.
- The weight goal is Garmin's `targetWeightGoal` and `startingWeight`, with
  `weightChangeRate` used for the ETA.
- Settings → Goals lets the owner override either one locally, with a
  "Use Garmin's goal" reset.
- The weight card shows a progress bar (start → current → target), kg to go,
  and an ETA at the current trend.

**Refresh and failure.**

- The app refreshes on foreground, on screen appear and on pull-to-refresh.
- The last fetched values are cached, so cards render instantly offline.
- Failures degrade quietly, except auth, which stays loud as it is today.

## Non-goals

- Editing a weigh-in's value. That would be delete + re-add, and it wasn't
  requested.
- Garmin-side per-drink history. There is no route for it.
- Writing goals back to Garmin (`calculateGoals` or a settings PUT). The
  override is local only.
- Body-composition fields (fat %, muscle, and so on). They are decoded as
  optional but not shown.

## Capabilities

### New Capabilities

- `weight-tracking`: Garmin-authoritative weigh-in history, delete sync, weight
  goal.
- `hydration-tracking`: Garmin-authoritative daily total, remove-drink sync,
  water goal.

## Impact

**GarminKit**

- New models `WeighInDayView`/`GarminWeighIn` (grams → kg) and
  `HydrationDaily`.
- New `GarminClient` methods: `weighIns(on:)`, a range helper, and
  `hydrationDaily(date:)`. The range helper is built on dayview, or on
  `weight/range` once that route is re-probed.
- `WeightOutbox` gets a delete-by-samplePk operation. `HydrationOutbox` gets
  negative deltas.

**FoodLogCore** (all pure and unit-tested)

- `WeightHistoryMerge`: Garmin samples + local pending → the display list,
  with de-duplication.
- `WeightGoalProgress`: start/current/target/rate → fraction, kg to go, ETA.
- `HydrationDayTotal`.

**App**

- `WeightLoader`, `HydrationLoader`, `WeightView`, `HydrationView`,
  `TodayWeightHydrationSection`.
- A new Settings "Goals" section, with goal overrides stored in
  `AppPreferences`.

**Ordering**

- **Depends on**: nothing (routes already confirmed).
- **Unblocks**: nothing.

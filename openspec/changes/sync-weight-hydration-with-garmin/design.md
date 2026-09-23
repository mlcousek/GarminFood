## Evidence (probed 2026-09-23, owner's live account)

| Route | Result |
|---|---|
| `GET /weight-service/weight/dayview/2026-09-23?includeAll=true` | 200. Two MANUAL samples, `weight` in grams (83900, 82800). Fields: `samplePk`, `timestampGMT` (epoch ms), `calendarDate`, `sourceType`. |
| `POST /weight-service/user-weight` (test 83.9 kg at 03:03:03 local) | 204, empty body. The sample appeared with `samplePk 1790152598056`. |
| `DELETE /weight-service/weight/2026-09-23/byversion/1790152598056` | 204, empty body. Gone on re-read; the real samples were untouched. |
| `GET /usersummary-service/usersummary/hydration/daily/2026-09-23` | 200. `{ valueInML: 1500, goalInML: 2800, lastEntryTimestampLocal, sweatLossInML, activityIntakeInML }` |
| `GET /nutrition-service/settings/2026-09-23` | 200. `startingWeight 80400`, `targetWeightGoal 76000`, `weightChangeType LOSS`, `weightChangeRate 250`. |

## D1: Weight merge rule

The display list is Garmin samples ∪ local entries whose outbox state is not
`delivered`. A delivered local entry is dropped in favour of its Garmin sample,
matched on |Δtime| ≤ 2 min and |Δweight| ≤ 0.05 kg.

Garmin's copy wins for two reasons. It is the trusted source, and it carries
the `samplePk` needed for deletes. The app can't store `samplePk` itself,
because the add route returns 204 with no body.

This is a pure function. Unit tests cover a delivered duplicate, a pending
entry, a Garmin-only entry, and near-miss timestamps.

## D2: Weight range reads

Only the dayview shape is confirmed. The Weight screen needs up to 90 days.

- **First task:** re-probe `weight/range/{start}/{end}`. garmin_mcp reads it as
  `dailyWeightSummaries[].allWeightMetrics[]`. If the probe confirms that
  shape, use it as one call.
- **Otherwise:**
  - The home card uses dayview for today and yesterday.
  - A 30-day range is built from dayview calls in a throttled task group
    (≤4 concurrent).
- **Caching:** results are cached per day in a JSON store. Past days (≥ 2 days
  old) are refetched at most once a day.

## D3: Deletes go through the outbox

- **Garmin-sourced weigh-in:** deleting it enqueues
  `deleteWeighIn(date, samplePk)` in `WeightOutbox`. The entry is hidden
  locally at once, then delivered on drain with the existing backoff. A failure
  shows in SyncQueueView, the same as a failed add.
- **Pending local entry:** deleting it just cancels it. No network call.

## D4: Hydration model

Garmin exposes only a day total, so:

    shown total = garmin.valueInML + Σ(local drinks for that day not yet delivered)

- **Delivered drinks:** they stay listed locally for history ("you logged"),
  but don't add to the total. Removing one enqueues a delta of −value.
- **Pending drinks:** removing one cancels it.

## D5: Goals

Each goal has a `GoalSource` of `.garmin` or `.override(value)`. Overrides are
stored in `AppPreferences`:

- `goals.water.overrideML`
- `goals.weight.overrideKg`
- `goals.weight.startKg`

The effective goal is the override, else Garmin's value, else a fallback:

| Goal | Fallback when neither is set |
|---|---|
| Water | 2000 ml |
| Weight | none, and the card hides the goal bar |

The ETA uses the least-squares slope of the last 14 days of weigh-ins when
there are at least 4 samples. Otherwise it uses Garmin's `weightChangeRate`
(g/week). The ETA is only shown when the slope points toward the target.

## Fallback when routes break

- **Read fails:** show the cached last-good values plus a "Couldn't refresh
  from Garmin" caption. Local pending entries always show.
- **Delete fails:** it stays in the outbox with a visible sync error. It is
  never silently dropped.

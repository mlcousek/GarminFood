## Context

Replaces the `SportAndBodyFeature` stub. Data, all from
`add-gamification-signals`' snapshot (no requests of its own):

- Activities: `ActivitySummary (typeKey, start (UTC instant), durationS,
  calories?, distanceM?)` from `GET /activitylist-service/activities/search/
  activities` — READ-ONLY, confirmed 200 on 2026-09-24, cached 120 days.
- Active kcal per day: `GET /usersummary-service/usersummary/daily`
  (confirmed 2026-09-23), cached.
- Entry timestamps and per-entry macros (carbs, protein) from the Garmin
  day-log digest or local servings.
- Weigh-ins (`weighInKg` per day) and `ProfileSignals.weightGoal`
  (`EffectiveWeightGoal`: override, else Garmin nutrition settings
  `startingWeight`/`targetWeight`, confirmed 2026-09-23).
- `fasting` outcome per day (`FastingDayEvaluator`), `noteTags` (`race`).

**Fallback**: if the activities route breaks, activity badges simply stop
progressing (their data requirement is unmet) — nothing is shown as failed,
and weight/fasting/race badges keep working.

## Decisions

### D1 — Which activities count

`SportActivityClass.classify(typeKey)`:
- **endurance**: typeKey contains `running`, `cycling`, `biking`,
  `hiking`, `swimming`, `skiing`, `rowing`, or is `walking` with duration
  ≥ 45 min;
- **strength**: `strength_training` (counts for Recovery Window only);
- everything else (e.g. `mobility`, `yoga`, `breathwork`) does not count.

Minimum duration 20 min for any counted activity. Activity end =
`start + durationS`.

### D2 — Rules and thresholds

| id | Title | Rule | Rarity |
|---|---|---|---|
| `sport.fuel-1` / `-10` / `-50` | Fuelled Up / Pit Crew / Race Engineer | endurance activity with ≥ 1 entry of ≥ 30 g carbs (or, when the entry's carbs are unknown, tagged `sport.carbRich`) logged 30–180 min before its start; counted once per activity | common / rare / epic |
| `sport.recovery-1` / `-10` / `-50` | Recovery Window / Protein Timer / Recovery Pro | endurance or strength activity followed by entries summing ≥ 20 g protein within 60 min after its end (protein must be known) | common / rare / epic |
| `sport.earned-5` / `-25` / `-100` | Earned It / Balanced Burner / Energy Accountant | a completed day with active kcal ≥ 400, ≥ 3 entries and a calorie goal, where 0.8 × goal ≤ intake ≤ goal + 0.5 × active kcal | uncommon / rare / epic |
| `sport.double-day` | Double Day | two counted endurance activities on one day and the protein goal met that day (strength counts for Recovery Window only, D1) | uncommon |
| `sport.gel-guru` | Gel Guru | ≥ 3 entries timestamped during a single endurance activity lasting ≥ 90 min | rare |
| `sport.long-haul` | Long Haul | an endurance activity ≥ 3 h with ≥ 1 entry during it | rare |
| `sport.race-day-1` / `-5` | Race Day Fuel / Serial Racer | a day tagged `race` with ≥ 1 entry; 5 such days | uncommon / epic |
| `sport.carb-loader` | Carb Loader | the two days before a `race` day both meet the carb goal | rare |
| `body.first-kilo` | First Kilo | a weigh-in ≥ 1.0 kg from the start weight in the goal's direction | common |
| `body.halfway` | Halfway There | a weigh-in with progress ≥ 50 % from start to target | rare |
| `body.target` | Target Reached | a weigh-in at or beyond the target (0.2 kg tolerance) | epic |
| `body.steady-30` | Steady as Sněžka | every weigh-in within ±1.0 kg of target over 30 consecutive days, with ≥ 8 weigh-ins in those days | legendary |
| `body.fast-3` / `-7` / `-14` / `-30` | Fast Starter / Fasting Week / Fasting Fortnight / Fasting Master | the kept-fast streak (`FastingDayEvaluator.keptStreak`'s rules over the window's per-day `fasting` outcomes: today's unjudged fast skipped, a broken or untracked earlier day ends it) reaches 3 / 7 / 14 / 30 | common / uncommon / rare / epic |

Goal direction: loss when target < start − 0.5 kg, gain when target >
start + 0.5 kg; otherwise maintenance, where only `body.steady-30` applies.
Progress = (start − weight) / (start − target) for loss (mirrored for
gain). Without a start weight, only `body.target` (then: within 0.2 kg of
the target, either side) and `body.steady-30` apply. Badges are permanent;
a later goal change does not re-arm them. The goal is the EFFECTIVE one --
the app's `FeatureHost` resolves override, else Garmin's cached
nutrition-settings plan (`WeightAndWaterOverview.weightGoal`), into
`ProfileSignals.weightGoal`.

Ids and titles live in `SportBodyCatalog`; every badge has `featureId` =
`SportAndBodyFeature.id` (`"sportBody"`, the registered stub's id) and
reuses an existing `AchievementCategory` (activity and weight badges under
Goal Hitting, fasting under Streaks) so the shared Achievements screen
needs no edit.

Counts for tiered badges (fuelled activities, recovered activities,
earned days, race days) are persisted per activity id / day, so they
accumulate beyond the 42-day window.

### D3 — Tags

`FoodTag+Sport.swift` declares `sport.carbRich` (banán, energetický gel,
ovesná kaše, müsli, rohlík, chléb, těstoviny, rýže, energy bar, iontový
nápoj, datle, med); `FoodTagRules+Sport.swift` fills the `.sport` rule set.
Only used as a fallback when an entry's carbs are unknown.

### D4 — Persistence

`features/sportBody/sport.json` (the registry gives the feature
`<features dir>/sportBody/`): `{ fuelledActivityIds: [String],
recoveredActivityIds: [String], earnedDays: [String], raceDays: [String],
activityDays: {id: yyyy-MM-dd} }` -- `activityDays` answers "this month"
counts from the store alone. Each list capped at 2,000, Optional fields,
quarantine helpers; `save()` loads first when nothing was read yet, so a
save-before-read never trips the unreadable-file guard. Unlock state lives
in `AchievementStore`.

### D5 — Rewards and moments

Badges only; XP is the standard `XPAward.achievementBonus` added by the
host per unlocked badge (the foundation's `XPAward.sportBadge = 0`).
The host shows the standard achievement moment. A small non-badge moment
("Fuelled right — 45 g carbs 90 min before the start"; "Recovered right")
fires at most once per activity, the first time it counts, style
`.celebration`, 0 XP -- only for an activity that ended within the last 36 h
(no backlog flood on the first run over a 120-day cache), and not when that
family's badge unlocks in the same run (the badge moment already
celebrates it).

The feature emits NO `RewardLedger` grants. Should one ever be added, its
key must start with the feature id and a dot (`sportBody.<...>`) -- the
host drops any other prefix.

### D6 — UI

- `SportBodySlotView`: "This month: 6 fuelled · 4 recovered", weight
  milestone chips (first kilo ✓, halfway 62 %), fasting streak flame.
- `Progress/SportBody/SportBodyView.swift`: recent activities (last 14
  days) each showing fuel/recovery ticks with the entries that counted;
  weight milestones against the goal; fasting streak.

### D7 — Testing

- Classification table incl. walking 44 vs 45 min, mobility excluded.
- Fuel window edges: 29 min before (no), 30 (yes), 180 (yes), 181 (no);
  carbs unknown + carbRich tag (yes); counted once per activity.
- Recovery: protein summed across two entries in 60 min; unknown protein
  ignored; strength counts.
- Earned It: floor and ceiling; not on the current day; active kcal 399.
- Gel Guru / Long Haul: entries strictly inside the activity.
- Race day, carb loader with missing carb goal (no).
- Weight: loss, gain, maintenance; no start weight; steady-30 with 7
  weigh-ins (no) and 8 (yes); tolerance.
- Fasting streak tiers.
- Store caps and decode.

## Risks / Trade-offs

- Timestamps: entries logged *after* the fact carry the logging time, not
  the eating time (the app has no "ate at" field). Windows are generous
  (30–180 min) to absorb this; the owner can log promptly to benefit.
- Activities synced to Garmin late (watch not synced) appear on a later
  refresh; badges then unlock late — acceptable.

## Open Questions

1. Is ≥ 20 g protein in 60 min the right recovery bar for the owner, or
   should it scale with body weight (≈ 0.25 g/kg)?
2. Should `training` day-note tags also count toward any badge? Not
   planned.

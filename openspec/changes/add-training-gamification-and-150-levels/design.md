## Context

Levels are a geometric curve (`LevelCurve`): 100 XP for level 1 → 2, then
× `growthFactor` per level. `rebalance-xp-economy` solved the factor
(1.05358) from an explicit budget (`XPBudget`) so that a typical active day,
≈ 128 XP, reaches **level 84 in three years**. The ceiling is 200.

The training experience (`AppExperience.training`) reads the vault's plan
through TrainingCore. Its only rewards are 14 badges
(`add-winter-arc-nutrition-and-rewards`), paid as an "optional source" that
is scaled so it never moves the pace.

Package rules that stay:

- Gamification never imports TrainingCore, and the reverse. The app copies
  plain values across (`TrainingSignals` today).
- The phone never computes what the vault computes (matching, `actual`,
  adherence, streaks inside the 84-day history).
- Every persisted file has a `StoreCatalog` entry and a frozen fixture.
- Two other changes are in flight in TrainingCore and the app (the daily
  check-in with pain mode, the habits screen). This change must merge beside
  them, so it adds new files and touches shared ones only where a line is
  unavoidable.

**The principle** (the plan's method, PM-RDY-1, PM-VOL-1/2, PM-DEL-1/2,
PM-XT-1): reward following the plan and honest self-monitoring. Never reward
doing more than the plan.

## Decisions

### D1 — The curve: 150 levels, the same formula, a flatter factor

```
XP(n → n+1) = round(100 × g^(n−1))      g = 1.03087, n = 1 … 149
threshold(L) = Σ XP(n → n+1) for n < L   threshold(150) = 297,264 XP
maxLevel = 150 (it was a 200 safety ceiling)
```

`g` is solved, not chosen: `XPBudget.solveGrowthFactor(150, 1,540 days,
typical training-experience day)` (D2), pinned to the literal within 1e-4 by
`XPBudgetTests`, exactly as before. Curve version 4;
`pastGrowthFactors = [1.045, 1.0505, 1.05358]`.

| Level | Threshold | XP for this level | Typical days, cumulative | Days for this level |
|---:|---:|---:|---:|---:|
| 2 | 100 | 103 | 0.5 | 0.5 |
| 10 | 1,020 | 131 | 5.3 | 0.7 |
| 25 | 3,481 | 207 | 18 | 1.1 |
| 50 | 11,131 | 444 | 58 | 2.3 |
| 75 | 27,491 | 949 | 143 | 4.9 |
| 100 | 62,474 | 2,029 | 324 | 10.5 |
| 125 | 137,285 | 4,338 | 712 | 22.5 |
| 140 | 218,483 | 6,845 | 1,132 | 35.5 |
| 149 | 288,265 | 8,999 | 1,494 | 46.6 |
| 150 | 297,264 | — | 1,541 | — |

`LevelCurveTests` pins the threshold column. `tools/level-curve-model.mjs`
prints this table and the checks below; it is a line-by-line mirror of the
Swift budget, because Swift does not run on the development machine.

**Why geometric again, not a polynomial.** A quadratic band
(`100 + 0.259 × (n−1)²`) would spread the late game more evenly (30 days for
the last level instead of 47). It was rejected: all four curve versions share
one formula, so "is the new curve below the old one at every level" is a
comparison of factors that a test can sweep, and the solver, the pin and the
migration code are reused unchanged. The 47 days stay inside the 6–8 week
limit.

### D2 — The budget: food core + training lines

`XPBudgetLine` gains `trainingOnly`. Three sums:

- `coreDailyXP` — the always-on food lines. **Unchanged, ≈ 128.04.** The
  optional-source allowance (0.5 %) still refers to it.
- `trainingDailyXP` — the `training` line, ≈ 64.91. It is the sum of
  `TrainingXPBudget.lines` (one sub-line per source: reward × frequency).
- `typicalDailyXP = core + training` ≈ **192.94**. The curve is solved
  against this.

Pace target: **level 150 after 1,540 days** of a typical training-experience
day (`XPBudget.targetLevel`, `targetDays`).

Rules kept honest by tests:

- one budget line per registered feature (unchanged);
- no food feature above 25 % of the core (unchanged);
- the training line at most 60 % of the core, so food logging stays the
  larger half; no single training sub-line above 15 % of the core (sessions
  are the largest, 13 %);
- the three scenario totals below match the Swift tables to 0.05 XP.

The training rewards are **no longer an optional source**: their XP is real
and budgeted. Supplements stay optional and unchanged.

### D3 — The numeric model: poor, typical, perfect

XP per day. "Typical" is a consistent athlete who is not perfect: 6 check-ins
a week, 85 % of 7 planned sessions done within the light, 6 of 10 weeks kept.
"Poor" is a bad week: 3 check-ins, 4 sessions, no kept week, food logged on 4
days. "Perfect" is everything, every day.

| Source | Reward | Typical | Poor | Perfect |
|---|---|---:|---:|---:|
| **Food core** (unchanged lines, `rebalance-xp-economy` D3) | | **128.04** | **43.72** | **192.80** |
| check-in | 10 / day | 8.57 | 4.29 | 10.00 |
| pain score logged (while asked; 40 % of days) | 2 / day | 0.69 | 0.34 | 0.80 |
| session RPE | 2 / session | 1.14 | 0.29 | 2.00 |
| session note | 1 / session | 0.29 | 0.00 | 1.00 |
| weekly gate test (while asked) | 15 / week | 0.86 | 0.43 | 0.86 |
| test recorded | 20 / test | 1.43 | 0.71 | 1.43 |
| habit tick | 2 / tick | 6.29 | 2.86 | 8.00 |
| full habit day | 6 / day | 3.00 | 0.43 | 6.00 |
| habit streak 7 / 30 / 100 / 365 | 20 / 40 / 80 / 200, once | 0.22 | 0.04 | 0.22 |
| ladder step unlocked | 40 / step | 0.21 | 0.10 | 0.21 |
| session within plan and light | 20 / session | 17.00 | 11.43 | 20.00 |
| honest call (amber/red → its option) | 8 / day | 0.80 | 0.34 | 0.80 |
| plan day kept (rest days too) | 8 / day | 6.29 | 3.43 | 8.00 |
| week approved | 10 / week | 1.36 | 1.14 | 1.43 |
| week kept within plan | 80 / week | 6.86 | 0.00 | 11.43 |
| easy week respected | 30 / week | 0.80 | 0.00 | 1.07 |
| gym twice | 20 / week | 2.00 | 0.71 | 2.86 |
| phase closed with recap | 150 / phase | 1.64 | 1.23 | 1.64 |
| season completed | 300 / season | 0.82 | 0.82 | 0.82 |
| race prep complete | 40 / race | 0.66 | 0.11 | 0.88 |
| carb-load day hit | 15 / day | 0.25 | 0.00 | 0.66 |
| race finished | 100 / race | 1.92 | 0.82 | 2.19 |
| race report | 60 / race | 0.99 | 0.16 | 1.32 |
| wise call (D7) | 100 / race | 0.06 | 0.06 | 0.06 |
| training badges (55) | 30 / badge | 0.78 | 0.29 | 1.07 |
| **Training** | | **64.91** | **30.05** | **84.74** |
| **Training experience** | | **192.94** | **73.78** | **277.54** |

| Play | XP / day | Days to level 150 | Years |
|---|---:|---:|---:|
| Perfect, every day | 277.5 | 1,071 | 2.9 |
| **Typical, every day** | **192.9** | **1,541** | **4.2** |
| Three typical weeks, one poor | 163.2 | 1,822 | 5.0 |
| One typical week, one poor | 133.4 | 2,229 | 6.1 |
| Food-first only, typical | 128.0 | 2,322 | 6.4 |
| Food-first only, perfect | 192.8 | 1,542 | 4.2 |

So the realistic band is 3–5 years: nobody plays 1,071 perfect days in a
row, and one poor week a month still finishes inside five years.

Checks the model and the tests assert: level 10 within 21 days (5.3); no
level above 56 days of typical play (46.6); perfect ≥ 2.9 years; the 3 : 1
mix ≤ 5 years.

**Honest calls are not a thing to maximise.** Their perfect frequency equals
the typical one: more amber mornings are not better play.

### D4 — Migration: XP is kept, the level can only rise

- **XP is not touched.** Only the mapping from XP to level changes.
- **No level goes down.** `g = 1.03087` is smaller than every earlier factor
  and the base is the same 100 XP, so every band, and therefore every
  threshold, is at or below the same level's on 1.045, 1.0505 and 1.05358.
  The level for any XP total is the same or higher. `LevelCurveTests` sweeps
  XP totals and every level 2–150 against all three past factors.
- **`peakLevel` stays** as a second guard (clamped to 150). The seeding code
  is unchanged; it now takes the maximum over three past factors.
- **What an existing ledger sees:** 3,000 XP was level 19 (displayed 20, a
  held peak) and becomes level 22; 4,210 XP: 25 → 28; 12,000 XP: 43 → 51.
- **Tiers.** The 20 tier names stay. Ranges up to level 90 are unchanged, so
  a title never moves down for anyone; the nine tiers above are re-banded to
  end at 150 (D5).
- **A one-time moment.** When `XPStore` loads a ledger written under curve
  version 3 or older, it records a pending announcement
  (`curveAnnouncement`, an Optional field). The engine shows it once
  ("Levels now go to 150 — you are level 22. Your XP is unchanged.") and
  marks it shown. A fresh install never sees it.
- **Level badges.** `achv-level-175` and `achv-level-200` are removed from
  the catalog (their thresholds were 4.4 M XP and beyond; nobody holds
  them). `achv-level-150` becomes "Max Level".
- **Fixtures.** `xp-ledger.json` (version 3) stays and now proves the
  migration; `xp-ledger.v4.json` is today's format.

### D5 — Level tiers for 150 levels

| Levels | Tier | Czech |
|---|---|---|
| 1–5 | Newcomer | Nováček |
| 6–10 | Rookie | Začátečník |
| 11–15 | Apprentice | Učeň |
| 16–20 | Regular | Štamgast |
| 21–27 | Steady Hand | Pevná ruka |
| 28–35 | Dedicated | Oddaný |
| 36–44 | Committed | Vytrvalý |
| 45–54 | Seasoned | Ostřílený |
| 55–65 | Veteran | Veterán |
| 66–77 | Expert | Expert |
| 78–90 | Elite | Elita |
| 91–100 | Master | Mistr |
| 101–110 | Grandmaster | Velmistr |
| 111–120 | Champion | Šampion |
| 121–130 | Luminary | Světlonoš |
| 131–139 | Mythic | Mýtický |
| 140–145 | Immortal | Nesmrtelný |
| 146–148 | Transcendent | Transcendentní |
| 149 | Ascendant | Na vzestupu |
| 150 | Legend | Legenda |

No prestige and no reset: level 150 is the end, and the bar says so.

### D6 — Facts cross the package line as plain values

```
projection + phone overlay ─► TrainingCore.TrainingPlanFacts.build   (what happened)
        raw projection bytes ─► TrainingCore.ProjectionRewardExtras  (fields not modelled yet)
                    the app  ─► Gamification.TrainingPlanSignals     (a copy)
   Gamification.TrainingXPRules.evaluate(signals, food snapshot)     (what it is worth)
```

- **`TrainingPlanFacts`** (new file) reads only what a day, a session, a
  week, a habit, a race or a phase says: the check-in light, each session's
  status and executed option, expected and done habits, unplanned runs, the
  carb-load flag, week status / targets / actual, habit states, race prep /
  report, phase status / recap, the season's end.
- **`ProjectionRewardExtras`** (new file) decodes, from the cached bytes, the
  few fields this change needs that the shared `Projection` model does not
  carry yet: `athlete.gate.date`, `week.actual.unplannedRunKm` /
  `overPlanKm`, applied plan-edit `outcomes`, and the not-yet-published
  `race.result`. Tolerant: any missing or broken field reads as absent. When
  the shared model gains these fields, this file can shrink; nothing else
  changes. It needs one read-only method on `ProjectionStore`.
- **`TrainingPlanSignals`** (Gamification) is the same data as plain strings
  and numbers. `FeatureContext.trainingPlan` carries it. The existing
  `TrainingSignals` and its bridge are untouched.
- **All judgement is in `TrainingXPRules`** (pure, Gamification): what is
  "within the light", a kept day, a kept week. The guards are therefore
  tested in one place with literal signals.

### D7 — The rules

**Light.** Only a check-in light counts. A light the vault inferred from the
executed option is not a self-report, so it reads as "no light".

**A session's verdict**

| Session | Morning light | Verdict |
|---|---|---|
| done, not a traffic-light session | any | as planned |
| done, traffic-light | none or green | as planned |
| done with A or R | amber | as planned, **honest call** |
| done with R | red | as planned, **honest call** |
| done, option unknown | amber | as planned (no bonus) |
| done with G | amber | **over the light** |
| done with G or A, or option unknown | red | **over the light** |
| skipped | any | excused |
| the plan marked it missed | amber or red | excused |
| the plan marked it missed | none or green | missed |
| not done, not judged by the plan yet | any | open |

"Missed" is the plan's own word (`status: missed`, written once the day is
over). The phone does not guess it from the date: a session still
"planned" in a plan file that is a day behind stays open until the file
catches up.

**A day's verdict**, in this order:

1. A date only the phone knows (no written week holds it) → *neutral*.
2. A later day → *open*.
3. Any session over the light, or an unplanned run on a red morning →
   *broken*.
4. Any session missed → *broken*.
5. Any session open → *open*.
6. A rest day: today → *open* (it is judged when it is over); otherwise no
   unplanned run → **kept**, an unplanned run → *neutral*.
7. At least one session as planned → **kept**.
8. Every session excused: red morning → **kept** (resting on red is the
   plan); otherwise *neutral*.

**A week's verdict** (closed weeks only): **kept** when no day is broken, at
least one day is kept, and the volume guard holds:

- run km ≤ target × 1.10 (GPS noise), and
- not (`over > 0` and `unplannedRunKm > 0`), where `over` is the vault's
  `overPlanKm`, else `runKm − target`.

So unplanned kilometres that take the week over its target break it, however
small. An easy week (outline kind deload, taper, recovery or transition) is
**respected** when it is kept and its run km are at or under the target.

**What is paid** (key → XP; every key once, `RewardLedger`):

| Key | When | XP |
|---|---|---:|
| `training.checkin.<day>` | checked in, within the grace window | 10 |
| `training.pain-log.<day>` | the check-in carried a pain answer, within grace | 2 |
| `training.habit.<day>.<habit>` | habit done, within grace, at most 8 a day | 2 |
| `training.habit-day.<day>` | every expected habit done, within grace | 6 |
| `training.habit-streak.<n>` | best habit streak reached 7 / 30 / 100 / 365 | 20 / 40 / 80 / 200 |
| `training.ladder-step.<habit>` | the habit is active | 40 |
| `training.session.<id>` | as planned, not a race | 20 |
| `training.honest.<day>` | an honest call that day | 8 |
| `training.day.<day>` | the day is kept | 8 |
| `training.rpe.<id>` / `training.note.<id>` | a done session has an RPE / a note | 2 / 1 |
| `training.gate.<week>` | a gate test at most 14 days old | 15 |
| `training.test.<id>` | a test session has a result | 20 |
| `training.week-approved.<week>` | the week is approved or closed | 10 |
| `training.week-kept.<week>` | the week is kept | 80 |
| `training.easy-week.<week>` | an easy week respected | 30 |
| `training.gym-week.<week>` | two strength sessions done | 20 |
| `training.phase.<id>` | the phase is closed and has a recap | 150 |
| `training.season.<id>` | the season's period has ended | 300 |
| `training.race-prep.<id>` | prep complete on or before race day | 40 |
| `training.carb-load.<day>` | a carb-load day whose carb goal was met | 15 |
| `training.race-fuel.<id>` | the vault says the fuel plan was followed | 30 |
| `training.race-finish.<id>` | the race session is done, the morning not red | 100 |
| `training.race-report.<id>` | the race has a report | 60 |
| `training.wise-call.<id>` | see below | 100 |

- **Grace window: today and the two days before.** Self-reported facts
  (check-in, pain answer, habit ticks) pay XP only inside it. A tick filled
  in later still counts for the streak and the badges; it pays no XP, so
  filling in two weeks at once is not a way to earn. Measured facts
  (sessions, weeks, races) pay whenever the plan shows them, because
  activities can sync late.
- **Habit streak.** A day counts when at least the ladder's gate share
  (`habits.gate.adherencePct`, 80 %) of its expected habits is done. A day
  with nothing expected is skipped. Today does not break it. A day the phone
  never saw breaks it. The vault's per-habit streaks stop at its 84-day
  history, so the feature keeps its own day records to reach 100 and 365.
- **Prep complete:** a start time, a carbohydrate-per-hour figure, and at
  least one checkpoint or gear item.
- **Carb-load day:** judged by the food side's goal status, which already
  uses the day's fuel band (`add-winter-arc-nutrition-and-rewards` D3).
- **Races pay a fixed amount.** Nothing reads distance, time, pace or
  priority. "Goal reached" and "PR" are one-off badges with no XP of their
  own, and they stay dormant until the vault publishes `race.result`.
- **Wise call (secret badge "Lived to Run Another Day").** A race that was
  not finished pays what a finish pays when the vault says a stop rule ended
  it (`race.result.stopRule`), or when its session was not done and that
  morning's check-in was red. The badge is revealed once; the XP is per
  race.
- **Plan edits pay no XP.** One badge for the first applied change. An edit
  can never raise a reward: a skipped session is only excused.

**Guards, each a test in `TrainingXPRulesTests`:**

1. An unplanned run pays 0 XP, on any day.
2. Unplanned km over the target → no `week-kept`, no `easy-week`.
3. A session over the light pays 0 and its day is not kept.
4. A red morning done as R, or rested, is a kept day.
5. Seven session days in a row pay exactly seven days' rewards. A week with
   rest days never pays less than the same sessions without them.
6. A race run on a red morning pays no finish XP.
7. The same signals evaluated twice add nothing (keys are stable).
8. No key or badge depends on km, minutes, pace, elevation or weight.

### D8 — Badges and the store

41 new badges beside the 14 existing ones, all `training.*`, each unlocked
once by the host with the generic 30 XP bonus:

| Ladder | Tiers |
|---|---|
| Habit streak (days) | 7 / 30 / 100 / 365 |
| Ladder steps unlocked | 3 / 6 |
| Sessions within plan and light | 25 / 100 / 300 / 1,000 |
| Plan days kept | 30 / 100 / 365 |
| Easy weeks respected | 1 / 4 / 12 |
| Sessions rated (RPE) | 25 / 100 |
| Weekly gate tests | 1 / 8 |
| Tests recorded | 1 / 5 |
| Weeks approved | 12 / 52 |
| Phases closed with recap | 1 / 4 |
| First applied plan change | 1 |
| Race preps complete | 1 / 5 |
| Carb-load days hit | 2 / 10 |
| Races finished | 1 / 5 / 15 |
| Race reports | 1 / 5 |
| Goal reached, PR (dormant) | 1 each |
| Wise call (secret) | 1 |
| Seasons completed | 1 / 3 |

`TrainingRewardsStore` (`training.json`) grows by three Optional fields, so
the schema version stays and the old fixture still decodes:

- `sets: { name: [id] }` — the counted ids behind each ladder (session ids,
  kept days, easy weeks, …), newest 2,000 each;
- `habitDayStates: { day: 0 | 1 | 2 }` — beside the existing
  `habitTicksByDay`, for the streak: nothing expected, expected and not
  met, met (at least the gate share of the expected habits done);
- `seasonEnds: { seasonId: day }` — so a season that ends while the next
  one is already selected is still seen.

When plan signals are present, "honest calls" and "kept weeks" are recorded
from the new rules (D7), so the two existing ladders and the XP agree.

A kept week, a closed phase, a completed season and a finished race get one
moment each, the first time the store records them. The very first run
with the plan's facts records the whole plan window at once and shows none
-- "first" is a file without `sets`, so a device that already filled the
five original lists is treated the same (the field is written by the first
run that carries any fact, even when no set got an id).

### D9 — Training variants of boss, bingo and journeys

In the training experience only; a card or boss already running finishes.
Bingo and journeys also need a plan with written days
(`TrainingPlanSignals.hasPlanDays`): a file without one keeps their food
rules, because nothing in it could ever be "kept".

- **Boss: the Impatience Imp** (`BossKind.impatienceImp`). "Whispers 'just a
  little more' every day." Habit: keep the day's plan. A hit is a kept day
  (D7). Its adherence is kept days / judged days over the four weeks before;
  it needs 10 judged days and competes like any other boss (the weakest
  habit wins). Outside the training experience it is never chosen, and the
  bestiary badge does not need it.
- **Bingo: eight training squares**, added to the pool there: check in on 5
  days; a full habit day; 3 full habit days; a kept day; 5 kept days; gym
  twice; rate a session; check in on all 7 days. None of them asks for an
  amber morning or for more training. They are judged from
  `TrainingPlanSignals`, and once more on the Monday after their week (the
  whole-day pass that settles last week's card): a session matched after a
  late sync, or a Sunday rest day, still ticks its square.
- **Journeys: the road trip moves by kept days.** The road trip turns
  active calories into kilometres, which pays for doing more. In the
  training experience it advances **8 km for every kept plan day** instead
  (a rest day included), and its conversion line says so.

The XP of these comes from the existing boss, bingo and journeys lines; no
new budget.

### D10 — The Progress tab's training section

Under the Level card, in the training experience:

- the level card gains "Level 22 of 150" and a thin 1–150 bar (both
  experiences);
- **Training**: this week (check-ins, kept days, gym), current streaks
  (check-in, habit, kept weeks in a row), and each ladder as a row with its
  count and next step. Tapping opens the full list.

A pure model (`TrainingProgressModel`, Gamification) produces the rows with
localized text; the view only draws them.

The feature runs on the usual refresh and on a log confirm. The app also
runs it after a check-in, a tick or a rating, so the XP shows at once.

## Defaults chosen (owner can revisit)

| # | Question | Default | Why |
|---|---|---|---|
| 1 | Target for level 150 | 1,540 typical days (4.2 y) | perfect play then lands at 2.9 y and a 3 : 1 mix at 5.0 y |
| 2 | Food-first on the same curve? | Yes, one curve | simpler; food-first alone takes ≈ 6.4 y |
| 3 | Back-filled ticks | no XP after 2 days; still count for streak and badges | no farming, no punishment for a forgotten tick |
| 4 | Habit streak day | ≥ 80 % of expected habits (the ladder's gate) | "follow the plan" is the plan's own bar |
| 5 | Rest on an amber morning | neutral: no XP, breaks nothing | red is a clear stop; amber has an option |
| 6 | Volume tolerance | 10 % over target, 0 when unplanned km caused it | GPS noise vs. extra runs |
| 7 | Easy weeks | deload, taper, recovery, transition | all are "do less on purpose" |
| 8 | Race XP by priority? | No, one amount | no incentive to enter more or bigger races |
| 9 | Road trip per kept day | 8 km | about what an active day gave before |
| 10 | Old ledgers | level rises at once (20 → 22) | the alternative, holding the old number, would hide real progress |

## Open questions for the owner

1. **Race outcome.** The contract has no machine-readable result. The app
   decodes an optional `race.result { outcome: finished | dnf | dns,
   goalReached, pr, stopRule, fuelPlanFollowed }`. Until the vault writes
   it: finish = the race session is done; wise call = red morning and no
   race; goal, PR and "fuel plan followed" stay dormant. Recommended: add
   the field to the race report's frontmatter.
2. **Is 4.2 years the right "typical"?** A 4.0-year target puts perfect play
   at 2.8 years. Recommended: keep 1,540 days.
3. **Should amber rest earn the day XP?** Recommended: no (default 5).
4. **Plan-day XP without a check-in.** A kept rest day pays 8 XP even with
   no check-in that morning. Recommended: keep — rest is the plan.
5. **The secret badge's name** ("Lived to Run Another Day").

## Risks / Trade-offs

- **Not compiled locally.** CI is the signal. The risky files are listed in
  tasks 9.
- **A first run pays the whole plan window at once** (two to three weeks of
  sessions and kept days, active ladder steps, approved weeks, closed
  phases): up to about a thousand XP, once, a few levels at the start. No
  moment is shown for each of them.
- **The reward ledger grows by about ten keys a day** in the training
  experience (it keeps keys forever). That is the "few thousand a year" it
  was designed for; a pruning rule for old day keys is a later change if
  the file ever gets large.
- **Late facts.** A session matched more than three days late still pays its
  own XP, but the road trip has sealed that day (journeys' existing rule).
- **Estimates.** Frequencies are assumptions. A change is one table line and
  a re-solved literal; levels never drop because of `peakLevel`.
- **Two near-identical structs** (`TrainingPlanFacts`, `TrainingPlanSignals`)
  are the price of the package boundary.

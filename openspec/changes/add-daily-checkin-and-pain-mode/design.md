## Context

`add-training-today-and-plan` decodes the vault's projection v1 into a
`TrainingSnapshot`; `add-training-checkins` records the morning light,
habit ticks and reminders; `add-checkin-pain-score` added the pain step;
`add-winter-arc-nutrition-and-rewards` reads `day.fuel` for the food side.
All four find a day through `snapshot.plan?.day(date)`, which is `nil` on
a day no written week holds and whenever there is no plan.

The vault's contract changed on 2026-09-30 (still v1): day skeletons
(`days`), `athlete.painMode`, and `fuel` on every day. This change makes
the app use all three. No Swift toolchain here: correctness rests on the
package tests in CI.

## Goals / Non-Goals

**Goals:** the check-in, habit ticks and reminders work on every day; the
pain features show only in pain mode; nothing treats "a fuel is there" as a
carb load; the reminder times are the owner's.

**Non-Goals:** a new "eat for training" screen (the richer `fuel` fields
are decoded and tested, the existing Today summary uses the band); a pain
trend chart; running any of the vault's rules on the phone; a new persisted
file.

## Decisions

### D1. One lookup: `TrainingSnapshot.day(_:)`

The snapshot keeps the skeletons (`skeletonDays`, the phone's check-ins
applied by the same `CheckInOverlay.applying(to:)` that the plan weeks get)
and answers `day(date)`: the written week's day, else the skeleton, else
`nil`. `EffectivePlan` stays what it was (the selected phase with the
phone's pending plan commands), so plan editing, session detail and the
statistics are untouched -- a skeleton has no sessions to edit.

*Alternative:* synthesize "unwritten" `Week`s from the skeletons. Refused
for the vault's own reason: a week carries a `revision` and a status, and
`(week, revision)` names exactly one schedule; a fake week would be a
schedule the vault never published.

The decoder drops a skeleton whose date a plan week already has, and a
repeated date, so the lookup can never disagree with the plan.

### D2. The check-in row is on every date

`checkInRow(on:)` no longer needs a day: it is `nil` only when the app may
not record. On a date the file does not cover (a copy more than three
weeks old) the chosen light is the phone's own check-in. The reminder
planner follows the same rule, so a reminder never fires for a day Today
cannot check in on. Habits do need the day (its `habitsExpected`), so the
habits reminder and ticks stop where the file's window stops.

### D3. Pain mode: the vault's word, bridged by the phone's own answer

`PainModeState.resolve`: on when `athlete.painMode.active`; else on when
this phone holds a pain answer with a score above 0 that the vault has not
read -- its event is not acknowledged (`acks[deviceId].seq`), and the
file's own `day.pains` for that date is not that answer. Nothing is
stored: the state falls out of the event log (kept 21 days) and the
projection, so it cannot drift, and once the vault has read the answer the
vault alone decides (it can be configured to keep pain mode off).

An amber or red light does not turn the phone's half on, although it does
start pain mode in the vault's default configuration: that is a vault
setting, and the phone never runs the vault's rules. The step appears with
the next projection.

"Something hurts?" is a view state, not a mode: it opens the step once.
Saving a score above 0 there is what turns the phone's half on; saving
zeros records the answer and leaves the mode off. The link needs a chosen
light, because the pain answer travels in the check-in.

### D4. Outside pain mode nothing pain-related is built

The builders decide, not the views: `TodayTrainingModel.painLine` and
`DayRowModel.painTags` are empty, `PainStepModel.opensExpanded` is false,
and the step carries `isPainMode` and `somethingHurtsTitle` so the view
draws one small link. A recorded answer of an earlier episode is not shown
while healthy -- that is the owner's request ("never stale nagging"). A
lock-screen Control's hand-off to Today (pain-score D7) happens only in
pain mode.

### D5. A carb-load day is `DayFuel.isCarbLoad`

`kind == "carb-load"`; for a fuel without a `kind` (a file older than this
contract, where the only fuel was a carb load) the single number or the
grams without a band. Used by `FuelFormatter.dayLine`, `DayFuelTargets`
and the race screen's carb-load rows. `kind` gains `daily`; `load`,
`fasting` and the fasting reasons are open enumerations, an unknown value
is kept as unknown and never read as "off".

### D6. Reminders: every day, the owner's times

The morning reminder is planned for each day of the 7-day window without a
light. Its body is "Green, amber or red?", and in pain mode "... Add your
pain score too." (the old "before you run" is wrong on a rest day).
`TrainingReminderTimes` (clamped into a day) replaces the two constants;
`TrainingModel` keeps them in UserDefaults under four keys, like the food
reminders. The scheduler diffs pending requests by identifier and text, and
a changed time changes neither -- so the request identifier carries the
fire time (`trainingReminder.<kind>.<day>.<HHmm>`, like the fasting
reminders'): the request at the old time is no longer planned and is
removed, the one at the new time is added, in the same pass. A request
from a build before this change has no time suffix and is replaced by the
first replan. A time picker reports every step of its wheel, so
`TrainingModel.syncReminders` runs one replan at a time (the next waits
for the one in flight): two replans interleaving around the scheduler's
awaits could leave requests at both times pending.

### D8. The vault's 2026-10-01 additions are read, not used

The same re-mirror brought the vault's training load and gates (still v1):
`athlete.gate`, the load fields of `week.actual`, `unplanned[].flag`,
`session.feedback.pains`, `done.manual` with `source` / `matchedBy`
`manual`, top-level `notices`, the habits' `streak` / `history` /
`adherence`, and the events `test.gate` and `session.done`. None of it is
this change's feature (the gate card, "done without a watch" and the habit
history each get their own change), so nothing new is decoded: unknown
keys are ignored, the new enumeration values read as `.unknown`, the new
event types as `.other`. Three places needed care so the richer file reads
well today:

- a session done by hand has a `done` with nothing this build can say
  about it (no option, no activity, an unknown `matchedBy`): its detail
  shows no "Done activity" card instead of an empty one -- the status
  already says "Done";
- `session-pain` and `pain-not-settled` are session rule notes that "only
  inform, never edit": `PlanEditPolicy.noteOnlyRules` keeps them out of
  the rules the owner may override (the note is still shown);
- the two refused `habit.tick` outcomes name no week and no session and
  match no plan command, so the plan-change lists ignore them.

### D7. Rewards and food on skeleton days

`TrainingRewardFacts` counts skeleton days up to today (a check-in or a
tick outside a written week is still a check-in); weeks stay the written
ones. `fuelTargets(on:)` and the paused-fasting days read skeletons, so
the Today fuel summary shows on every day of the window. Field names match
what the food change assumed (`carbsGPerKg` number or band,
`proteinGPerKg`, `fasting`), so nothing else moved.

## Risks / Trade-offs

- A recorded pain answer is invisible while pain mode is off -> it is one
  tap away ("Something hurts?" opens the step with that answer).
- If the vault never acknowledged this device, an unread answer above 0
  would keep the phone's half on for the log's 21 days -> the second test
  (the file shows the same answer) ends it at the next projection.
- A check-in reminder now fires on rest days -> the owner asked for it;
  the switch and the time are in the notification settings.
- The Today fuel summary's title still says "Fuel for today's training" on
  a rest day -> wording only; left for the food screen's own change.

## Migration Plan

None. An older cached projection has no `days` and no `painMode`: no
skeletons, pain mode off, the check-in row still shows.

## Open Questions

- Should an amber/red check-in open the pain step at once? (Needs the
  vault's `pain_mode` setting in the projection to be safe.)

## Why

The vault's event contract gained an additive field on 2026-09-30 (its
Training Hub Contract, "Event log v1" and the fixture changelog, decision
A57): `checkin.morning` may carry `pains`, a morning pain score per site.
The vault turns it into `day.pains` in the projection and into two
always-on week notes (`pain-rising`, `pain-high`) that follow a common
pain-monitoring model: morning pain in a tendon must not rise week to
week, and a score above 5/10 is a flag. The week-to-week comparison needs
at least three scored mornings in each seven-day window, and a morning
without an entry is never counted as 0, so the contract asks the app to
send the Achilles every morning, 0 included.

The app records the morning light in one tap (Today's row and the
lock-screen Controls, `add-training-checkins`), but has no way to send the
score. Without it the vault's pain flags never fire.

## What Changes

- **The wire format** (TrainingCore `Events/HubEvent.swift`, still the only
  file that knows it): `checkin.morning` gains `pains?: [{site, score,
  note?}]`. `site` is `achilles-left`, `achilles-right`, `knee-left`,
  `knee-right` or `other` (anything else reads as `other`); `score` is
  0-10 in steps of 0.5; `note` 1-200 characters. The encoder writes
  `pains` like every optional key: `null` when not asked. Scores are
  written as integers when whole (`1`, not `1.0`), so the golden bytes do
  not depend on the platform's number printing.
- **Replace/keep semantics** (`CheckInOverlay`): a later check-in of the
  same date without `pains` keeps the earlier answer; one with `pains`
  (even `[]`) replaces it -- the vault's rule, applied to the phone's
  optimistic overlay.
- **Decoding** (`Projection.Day.pains`): tolerant, like every field --
  absent or `null` is "not asked", `[]` is "nothing hurts", a broken entry
  is dropped, an unknown site reads as `other`.
- **Today** (`CheckInModels` / new `PainModels`, the app's check-in row):
  after the light is chosen, a compact pain step: the Achilles side(s) the
  owner scored last (else the left Achilles), each pre-filled with 0 so one
  tap on Save confirms "0"; a 0-10 half-step control per row; "Add another
  site" (right or left Achilles, left or right knee, other with a short
  note); sent in one check-in event with the same light. Editable the same
  day (re-sends a check-in that replaces `pains`). The training card shows
  the day's recorded pain.
- **Plan** (`DayRowModel.painTags`): the week agenda's day rows and the
  month's day sheet show a pain tag per site ("Achilles (left) 5.5/10").
  The vault's `pain-*` week notes already render as rule notes.
- **Controls** stay light-only. The app, opened by a Control, goes to
  Today's today, where the pain step is waiting because the day's pain is
  not asked yet.
- **Fixtures**: all four vault contract fixtures re-mirrored verbatim;
  goldens that change with them are updated.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None archived. `training-checkins` and `training-event-log` (from
`add-training-checkins`), `training-plan-view` and `training-projection`
(from `add-training-today-and-plan`) are not archived yet; this change
adds requirements to them. Their archive must fold these together.

## Non-goals

- Computing a pain trend or a flag on the phone. The vault computes
  `pain-rising` / `pain-high`; the app only shows its notes (the phone
  never computes what the vault computes).
- Pain in the lock-screen Controls (they stay three one-tap lights).
- A pain history chart; body sites beyond the contract's five.
- Any change to the vault.

## Impact

- TrainingCore: new `Contract/Pain.swift` (`PainSite`, `PainEntry`), new
  `ViewModels/PainModels.swift` (`PainDraft`, `PainStepModel`,
  pain lines and tags); `HubEvent` (`MorningCheckInPayload.pains`, encode,
  decode, validate); `Projection.Day.pains`; `CheckInOverlay.pains` and
  the replace/keep fold; `EffectivePlan` applies the phone's pains;
  `CheckInRowModel.pain`, `TodayTrainingModel.painLine`,
  `DayRowModel.painTags`; strings in both `.lproj` tables and
  `TrainingKey`; tests (`HubEventTests`, `PainTests`,
  `ProjectionDecodingTests`, `PlanBuilderTests`, `PlanEditingTests`,
  `CheckInBuilderTests`); the four mirrored fixtures, `CONTRACT.md`, the
  app golden `events.v1.app.jsonl`.
- App: `TrainingTodayCards` (the pain step in `CheckInRowView`, the pain
  line), `TodayView`, `TrainingModel.recordPain`, `TrainingEventsService`
  (`onControlCheckIn`), `AppEnvironment` (routes a Control check-in to
  Today's today), `WeekAgendaView` / the day sheet (pain tags); app strings
  in `Localizable.xcstrings`.

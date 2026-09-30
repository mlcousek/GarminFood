## Context

The vault's contract (Training Hub Contract, "Event log v1", changelog
2026-09-30, decision A57) added `pains` to `checkin.morning` and `pains` to
every projection day. Its fixtures changed: `events.v1.example.jsonl` has a
new seq 24 (a second check-in of 2030-10-23, same amber light and option,
with `achilles-left` 5.5 and a note and `knee-right` 1 without one), and
`projection.v1.example.json` gives every day `pains` (null except
2030-10-23), W43 a `pain-high` rule note, and the phone's ack seq 24. The
minimal fixtures are unchanged. Branch `mlcousek/checkin-pain-score`, on
`mlcousek/today-habits-and-races` (#114).

## Goals / Non-Goals

Goals: send the morning pain score with the check-in at almost no extra
cost (one tap confirms 0), keep it editable the same day, show it on Today
and in Plan, and follow the vault's replace/keep rule exactly.

Non-goals: see the proposal. The phone never computes the pain flags.

## Decisions

### D1 -- The wire shape

`MorningCheckInPayload.pains: [PainEntry]?`. `nil` = not asked, `[]` =
asked, nothing hurts. Encoded as the contract's list of
`{note, score, site}` objects (sorted keys). Like every optional key the
app writes, `pains` is written as `null` when not asked and an entry's
`note` as `null` when it has none -- the vault treats `null` like an absent
key (`e.payload.pains != null` in its fold). The existing golden check-in
lines therefore gain `"pains":null`; the bytes are deterministic, and a
sealed segment is never re-encoded (its bytes are frozen in the queue), so
no already sealed file changes.

A score is written as an integer when it is whole (`0`, `1`) and as a
double otherwise (`5.5`): every half step is exact in binary, and this
keeps the golden independent of how Foundation prints `1.0`.

Validation before recording (`HubEventPayload.validate`): every score in
0...10 and a multiple of 0.5; a note, when present, not blank and at most
200 UTF-16 code units (the vault's validator counts JavaScript string
length). Duplicate sites are allowed by the contract (the vault takes the
highest), but the app's draft never produces them.

Decoding the app's own events: `pains` absent or `null` -> `nil`; each
entry through `PainEntry` (below).

### D2 -- Sites

`PainSite`: `achillesLeft`, `achillesRight`, `kneeLeft`, `kneeRight`,
`other`, raw values the contract's words. Any other string decodes as
`.other` -- in the projection (the vault already publishes unknown sites as
`other`) and in events -- so a newer vault or app with more sites never
breaks this one. Labels are UI vocabulary: "Achilles (left)" /
"Achilovka (levá)", "Knee (right)" / "Koleno (pravé)", "Other" / "Jiné".
No personal history in strings, fixtures or docs: the defaults below are
derived from what was recorded, not written into the code as a fact about
anyone.

### D3 -- Replace/keep on the phone

`CheckInOverlay` keeps, per date, the `pains` of the latest check-in of
that date that carries them (non-nil), with that event's delivery. A later
check-in without `pains` (a corrected light, or a Control) leaves it; one
with `pains` replaces it, `[]` included. `EffectivePlan` applies the
phone's pains to the day like the light, so every builder reads
`day.pains`. This is exactly the vault's fold, so both agree once the
vault ingests the events.

### D4 -- Decoding `day.pains`

`Day.pains: [PainEntry]?`, lenient: absent, `null` or the wrong type ->
`nil`; a list -> a lossy list (an entry without a numeric score is dropped
and recorded); `site` through D2; `note` a string or nil. A score outside
0...10 is kept as written (display only; the vault validated it).

### D5 -- The pain step on Today

The check-in row gets `pain: PainStepModel?`, non-nil when the row has a
chosen light (a real check-in, not one inferred from the executed option).

- **Not asked yet** (`day.pains == nil`): the step is open under the
  lights. Rows: the Achilles sites of the most recent earlier day that has
  pains with an Achilles entry (the phone's overlay and the projection),
  else the left Achilles alone; each at 0. One tap on "Save" sends the
  check-in with those zeros. "Not now" folds it for this screen only (it
  returns next time, because the answer is still unknown).
- **Asked**: a one-line summary is on the card ("Pain: Achilles (left)
  5.5/10 · Knee (right) 1/10" or "Pain: none"), and the row has an "Edit
  pain" button that opens the same step with the recorded entries.
- Each row: the site's label, the score ("4.5/10", Czech "4,5/10"), a
  slider 0...10 step 0.5 (VoiceOver adjustable by half steps), and a
  remove button. "Add another site" lists the sites not yet in the draft;
  "Other" asks for a short note (up to 200 characters, trimmed; empty is
  no note).
- "Save" records `checkin.morning` with the same date, light, session and
  option as the row, plus `pains` from the draft (removing every row sends
  `[]`: asked, nothing hurts).

`PainDraft` (pure, tested) holds the rows and does the rounding, the
add/remove rules, the default sites and the payload. The view only draws
it.

### D6 -- Plan

`DayRowModel.painTags`: one tag per recorded entry in the day's order,
"Achilles (left) 5.5/10"; `[]` when not asked or nothing hurts (the vault's
day header does the same). The week agenda's day rows and the month's day
sheet show them with a bandage symbol. The vault's `pain-rising` and
`pain-high` notes reach the week through the existing rule-note lines.

### D7 -- Controls

The Controls still send the light only (`pains` null, so an earlier
answer that day is kept). After a Control's check-in succeeds the app
selects the Today tab and today's date (`TrainingEventsService
.onControlCheckIn`, set by AppEnvironment), where the pain step is open
because the day's pain is not asked yet.

## Risks / Trade-offs

- **Existing golden lines change** (`"pains":null`). Accepted: the
  alternative (omit the key when nil) would be the only optional key the
  app does not write, and the vault reads both the same.
- **No Mac.** Swift compiles only in CI; the view code is thin and every
  rule is in TrainingCore's tests.
- **Default sites from history** can be surprising the first morning after
  a different site was scored; it is one tap to change, and it never
  records anything by itself.

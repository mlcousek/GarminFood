## Context

Three reports from the owner's first day with the vault connected (see
the proposal). All three are small and share one branch,
`mlcousek/today-habits-and-races`, on `main` `e2d871a`.

## Goals / Non-Goals

Goals: a configured connection fetches the plan without waiting for a
foreground; the habit ladder is trackable from Today; any upcoming race is
visible on Today while the main race stays visible.

Non-goals: see the proposal. The phone still never computes what the
vault computes (gates, windows, expected habits).

## Decisions

### D1 -- The setup fetch

**Finding verified.** `VaultController.setEnabled`, `saveRepository`,
`saveToken` and `testConnection` ended in `reload()` only. The first
`refreshInBackground` came from `AppEnvironment.refreshOnForeground`
(launch / foreground / pull to refresh), `tryAgain`, or the upload
auth-stop hook. Settings is reached while the app is already in the
foreground, so nothing fetched until the owner left and came back.

**Rule, in VaultKit (`VaultSetupRefresh`, pure, tested):**

- nothing unless the inputs are now usable (enabled, configured, token);
- switch turned on: fetch when that made the inputs usable, or when there
  has never been a successful sync;
- repository or token saved: fetch (new credentials);
- "Test connection" whose repository probe succeeded: fetch only when there
  has never been a successful sync;
- one at a time; a credential change while a fetch runs is coalesced into
  exactly one follow-up; anything else is dropped.

With the Settings order (switch, repository, token, test) this is exactly
one fetch, at the token. The fetch is `ProjectionStore.refresh(via:inputs:
force:)` (new in TrainingCore, also used by the foreground refresh): the
coordinator's gated GET with the projection validator, folded into the
store. `force: true` skips only the 60 s interval, never the gate. It runs
unstructured (local-first: no save path awaits GitHub) and only when
`isRefreshAllowed` (Garmin-connected, out of onboarding -- the same rule as
the foreground fetch, A26). When it ends, `onProjectionRefresh` reloads
TrainingModel, which then reads the cached projection.

Settings -> Vault's status shows "Fetching your plan…" with a spinner while
it runs, then "Plan fetched. Today and Plan show it." or "The plan file
couldn't be read. Today and Plan say why."; a failure shows in the existing
"Last problem" row (loud ones also in the banner).

**Why a package type.** The app target has no tests without a Mac. The
decision lives in VaultKit; the chain "settings -> one fetch -> cached
projection loads" is tested in TrainingCore (`SetupRefreshTests`) over the
in-memory transport and real stores. The controller only replays it.

### D2 -- The Habits card

`TodayTrainingBuilder.habitsCard(on:)` -> `HabitsCardModel`, `nil` only
when the ladder is empty:

- `stepText` "Step n of N": the highest active step's position in the
  ladder (positions, not the vault's `step` numbers, which may start at 0);
- `rows`: ladder order, the active habits plus any habit the day expects;
  a row the day expects has the existing on/off tick (when recording is
  allowed) and the vault's count; an active habit the day does not expect
  says "Not on today's plan" and has no tick. Rows reuse `HabitRowModel`;
- `progressText` "d of e done today" over the expected rows, from
  `TrainingSnapshot.habitDone` (the phone's latest tick over the vault's
  count); `nil` when the day expects none;
- `next`: the first `next` habit, with "Gate met: ..." when the vault set
  `gateMet` on the current step, else "Unlocks when <current> holds P %
  over a W-day window" from `habits.gate`, and "Earliest start <date>".

Card id `habits` (AppearanceKit) replaces `habitsToday` in the training
catalog, at the same position -- right after `trainingDay`, whose first row
is the morning check-in. A new id is the resolver's way to add a card to a
stored layout (rule 3: after its nearest present predecessor, default
visible), so the card appears for the owner even if he hid or moved the old
one; the retired id stays in storage unrendered (rule 2). The header and
the next-step row open the full ladder (`HabitLadderView`).

### D3 -- The race chip and B races

`raceChip(from:)` takes the first race on or after the day, any priority.
The model gains `priorityCode`, `priority`, `priorityText` ("B race",
"Hero race") and `mainRace`: the first upcoming hero race, else the first
upcoming A race, when it is not the chip's race -- shown as a second line
"Main race: <name> · <countdown>". The chip shows the letter as text (with
★ for the hero), never colour alone, and opens the race's screen.

Season timeline and race screen already draw every priority and label the
time before the first phase "No phase planned"; a race without a phase says
"No phase covers this race yet" and has no taper. A test pins this for two
B races before the first phase.

### D4 -- Strings

TrainingCore (both `.lproj`, `TrainingKey`): "Step %lld of %lld",
"%lld of %lld done today", "Not on today's plan", "Unlocks when %@ holds
%lld %% over a %lld-day window", "Next step: %@", "Main race: %@ · %@".
App (`Localizable.xcstrings`, edited as text): "Habits", "Shows when a race
is ahead", "Shows when the plan has a habit ladder", "Fetching your plan…",
"Plan fetched. Today and Plan show it.", "The plan file couldn't be read.
Today and Plan say why.".

## Risks / Trade-offs

- A setup fetch and a foreground fetch can overlap; the coordinator skips
  the second (`alreadyRunning`) and both paths reload TrainingModel.
- If the vault publishes days without `habitsExpected`, the card shows the
  active habits without ticks ("Not on today's plan"); that is the vault's
  answer, shown honestly.
- The old "Today's habits" catalog strings stay (unused) to keep the
  catalog edit additive.

## Migration Plan

None: no stored format changes. A stored `habitsToday` placement is kept
and ignored.

## Open Questions

None.

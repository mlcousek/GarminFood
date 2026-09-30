## Why

The owner connected the vault on his phone and reported three things.

1. **The first sync did not start.** Finishing the setup in Settings ->
   Vault (switch on, repository, token, "Test connection") only re-read
   local state. The first projection fetch waited for the next
   foreground, pull to refresh or "Try again", so a configured owner could
   open Today or Plan and sit on "Fetching your plan..." indefinitely.
   A review finding said so; it was verified in
   `GarminFood/Vault/VaultController.swift`: `setEnabled`,
   `saveRepository`, `saveToken` and `testConnection` each end in
   `reload()` and none calls `refreshInBackground`; the only callers were
   `AppEnvironment.refreshOnForeground`, `tryAgain` and the upload
   auth-stop hook.
2. **The habit ladder is hidden.** Today's "Today's habits" card listed
   only the habits the plan expected that day and hid itself otherwise;
   the ladder (the step he is on, what unlocks the next one) was one tap
   behind that card or deeper in Plan. He cannot track it.
3. **B races are invisible on Today.** The race chip showed only the next
   A or hero race. The vault now publishes the autumn's B races in
   `season.races`, and the season starts two weeks before its first phase.

## What Changes

- **Setup fetch** (VaultKit `VaultSetupRefresh`, TrainingCore
  `ProjectionStore.refresh(via:)`, the app's `VaultController`): once the
  connection becomes usable (on, repository, token) -- or a test succeeds
  before any sync -- one non-blocking forced fetch starts, through the same
  coordinator gate; its progress and answer show in Settings -> Vault's
  status; TrainingModel reloads the cached projection when it ends.
- **Habits card on Today** (TrainingCore `HabitsCardModel`, AppearanceKit
  card id `habits`): the ladder step ("Step 2 of 6"), the active habits
  with today's on/off ticks (through the existing recorder, A42), the
  day's progress ("1 of 2 done today") and each habit's 14-day window, the
  next step and what unlocks it, and a tap-through to the full ladder. It
  shows whenever the plan has a ladder, right after the training card
  (whose top row is the check-in). It replaces the `habitsToday` card id,
  so it joins every stored layout visible.
- **Race chip** (TrainingCore `raceChip(from:)`): the next race of any
  priority with its letter, and the season's main race (hero, else A) as a
  second line when that is a later race. Season and Race screens are
  pinned by tests for B races and races before the first phase.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None archived. `vault-connection` (from `add-vault-connection`) and
`training-today` / `training-season-view` (from
`add-training-today-and-plan` / `add-season-phase-race-screens`) are not
archived yet; this change adds requirements to them. It replaces two
sentences of `training-today`'s "Habits, the next race and the weekly note
are shown without controls": the habits card no longer hides when the day
expects nothing, and the chip is no longer limited to A or hero races.
Their archive must fold these together.

## Non-goals

- Ticking a habit the plan does not expect that day (the vault decides
  what is expected; the phone never computes it).
- Starting, pausing or reordering ladder steps from the phone (a desk
  decision).
- Any change to the projection contract or to the vault.

## Impact

- VaultKit: new `VaultSetupRefresh.swift` (+ `VaultSyncInputs.isUsable`),
  `VaultSetupRefreshTests`.
- TrainingCore: `ProjectionStore.refresh(via:inputs:force:)`; new
  `ViewModels/HabitsCardModel.swift`; `HabitRowModel.isScheduledToday` /
  `notTodayText`; `RaceChipModel` priority fields and `MainRaceLineModel`;
  six strings in both `.lproj` tables and `TrainingKey`; tests
  (`SetupRefreshTests`, `TodayBuilderTests`, `CheckInBuilderTests`,
  `SeasonPhaseRaceTests`).
- AppearanceKit: `TodayCardID.habits` replaces `habitsToday`;
  `TrainingLayoutTests`, `AppShellTests`.
- App: `VaultController` (setup fetch, `isSyncingPlan`,
  `lastSetupReport`, `isRefreshAllowed`), `AppEnvironment` (wires it),
  `VaultSettingsView` (status row), `TodayView`, `TrainingTodayCards`
  (`HabitsTodayCard`, `RaceCountdownChip`), `LayoutCardInfo`; six app
  strings in `Localizable.xcstrings`.

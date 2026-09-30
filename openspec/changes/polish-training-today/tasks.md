Every task ends with CI green: `swift test` for every package, the
design-token lint, the app and widget `xcodebuild`, and the `localization`
job. Every new `.swift` file starts with a header comment saying why it
exists and what depends on it. All new user-facing text is in English and
Czech. **Fixtures are synthetic** (the vault example's 2030 season ids);
never a token, the vault repository's name or real vault data. Branch
`mlcousek/today-habits-and-races`, on `main` `e2d871a`. Relative size:
S / M / L.

## 1. Setup fetch (S)

- [x] 1.1 Verify the review finding: `VaultController` settings actions only called `reload()`; the first fetch waited for a foreground (design D1).
- [x] 1.2 VaultKit `VaultSetupRefresh` (+ `VaultSyncInputs.isUsable`) and `VaultSetupRefreshTests`: the Settings order fetches once, not before usable, switch back on, coalesced follow-up, test before/after a sync, reset.
- [x] 1.3 TrainingCore `ProjectionStore.refresh(via:inputs:force:)`, used by the foreground and the setup fetch.
- [x] 1.4 `SetupRefreshTests`: repository -> token -> switch on -> exactly one request -> the cached projection loads (not "Fetching your plan..."); the refresh step respects the gate.
- [x] 1.5 App: `VaultController` requests the setup fetch after each settings action and a successful test, runs it unstructured, exposes `isSyncingPlan` / `lastSetupReport`; `AppEnvironment` wires `isRefreshAllowed`; Settings -> Vault shows the progress and the answer.

## 2. Habits card (M)

- [x] 2.1 TrainingCore `HabitsCardModel` / `habitsCard(on:)`; `HabitRowModel.isScheduledToday` / `notTodayText`; strings in both `.lproj` tables and `TrainingKey`.
- [x] 2.2 Tests: step, rows, ticks only on expected habits, day progress (vault count and the phone's tick), next step with the gate and with "Gate met", a day without expected habits, no ladder; Czech.
- [x] 2.3 AppearanceKit `TodayCardID.habits` replaces `habitsToday` after `trainingDay`; test that it joins a stored layout visible and the retired id is kept unrendered.
- [x] 2.4 App: `HabitsTodayCard` (header with the step and a chevron to the ladder, progress bar, rows with ticks, next-step row), `TodayView` availability and rendering, `LayoutCardInfo`; app strings.

## 3. Races (S)

- [x] 3.1 `raceChip(from:)`: the next race of any priority, priority fields, the main race line; tests (B, C, hero next, A made main).
- [x] 3.2 `RaceCountdownChip`: the priority letter as text, the second line, opens the race.
- [x] 3.3 `SeasonPhaseRaceTests`: two B races before the first phase -- gap, markers, lanes, race screen, chip.

## 4. Verification

- [x] 4.1 `openspec validate polish-training-today --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`.
- [ ] 4.2 CI green on the PR (Swift compiles only there).
- [ ] 4.3 On the phone: finish the vault setup in Settings and see the plan arrive without leaving the app; the Habits card after the training card; the next B race on the chip with the main race below.

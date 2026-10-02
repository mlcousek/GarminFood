Every task ends with CI green: `swift test` for TrainingCore, the
design-token lint, the app and widget `xcodebuild`, and the `localization`
job. Every new `.swift` file starts with a header comment saying why it
exists and what depends on it. All new user-facing text is in English and
Czech. **Fixtures are synthetic** (the vault example's 2030 season); no
token, repository name, real vault data or personal health history in
strings, fixtures or docs. Branch `mlcousek/daily-checkin-and-pain-mode`
on `main`. Nothing is persisted in a new file (no `StoreCatalog` entry):
the reminder times are four UserDefaults keys, pain mode is derived.
Relative size: S / M / L.

A box is ticked when the code was written and read back against its call
sites and tests; nothing here was compiled locally (no Swift toolchain),
so 6.2 and 6.3 stay open until CI and the phone have said so.

## 1. Contract (M)

- [x] 1.1 Re-mirror all four vault contract fixtures verbatim from the vault's main branch (a grep for names, repositories, tokens and real dates first; compared by blob hash); update the fixtures' `CONTRACT.md` for the 2026-09-30 and 2026-10-01 contract.
- [x] 1.2 `Projection.days` (day skeletons: lossy, sorted, a planned or repeated date dropped; read with `plan: null` too).
- [x] 1.3 `Athlete.painMode` (`Contract/Pain.swift` `PainMode`, `PainModeReason`): tolerant.
- [x] 1.4 `DayFuel`: `kind` gains `daily`; `fastingReasons`, `load`, `plannedMin`, `rules`; `isCarbLoad` is the only carb-load test (`FuelFormatter.dayLine`, `DayFuelTargets`, `RacePrepMath`).
- [x] 1.5 The 2026-10-01 additions the app does not use yet (`athlete.gate`, `week.actual` load fields, `unplanned[].flag`, `feedback.pains`, `done.manual`, `source`/`matchedBy` `manual`, `notices`, habit `streak`/`history`/`adherence`) are ignored or unknown, never an error; `test.gate` and `session.done` events read as `.other`; `PlanEditPolicy.noteOnlyRules` keeps the session pain notes from offering a rule override.

## 2. Every day works (M)

- [x] 2.1 `TrainingSnapshot.skeletonDays`, `day(_:)`, `allDays`; `CheckInOverlay.applying(to:)` lays the phone's light and pain over skeletons too.
- [x] 2.2 `checkInRow(on:)` on every date (written, skeleton, no plan, outside the file); the empty states keep the day's light and carb-load line.
- [x] 2.3 Habits: `habits(on:)`, `habitsCard(on:)`, `habitDone`, the evening reminder read `day(_:)`.
- [x] 2.4 Plan: `dayRow`, the month `cell`, `WeekAgendaModel.unwrittenDays` (app: `WeekAgendaView`).
- [x] 2.5 `TrainingRewardFacts.build` counts skeleton days; `fuelTargets(on:)`, `fastingPausedDays`, `rewardSignals` no longer need a plan (`TrainingNutritionBridge`).

## 3. Pain mode (M)

- [x] 3.1 `Plan/PainModeState.swift` (`resolve`: the vault's word, else the phone's unread answer above 0) and `CheckInOverlay.unconfirmedPainDates`; `TrainingSnapshot.painMode`.
- [x] 3.2 Builders: `PainStepModel.isPainMode` / `opensExpanded` / `somethingHurtsTitle`; `painLine` and `painTags` only in pain mode.
- [x] 3.3 App: `PainStepView` draws the "Something hurts?" link outside pain mode; `TrainingModel.isPainMode`; the Control hand-off to Today only in pain mode (`AppEnvironment`).
- [x] 3.4 Strings: `painSomethingHurts` in `TrainingKey` and both `.lproj` tables.

## 4. Reminders (M)

- [x] 4.1 `TrainingReminderPlanner`: a check-in reminder on every day without a light (no plan needed), the short body and the pain-mode body; `TrainingReminderTimes` (clamped, 04:05 / 20:10 by default).
- [x] 4.2 `TrainingModel.reminderTimes` / `setReminderTimes` (four UserDefaults keys), one replan at a time; the 7-day window.
- [x] 4.3 `NotificationScheduler`: the request identifier carries the fire time, so a changed time replaces the pending requests.
- [x] 4.4 `NotificationSettingsView`: two time pickers under the training switch; footer text; app strings (EN + CS) in `Localizable.xcstrings`.

## 5. Tests (M)

- [x] 5.1 `DailyCheckInTests`: skeletons and pain mode on both fixtures, tolerance, the lookup, the check-in / habits / plan / reward facts outside the written weeks and without a plan, pain mode on and off and its two ends, the reminders and the owner's times.
- [x] 5.2 The golden check of the example's fuel on every day and the gram targets (`add-winter-arc-nutrition-and-rewards` task 5.3, ticked there).
- [x] 5.3 Goldens that change with the fixtures: `HubEventTests` (31 lines, `.other` types), `CheckInBuilderTests` (reminders every day, a row outside the plan), `ProjectionDecodingTests`, `PlanBuilderTests`, `TodayBuilderTests`, `PlanEditingTests`, `PainTests`, `TrainingStatsTests`, `SeasonPhaseRaceTests`, `TrainingRecorderTests` -- each re-read against the new fixtures.

## 6. Verification

- [x] 6.1 `openspec validate add-daily-checkin-and-pain-mode --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`.
- [ ] 6.2 CI green on the PR (Swift compiles only there).
- [ ] 6.3 On the phone: a check-in on a rest day and in an unwritten week; with pain mode off no pain step, "Something hurts?" opens it and a score above 0 brings the pain line back; a Control check-in stays where the app was while healthy; the check-in reminder on a rest day, at a changed time; the Today fuel summary and "fasting paused" on a day outside the written weeks.

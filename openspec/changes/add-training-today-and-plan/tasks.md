Every task ends with CI green: `swift test` for every package (TrainingCore
included from task 2.1), the design-token lint, the app and widget
`xcodebuild`, and the `localization` job. Every new `.swift` file starts
with a header comment saying why it exists and what depends on it. All new
user-facing text is in English and Czech (Czech plural forms for counts).
**Fixtures are synthetic**: the vault's contract fixtures (themselves
generated from a synthetic season) and app-authored mutations of them;
never a copy of real vault data. Branch
`mlcousek/add-training-today-and-plan-wN`, one PR per wave. Relative size:
S / M / L.

**Order**: starts after `add-vault-connection` wave 1 (VaultKit) and
`rebrand-to-jirkas-arc` wave 1 (experience shell) have merged. The
projection v1 contract is final (the vault's `add-training-plan-model`);
**the last wave merges only after group 1 has mirrored the vault's contract
fixtures**.

## 0. Owner decisions (before wave 4)

Each has a proposed default; unanswered ones are built as the default and
marked *defaulted, owner may override*.

- [ ] 0.1 Training Today default: summary compact, meals expanded (default) (design D7). *Defaulted, owner may override.*
- [ ] 0.2 Plan tab opens on Week (default) or Month (D10). *Defaulted, owner may override.*
- [ ] 0.3 Stale after 24 h without a successful sync (default) (D5). *Defaulted, owner may override.*
- [ ] 0.4 Race chip: the next race with priority A or `hero: true` (default), or any priority (D7). *Defaulted, owner may override.*
- [ ] 0.5 Training-day time zone: the projection's `athlete.tz` (default, matches the contract's dates) or the device's (D6). *Defaulted, owner may override.*

## 1. Contract mirror (the vault's final projection v1)

- [x] 1.1 When the vault publishes them, copy `scripts/fixtures/hub/contract/projection.v1.example.json` and `projection.v1.minimal.json` **verbatim** into `ios/TrainingCore/Tests/TrainingCoreTests/Fixtures/Contract/vault/`, with `CONTRACT.md` (contract version 1, date copied, source change `add-training-plan-model`; no vault path or repository name). Before committing, grep both for the owner's name, handle and any real race or phase name; the vault guards this too, but this repository is public.
- [x] 1.2 Golden tests: both fixtures decode with zero `DecodeIssues`; every field in design D4 is asserted against the example's values; the minimal fixture yields the "No active plan" states on Today and Plan. Replace the provisional hand-written example from task 2.3 with the vault's and delete it.
- [x] 1.3 Check the models against the fixtures for the details the contract's prose leaves open, and record each answer, dated, in design.md: the schedule-kind spelling (`weeklyCount` vs `weekly_count`; both accepted, D3); which week a Sunday `aiNote` is attached to (D7); whether `days[].habitsDone` and `targets.hrMin` (being added to v1) are present; `targets.zone`'s case (`Z2`).
- [x] 1.4 Re-run the golden builder tests on the mirrored example (Today for a fixed date, a week, a month, a detail, the ladder); fix any screen that loses information. Re-mirror whenever the vault changes its fixtures (additive changes only within v1).

## 2. Wave 1 — TrainingCore contract layer (L)

- [x] 2.1 `ios/TrainingCore/Package.swift` (swift-tools 5.10, iOS 17 + macOS 14, depends on VaultKit and GarminKit, `defaultLocalization: "en"`, `resources: [.process("Resources")]`, test target `exclude: ["Fixtures"]`); `build.yml` step "Run TrainingCore unit tests"; `project.yml` package (app target only); `tools/check-localizations.mjs` `PACKAGES` gains `TrainingCore`.
- [x] 2.2 `OpenEnum`, `LossyArray`/`LossyMap` + `DecodeIssues`, `LocalizedText` (string or object; cs → cz → en → first), `LocalDate`, `ISOWeek`, `ClockTime`. Tests: unknown values, dropped elements recorded, language fallback, plain strings, W53 and year boundaries.
- [x] 2.3 `ProjectionHeader` + the final v1 models of design D3 (season, phases, races with prep, the selected-phase `plan`, weeks with `phaseId`/`actual`/`aiNote`, seven days with `fuel`/`unplanned`/`habitsDone`, sessions, options, `Done`, `ActivityRef`, workouts with steps and measures, test history, habits with every schedule kind, reserved fields); identity-only required. Until task 1.1, a hand-written synthetic example following the contract section field for field, marked provisional in `CONTRACT.md`. Edge fixtures as mutations of it (D13): unknown fields and enums, lossy, `schemaVersion: 2`, not a projection, a `supersededBy` hint, snake_case schedule kinds.
- [x] 2.4 `ProjectionStore`: `validate(bytes)` (throws for invalid and unsupported major), launch decode of cached bytes off the main actor, `ProjectionState`, freshness from `asOf` (`.behind`) and the last successful sync (`.stale`, per 0.3), never `generatedAt`. Tests with an in-memory `VaultTransport` and a real `ConditionalFileSync` on temp files: bad file keeps last good; v2 keeps last good and reports `unsupportedMajor`; offline cold start; old `generatedAt` with a fresh sync is not stale.
- [x] 2.5 `TrainingDay.resolve` (in `athlete.tz` per 0.5, device fallback), `HRZoneMapper` (`Z2`/`z2`, `hrZones: null`, `hrMin`/`hrMax` ranges). Tests: boundary hour, 00:40, other dates, DST change days, zone edges.

## 3. Wave 2 — View models and formatting (L)

- [x] 3.1 `TrainingSnapshot`, `EffectivePlan` + empty `PendingOverlay`, `TrainingCapabilities` (all false) (D8).
- [x] 3.2 Formatters: targets ("12 km · ≤144 bpm (Z2)", "129–144 bpm", "Z2 · 129–144 bpm", time), every step kind (warm-up, active, interval with times and recovery, recovery, cool-down, exercise with sets/reps/tempo/load, hold with side, rest), fuel (carb load, carbs per hour), countdowns ("today", "tomorrow", "in %lld days" plural, "about"), schedules (all five kinds), statuses, test values with units. `en`/`cs` `.lproj` + `.stringsdict`. Tests in both languages.
- [x] 3.3 `TodayTrainingModel` (sessions, option cards with highlight reason incl. `done.option: null`, fuel lines, test/race badges, every D11 state), `HabitRowModel` (`.displayOnly`, `window14: null`, `habitsDone`), `RaceChipModel` (per 0.4, `dateApprox`), `WeeklyNoteTeaserModel` (current week's `aiNote`, else the latest earlier one). Golden tests for fixed dates.
- [x] 3.4 `WeekAgendaModel` (phase title by `phaseId`, outline row, targets vs `actual`, seven days, unplanned rows, fuel, outline-only and out-of-season weeks, paging across the season), `MonthCalendarModel` (42 cells, Monday first, week column with targets, glyph states incl. unplanned, overflow, light, race flags from `season.races`, today), `SessionDetailModel` (option pre-selection, workout steps, why order, done with "Option not identified", fuel, test result vs `tests[].history`, race day), `HabitLadderModel` (`recordedDays`, `gateMet` only on the highest active step). Golden tests.
- [x] 3.5 AppearanceKit: `TodayCardID` cases `raceCountdown`, `trainingDay`, `habitsToday`, `weeklyNote`; `trainingDay` variants `options`/`compact`; `LayoutCatalog.today(for: .training)` in the D7 order with the summary compact by default (per 0.1); `LayoutPreset.training`. Tests: training golden order; food-first catalog unchanged; rule-3 insertion into a stored food layout puts the four cards after the day switcher and keeps every food card's position and variant.
- [x] 3.6 AppearanceKit: readiness colours (`success`, `warning`, `danger`) pairwise distinct in every resolved palette × scheme × contrast (D9); fit any failing theme's roles; record which themes needed it. No theme needed fitting: an offline OKLab check of every success/warning/danger set (Classic, Legible, Forest, High Contrast; normal and increased contrast) gives a minimum ΔE of 0.12 against the 0.10 threshold (`ContrastPolicy.minimumReadinessDistance`); `TrainingLayoutTests` is the authority in CI.

## 4. Wave 3 — Today (M)

- [x] 4.1 `VaultServices`: owns `ProjectionStore`, passes its validator to `ConditionalFileSync`; `GarminFood/Training/TrainingModel.swift` (`@MainActor @Observable`) holds the snapshot and rebuilds it after each refresh and on day change.
- [x] 4.2 `ContentView`: the experience input becomes the vault connection switch; remove the "Preview training shell (testing)" toggle and its preference key.
- [x] 4.3 Today cards: `TrainingDayCard` (session blocks, `OptionCard` ×3, a single card for sessions without options, fuel lines, compact variant, every D11 state), `HabitsTodayCard`, `RaceCountdownChip`, `WeeklyNoteCard` + full-note sheet; new arms in `TodayView`'s switch; availability rules (hidden when their data is absent); `LayoutCardInfo` titles, icons and variant names.
- [x] 4.4 Option cards per D9: token tints only, letter + shape, larger shapes with Differentiate Without Color, stacked at accessibility text sizes, one VoiceOver element each with spoken meaning; the watch line only when `watch` is non-null.
- [x] 4.5 Training cards follow the day switcher (`TrainingDay.resolve`); tapping an option pushes the session detail at that option.
- [x] 4.6 Czech strings for every new key; `node tools/check-localizations.mjs --scan` and `sh tools/lint-design-tokens.sh` pass.

## 5. Wave 4 — Plan tab (L)

- [x] 5.1 `PlanTabView`: Week · Month segmented control (remembered, default per 0.2), freshness line (`asOf`, last sync), D11 states, toolbar button to the habit ladder; consumes the router's pending date.
- [x] 5.2 `WeekAgendaView` with paging across the season.
- [x] 5.3 `MonthCalendarView` (grid, week column, glyph styles distinguishable without colour, race flags, day sheet with unplanned rows), swipe between months.
- [x] 5.4 `SessionDetailView` (option picker, targets, steps, why, origin once published, done, fuel, test result vs history, race day).
- [x] 5.5 `HabitLadderView`.
- [x] 5.6 Race chip → Month at the race date; `garminfood://plan?date=` → the week containing it.
- [x] 5.7 Czech strings; checker and lint pass.

## 6. Close-out

- [x] 6.1 Group 1 done (vault fixtures mirrored, decoding and builders green on both).
- [x] 6.2 `CLAUDE.md` architecture section: TrainingCore's role, its boundary rule, and "the phone never computes what the vault computes".
- [ ] 6.3 CI green on every wave PR; `openspec validate add-training-today-and-plan --strict` passes.

## 7. On-device verification (owner)

Device checks use the vault's synthetic `projection.v1.example.json`,
committed by the owner to a test branch of his vault, with the branch field
of Settings → Vault pointed at it; then the real branch once the vault
publishes his plan.

- [ ] 7.1 Connection off: the app is food-first, exactly as before. Turn it on: four tabs; Today shows the training cards above his existing food cards in his order.
- [ ] 7.2 Today on a traffic-light day: three option cards with labels and targets in zones; a done ride on a run day marks R; a done run shows "Done" with no option marked. Check with Differentiate Without Color, at the largest text size, and with VoiceOver.
- [ ] 7.3 Step the day switcher to tomorrow and yesterday: the training card follows. At 00:40 (or by changing the phone's clock), today's card still shows the previous training day.
- [ ] 7.4 Habits card (including a "not recorded yet" habit), race chip (tap → month with the flag), weekly note teaser and full sheet, a carb-load day's fuel line.
- [ ] 7.5 Log a food from "Log again" below the training cards: two taps, committed, summary updates.
- [ ] 7.6 Plan → Week: phase title, targets vs `actual`, unplanned rows, paging into outline weeks and out of the season. Month: glyph states, week numbers, race flags, day sheet, detail. Detail: options, steps, zones, why, done, fuel, a test result against its history.
- [ ] 7.7 Airplane mode cold launch: the cached plan appears at once. A day later without syncing: "Plan as of …". Push a `schemaVersion: 2` file to the test branch: the loud update message, last good still shown. Push invalid JSON: the quiet notice, last good shown.
- [ ] 7.8 The fiancée's standalone install: unchanged (food-first, three tabs, no training cards in the layout editor).

Every task ends with CI green: `swift test` for TrainingCore, the
design-token lint, the app and widget `xcodebuild`, and the
`localization` job. Every new `.swift` file starts with a header comment
saying why it exists and what depends on it. All new user-facing text is
in English and Czech (Czech plural forms for counts). Fixtures are the
vault's synthetic contract fixtures and small mutations of them. One
branch, `mlcousek/add-season-phase-race-screens`, shared with
`add-training-stats` (committed after this change). Relative size: S / M
/ L.

## 0. Owner decisions

Each has a proposed default; unanswered ones are built as the default and
marked *defaulted, owner may override*.

- [ ] 0.1 Today's race chip opens the race screen (default) or, as before, the month at the race day (design D2). *Defaulted, owner may override.*
- [ ] 0.2 Season as a third Plan segment, Week · Month · Season (default), or a fifth tab (D2). *Defaulted, owner may override.*
- [ ] 0.3 A week's run target: the written week's `targets.runKm`, else the outline row (default, the same number Plan -> Week shows), or the outline first like the vault's planner (D4). *Defaulted, owner may override.*
- [ ] 0.4 Carb-load grams outside the plan's window: g/kg x the plan's `athlete.weightKg` (default, the contract's formula and constant) or the phone's latest weigh-in (D5). *Defaulted, owner may override.*
- [ ] 0.5 "Today" on the timeline: the current training day (default, as the race chip) or the file's `asOf` (D3). *Defaulted, owner may override.*

## 1. TrainingCore -- text (S)

- [x] 1.1 `Formatting/SeasonText.swift`: `DateText.dayMonthYear`, `longRange`, `monthTick`; `NumberText.clock(_:plus:)` ("+1 d" past midnight), `pace(minutesPerKm:)`, `climb`, `percent`; names for phase kind and status, race priority, checkpoint aid.
- [x] 1.2 51 `TrainingKey` cases with en/cs `Localizable.strings` entries and seven plural keys in both `.stringsdict` files (weeks, days ago, about days ago, starts in, days left, days before, days after); `node tools/check-localizations.mjs` passes.

## 2. TrainingCore -- models and builders (L)

- [x] 2.1 `SeasonTimelineModel` + `PlanBuilder.seasonTimeline()`: fractions of the season's period, month ticks, bands (kind, status, weeks, selected, current, clamped), gaps "No phase planned", races (priority, hero, approximate, unanchored, countdown incl. past, distance, clamped), `SeasonLanes.assign`, today's mark, the "No season yet" state (D3).
- [x] 2.2 `PhaseRamp.series`/`totals` and `PlanBuilder.phaseDetail(id:)`: header and progress, goals and rules for the selected phase only (restricted text otherwise), ramp rows (the written week's target else the outline's per 0.3; the vault's `actual`; "Not in the app's window"), key sessions with dates, tests in the phase, races, recap with summary and judged test lines (D4); `defaultPhaseID()`.
- [x] 2.3 `RacePrepMath` and `PlanBuilder.raceDetail(id:)`: countdown, priority, anchor or unanchored, stub, start and cutoff, checkpoint rows (clock times, buffers, section paces from the last checkpoint with a target, heart-rate caps), fuel lines and totals, carb-load rows (plan grams, else weight formula per 0.4, else none), gear (mandatory first), taper, race-day sessions, report (D5); `nextRaceID()`.
- [x] 2.4 `SeasonPhaseRaceTests`: golden on the example fixture (today = `asOf`) for all of the above, the mutations (race outside the season, widened phase for recap test lines, weight 72 kg without the day's fuel, no weight, checkpoint without target), Czech for our own strings and numbers; no assertion spells CLDR month abbreviations or list spacing.

## 3. App (M)

- [x] 3.1 `PlanTabView`: `PlanMode.season`, the Season segment, `RaceDetailView` pushed for `AppRouter.pendingRaceID`.
- [x] 3.2 `SeasonTimelineView`: header, the axis (track, bands, gaps, ticks, flags on lanes, today's line; one VoiceOver element), phase and race rows opening their screens.
- [x] 3.3 `PhaseDetailView`: header with progress, goals, rules, recap, weeks (target outlined, run filled, legend), key sessions -> session detail, test results, races -> race screen.
- [x] 3.4 `RaceDetailView`: header, stub, race plan (checkpoints with a flagged negative buffer), race fuel, carb load with "Open food log" (D6), gear, taper, race-day session; anchoring phase link.
- [x] 3.5 `AppRouter.openRace(id:)` and `pendingRaceID` (cleared when the experience leaves training); Today's race chip calls it (per 0.1).
- [x] 3.6 23 app catalog keys with Czech in `Localizable.xcstrings` (inserted as text, CRLF kept, valid JSON); `node tools/check-localizations.mjs --scan` and `sh tools/lint-design-tokens.sh` pass.

## 4. Close-out

- [x] 4.1 `openspec validate add-season-phase-race-screens --strict` passes.
- [ ] 4.2 CI green on the branch's PR (first compile of this change's Swift).

## 5. On-device verification (owner)

With the vault's synthetic example on a test branch of the vault (Settings
-> Vault -> branch), then the real plan.

- [ ] 5.1 Plan -> Season: the phases, the gap after the last phase, the races on lanes, today's line; Dynamic Type at the largest size; VoiceOver reads the timeline summary and each row.
- [ ] 5.2 A phase: header progress, goals and rules only on the current phase, weeks with target vs run, a key session opens its detail, a closed phase's recap.
- [ ] 5.3 A race: countdown, checkpoint table, buffers, paces, fuel totals, carb load, gear, taper; an unanchored race and a race without prep.
- [ ] 5.4 Today's race chip opens the race screen; "Open food log" on a carb-load day shows Today on that date with the training card's carb-load line.
- [ ] 5.5 The fiancée's food-first install: unchanged (no Plan tab).

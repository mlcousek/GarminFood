Every task ends with CI green: `swift test` for TrainingCore, the
design-token lint, the app and widget `xcodebuild`, and the
`localization` job. Every new `.swift` file starts with a header comment
saying why it exists and what depends on it. All new user-facing text is
in English and Czech (Czech plural forms for counts). Fixtures are the
vault's synthetic contract fixtures and small mutations of them. Branch
`mlcousek/add-season-phase-race-screens`, after that change's commits.
Relative size: S / M / L.

## 0. Owner decisions

Each has a proposed default; unanswered ones are built as the default and
marked *defaulted, owner may override*.

- [ ] 0.1 Statistics from a Plan toolbar button and the Phase screen (default) or as a fourth Plan segment (design D7). *Defaulted, owner may override.*
- [ ] 0.2 Default scope: the current phase (default) or the whole season (D2). *Defaulted, owner may override.*
- [ ] 0.3 Adherence = done / (done + missed + skipped), today's planned session not counted until the vault marks it (default), or counting it (D3). *Defaulted, owner may override.*

## 1. TrainingCore -- text (S)

- [x] 1.1 14 `TrainingKey` cases with en/cs `.strings` entries and the plural "%lld sessions" in both `.stringsdict` files; `node tools/check-localizations.mjs` passes.

## 2. TrainingCore -- models (M)

- [x] 2.1 `StatsScope`, `StatusCounts` (due, adherence), `PlanBuilder.defaultStatsScope()` and `stats(scope:)` with the scope's range, title and the no-plan state (D1, D2).
- [x] 2.2 Adherence per week and per phase from the file's statuses; summary; weeks of the scope not in the file listed ("Not in the app's window"), never counted (D3).
- [x] 2.3 The G/A/R split of done traffic-light sessions with "Option not identified" (D4).
- [x] 2.4 Volume vs target via `PhaseRamp` with differences in km and % and the totals summary (D5).
- [x] 2.5 Test cards: per-measure points, latest, first -> last, verdict; `TestAsymmetry` pairs `_l`/`_r` with |L - R| / max(L, R) per date and latest (D6).
- [x] 2.6 `TrainingStatsTests`: golden on the example fixture in English and Czech, counts equal to the vault's `actual`, a `skipped` mutation, the ramp equal to the Phase screen's, asymmetry arithmetic, the no-plan states.

## 3. App (M)

- [x] 3.1 `TrainingStatsView`: scope picker, header with notices, adherence card (stacked weekly bars, week and phase rows, outside weeks), option split card (proportional bar with letters, badge rows), volume card (grouped target/run bars, rows, summary), test cards (line chart, verdicts, asymmetry history); Theme tokens only; charts hidden from VoiceOver with rows as the accessible form (D3-D7).
- [x] 3.2 Entry points: a Statistics toolbar button on Plan (current phase, per 0.1/0.2) and a Statistics link on the Phase screen (that phase).
- [x] 3.3 13 app catalog keys with Czech in `Localizable.xcstrings` (inserted as text, CRLF kept, valid JSON); `node tools/check-localizations.mjs --scan` and `sh tools/lint-design-tokens.sh` pass.

## 4. Close-out

- [x] 4.1 `openspec validate add-training-stats --strict` passes.
- [ ] 4.2 CI green on the branch's PR (first compile of this change's Swift).

## 5. On-device verification (owner)

- [ ] 5.1 Plan -> Statistics on the synthetic example: adherence bars and rows, the outside weeks on Whole season, the G/A/R bar, volume bars, the calf test's asymmetry.
- [ ] 5.2 A phase's Statistics link opens that phase's scope.
- [ ] 5.3 Largest Dynamic Type, VoiceOver (rows read their numbers), Differentiate Without Color (letters and shapes still tell G/A/R apart).

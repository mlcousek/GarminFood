Every task ends with CI green: `swift test` for every package, the
design-token lint, the app and widget `xcodebuild`, and the `localization`
job. Every new `.swift` file starts with a header comment saying why it
exists and what depends on it. All new user-facing text is in English and
Czech. **Fixtures are synthetic** (the vault example's 2030 season); no
token, repository name, real vault data or personal health history in
strings, fixtures or docs. Branch `mlcousek/checkin-pain-score`, on
`mlcousek/today-habits-and-races` (#114). Relative size: S / M / L.

## 1. Contract (M)

- [x] 1.1 Re-mirror all four vault contract fixtures verbatim from the vault's main branch (a grep for names, repositories, tokens and real dates first); update `CONTRACT.md`.
- [x] 1.2 `Contract/Pain.swift`: `PainSite` (unknown -> `other`), `PainEntry` (tolerant decode, integer-when-whole encode, score and note bounds).
- [x] 1.3 `HubEvent`: `MorningCheckInPayload.pains`, encode (`null` when not asked), decode, validate; header comment (case-sensitive key order).
- [x] 1.4 `Projection.Day.pains`, lenient and lossy.
- [x] 1.5 `CheckInOverlay`: pains per day, keep without / replace with (`[]` included); `EffectivePlan` applies them.

## 2. Models (M)

- [x] 2.1 `ViewModels/PainModels.swift`: `PainDraft` (rounding, add/remove, notes, default sites), `PainStepModel`, `painLine`, `painTags`.
- [x] 2.2 `CheckInRowModel.pain`, `TodayTrainingModel.painLine`, `DayRowModel.painTags`.
- [x] 2.3 Strings in `TrainingKey` and both `.lproj` tables (sites, score, tag, line, step).

## 3. Tests (M)

- [x] 3.1 `HubEventTests`: the app golden gains `"pains":null`; new golden `checkin-pains.v1.app.jsonl` (list, `[]`, escaped note; accepted by the vault's `validateEvent`); bounds; unknown site; the vault example's seq 24.
- [x] 3.2 `PainTests`: decoding tolerance, replace/keep in the overlay and over the projection, draft, default sites, the step (open, folded, payload, delivery), the card line and the Plan tags, Czech ("5,5/10").
- [x] 3.3 Goldens that change with the fixtures: `ProjectionDecodingTests` (ack 24, W43 `pain-high`), `PlanBuilderTests` (W43 rule notes).

## 4. App (M)

- [x] 4.1 `CheckInRowView`: the pain step (rows with a half-step slider, add another site, note for other, remove, Not now, Save); the card's pain line.
- [x] 4.2 `TrainingModel.recordPain`; `TodayView` wires Save.
- [x] 4.3 Plan: `DayRowView` shows the pain tags (week agenda and day sheet).
- [x] 4.4 Controls stay light-only; `TrainingEventsService.onControlCheckIn` + `AppEnvironment` bring Today's today forward.

## 5. Verification

- [x] 5.1 `openspec validate add-checkin-pain-score --strict`, `node tools/check-localizations.mjs --scan`, `sh tools/lint-design-tokens.sh`.
- [ ] 5.2 CI green on the PR (Swift compiles only there).
- [ ] 5.3 On the phone: a light, then Save at 0; edit the score later that day; a Control check-in opens Today with the pain step; the tags in Plan; the vault's next projection shows the same `day.pains`.

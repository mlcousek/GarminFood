## 1. Shared day ledger (Gamification, pure)

- [x] 1.1 `Features/Journeys/DailyLedger.swift` (sealing per design D1; also used by records). Tests: fold-once, open-day recompute, first-run sealing, late log for yesterday.

## 2. Journeys

- [x] 2.1 `JourneyCatalog.swift`: protein stages, water milestones + Podolí percentage, road-trip route with stage 2, passport milestones; conversions documented in comments.
- [x] 2.2 `JourneysEvaluator`: per-day values from signals, weight-based km per sealed day, milestone crossings (multiple per day), stage rollover.
- [x] 2.3 `JourneysStore` (Optional fields, quarantine helpers).
- [x] 2.4 Replace the stub `JourneysFeature`: grants `journeys.<id>.<milestone>`, badges (design D7), one combined moment, summary; expose `journeys()`.
- [x] 2.5 Tests: conversions, Sněžka crossing, two milestones in one day = two grants one moment, Podolí percentage, fallback weight, missing-data days, store decode.

## 3. Personal records

- [x] 3.1 `Features/Records/PersonalRecordCatalog.swift`: the 8 records (design D6) with metric functions and thresholds.
- [x] 3.2 `RecordsEvaluator`: live vs closed-day evaluation, strict improvement, warm-up (7 qualifying days), silent baseline, streak metric, fast-gap metric (≤ 48 h).
- [x] 3.3 `RecordsStore` (current, previous, qualifyingDays, last 10 PRs).
- [x] 3.4 Replace the stub `PersonalRecordsFeature`: grants `records.<id>.<day>`, badges, moments, summary; expose `records()`.
- [x] 3.5 Tests: every metric from literal `DaySignals`; protein PR once per day; lowest-sugar on closed day only; off-target ignored; warm-up; first run silent; hidden when data unavailable.

## 4. UI (thin)

- [x] 4.1 `Progress/Slots/JourneysSlotView.swift` + `Progress/Journeys/JourneysView.swift` (milestone path, conversion line; Reduce Motion).
- [x] 4.2 `Progress/Slots/RecordsSlotView.swift` + `Progress/Records/RecordsView.swift` (Garmin-style PR list). VoiceOver, Dynamic Type, dark mode.

## 5. Verify

- [x] 5.1 `openspec validate add-journeys-and-records --strict` passes.
- [ ] 5.2 CI green (`swift test` Gamification; app + widget build).
- [ ] 5.3 On-device check: after first launch, journeys show plausible totals from recent history with one summary moment and records show values with no PR moments; a high-protein day later triggers exactly one PR moment.

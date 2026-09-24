## 1. Catalog and generator (Gamification, pure)

- [ ] 1.1 `Features/WeeklyBingo/BingoTask.swift` + `BingoTaskCatalog.swift` with the 35 tasks in design D2.
- [ ] 1.2 `BingoCardGenerator.generate(week:eligible:previousCard:)` per design D3.
- [ ] 1.3 Tests: determinism, composition, family uniqueness, requirement filtering, previous-week exclusion + relaxation, hard tasks not sharing a line, catalog ids unique.

## 2. Completion and rewards

- [ ] 2.1 `BingoEvaluator`: day/week scope over `SignalsSnapshot` restricted to the card week; sticky completion; unknown id = free.
- [ ] 2.2 Line detection (8 lines, centre free) and reward grants with keys `bingo.line.<week>.<line>`, `bingo.full.<week>`, `bingo.freeze.<week>`.
- [ ] 2.3 Badges per design D6 (`featureEvaluated`, `featureId: "bingo"`, rarity overrides).
- [ ] 2.4 Tests: every task type via literal `DaySignals`; stickiness; outside-week days ignored; rewards once across two runs with a real `RewardLedger`; four corners, X, counters.

## 3. Persistence and feature

- [ ] 3.1 `BingoStore` (12-week cap, Optional fields, quarantine helpers). Tests: round-trip, cap, old-file decode.
- [ ] 3.2 Replace the stub `WeeklyBingoFeature` with the real feature: generate-if-missing, evaluate, emit grants/badges/moments/summary; expose `currentCard()` and `pastCards()` for the UI.

## 4. UI (thin)

- [ ] 4.1 `Progress/Slots/BingoSlotView.swift`: mini grid, lines, days left.
- [ ] 4.2 `Progress/Bingo/BingoCardView.swift` + square sheet + past-cards pager; line-stroke animation (Reduce Motion: fade); VoiceOver labels; Dynamic Type; dark mode.

## 5. Verify

- [ ] 5.1 `openspec validate add-weekly-bingo --strict` passes.
- [ ] 5.2 CI green (`swift test` Gamification; app + widget build).
- [ ] 5.3 On-device check: a card appears on Monday; logging a fruit ticks "An Apple a Day" if on the card; completing a line shows the BINGO moment once; card unchanged after app relaunch.

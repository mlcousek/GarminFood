## 1. Calendar (Gamification, pure)

- [ ] 1.1 `Features/Seasonal/SeasonalCalendar.swift`: computus + derived dates (design D1). Tests: the 9-year Easter table and all derived dates for 2026/2027.
- [ ] 1.2 `Features/Seasonal/CzechNameDays.swift`: full civil name-day table + folded lookup. Tests: Jiří, Jiri, Jan, Josef, Václav, Martin, Marie, unknown.

## 2. Tags (FoodLogCore)

- [ ] 2.1 `Signals/FoodTag+Seasonal.swift` (tag constants, design D3).
- [ ] 2.2 Fill `Signals/FoodTagRules+Seasonal.swift` with phrases and exclusions.
- [ ] 2.3 `SeasonalTaggerTests` golden cases incl. kapr/kapary, houby/mycí houba, čočka, vosí hnízda, řízek, chlebíček.

## 3. Events and evaluation

- [ ] 3.1 `SeasonalEventCatalog.swift`: the 12 events (design D2) with windows, quests and badges (`event.<id>`, `.limited(eventId:)`, rarity overrides) + collector badges.
- [ ] 3.2 `SeasonalEvaluator`: state per event (upcoming/active/ended), sticky quest progress, completion.
- [ ] 3.3 `SeasonalStore` (Optional fields, current + previous year progress, quarantine helpers).
- [ ] 3.4 Replace the stub `SeasonalEventsFeature`: grants (`event.<id>.<year>`, bonus keys), badges, moments, summary; expose `activeEvents()`, `upcomingEvents()`, `yearOverview()`.
- [ ] 3.5 Tests: window boundaries; Štědrý den variants; Easter both-tags rule; St Martin bonus only on 11 Nov; yearly idempotency; name-day absent path; collector counts.

## 4. UI (thin)

- [ ] 4.1 `Today/Slots/SeasonalBannerSlot.swift`: active (or upcoming) event banner with quest checkmarks.
- [ ] 4.2 `Progress/Slots/SeasonalSlotView.swift` + `Progress/Seasonal/SeasonalEventsView.swift`: this year's events timeline, earned years on badges. VoiceOver, Dynamic Type, dark mode.

## 5. Verify

- [ ] 5.1 `openspec validate add-seasonal-events --strict` passes.
- [ ] 5.2 CI green (`swift test` FoodLogCore + Gamification; app + widget build).
- [ ] 5.3 On-device check: with the device date inside a window (or the next real window — mushroom season is active on 2026-09-24), the Today banner appears; logging "Houbová polévka" advances the quest; Settings → Diagnostics shows no errors.

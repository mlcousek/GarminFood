## 23. Streak engine

- [ ] 23.1 **CARRIED to add-app-shell-and-meal-dashboard 1.2: the pure streak function exists, but days are keyed by capture time with a fixed 04:00 cutoff rather than the entry's logged date.** Implement streak computation as a pure function over the local log history: given the set of logged dates (using the Garmin nutrition-day boundary, design.md D1) and today's date, return the current streak length and whether today already counts.
- [x] 23.2 **DONE (audit 2026-09-16): rolling 7-day grace rule in StreakEngine.swift; the three named edge cases are covered by StreakEngineTests (plus misses exactly 7 days apart).** Implement the one-miss-per-rolling-week grace rule (D2). Write unit tests for the edge cases named in design.md's Risks: two misses in one week, a miss immediately followed by a make-up day, a miss straddling a week boundary.
- [x] 23.3 **DONE (audit 2026-09-16): StreakEyebrow in TodayHeroView shows the at-risk state (dimmed flame, "Log something to keep it") vs safe (gradient flame); at-risk computed in StreakEngine.** Build the flame + count UI on the app's main screen, with a distinct visual state for "streak at risk today" (logged yesterday, nothing yet today) versus "streak safe."
- [x] 23.4 **DONE (audit 2026-09-16): 7-day milestones queued by GamificationEngine and presented by MomentOverlay with animation and haptic. Follow-ups (Reduce Motion gating, no repeat haptic on dismiss) are tracked in add-app-shell-and-meal-dashboard 7.5.** Add a subtle celebratory moment (haptic + brief animation) the first time a new streak milestone is reached in a session (e.g., every 7 days), per config.yaml's Design & UX principles.

## 24. Levels and XP

- [x] 24.1 **DONE (audit 2026-09-16): XPAward table in XPStore.swift (10 per log, +20 streak, +25 goal, +50 challenge); goal status recorded by GamificationEngine.refreshGoalStatus.** Define the XP award table: flat XP per log, larger XP for streak extension and for hitting a day's nutrition goal (from `garmin-sync`'s already-fetched goals).
- [x] 24.2 **DONE (audit 2026-09-16): LevelCurve.xpRequired / level(forTotalXP:), 100 XP base, x1.3 per level.** Define the level curve (thresholds growing roughly geometrically) and implement level-from-XP as a pure function.
- [x] 24.3 **DONE (audit 2026-09-16): level card on Home; level-up moment with animation and haptic via MomentOverlay. A dedicated level screen comes in add-app-shell-and-meal-dashboard 7.2.** Build the level display (current level, progress toward next) and the level-up moment (full animated transition + haptic, per design.md D5 — this is a named requirement, not optional polish).
- [x] 24.4 **DONE (audit 2026-09-16): LevelCurveTests (7) and XPStoreTests (9).** Unit test the XP/level functions directly — no device or UI needed for this half of the feature.

## 25. Challenges

- [x] 25.1 **DONE (audit 2026-09-16): 13 templates in ChallengeTemplates.swift across all three categories, each evaluated locally by ChallengeEngine.progress.** Author the initial 10–15 challenge templates (design.md D4) covering streak-extension, goal-hitting, and variety-seeking, each with a locally-evaluable completion condition against the log history.
- [x] 25.2 **DONE (audit 2026-09-16): one active challenge (within the "one or two"), replaced on completion or when its window elapses (ChallengeStore, GamificationEngine).** Implement challenge rotation: one or two active at a time, replaced on completion or after a time window elapses.
- [x] 25.3 **DONE (audit 2026-09-16): progress card on Home and a completion moment with XP. A full challenges screen comes in add-app-shell-and-meal-dashboard 7.4.** Build the challenge progress UI (progress bar or equivalent) and the completion moment (reward + animation).
- [ ] 25.4 **CARRIED to add-app-shell-and-meal-dashboard 4.4 (four templates untested, two missing incomplete cases).** Unit test each challenge template's completion condition against constructed log histories, not just the happy path.

## 26. Design system

- [ ] 26.1 **CARRIED to add-app-shell-and-meal-dashboard 1.3 (tokens exist, but only in the app target; the widget copies colours by hand).** Define the shared design tokens (color palette supporting light/dark, type scale, spacing scale) used by every screen from this point forward — food-log-core's UI, the progress screen, and the widgets/Controls all draw from the same source rather than each screen improvising.
- [ ] 26.2 **CARRIED to add-app-shell-and-meal-dashboard 10.10 (device check).** Verify Dynamic Type scaling and VoiceOver labels on the streak, level, and challenge UI specifically, since these are the newest and most visually expressive screens.
- [ ] 26.3 **CARRIED to add-app-shell-and-meal-dashboard 7.5 (bounce and pulse still run under Reduce Motion).** Verify Reduce Motion is respected — the celebratory animations in 23.4, 24.3, and 25.3 need a reduced/instant fallback, not just a fast version of the same animation.

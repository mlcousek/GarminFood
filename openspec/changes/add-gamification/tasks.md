## 23. Streak engine

- [ ] 23.1 Implement streak computation as a pure function over the local log history: given the set of logged dates (using the Garmin nutrition-day boundary, design.md D1) and today's date, return the current streak length and whether today already counts.
- [ ] 23.2 Implement the one-miss-per-rolling-week grace rule (D2). Write unit tests for the edge cases named in design.md's Risks: two misses in one week, a miss immediately followed by a make-up day, a miss straddling a week boundary.
- [ ] 23.3 Build the flame + count UI on the app's main screen, with a distinct visual state for "streak at risk today" (logged yesterday, nothing yet today) versus "streak safe."
- [ ] 23.4 Add a subtle celebratory moment (haptic + brief animation) the first time a new streak milestone is reached in a session (e.g., every 7 days), per config.yaml's Design & UX principles.

## 24. Levels and XP

- [ ] 24.1 Define the XP award table: flat XP per log, larger XP for streak extension and for hitting a day's nutrition goal (from `garmin-sync`'s already-fetched goals).
- [ ] 24.2 Define the level curve (thresholds growing roughly geometrically) and implement level-from-XP as a pure function.
- [ ] 24.3 Build the level display (current level, progress toward next) and the level-up moment (full animated transition + haptic, per design.md D5 — this is a named requirement, not optional polish).
- [ ] 24.4 Unit test the XP/level functions directly — no device or UI needed for this half of the feature.

## 25. Challenges

- [ ] 25.1 Author the initial 10–15 challenge templates (design.md D4) covering streak-extension, goal-hitting, and variety-seeking, each with a locally-evaluable completion condition against the log history.
- [ ] 25.2 Implement challenge rotation: one or two active at a time, replaced on completion or after a time window elapses.
- [ ] 25.3 Build the challenge progress UI (progress bar or equivalent) and the completion moment (reward + animation).
- [ ] 25.4 Unit test each challenge template's completion condition against constructed log histories, not just the happy path.

## 26. Design system

- [ ] 26.1 Define the shared design tokens (color palette supporting light/dark, type scale, spacing scale) used by every screen from this point forward — food-log-core's UI, the progress screen, and the widgets/Controls all draw from the same source rather than each screen improvising.
- [ ] 26.2 Verify Dynamic Type scaling and VoiceOver labels on the streak, level, and challenge UI specifically, since these are the newest and most visually expressive screens.
- [ ] 26.3 Verify Reduce Motion is respected — the celebratory animations in 23.4, 24.3, and 25.3 need a reduced/instant fallback, not just a fast version of the same animation.

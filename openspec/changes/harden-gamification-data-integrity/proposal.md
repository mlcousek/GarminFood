## Why

Gamification currently records a confirmed food independently from the
user-visible food-log lifecycle. That makes the local game state vulnerable
to drift when an entry is backdated, deleted, queued and then cancelled, or
created as a multi-ingredient meal preset.

Achievements are intentionally permanent once earned. Deleting a food must
not remove an already-unlocked badge. However, deletion must stop that food
from contributing to reversible, current-state mechanics such as streaks,
daily challenges, retained-history variety, and active challenge progress.

## What Changes

- Introduce an app-owned food-log identity carried through usage history so a
  deleted or cancelled log can remove exactly the matching local usage event.
- Pass the selected nutrition day through the gamification confirmation
  boundary, rather than deriving it from the confirmation timestamp.
- Record one lifetime log per durable food entry, including every ingredient
  of a meal preset, while preserving the existing one-per-preset XP behavior
  unless its product rule is deliberately changed.
- Make lifetime goal-hit accounting idempotent for any previously observed
  date, not only for the most recently observed date.
- Add regression coverage for deletion, queued-entry cancellation, historical
  logging, meal presets, out-of-order goal refreshes, and persisted ledger
  reloads.

## Non-goals

- Revoking achievements, their dates, XP, or celebration history.
- Changing the calorie-total semantics of an already confirmed entry.
- Retrospectively repairing existing on-device gamification data without an
  explicit migration design.

## Impact

- `FoodLogCore`: usage-history schema and the log/delete coordination seam.
- `Gamification`: lifetime-stat identity and idempotency rules.
- App target: confirmation and deletion orchestration.
- Tests: package unit tests plus app-target integration tests for the full
  confirmation/deletion lifecycle.

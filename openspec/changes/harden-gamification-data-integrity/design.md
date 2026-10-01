## Invariants

1. **Achievements are permanent.** An achievement already written to
   `AchievementStore` remains visible after a food deletion. This is the
   existing product rule and is not a defect.
2. **Current-state mechanics reflect retained entries.** A deleted or
   cancelled food must no longer appear in `UsageHistoryStore`, and therefore
   must not support a streak, a daily challenge, retained-history variety, or
   an active challenge.
3. **Lifetime statistics reflect confirmed food entries.** A meal preset with
   N durable food entries contributes N lifetime logs. Its calories remain the
   sum of all ingredients.
4. **The selected nutrition day is authoritative.** A user logging food for
   2026-09-01 on 2026-09-30 contributes calories and day-specific evaluation
   to 2026-09-01, never to the tap timestamp's day.
5. **Goal status is date-idempotent.** Re-fetching an older day after a newer
   day cannot increment that macro's lifetime count again.

## Findings

### F1 — Deleted food keeps affecting current gamification

`DayLogLoader.delete(_:)` deletes the remote entry or removes its outbox item,
but neither path removes the corresponding `UsageEvent`.
`AppEnvironment.delete(_:)` only refreshes goal status afterward. As a
result, a deleted meal remains in local streak/challenge calculations and in
retained-history variety. The current usage event has no durable identity
link to an outbox id or Garmin log id, so deletion cannot safely target one
specific event.

### F2 — Backdated food is credited to today in lifetime daily totals

`LogEntryCoordinator` correctly persists the selected `nutritionDay`, but
`GamificationEngine.handleLogConfirmed` computes its day from `now`.
Consequently `LifetimeStatsStore.recentDayCalories` and
`maxSingleDayCalories` apply a backdated entry to the confirmation day. This
can unlock an extreme-day achievement for the wrong date.

### F3 — Meal presets undercount lifetime log achievements

`confirmMealPreset` creates one durable entry and one `UsageEvent` per
ingredient, but its view calls `handleLogConfirmed` once. Therefore
`LifetimeStatsStore.totalLogsEver` rises by one while the user has logged N
foods. The lifetime-log badges can be delayed relative to the actual food
history.

### F4 — Goal-hit totals are only adjacent-call idempotent

`LifetimeStatsStore` stores only `lastCountedGoalDay` per macro. Processing
day A, then B, then refetching A increments A again because A is no longer
the last observed day. The app explicitly refreshes selected historical days,
so this ordering is realistic. The ledger needs a bounded or complete set of
counted dates (with a documented retention/migration policy) rather than one
last-date value.

## Test strategy

### Package regression tests

- `LifetimeStatsStore`: reload persistence, out-of-order same-day goal
  refreshes, selected-day calorie accumulation, and multi-entry meal totals.
- `UsageHistoryStore`: remove-by-log-identity preserves unrelated same-food
  events and survives a reload.
- `AchievementStore`: an already unlocked achievement remains permanent when
  a later context no longer meets its condition.

### App-target integration tests

- Confirm a dated food, delete it, then refresh: the day no longer counts for
  streak/daily/active challenge progress, while its already unlocked
  achievement stays visible.
- Cancel a queued food: the same local-state removal occurs without making a
  network request.
- Confirm a historical food: the ledger's daily max is assigned to the
  selected date.
- Confirm a three-ingredient preset: usage history and `totalLogsEver` each
  grow by three; XP follows the explicitly selected product rule.

### Manual verification

- Log a food, observe an achievement, delete it, relaunch, and confirm the
  badge remains while current challenges/streak state no longer relies on the
  deleted entry.
- Add food to a past day and verify its calorie/day displays and future
  achievement eligibility use that past date.

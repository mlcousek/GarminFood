## Why

Food logging has several valid entry points: the in-app confirmation screen,
Siri/Control quick picks, custom-food creation, and the durable food, weight,
and hydration queues. These paths currently do not all preserve the same
post-commit guarantees.

An entry that succeeds through one surface must receive the same
gamification, sync, and error-recovery treatment as the equivalent entry
from every other surface. A successful remote create must never be presented
as safely retryable failure.

## What Changes

- Route every successful food confirmation through a shared post-commit
  pipeline that performs both donation and gamification exactly once.
- Include food, weight, and hydration queues in background-delivery
  scheduling and execution.
- Represent a successful custom-food write with an unreadable response as an
  ambiguous success, never as a safe-to-retry creation failure.
- Make weight and hydration's local-history and outbox writes recoverable as
  one user-visible operation.
- Add focused unit/integration coverage for each failure and alternate-entry
  surface.

## Non-goals

- Changing the existing Garmin API contract without new observed evidence.
- Adding network waits to the food-log confirmation experience.
- Retrospectively deduplicating remote custom foods without a confirmed
  server-side identity/reconciliation mechanism.

## Impact

- App target: Quick Pick intent routing, background refresh orchestration,
  and custom-food creation UX.
- `FoodLogCore`: weight/hydration durable-write sequencing.
- `GarminKit`: custom-food response classification, if the ambiguity is
  represented at the client layer.

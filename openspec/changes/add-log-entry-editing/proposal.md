## Why

Today the only way to fix the amount of a logged food is to delete it and log
it again. Garmin's private API has no edit route. Every client checked uses
only `action: "ADD"`, and garmin_mcp found that a DELETE action on quickAdd is
silently ignored. So an edit has to be expressed as **log the corrected entry,
then delete the old one**. That order matters: if a step fails, the food is
never lost.

In the 2026-09-23 grilling session the owner chose which fields are editable
and which gestures to add:
- **Editable fields:** the amount and the meal. Serving unit and day are not
  editable.
- **Swipe actions on entries:** Edit amount, Move meal, Duplicate, Delete.
- **Copy a past meal:** re-log yesterday's (or any day's) breakfast in one tap.

## What Changes

- **Swipe actions.** Every entry on the home meal cards and in `MealDetailView`
  gets these actions:
  - Leading swipe: Edit, which opens an amount stepper plus a meal picker in a
    sheet.
  - Trailing swipe: Delete.
  - Context menu: Duplicate, and Move to <meal>.
- **Edit.** An edit is one durable outbox operation, `replace`. It carries the
  new item and the old `logId`:
  - On drain, the new item is created first.
  - Only after that succeeds is the old item deleted, with
    `DELETE /nutrition-service/food/logs/{date}` and `{logIds:[old]}`. That
    route is used by the app's delete today and live-verified by garmin_mcp.
  - If the delete then fails, the replace is kept as a pending delete that
    retries with backoff. It stays visible in the sync queue.
  - The UI shows the edited amount immediately. It never waits on the network.
- **Move meal.** Same replace mechanism, with a different `mealId`.
- **Duplicate.** A plain add of the same food, serving and quantity to the same
  meal.
- **Copy a past meal.** Each meal card gets "Copy from…". It offers
  Yesterday's <meal> or any previous day's <meal> from a date picker, then
  shows a preview list with checkboxes and logs the selected items. Each item
  is an ordinary outbox add.
- **Food identity for re-adding.** A read-back entry carries `foodId`,
  `servingId`, `source`, `regionCode` and `languageCode`. The replacement is
  built from those, so the region fix from `fix-custom-food-log-region` stays
  in force.

## Non-goals

- Editing the serving unit or moving to another day. The owner didn't pick
  them, and each is a second-order variant of the same replace.
- Editing quick-add entries (entries without a `foodId`). Only Delete is
  offered for them.
- Batch edit of several entries.

## Capabilities

### Modified Capabilities

- `food-log-entry`: edit, move, duplicate, and copy a past meal.

## Impact

- **GarminKit.** `OutboxEntry` gains an optional `replaces: {date, logId}`, and
  `drain` handles the create-then-delete sequence with a persisted intermediate
  state (`createdAwaitingDelete`). Existing outbox files still decode, because
  the new field is optional.
- **FoodLogCore.** `LogEntryCoordinator` gains `edit(entry:newQuantity:newMeal:)`,
  `duplicate` and `copyMeal(from:to:items:)`. `Reconciliation` must treat a
  replaced item's old `logId` as expected-to-disappear, not as a missing
  delivery.
- **App.** `TodayView` meal cards, `MealDetailView`, a new `EditEntrySheet`,
  and a new `CopyMealSheet`.
- **Depends on**: nothing, since the create and delete routes are both in use.
  Order-sensitive with `improve-log-food-shelves` only through
  `UsageHistory.record` (edits record usage with `mealType`, if that change has
  landed).
- **Unblocks**: nothing.

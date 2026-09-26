## 1. Outbox replace (GarminKit)

- [x] 1.1 Add `OutboxEntry.replaces: ReplacedLog?` (date, logId) as an optional field, and a new state `createdAwaitingDelete`. Test that old outbox files still decode.
- [x] 1.2 Drain handles a replace per D1: create, persist the state, then delete. A 404 on the delete counts as success. Tests: happy path, create fails, delete fails then retries, crash resume (starting from a persisted `createdAwaitingDelete`), 404 on delete.
- [x] 1.3 Reconciliation per D2, plus tests.

## 2. Domain (FoodLogCore)

- [x] 2.1 Add `LogEntryCoordinator.edit(loggedFood:newQuantity:newMeal:)`, which builds the replacement from the read-back `foodMetaData`, `servingId` and region/language. Tests.
- [x] 2.2 Add `duplicate(loggedFood:)`. Tests.
- [x] 2.3 Add `CopyMealPlanner` (source-day items + meal → copyable requests + non-copyable items), and `copyMeal`. Tests.
- [x] 2.4 Add the day-view overlay for pending replaces (hide the old row, show the new one as pending). Tests.

## 3. UI

- [x] 3.1 Swipe and context actions on entries in the `TodayView` meal cards and in `MealDetailView`: Edit, Move, Duplicate, Delete.
- [x] 3.2 `EditEntrySheet`: a quantity stepper and text field, a meal picker, and live kcal.
- [x] 3.3 `CopyMealSheet`: Yesterday plus a date picker, and a preview with checkboxes.
- [x] 3.4 Haptics on confirm. VoiceOver custom actions that mirror the swipe actions.

Implementation note (3.1): the Today meal cards are a plain stack, not a
`List`, so swipe actions only exist on `MealDetailView`. On the cards, tap a
row to edit it and long-press for Move/Duplicate/Delete; VoiceOver gets all
of them as custom actions on both screens (EntryEditing.swift).

## 4. Verify

- [x] 4.1 CI green. *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
- [ ] 4.2 On device: edit an amount and check it in Connect; move a meal; duplicate; copy yesterday's breakfast.

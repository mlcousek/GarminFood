## Evidence

- **No edit action exists.** Every client checked sends only `"action": "ADD"`:
  - garmin_mcp at `6fe000e`, `nutrition.py` (ADD at lines 701, 787 and 975)
  - python-garminconnect 0.3.2
  - tamcore/garmin-mcp

  garmin_mcp commit `db82d35` records that `PUT /food/logs/quickAdd` with
  `action=DELETE` plus a `logId` returned 200 and was silently ignored. The
  only other lead is `/food/logs/bulk`, which is known only from decompiled
  strings, so it is not used.
- **Delete works.** `DELETE /nutrition-service/food/logs/{date}` with body
  `{"logIds":[…]}` returned 204 in garmin_mcp's live e2e test. This app has
  called it since `add-garmin-auth-and-sync` (DayLogLoader delete).
- **Create works.** `PUT /nutrition-service/food/logs` was confirmed on
  2026-09-16 and is used daily.

## D1: Replace = create, then delete (never the reverse)

If the delete ran first and the create then failed, the user's food would be
gone from Garmin. Doing the create first means the worst failure is a
temporary duplicate. That duplicate is visible, and the pending delete is
retried until it lands.

States of a replace entry in the outbox:

    pending → (create 2xx) → createdAwaitingDelete → (delete 2xx) → delivered
                      ↘ create fails → pending (backoff, existing rules)
                                         ↘ delete fails → createdAwaitingDelete (backoff; shown in SyncQueueView)

`createdAwaitingDelete` is persisted before the delete request is sent. A crash
between the two steps therefore resumes at the delete, and the create is never
sent twice.

## D2: Reconciliation

Reconciliation compares local deliveries against Garmin's read-back. It
already skips duplicates made by the official app
(`couldBeThisAppsDelivery`). It must now also do two things:
- Accept the old `logId` of a replace as "expected to vanish".
- Accept a temporary duplicate while the replace is in `createdAwaitingDelete`,
  instead of trying to delete it again.

## D3: Local display during an edit

The day view overlays pending operations on Garmin's read-back:
- A replace hides the old `logId` row and shows the new amount, marked pending.
- This is the same overlay pattern the dashboard already uses for pending adds.

## D4: Copy a past meal

1. Read the source day with `GET /nutrition-service/food/logs/{date}`
   (confirmed 2026-09-14). This is also the existing cached day-log path.
2. Filter to the chosen meal.
3. Build `CreateFoodLogEntryRequest`s from each item's `foodMetaData`
   (`foodId`, `source`, `regionCode`, `languageCode`) plus `servingId` and
   `servingQty`.
4. Enqueue one ordinary add per item.

Quick-add items (no `foodId`) in the source meal are listed as not copyable.

## Fallback

If Garmin ever rejects the delete step permanently (a 4xx other than 404),
the replace is surfaced as "Old entry couldn't be removed — delete it
manually", with a one-tap retry. A 404 on delete counts as success: the item
is already gone.

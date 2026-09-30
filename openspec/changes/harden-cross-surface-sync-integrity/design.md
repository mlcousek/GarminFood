## Required invariants

1. A successfully committed food entry gains its gamification effects exactly
   once regardless of whether it originated in SwiftUI, Siri, or Control
   Center.
2. A pending entry in any durable queue is eligible for background delivery.
3. A remote 2xx custom-food creation response is never shown as a definitely
   failed operation solely because the response body is unexpected.
4. A visible local save failure for weight or hydration must not leave a
   deliverable remote write behind without a durable, discoverable local
   record.

## Findings

### F1 — Quick Pick bypasses gamification

`QuickPickControlAction.performLog` commits through
`LogEntryCoordinator.confirm` and then calls its observer. The configured
observer only donates an App Intent; it does not call
`GamificationEngine.handleLogConfirmed`. Siri/Control food entries therefore
miss XP, lifetime statistics, challenge completion, achievements, and
celebration moments.

### F2 — Weight and hydration are not background-delivered

`BackgroundRefresh.run` drains only the food outbox, while
`AppEnvironment.didEnterBackground` schedules only when the food-derived
undelivered count is nonzero. A pending weight or hydration entry can remain
unsent until the user foregrounds the app.

### F3 — Custom-food response decoding turns successful creates into retries

`GarminClient.createCustomFood` accepts a 2xx response and then requires a
`FoodSearchResult` body. A successful response with another valid shape
throws a decoding error. The UI presents this as a failed create and permits
another create, risking permanent duplicate foods.

### F4 — Weight/hydration can sync after a visible local-save failure

The coordinators enqueue the remote write before persisting the user-visible
local history record. A subsequent local persistence failure throws to the
UI, yet leaves the queued entry deliverable later.

### F5 — Quick Pick display quantity is not its confirmation quantity

Quick Pick cards retain and display the most recently logged serving
multiplier, but both entry points create a `LogTarget` containing only the
food and serving. `LogEntryConfirmView` then initializes quantity to `1`.
A card labelled `2.5x` can therefore silently enqueue one serving when
confirmed without editing.

### F6 — Deleting an in-flight food delivery can orphan it remotely

The food outbox snapshots a pending entry before awaiting the remote POST.
While the request is in flight, the dashboard marks it syncing and its delete
action removes only the local outbox record. If the POST subsequently
succeeds, the outbox treats the missing local record as harmless and no
compensating remote delete is issued.

### F7 — Reconciliation can delete an independent later Garmin entry

When more matching remote entries exist than local outbox entries,
reconciliation deletes later timestamp-sorted matches. A user can create the
same food, serving, quantity, and meal in Garmin Connect after the app's
delivery but before reconciliation. That legitimate later entry is
indistinguishable from a retry duplicate and is selected for deletion.

### F8 — Background reconciliation strands sent entries after a read failure

The background worker reconciles only entries delivered in its current run
and schedules future execution only for pending entries. A 2xx food write
followed by a failed read leaves an entry in `sent`; later background runs do
not reconcile it or schedule another retry.

## Test strategy

- App-intent integration: one quick-pick invocation produces one food entry,
  one XP/lifetime update, and no duplicate award.
- Background worker: a pending weight-only or hydration-only queue schedules
  and drains without a food entry; retry scheduling includes all queue types.
- Custom-food transport: a 201 unreadable body yields an
  ambiguous-success result and disables blind repeat creation.
- Coordinator failure injection: a failed local weight/hydration history
  write compensates the newly created queue item, with a separate test for
  compensation failure and its visible recovery state.
- Quick Pick handoff: a `2.5x` recent item initializes confirmation at `2.5`,
  not one serving.
- In-flight delete: a gated delivery that succeeds after local deletion
  produces a durable compensating remote-delete state.
- Reconciliation ownership: a later matching manual Garmin entry is never
  deleted without a reliable ownership/idempotency identifier.
- Background recovery: a sent entry left after a failed reconciliation read
  is retried and keeps background scheduling active.

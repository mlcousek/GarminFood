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

### F9 — Signing out permits cross-account writes and local-data exposure

Sign-out clears credentials and profile data but deliberately retains durable
queues, which are not associated with a Garmin identity. If account B signs
in after account A saved offline work, foreground draining sends A's queued
food to B's diary. Other retained local health and food data also remains
visible in the live environment.

### F10 — First enabled reminder can miss scheduling after permission grant

Enabling a reminder requests notification permission asynchronously and
persists the enabled setting immediately. The initial notification sync sees
`notDetermined` and returns. After the user grants permission, the UI updates
its displayed authorization state but does not re-run notification scheduling.

### F11 — Daily reminders stop without a foreground launch

Meal, streak, and challenge reminders are one-shot requests scoped to the
current date. No future horizon is preplanned, and neither the background
worker nor any recurring scheduling path replaces them after midnight while
the app remains closed.

### F12 — Profile header prefers an opaque Garmin display identifier

The profile header prefers `displayName` before `fullName`. Garmin can return
an opaque UUID-like display value alongside the user-facing full name, so the
screen displays an account-like identifier rather than the actual name.

### F13 — Deleting a delivered weigh-in is local-only

The current delete path removes a local delivered weight record and leaves its
sent outbox entry unchanged. It performs no corresponding Garmin deletion,
despite a confirmed remote deletion route and a readable remote sample
identifier. The app and Garmin histories silently diverge.

### F14 — Superseded food searches can overwrite current results

The catalog cancels old search tasks when the query changes, but requests
already in flight can still apply their results, errors, and loading-state
changes after cancellation. A delayed response for an old query can therefore
be shown under a newer query and can clear the newer query's spinner.

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
- Account switch: pending account-A entries and account-scoped retained data
  are unavailable and non-deliverable after account B signs in.
- Notification authorization: enabling the first reminder and granting
  permission causes its request to be scheduled immediately.
- Reminder rollover: a user who does not foreground after midnight still has
  a request scheduled for the next configured reminder time.
- Profile-name selection: a UUID-like display value with a populated full name
  resolves to the full name.
- Delivered weigh-in deletion: a successful remote delete and a local delete
  complete together; remote failure remains visible and retryable.
- Search request ownership: a delayed cancelled query cannot apply results,
  error, or loading state after a newer query begins.

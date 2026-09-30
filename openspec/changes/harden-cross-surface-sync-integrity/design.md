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

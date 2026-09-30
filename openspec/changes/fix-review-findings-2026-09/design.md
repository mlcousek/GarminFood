## Context

Sixteen findings, each verified against e2d871a before any change. Paths are
under `ios/`. "Not real" findings changed nothing; the evidence is kept here.

## Verdicts and evidence

### 1. Quick Pick / Siri bypasses gamification -- real

`Shared/QuickPickLoggingIntents.swift` `performLog` called
`logEntryCoordinator.confirm` / `confirmCustomFood` and then only
`logObserver?.didLog` (Siri donations). `GamificationEngine.handleLogConfirmed`
is called only by the confirm screens (`LogEntryConfirmView.swift:415`,
`MealPresetConfirmView.swift:202`) and `AppEnvironment.duplicateEntry/copyMeal`;
`refresh()` never awards. `GarminFood/Shortcuts/LogNamedFoodIntent.swift` had
the same gap and is fixed with it.

### 2. 2xx custom-food create shown as failed -- real

`GarminClient.createCustomFood` threw `decodingFailed` for a 2xx whose body
wasn't a `FoodSearchResult`; `CreateInGarminConfirmView.createInGarmin`
(`GarminFood/Catalog/MatchConfirmationView.swift`) showed "Couldn't create ...
Try again" and re-enabled the button (`defer { isCreating = false }`). The
`Food(searchResult:) == nil` branch also re-enabled it. Either way a second
tap created a duplicate food in Garmin.

### 3. Background handles only food -- real, partly

The drain half was already fixed (`BackgroundRefresh.run` drained all three
outboxes since 2026-09-23). The scheduling half was not:
`AppEnvironment.didEnterBackground` read `undeliveredCount`, which
`logConfirmed` refreshes for food but `weightLogged`/`hydrationLogged` did not
-- it was refreshed only at the end of `drainAndReconcile`, which returns early
while another drain runs. Leaving the app during an offline drain right after a
weigh-in cancelled the refresh.

### 4. Health enqueue before local save -- real

`WeightLogCoordinator.logWeight` / `HydrationLogCoordinator.logHydration`
enqueued first (the outbox id was needed for `outboxEntryId`), then
`store.upsert`; a failed upsert threw to the user but left the entry queued.
The stores also kept the new record in memory after a failed save.

### 5. Deleting a syncing entry orphans it -- not real

Food: `OutboxStore.cancel` refuses a claimed (in-flight) entry
(`GarminKit/.../Outbox.swift:438`, `OutboxEditError.entryInFlight`), surfaced as
`LogEntryEditError.stillSyncing` (`LogEntryCoordinator.deletePending`, used by
`DayLogLoader.delete`); a `.sent` entry is refused as `alreadyDelivered`. The
unconditional `Outbox.delete(id:)` is called only by Reconciliation after a
confirmed match. Weight and water keep a tombstone: `cancel` flags
`removalRequested` on an in-flight add and `settle` queues the compensating
delete / negative correction once Garmin accepts it (`WeightSync.swift:328`,
`HydrationSync.swift:235`). Tests: `OutboxTests.testAnEntryBeingSentCannotBe
EditedUnderneathTheDrain`, `WeightSyncTests.testDeletingAWeighInWhileItsPostIs
InFlightDeletesItFromGarminOnceAccepted`, `HydrationSyncTests.testRemovingA
DrinkWhileItsPostIsInFlightSendsACorrectionOnceGarminAcceptsIt`.

### 6. Reconciliation deletes a later identical entry -- not real

Since fix/reconcile-duplicate-delete (2026-09-23) only a Garmin entry whose
`logTimestamp` equals a locally expected entry's own `createdAt` (2 ms) and is
left over after each such entry claimed its own copy is ever deleted
(`Reconciliation.provableRetryCopies`, `isOwnDelivery`,
`Reconciliation.swift:365-386`). An independently logged identical food has a
different timestamp (or none: fails closed) and is kept. Tests:
`ReconciliationTests.testASecondIdenticalLogWithinTheClockToleranceIsNever
Deleted`, `testAReSentDeliveryIsStillCleanedUpButASeparateLogBesideItIsNot`.

### 7. Quick Pick loses the remembered amount -- not real

Every quick-pick card tap passes the card's amount:
`FoodCatalogView.selectQuickPick` (`.custom(draft, initialQuantity:
item.numberOfUnits)` / `.catalog(..., initialQuantity: item.numberOfUnits)`,
also for Usual and Recent), `TodayView.logAgain` likewise, and
`LogEntryConfirmView.init` starts at `LogQuantity.initial(remembered:)` (1 only
when out of bounds). The Control/Siri path uses `QuickPickResolution`, which
carries `entry.numberOfUnits` (`QuickPickResolutionTests.testACatalogFood
ResolvesWithItsExactServingAndRememberedAmount`). Favorites cards show no
amount by design (`FavoritesShelf.swift` header).

### 8. Background strands `.sent` food entries -- real

`BackgroundRefresh.deliver` reconciled only that pass's `delivered`; a `.sent`
entry whose re-read failed (`reconciliationSkipped`) was never picked up by a
later background pass, and `.sent` didn't keep a refresh scheduled. (The
foreground `drainAndReconcile` already reconciles every `.sent` entry.)

### 9. Queued entries cross Garmin accounts -- real

Outbox entries carried no account and `TokenProvider.signOut` kept them
"to drain once the session is restored" -- by whichever account signs in.

### 10. First reminder never schedules -- real

`NotificationSettingsView` toggles call `onChange` (-> `syncNotifications`)
immediately and request permission in a separate task;
`NotificationScheduler.performSync` returns while the status is
`.notDetermined`, and nothing re-synced after the prompt was accepted.

### 11. Reminders stop after midnight -- real

`NotificationScheduler.performSync` scheduled one-shot requests for TODAY only;
`TrainingReminderPlanner.plan` covered today and tomorrow. No background path
re-plans, so a phone left closed got no reminders from the next day on.

### 12. Deleting a delivered weigh-in is local-only -- not real

The only UI delete path (`WeightView.swift:164` -> `AppEnvironment.deleteWeighIn`
-> `WeightLogCoordinator.delete(_:)`, `WeightLogCoordinator.swift:143`) queues
`DELETE /weight-service/weight/{date}/byversion/{samplePk}` (live-confirmed
2026-09-23) for a Garmin sample, and a delete-by-match for a delivered local
weigh-in whose sample isn't known yet (line 169). Tests:
`WeightLogCoordinatorTests.testDeletingAGarminWeighInQueuesAGarminDelete
WithoutAnyNetworkCall`, `testDeletingADeliveredButUnmatchedWeighInDeletesIt
FromGarminByMatch`. The local-only `deleteWeight(_:)` has no app caller.

### 13. Cancelled search overwrites newer results -- not real

`FoodCatalogView` runs the search in `.task(id: query#...)`, so a new query
cancels the old task; `FoodSearchModel.run` (main actor) checks
`Task.isCancelled` before applying each snapshot
(`SearchResultsSection.swift:65`) with no suspension between the check and the
assignment, and the model has no separate loading flag to clear. The engine's
stream cancels its task on termination and stops emitting once cancelled
(`FoodSearchEngine.swift:128`, `268`, `293`; `FoodSearchEngineTests.
testStoppingTheStreamCancelsTheDebouncedRemoteSearch`).

### 14. Profile shows a UUID over `fullName` -- not real

`ProfileView.headerName` prefers the local name, then `fullName`, then
`displayName` (fix-testing-feedback-quick-wins 3.1, `ProfileView.swift:123`).

### 15. Unreadable store overwritten as empty -- not real

Every user-data store loads through `PersistedJSON.load`
(`GarminKit/.../PersistedJSON.swift:130`): missing -> empty; unreadable ->
left in place, `loaded` stays false and every write is refused by
`ensureSafeToWrite` (line 178) until a later read succeeds; undecodable ->
moved aside. Test: `PersistedJSONTests.testUnreadableOutboxRefusesToSaveThen
RecoversOnceReadable`. Documented exceptions: DiagnosticsLog, the Siri
`DonationLedger`, the offline-index status (no user data).

### 16. Accepted write re-sent after restart -- real

All three drains ignore a failed write of the post-2xx state (`try?` /
"couldn't persist a delivery result"); after process death the entry reloads
`.pending` and is POSTed again. Food duplicates were cleaned up by
Reconciliation (same `createdAt`), but a weigh-in or a drink stayed doubled.

## Decisions

- **D1 Relay, not a direct call (1).** The intents live in `Shared/`, compiled
  into the widget, which doesn't link Gamification; and an intent can run
  before `AppEnvironment` exists. `ConfirmedLogRelay` (FoodLogCore, main actor)
  holds logs until the app attaches `handleLogConfirmed`, hands each over once
  (dedup by entry id). In-memory is enough: the intents run in the app process
  (`openAppWhenRun`).
- **D2 A 2xx is a create (2).** `CustomFoodCreation.create` takes the send as a
  closure (testable without Keychain/network). Unknown body ->
  `.createdDetailsPending`; the gate never allows a second create after a 2xx.
  A thrown error (no 2xx seen) may still be retried -- a transport error after
  the request left is the one residual ambiguity, unchanged.
- **D3 Ask the outboxes (3, 8).** `OutboxBacklog.needsDelivery` reads the three
  outboxes; it counts `.pending`, unparked replaces, and unreconciled food
  `.sent` (weight/water `.sent` are kept as history, so never).
- **D4 Local first (4).** The outbox id is generated up front
  (`logWeight/logHydration(id:)`), the local record saved first, then the entry
  enqueued; a failed enqueue removes the local record again (best effort).
- **D5 Account key (9).** `GarminAccountKey` = SHA-256 of the profile's
  `userName` (else `displayName`), stored with a fingerprint of the OAuth1
  token and trusted only for that token. Stamped at enqueue; drains and
  Reconciliation only handle entries whose stamp matches (unstamped = any).
  Held entries stay pending and visible. Residual: if an account's identifier
  itself changes, its old entries stay held (visible, deletable).
- **D6 Send marker (16).** `sendStartedAt` is written (whole-file, in-memory only
  after success) before the request; not sent if that fails; cleared with the
  outcome. On a reload with the marker: food -> `.sent` for Reconciliation
  (plain creates; replaces keep their documented re-create path), weigh-in add
  -> day-view lookup (`WeighInMatching`) first, drink -> `.failed` with a note
  (no per-drink lookup exists), deletes -> repeat (404 = done).
- **D7 Reminder window (10, 11).** `NotificationPlanning.planWindow` = today's
  plan + the next 6 days as "nothing logged yet"; the streak reminder stays
  today-only (tomorrow's risk can't be known). 29 requests at most for food;
  training `plan(days: 7)` from the cached projection. Permission granted from
  undecided -> one re-sync.

## Risks

- No local compiler: everything is verified by CI (`swift test` per package,
  `xcodebuild`). The GarminKit outbox changes are the widest.
- Held entries of another account keep a background refresh scheduled.
- A "possibly delivered" drink needs the user to decide (sync queue).

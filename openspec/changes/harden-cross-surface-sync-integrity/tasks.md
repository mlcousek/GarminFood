## 1. Consistent food post-commit behavior

- [ ] 1.1 Extract a shared app-layer post-commit pipeline for food logging.
- [ ] 1.2 Route SwiftUI, Siri, and Control quick-pick confirmation through it.
- [ ] 1.3 Add an exactly-once gamification integration test for Quick Pick.

## 2. Durable background delivery

- [ ] 2.1 Expose pending work across food, weight, and hydration queues.
- [ ] 2.2 Drain all supported queues in the registered background task.
- [ ] 2.3 Add background-worker tests for weight-only and hydration-only work.

## 3. Custom-food create recovery

- [ ] 3.1 Classify post-2xx response decoding failure as ambiguous success.
- [ ] 3.2 Add a reconcile/re-search recovery path before another create.
- [ ] 3.3 Add transport and UI-state regression tests for an unreadable 2xx body.

## 4. Weight and hydration atomicity

- [ ] 4.1 Add failure injection for local-history persistence.
- [ ] 4.2 Compensate or retain a durable local pending record when local
  persistence fails after queueing.
- [ ] 4.3 Test successful compensation and explicit compensation-failure
  recovery.

## 5. Food lifecycle integrity

- [ ] 5.1 Carry a Quick Pick's retained quantity into confirmation and add a
  UI-input mapping regression test.
- [ ] 5.2 Represent deletion requested during an in-flight delivery as a
  compensating remote-delete operation; add a gated-delivery race test.
- [ ] 5.3 Stop destructive duplicate cleanup without a reliable ownership
  identifier; add a later independent-Garmin-entry regression test.
- [ ] 5.4 Reconcile previously sent entries and retain background scheduling
  after a reconciliation read failure.

## 6. Account and notification lifecycle

- [ ] 6.1 Bind retained queues and account-scoped local data to a stable
  Garmin identity; quarantine or purge it safely on account change.
- [ ] 6.2 Add same-account reconnect and different-account switch tests.
- [ ] 6.3 Re-run notification scheduling after first authorization is granted.
- [ ] 6.4 Schedule/reconcile a future reminder horizon that survives
  midnight without foregrounding.
- [ ] 6.5 Add authorization-transition and date-rollover scheduler tests.

## 7. Profile, search, and delivered-data consistency

- [ ] 7.1 Prefer validated user-facing profile names over opaque display IDs.
- [ ] 7.2 Add remote-aware delivered weigh-in deletion with visible retry
  recovery.
- [ ] 7.3 Add a request-generation guard around catalog and Open Food Facts
  result application.
- [ ] 7.4 Add regression tests for profile-name selection, delivered
  weigh-in deletion, and superseded search responses.

## 8. Durable-store recovery

- [ ] 8.1 Distinguish missing persisted files from unreadable existing files;
  retry safely or reject writes while data is unavailable.
- [ ] 8.2 Make remote acknowledgement state durable before reporting delivery,
  with an explicit ambiguous-delivery recovery state if persistence fails.
- [ ] 8.3 Add restart tests for transient read failure and post-acknowledgement
  write failure across food, weight, and hydration queues.

## 9. Verification

- [ ] 9.1 Run all Swift package suites.
- [ ] 9.2 Run app-target integration tests on iOS Simulator.
- [ ] 9.3 Verify background delivery on a device with interrupted
  connectivity.

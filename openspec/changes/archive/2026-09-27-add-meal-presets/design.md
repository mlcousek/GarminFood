## Context

`add-food-log-core` already has two relevant precedents to build on rather than reinvent:

- **`CustomFoodDraft`** (design.md D4 of that change): a locally-created food that logs to Garmin as an existing "backing" food+serving, scaled by a multiplier, because `GarminClient.createCustomFood`'s request/response shape is documented-but-unconfirmed. A meal preset's custom-food ingredients reuse this exact mechanism unchanged.
- **`LogEntryCoordinator.confirm`/`confirmCustomFood`**: the confirm-and-commit action, structurally zero-network-wait because `Outbox.logFood` only appends to a local JSON file. Both already do everything one preset ingredient needs (write the outbox entry, record usage history, remember the serving default).

## Goals / Non-Goals

**Goals:**

- Logging a preset feels like logging a single food: one tap, one confirm screen, immediate success.
- Every ingredient still shows up in Garmin Connect's own food log individually, and in this app's own quick-pick ranking — nothing about single-food logging gets worse or different for a food that happens to also be part of a preset.
- A preset stays fully loggable offline, at confirm time, with zero network wait — same guarantee every other confirm screen in this app already has.

**Non-Goals:**

- Perfect recipe modeling (yields, servings-per-batch, ingredient substitution). See proposal.md's Non-goals.

## Decisions

### D1 — N separate outbox entries, not one aggregated Garmin food

Two ways to represent "log this whole meal" were considered:

1. **One aggregated custom food** (sum every ingredient's macros into a single new Garmin food, created via `createCustomFood`, then log one entry).
2. **N separate entries**, one per ingredient, all sharing the same meal type/date/timestamp.

Chosen: **(2)**. `createCustomFood`'s request/response shape is still documented-but-unconfirmed (`GarminClient.createCustomFood`'s own header) — betting a second, bigger feature on that same unconfirmed contract compounds the existing risk for no real benefit. Option (2) instead reuses `LogEntryCoordinator.confirm`/`confirmCustomFood` completely unchanged: every ingredient is indistinguishable, to Garmin and to this app's own usage history, from that same food logged on its own — which is also already verified behavior, just invoked N times in one action instead of once.

Trade-off accepted: Garmin Connect's own food log will show N rows for one "meal" rather than one. This is judged acceptable — Garmin's log already shows individual foods per meal, not a "meal" concept of its own, so N rows under (say) Breakfast is consistent with how Garmin already presents everything else.

### D2 — An ingredient is a full snapshot, not a live reference

A `MealPresetIngredient` stores its own `Food`/`Serving` (and, for a custom-food ingredient, the full `CustomFoodDraft`) at add-time, not just an id. This mirrors `FoodCacheStore`'s existing pattern (a cached snapshot, not a live lookup) and buys the same property: a preset stays fully loggable offline, and survives that ingredient's own food being edited or removed elsewhere later, without a dangling reference. The accepted cost: if the user edits a custom food's backing/macros after adding it to a preset, the preset keeps the OLD snapshot until re-added — judged acceptable given this app's existing quick-pick/serving-default systems already work the same way (snapshot-on-use, not live-tracking).

### D3 — `confirmMealPreset` is not transactional

Each ingredient is its own durable local commit (`Outbox.logFood` only ever appends to a file). If ingredient 3 of 5 throws, ingredients 1-2 are already committed and stay that way — there is no meaningful "undo" that wouldn't mean discarding real, already-durable entries to paper over an unrelated failure (e.g. a full disk). `confirmMealPreset` rethrows immediately on the first failure, exactly like every other `throws` method on `LogEntryCoordinator`; the confirm screen's error message names this ("some ingredients may already be saved").

### D4 — "Portions" scales the whole preset, ingredient quantities stay fixed relative to each other

Rather than letting the user re-edit each ingredient's quantity at LOG time (which would defeat the point of a fixed, reusable preset), the confirm screen offers one "Portions" multiplier applied to every ingredient's own preset-defined quantity together. Editing an individual ingredient's quantity is still possible, but only in the preset EDITOR, where it changes the preset itself going forward.

## Risks / Trade-offs

- **A preset ingredient's snapshot can drift from its source food** (D2's accepted cost) → mitigated by nothing automatic; a future refinement could offer "refresh this ingredient from the catalog," not built here.
- **N-entries-per-preset means N chances for outbox delivery to fail independently** → each ingredient still surfaces in the existing sync queue screen (`SyncQueueView`) exactly like any other queued entry, so a partial-delivery failure is visible and individually retryable, not silent.
- **Building on `confirmCustomFood` means a preset's custom-food ingredients inherit that path's own unconfirmed-route risk** (custom-food creation via `createCustomFood`, when used) → this is not new risk introduced by this change; it's the same existing risk `CustomFoodDraft` already carries, now also reachable via a preset.

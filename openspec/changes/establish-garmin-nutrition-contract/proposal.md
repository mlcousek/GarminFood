## Why

Every other change in this project assumes food can be written into Garmin Connect, and nobody has demonstrated that it can. Probing on 2026-09-14 proved the nutrition service is live and food search works, but every guessed food-log route returned 404. Until the write contract is observed rather than assumed, building an app on top of it is building on nothing. This change turns a guess into evidence, and stops the project early if the evidence says no.

## What Changes

- Establish a **route registry**: one machine-readable file recording every Garmin endpoint the project depends on, with method, path, last-verified date, and the status code actually observed.
- Establish a **read-only probe harness** that re-verifies the whole registry on demand, so a future failure can be told apart from a mistaken URL.
- **Discover the food-log read and write routes** by inspecting the Garmin Connect Android client rather than by guessing paths. Guessing has already been tried and exhausted.
- Record the discovered write contract — method, path, request body, meal-type enumeration, response shape — backed by a captured transaction.
- Make the project's continuation conditional on that evidence, with an explicit stop condition.

## Capabilities

### New Capabilities

- `garmin-route-registry` - an evidence-backed record of the private Garmin endpoints this project depends on, plus the read-only tooling that keeps it honest.

### Modified Capabilities

None.

## Non-goals

- **Writing anything to the Garmin account.** This change documents the write contract; the first actual write is owned by `add-garmin-auth-and-sync`.
- **Token acquisition and storage.** Reusing the owner's existing OAuth1 token is enough for recon; a proper bootstrap flow is owned by `add-garmin-auth-and-sync`.
- **Normalising food data into app models.** Owned by `add-food-log-core`.
- **Fixing the vault's broken `sync-nutrition.mjs`.** Owned by `add-companion-surfaces`, and it cannot be fixed until this change finds the real log route.

## Impact

Affected surfaces: `tools/` (probe harness), `docs/garmin-routes.json` (new registry), `openspec/specs/garmin-route-registry/`.

No application code exists yet, so nothing is broken by this change.

**Depends on**: nothing. This is the first change and the gate for all others.

**Unblocks**: `add-garmin-auth-and-sync`, `add-food-log-core`, `add-glanceable-surfaces`, `add-companion-surfaces`. If this change concludes no write path exists, the project reduces to a read-only companion app and the remaining changes are re-scoped.

## Context

Garmin offers no public API for writing nutrition data. The Connect Developer Program's Health API is read-only for partners; the push APIs cover workouts and courses only. MyFitnessPal and Cronometer write consumed calories through a partner-only Health SDK that is not available to individuals. So the only route for a personal app is Garmin's private mobile API at `connectapi.garmin.com` — the same surface the Connect app uses.

Two things happened in 2026 that shape every decision below.

**January 2026** — Garmin shipped native nutrition tracking in Connect+ ($6.99/mo). This is what makes the project possible at all: before it, no nutrition endpoints existed to call. Food entries come from a global database, with barcode scanning and AI photo recognition in the app, and favourites/recents loggable from the watch.

**March 2026** — Garmin put its SSO login endpoints (`/sso/signin`, `/mobile/api/login`) behind Cloudflare bot protection. Scripted login broke everywhere. `garth`, the Python library underpinning most of the ecosystem, was deprecated on 2026-03-28 with a final release. Its author's note is the relevant part: an existing saved session keeps working until the OAuth1 token expires (~1 year from issue), but **new logins do not work**. Any design that takes a username and password is already dead.

### What was actually probed, 2026-09-14

Read-only, against the owner's live account, using the OAuth1 token the Obsidian `garmin-health-sync` plugin already holds. Evidence, not assumption:

| Route | Status | What it means |
| --- | --- | --- |
| `POST /oauth-service/oauth/exchange/user/2.0` | 200 | Auth is alive. Returns a ~24h OAuth2 access token (`expires_in` 88227s observed). |
| `GET /usersummary-service/usersummary/daily?calendarDate=<d>` | 200 | Control. Exposes `consumedKilocalories: null`, `remainingKilocalories`, `activeKilocalories`, `bmrKilocalories`. **`consumedKilocalories` is the field this project exists to populate.** Currently null — nothing has ever been logged on this account. |
| `GET /nutrition-service/food/search?searchExpression=banana` | 200 | **The nutrition service is live.** 20 results. |
| `GET /nutrition-service/food/search` (any other param name) | 400 | Garmin names the missing parameter for us: `'searchFood.arg0.searchExpression' searchExpression query parameter must be provided (provided value: null)`. |
| `GET /nutrition-service/food/{log,favorite,recent,custom,barcode}/...` | 404 | Route does not exist at that path. ~30 shapes tried. |
| `GET /nutrition-service/{diary,daily,summary,foodlog}/<date>` | 404 | Same. |
| `GET /{diary,food,meal,fooddiary,nutritionlog}-service/...` | 404 | No alternative service name found. |
| `GET /userprofile-service/userprofile/settings` | 200 | Locale/measurement settings available. |
| Any route on `connect.garmin.com` | 200 HTML | Sign-in page, not API data. The mobile OAuth2 token is only honoured on `connectapi.garmin.com`. |

No 402 or 403 was seen anywhere, so no entitlement wall was observed — but since nothing has ever been logged, absence of a paywall error is not proof the account has Connect+.

### The food object, as returned by search

This is the shape a write will almost certainly have to reference:

```json
{
  "type": "FOOD",
  "foodMetaData": {
    "foodId": "5388", "foodName": "Banana", "foodType": "GENERIC",
    "source": "FATSECRET", "regionCode": "US", "languageCode": "en"
  },
  "foodImages": [{ "imageUrl": "...", "imageType": "0" }],
  "nutritionContents": [{
    "servingId": "54068", "servingUnit": "g", "numberOfUnits": 100,
    "calories": 89, "carbs": 22.84, "protein": 1.09, "fat": 0.33,
    "fiber": 2.6, "sugar": 12.23, "saturatedFat": 0.112,
    "monounsaturatedFat": 0.032, "polyunsaturatedFat": 0.073,
    "cholesterol": 0, "sodium": 1, "potassium": 358,
    "vitaminA": 3, "vitaminC": 8.7, "calcium": 5, "iron": 0.26,
    "unitHasServing": false
  }],
  "isRecent": false, "isFavorite": false,
  "servingQty": 1, "logTimestamp": "..."
}
```

Three inferences worth stating explicitly, because they are inferences and not observations:

1. **Garmin's food database is FatSecret.** `source: "FATSECRET"` appears on every generic result. That is a commercial database of ~1.9M foods with good European coverage — which is why `rohlik` returns 13 Czech results.
2. **A log entry is probably `(foodId, servingId, numberOfUnits, mealType, date)`.** Every field needed to identify a portion is already in the search result, and `servingQty` / `logTimestamp` / `isFavorite` / `isRecent` being present on a *search* result strongly suggests the search and log responses share a DTO.
3. **`regionCode`/`languageCode` are response fields, not request filters.** Passing them as query parameters returns 400.

## Goals / Non-Goals

**Goals:**

- Produce a documented, dated, machine-readable registry of every Garmin route this project will call.
- Discover the food-log write contract by observation, and capture one real transaction as proof.
- Give the project an honest stop condition, decided on evidence rather than optimism.
- Make re-verification a single command, so that when Garmin changes something the failure is diagnosable in minutes.

**Non-Goals:**

- Building any app code. No Swift is written in this change.
- Making the first write. Documenting the contract and exercising it are separate acts.
- Supporting anyone else's Garmin account. Single-user, single-account, throughout.
- Achieving stability. This surface is undocumented and will break; the goal is fast diagnosis, not permanence.

## Decisions

### D1 — Discover the write path by decompiling the Android client, not by guessing

Roughly 30 path shapes have already been probed and all 404'd. Continuing to guess has poor expected value. The Garmin Connect Android APK contains the endpoint strings as literals. `jadx` on the APK, then grep for `nutrition-service`, yields the real paths, the HTTP methods, and usually the DTO field names, in one pass and without touching the account.

*Alternatives considered.* **mitmproxy against the iOS app** gives ground truth including exact payloads, but Garmin may pin certificates, and on a non-jailbroken iPhone pinning is the end of the road. Worth attempting second, because when it works it is definitive. **Frida on a rooted Android device** defeats pinning but is disproportionate effort for a personal project. **Continued blind probing** is cheap but has already failed.

Decompilation reads a shipped binary to achieve interoperability with the owner's own account and own data. It does not redistribute Garmin code and does not circumvent any access control.

### D2 — The registry is a data file, not prose

`docs/garmin-routes.json`, keyed by logical operation, each entry carrying `method`, `path`, `lastVerified`, `observedStatus`, and `notes`. Prose rots silently; a data file can be executed against. The probe harness reads this file rather than carrying its own hardcoded list, so verification and documentation can never drift apart.

The vault's existing `scripts/lib/garmin.mjs` already has this instinct — it carries a comment block recording which wellness endpoints were probed live on 2026-08-19 and what each returned. That convention works and is worth formalising.

### D3 — Distinguish the four failure modes, always

A probe that reports "failed" is useless. Four statuses mean four different things and four different next actions:

- **401** — the OAuth1 token expired or was revoked. Re-bootstrap through a browser. Expected roughly annually.
- **404** — the route does not exist. Our path is wrong, or Garmin moved it.
- **400** — the route exists and our request is malformed. *This is the most valuable failure*, because Garmin's Spring Boot validators name the missing parameter. `searchExpression` was discovered exactly this way.
- **402/403** — entitlement. The account lacks Connect+.

### D4 — The stop condition is explicit

If, after both D1 and the mitmproxy fallback, no write route is found or writes are rejected on entitlement the owner will not pay for, the project does not proceed as designed. It falls back to one of:

- **Read-only companion** — fast local logging with excellent widgets, Garmin read-only for burned calories. Loses the "all food in Garmin" goal.
- **Cronometer bridge** — log into Cronometer's documented API, let its existing partner integration push consumed calories into Garmin. Garmin then holds totals but not the full diary.

Both are worse than the design, and both are better than a half-built app. The decision point is task 3.4.

### D5 — Read verification precedes write attempts, without exception

No task in this change writes to the account. The first write happens in `add-garmin-auth-and-sync`, against a deliberately distinctive test food, on a date the owner can inspect and undo by hand. A private API with an unknown contract is exactly the wrong place to discover an idempotency bug.

## Risks / Trade-offs

- **The write route may not exist on this surface at all** → Garmin may gate nutrition writes to the app's own signed client, or to a different host. Mitigation: D1 reveals the host as well as the path; mitmproxy confirms. If it is client-attested, D4 applies.

- **The account may not have Connect+, and nutrition may be entitlement-gated** → every probe so far returned 404 rather than 403, so a paywall has not been *observed*, but neither has it been excluded. Mitigation: task 1.4 settles this directly by logging one food by hand in the Connect app. Cheapest possible experiment, and it also produces a real payload to read.

- **The OAuth1 token expires (~1 year) and the March 2026 Cloudflare wall makes re-acquisition manual** → this is not a risk, it is a certainty on a known schedule. Mitigation: the browser-based bootstrap in `add-garmin-auth-and-sync` is designed as a first-class, documented flow rather than an error path, and the app surfaces "sign in again" loudly.

- **Garmin changes the route and everything silently returns null** → this has already happened once, in this owner's own vault: `getNutritionLog()` wraps a 404 in `catch { return null }`, so `sync-nutrition.mjs` has reported "0 days with data" instead of "this endpoint does not exist" since the day it was written. Mitigation: D3, plus the rule that auth and route failures are loud while empty data is quiet.

- **Rate limiting during discovery** → Garmin throttles. Mitigation: 400-450 ms between probes, honour `Retry-After`, and treat 429 as stop-and-resume. The existing vault client already learned this lesson the hard way during an activity backfill.

## Open Questions

1. **Does this account have Connect+?** Unresolved by probing. Settled by task 1.4.
2. **Is the food log per-day or per-entry addressable?** `logTimestamp` on search results hints at per-entry. Settled by D1.
3. **What is the meal-type enumeration?** The vault's speculative parser guesses `mealName` with underscores (`BREAKFAST`, `MORNING_SNACK`?). Unconfirmed.
4. **Can a custom food be created via API?** Matters for Czech foods missing from FatSecret. If not, the fallback is logging a generic food with an adjusted serving quantity.

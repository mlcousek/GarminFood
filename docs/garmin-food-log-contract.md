# Garmin food-log write contract

Status as of **2026-09-16**. **The route and body below are taken from a client that writes to a real account successfully** — [garmin_mcp](https://github.com/Taxuspt/garmin_mcp) (`log_food_to_meal` / `delete_food_log` in `src/garmin_mcp/nutrition.py`, covered by its own live end-to-end tests). **Confirmed by this project's own first write on 2026-09-16** (task 11.4). A real device logged a FatSecret food, and it read back exactly once, in the right meal, with every field as sent. `tools/garmin-write-probe.mjs` makes further writes from Windows without a device build.

### What changed on 2026-09-16, and why

The contract this doc originally recorded (a flat `POST`, reconstructed from dex strings — kept below the read shape for the record) was wrong in almost every respect, and the app's first real write on a device failed silently because of it. Comparing it with garmin_mcp:

| | Originally inferred | What actually works |
|---|---|---|
| Method | `POST` | **`PUT`** |
| Envelope | flat object | `{ "mealDate", "foodLogItems": [ … ] }` |
| Meal | `mealType: "SNACKS"` | **`mealId`** — a numeric, *per-date* meal instance id |
| Quantity | `numberOfUnits` | **`servingQty`** |
| Namespace | — | **`source`**: `GARMIN` or `FATSECRET`; the wrong one is a 400 |
| Delete path | `/nutrition-service/food/logs` | `/nutrition-service/food/logs/{date}` |

Checked against this project's own account by read-only probing the same day: meal instance ids and windows from `GET /nutrition-service/meals/{date}` match what the body needs; every `FATSECRET` food id is numeric and every `GARMIN` id (including custom foods) is 32-character hex, so a missing `source` can be inferred; entries the official app created carry `mealTime` equal to their meal's `startTime` and a `logTimestamp` of the moment of logging.

## How this was gathered

1. Live GET probing found the read route `GET /nutrition-service/food/logs/{date}` (see `docs/garmin-routes.json`), which returns real logged entries with a rich, consistent shape.
2. Downloaded the current Garmin Connect Android client (v5.29, Sep 2026) from a public APK mirror, extracted the base APK's `classes*.dex` files, and scanned them for ASCII string literals. This surfaced every `nutrition-service` route path as compiled string constants, plus Kotlin data-class `toString()` fragments that name DTO fields (e.g. `FoodLogRequestDTO(date=`, `, mealType=`, `, foodId=`).
3. Cross-referenced those field names against the real shape of a `loggedFoods` entry from step 1, since a create request for the same resource is very likely to accept the fields the read response echoes back.

**Limitation to be explicit about:** the dex string pool is alphabetically sorted, which destroys the original source order of the `toString()` fragments. So this contract has high confidence in *which fields exist*, and only moderate confidence in exactly how they're spelled/nested in the request body, since that requires either a successful write or full bytecode disassembly (not attempted).

## The route

```
GET /nutrition-service/meals/{date}      # resolve the meal instance id first
PUT /nutrition-service/food/logs
```

| Purpose | Method | Path | Source |
|---|---|---|---|
| Meal definitions for a date | GET | `/nutrition-service/meals/{date}` | probed live, 200 |
| Create entries | PUT | `/nutrition-service/food/logs` | garmin_mcp |
| Quick-add by name + macros | PUT | `/nutrition-service/food/logs/quickAdd` (`quickAddItems`) | garmin_mcp |
| Delete | DELETE | `/nutrition-service/food/logs/{date}` (body `{"logIds": [...]}`) | garmin_mcp |
| Bulk create | POST? | `/nutrition-service/food/logs/bulk` | dex strings only |

## Request body

```json
{
  "mealDate": "2026-09-16",
  "foodLogItems": [
    {
      "logTimestamp": "2026-09-16T10:30:00.250Z",
      "logSource": "GCW",
      "logCategory": "REGULAR_LOG",
      "mealTime": "10:00:00",
      "action": "ADD",
      "mealId": 123456,
      "foodId": "<id from search>",
      "servingId": "<id from that food's nutritionContents>",
      "source": "FATSECRET",
      "regionCode": "US",
      "languageCode": "en",
      "servingQty": 1.5
    }
  ]
}
```

- `mealId` — from `GET /nutrition-service/meals/{date}`: `meals[].mealId` where `mealName` is `BREAKFAST` / `LUNCH` / `DINNER` / `SNACKS`. It differs for every date, so an entry queued offline resolves it at delivery time.
- `mealTime` — `HH:mm:ss`. A meal with a window uses its `startTime`, as the official app does. `SNACKS` has no window: use the local time of logging, moved just past any window it falls inside, because garmin_mcp picks `mealId` *from* `mealTime`.
- `logTimestamp` — ISO-8601 UTC with milliseconds; the moment the user logged it.
- `servingQty` — how many of `servingId`; the same field `LoggedFood.matchesQuantity` checks first on read-back.
- `source` — `foodMetaData.source` from search. When unknown, infer it: numeric id → `FATSECRET`, otherwise `GARMIN`.
- `logSource` / `regionCode` / `languageCode` — client-supplied constants. garmin_mcp sends `GCW` / `US` / `en`; the official mobile app's entries read back as `GCM` / `CZ` / `en` on this account, including for a food that search reports under `US`, so the region is not checked against the food.

## Originally inferred request body (superseded — kept for the record)

Based on `FoodLogRequestDTO` and the shape of a read entry's `foodMetaData`/`nutritionContent`:

```json
{
  "date": "2026-09-14",
  "mealType": "BREAKFAST",
  "foodId": "17926789",
  "servingId": "16904392",
  "numberOfUnits": 1
}
```

- `date` — `YYYY-MM-DD`, local nutrition-day date (see the day-window note below).
- `mealType` — an enum. Confirmed values from real reads, via `meal.mealName`: `BREAKFAST`, `LUNCH`, `SNACKS`. `DINNER` presumed to exist but not yet observed on this account.
- `foodId` — from a prior search result's `foodMetaData.foodId`.
- `servingId` — from that same food's chosen `nutritionContents[i].servingId`.
- `numberOfUnits` — quantity multiplier against that serving (a read entry showed both a fractional `servingQty` at the top level and a `numberOfUnits` inside `nutritionContent` — which of the two a write actually wants is unconfirmed; they may be aliases or may serve different purposes).

**Fields observed on read but presumed server-assigned, not client-supplied:** `id`, `logId`, `logTimestamp`, `logSource` (observed value: `GCM`), `logCategory` (observed value: `REGULAR_LOG`), `mealId` (numeric, appears to be a per-day-instance meal identifier rather than a stable enum — `customMealId` may be the more useful client-facing handle).

## The read shape this must eventually match

A single `loggedFoods` entry, from `GET /nutrition-service/food/logs/{date}` (field names only; no real values reproduced here — this account has real personal food data and it does not belong in a committed doc):

```json
{
  "id": "<string, appears to equal foodId>",
  "logId": "<hex string, unique per log entry, used for delete>",
  "logTimestamp": "<ISO 8601 datetime>",
  "logSource": "GCM",
  "logCategory": "REGULAR_LOG",
  "servingQty": 0.7,
  "foodMetaData": {
    "foodId": "<string>",
    "foodName": "<string>",
    "foodType": "<string, e.g. BRAND>",
    "brandName": "<string, optional>",
    "source": "GARMIN | FATSECRET",
    "regionCode": "<string, e.g. CZ>",
    "languageCode": "<string, e.g. en>",
    "customFoodType": "FOOD"
  },
  "nutritionContent": {
    "servingId": "<string>",
    "servingUnit": "<string, e.g. G or 100g>",
    "numberOfUnits": 100,
    "calories": 65,
    "carbs": 13,
    "protein": 0.3,
    "fat": 0.4,
    "fiber": 16,
    "sugar": 1.6,
    "saturatedFat": 0.8,
    "sodium": 4,
    "unitHasServing": false
  },
  "isFavorite": true,
  "mealId": 966545,
  "customMealId": 185179,
  "mealTime": "06:01:41",
  "foodInactive": false,
  "type": "FOOD"
}
```

## The nutrition day is not calendar midnight-to-midnight

`GET /nutrition-service/food/logs/{date}` returned `dayStartTime: "04:00:00"` and `dayEndTime: "17:00:00"` on the day this was observed. This is a **major** finding for anything computing "today" client-side: the widget/Control's local-date logic must not assume a nutrition day starts at 00:00. Whether this window is a fixed account setting, tied to the user's sleep schedule, or something else entirely is unconfirmed — but it must be read from the API response, never hardcoded.

## An important surprise: the account already has real nutrition data

While probing the read route, real logged food was found on the account for the current date — `logSource: "GCM"` (Garmin Connect Mobile), Czech food names, multiple meals. This means:

- Connect+ nutrition tracking is **already active and in use** on this account, most likely confirming task 1.1's entitlement question without needing to check the subscription screen separately.
- The `usersummary-service/usersummary/daily` route's `consumedKilocalories` field was `null` even while this real data existed — **that field is not fed by the nutrition-service data at all**. Any surface that reads "today's consumed calories" must read `dailyNutritionContent.calories` from `food/logs/{date}`, never `consumedKilocalories` from the legacy summary route.

## Barcode scanning has poor Czech coverage (owner-confirmed, 2026-09-14)

Tried directly in the Garmin Connect app's own native barcode scanner: a Czech product barcode was **not recognized**. This is independent of whether `GET /nutrition-service/food/search/barCode` works as an API route — if Garmin's own first-party client can't resolve a Czech barcode, the underlying database (FatSecret + Garmin's own catalog) simply doesn't have the coverage, and building a client-side barcode feature on top of it would mostly hit dead ends for this project's primary use case.

**Consequence:** barcode scanning is deprioritized in `add-food-log-core` (see that change's design.md D3) — not removed, since it may still work for non-Czech/international packaged goods, but it should not be treated as a reliable primary entry path the way text search is (`rohlik` → 13 real Czech results, confirmed working). Owner decision, 2026-09-14: do not spend further effort probing or testing the barcode route for now.

## What remains genuinely unconfirmed

1. The exact JSON body Content-Type and field spelling/order for `createFoodLogEntry`.
2. Whether `numberOfUnits` or `servingQty` (or both) is the client-supplied quantity field on write.
3. The full `mealType` enum beyond the confirmed `BREAKFAST` value.
4. Whether any write route is gated behind Connect+ specifically, versus being open to any account (no 402/403 has been observed anywhere, including reads, but nothing has attempted a write yet).
5. Whether `foodSearchAutocomplete`, `mealsForDate`, `recentFoods`, `nutritionCurrentStatus`, and `calorieSummaryDaily` behave as their names suggest — found as string literals, not yet exercised live.

Resolving 1-3 is the single highest-value remaining task before any Swift implementation begins.

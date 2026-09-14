## 1. Settle the entitlement question

- [ ] 1.1 Confirm whether the Garmin account has an active Connect+ subscription (Connect app → account → subscription). Record yes/no; if no, decide whether to buy one month for the experiment before continuing.
- [ ] 1.2 In the Garmin Connect iOS app, log three foods by hand on today's date: one searched generic food, one barcode-scanned packaged product, one custom food. Use a distinctive item so it is easy to find and delete later.
- [ ] 1.3 Re-run `node tools/probe-garmin-nutrition.mjs --date <that date> --dump`. Record every status code. A route that was 404 while empty and stays 404 with data present is genuinely absent, not lazily created.
- [ ] 1.4 **Gate.** Record the verdict: does `consumedKilocalories` in `/usersummary-service/usersummary/daily` become non-null after logging by hand? If it does not, Garmin's nutrition data does not reach the summary surface and the project's premise needs revisiting.

## 2. Discover the food-log routes

- [ ] 2.1 Obtain the Garmin Connect Android APK (version 5.20.0.20 or later — nutrition shipped in 5.20.0.20).
- [ ] 2.2 Decompile with `jadx`. Grep the output for `nutrition-service`, `foodLog`, `searchFood`, `mealType`, and `servingId`. Record every distinct URL literal found.
- [ ] 2.3 Extract the request DTOs for food-log create/update/delete: field names, types, and any enum constants (especially the meal-type enumeration).
- [ ] 2.4 Verify each discovered READ route live with `node tools/garmin-get.mjs <path>`. Record status and payload shape. Do not exercise write routes yet.
- [ ] 2.5 If decompilation yields nothing usable, fall back to intercepting the iOS app with mitmproxy or Proxyman. Record whether certificate pinning blocks it — a negative result is still a result, and it closes the option.

## 3. Build the registry and harness

- [ ] 3.1 Create `docs/garmin-routes.json`. One entry per logical operation with `method`, `path`, `lastVerified`, `observedStatus`, `notes`. Seed it with the routes already verified on 2026-09-14.
- [ ] 3.2 Refactor `tools/probe-garmin-nutrition.mjs` to read its route list from `docs/garmin-routes.json` instead of a hardcoded array, so documentation and verification cannot drift.
- [ ] 3.3 Make the harness classify and report 400 / 401 / 402 / 403 / 404 / 429 distinctly, and print 400 response bodies in full — Garmin's validators name the missing field, which is how `searchExpression` was found.
- [ ] 3.4 **Gate.** If no write route has been found by this point, stop and choose a fallback from design.md D4 (read-only companion, or Cronometer bridge). Do not proceed to `add-garmin-auth-and-sync` on hope.

## 4. Document the write contract

- [ ] 4.1 Write `docs/garmin-food-log-contract.md`: the write route's method, path, request body with every field, the meal-type enumeration, the response shape, and the observed status codes for success and for each rejection.
- [ ] 4.2 Record how an entry is identified for update and delete — entry id, or the `(date, mealType, foodId)` tuple.
- [ ] 4.3 Record the idempotency story: what happens when the same entry is posted twice. If Garmin has no idempotency key, note that de-duplication is the client's problem and hand that constraint to `add-garmin-auth-and-sync`.
- [ ] 4.4 Note the date each fact was observed, against each fact, not once at the top of the file.

## 5. Close the loop on the vault

- [ ] 5.1 Record that the vault's `scripts/lib/garmin.mjs` `getNutritionLog()` calls `/nutrition-service/food/log/date/{date}`, which returns 404, and that its `catch { return null }` has masked this since it was written.
- [ ] 5.2 Note the corrected route in `docs/garmin-routes.json` so `add-companion-surfaces` can fix `sync-nutrition.mjs` without repeating the investigation.

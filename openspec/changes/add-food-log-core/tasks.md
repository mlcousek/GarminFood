## 12. Food catalog and search

- [ ] 12.1 Build `FoodCatalog.search(term:)` calling `GET /nutrition-service/food/search?searchExpression=<term>` through `GarminKit`, with a short in-memory cache keyed by search term.
- [ ] 12.2 Model the response: `Food` (foodId, name, source, images) and `Serving` (servingId, unit, numberOfUnits, full macro/micro breakdown) as separate types, since one food has many servings.
- [ ] 12.3 Verify Czech-language search terms return usable results as part of test coverage (`rohlik`, `chleba`, `tvaroh`) — confirmed reachable 2026-09-14, but pin it with a test rather than trusting the one-off probe forever.

## 13. Local ranking

- [ ] 13.1 Add a local usage log: `(foodId, servingId, numberOfUnits, timestamp)` appended on every successful log, independent of Garmin's own `isFavorite`/`isRecent` flags.
- [ ] 13.2 Build the "quick pick" ranking from recency + frequency. Surface the top N as the default set a Control or widget quick-add button can bind to.
- [ ] 13.3 Cache the per-food serving default (design.md D2) and pre-select it whenever that food is picked again, while keeping it editable.

## 14. Barcode scanning

- [ ] 14.1 Implement the `DataScannerViewController` flow scoped to `[.ean13, .ean8, .upce, .code128, .itf14, .gs1DataBar]`, gated on `DataScannerViewController.isSupported` and `.isAvailable`.
- [ ] 14.2 Implement UPC-A/EAN-13 normalisation (design.md D3): try the scanned code as-is, then with the leading zero stripped, before falling back to custom-food creation.
- [ ] 14.3 Add `NSCameraUsageDescription` and verify the scanner degrades to "unavailable" messaging on unsupported hardware rather than crashing.

## 15. Custom foods

- [ ] 15.1 Build the custom-food editor: name, serving unit, and the macro fields the write contract requires (per `establish-garmin-nutrition-contract` task 4).
- [ ] 15.2 Store custom foods locally with the same shape as a Garmin food/serving pair, so the log-entry flow treats them identically.
- [ ] 15.3 Once `establish-garmin-nutrition-contract` settles whether custom-food creation is possible via the API, wire it up; if not, implement the best-fit-existing-food fallback from design.md D4 and surface the discrepancy to the user.

## 16. Log-entry flow

- [ ] 16.1 Build the confirm screen: chosen food, chosen serving, quantity, meal type, date (defaulting to today, editable for a late log).
- [ ] 16.2 On confirm, hand the entry to `garmin-sync`'s per-process outbox (from `add-garmin-auth-and-sync`) and update the local usage log (13.1) in the same action.
- [ ] 16.3 Confirm the flow completes with zero network wait: simulate airplane mode and verify the confirm screen still commits the entry instantly.

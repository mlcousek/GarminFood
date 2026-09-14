## 12. Food catalog and search

**Implemented as `ios/FoodLogCore` (`FoodCatalogSearch.swift`, `Food.swift`) + `ios/GarminFood/Catalog/FoodCatalogView.swift`, 2026-09-14. Compiles by inspection and unit tests pass by inspection -- no local Swift/Xcode toolchain was available to actually run `swift build`/`swift test`; CI is the first real compiler this code sees. See the implementation report for exactly what that means.**

- [x] 12.1 `FoodCatalogSearch.search(term:)` calls `GarminClient.searchFood(term:)` (via the `FoodSearching` seam, for testability) with a short in-memory cache keyed by search term, capped at 50 entries.
- [x] 12.2 `Food` (id, name, brandName, source, servings, imageURL, Garmin's own isFavorite/isRecent) and `Serving` (id, unit, numberOfUnits, full macro/micro breakdown) modeled as separate types in `FoodLogCore/Food.swift`, adapted from GarminKit's `FoodSearchResult`/`NutritionContent`. `imageURL` is always `nil` today -- Garmin's confirmed response shape carries no image field (documented in Food.swift's header); kept as a forward-compatible optional rather than dropped.
- [x] 12.3 Czech-term decoding pinned with `FoodCatalogSearchTests.testCzechLanguageSearchTermsProduceUsableFoods` (`rohlik`, `chleba`, `tvaroh` fixtures, matching the confirmed real response shape). This pins the DECODING path only -- it cannot re-verify against Garmin's live server without a network call, which this test suite deliberately never makes.

## 13. Local ranking

**Implemented as `ios/FoodLogCore` (`UsageHistory.swift`, `ServingDefaults.swift`), 2026-09-14.**

- [x] 13.1 `UsageHistoryStore` appends `(foodId, servingId, numberOfUnits, timestamp)` to a JSON file on every successful log (wired into `LogEntryCoordinator.confirm`/`confirmCustomFood`), independent of Garmin's own flags. Storage format documented plainly in the file header for `add-gamification` to read.
- [x] 13.2 `QuickPick.rank(events:)` ranks by a recency-weighted-frequency score (`0.5 ^ (ageInDays / halfLifeDays)`, summed per food+serving pair); the app's `FoodCatalogView` surfaces the top entries as the "Quick pick" shelf. Not yet consumed by a Control/widget quick-add button -- that's `add-glanceable-surfaces`' job, per this change's own non-goals.
- [x] 13.3 `ServingDefaultStore` + `ServingResolution.resolve` cache and pre-select the per-food serving default, editable via `ServingPickerSheet`; a stale/unknown remembered `servingId` resolves to `nil` (re-prompt) rather than guessing, per design.md's named risk.

## 14. Barcode scanning

**Implemented as `ios/GarminFood/Catalog/BarcodeScanner.swift` + `BarcodeScanScreen.swift` + `FoodLogCore/BarcodeResolution.swift`, 2026-09-14 -- functional per this change's own deprioritization (design.md D3), not polished. UNVERIFIED ON A REAL DEVICE OR SIMULATOR (no Mac/Xcode available to this implementation pass); CI's `xcodebuild build`/archive is the first real check this code gets.**

- [x] 14.1 `DataScannerViewController` flow scoped to `[.ean13, .ean8, .upce, .code128, .itf14, .gs1DataBar]`, gated on `DataScannerViewController.isSupported`/`.isAvailable` (`BarcodeScannerAvailability`). The exact `DataScannerViewController` initializer parameter order used is a best-effort recollection, not verified against the real SDK -- flagged explicitly in the implementation report as the one line most likely to need a CI-driven fix.
- [x] 14.2 `BarcodeNormalization.candidates(forScanned:)` tries the scanned code as-is, then the leading-zero-stripped 12-digit form, before `BarcodeScanScreen` falls back to custom-food creation (pre-filled with the scanned code as a note) on total non-resolution. Unit-tested in `BarcodeResolutionTests.swift`.
- [x] 14.3 `NSCameraUsageDescription` added to `ios/project.yml`. `BarcodeScanScreen` shows an explicit "Scanner unavailable" `EmptyStateView` when unsupported, rather than presenting a broken camera view -- NOT verified on real unsupported hardware, since none was available to this pass.

## 15. Custom foods

**Implemented as `ios/FoodLogCore/CustomFood.swift` + `ios/GarminFood/CustomFood/CustomFoodEditorView.swift`, 2026-09-14.**

- [x] 15.1 Custom-food editor built: name, brand, serving unit, quantity, and calories/carbs/protein/fat/sugar/sodium macro fields.
- [x] 15.2 Custom foods store the same `Food`/`Serving` shape a Garmin food does (`CustomFoodDraft.asFood()`), so `LogEntryConfirmView` treats them identically for display and quick-pick purposes.
- [x] 15.3 **Implements the "if not possible" branch only, deliberately, per this task's own conditional wording.** `establish-garmin-nutrition-contract`'s `createCustomFood` route remains "documented, not exercised" as of this pass -- genuinely unconfirmed, not settled -- so no code here calls it. Instead: a custom food REQUIRES a user-picked backing Garmin food+serving at creation time (via `FoodCatalogView(mode: .pickBackingFood)`) plus a quantity multiplier; logging it sends the BACKING food/serving to `Outbox`, scaled by that multiplier, and `LogEntryConfirmView` surfaces `CustomFoodDraft.discrepancyNote` ("Recorded in Garmin as \"X\"...") to the user on confirm, per design.md D4 and the food-catalog spec's "discrepancy... shown to the user" requirement. Wiring the real API, if it's ever confirmed possible, is additive (see CustomFood.swift's header comment) -- not attempted now, per config.yaml's "no task writes to the Garmin account before the write contract is documented" rule.

## 16. Log-entry flow

**Implemented as `ios/FoodLogCore/LogEntryCoordinator.swift` + `MealTypeDefaulting.swift` + `ios/GarminFood/LogEntry/LogEntryConfirmView.swift`, 2026-09-14.**

- [x] 16.1 Confirm screen built: chosen food/serving, quantity (stepper), meal type (segmented picker, defaulted from time of day via `MealTypeDefaulting.defaultMealType`, unit-tested), date (`DatePicker`, defaulting to today via `NutritionDate.todayString`, editable).
- [x] 16.2 On confirm, `LogEntryCoordinator.confirm`/`confirmCustomFood` calls `GarminKit.Outbox.logFood` (the hand-off to `garmin-sync`'s per-process outbox) AND updates `UsageHistoryStore`/`ServingDefaultStore` in the same coordinator method -- not two separate, separately-failable actions.
- [ ] 16.3 **Not run.** "Simulate airplane mode... verify the confirm screen still commits the entry instantly" needs a real device or simulator, neither available to this implementation pass. Structurally true by construction instead -- `Outbox.logFood` (GarminKit, already unit-tested in `OutboxTests.swift`) only appends to a local JSON file and returns, and `LogEntryCoordinator`'s own tests (`LogEntryCoordinatorTests.swift`) confirm the entry is enqueued and durable without mocking or requiring network access -- but an actual airplane-mode, on-device confirmation remains outstanding.

## Cross-cutting (not in the original numbered list, done as part of this pass)

- [x] Wired `add-garmin-auth-and-sync` task 11.1 (AuthState -> actual app UI: a persistent banner, `AuthBannerView.swift`) and the "on foreground" half of task 9.5 (`AppEnvironment.refreshOnForeground()`, called from `ContentView`'s `.task`/`.onChange(of: scenePhase)`) -- both were explicitly deferred to "Phase 2" by that change's own tasks.md. `BGAppRefreshTask` registration (the background-while-closed half of 9.5) remains NOT done -- see `AppEnvironment.refreshOnForeground()`'s doc comment.
- [x] Added `GarminClient.searchFoodByBarcode(ean:)` to `ios/GarminKit` (the one change made to that already-implemented package) -- the route was already recorded in `docs/garmin-routes.json`; this just implements the client call, with the response payload shape explicitly marked UNCONFIRMED in its doc comment (no successful barcode lookup has ever been observed).

## 1. Garmin read route

- [x] 1.1 Add `CalorieSummaryDailyResponse`/`CalorieSummaryDay` to
      `GarminKit/Sources/GarminKit/GarminModels.swift`, reusing the
      existing `DailyNutritionContent`/`NutritionGoals` types for the
      per-day `nutritionContent`/`nutritionGoals` fields (both `Optional`,
      matching the route's confirmed "a day with nothing logged omits the
      key entirely" behavior).
- [x] 1.2 Add `GarminClient.calorieSummaryDaily(startDate:endDate:)`
      (`GET /nutrition-service/calorie/summary/daily`), following
      `dailyFoodLog`'s decode/error-handling pattern.
- [x] 1.3 Update `docs/garmin-routes.json`'s `calorieSummaryDaily` entry to
      record that it is now actually implemented and called by this
      project, without overclaiming fresh device verification.

## 2. Hydration streak (pure, local)

- [x] 2.1 Add `HydrationHistory.streak(for:goalML:on:calendar:)` to
      `FoodLogCore/Sources/FoodLogCore/HydrationTracking.swift` -- simple
      consecutive-day count, no grace-day forgiveness (that's a
      `Gamification`-level concept `FoodLogCore` cannot depend on).
- [x] 2.2 Unit tests in `FoodLogCoreTests/HydrationTrackingTests.swift`:
      counts a consecutive run, stops at the first shortfall day, is zero
      when today itself is short, is zero for a zero/negative goal.

## 3. App layer

- [x] 3.1 Add `GarminFood/Trends/MacroTrendLoader.swift` (`@MainActor
      @Observable`, mirrors `WeightLoader`'s shape) -- fetches ~30 days via
      `calorieSummaryDaily`, using `NutritionDayBoundary` for the date
      range, producing `[MacroTrendDay]` (oldest first, `nil` fields for
      "nothing logged", never a fabricated zero).
- [x] 3.2 Wire `trendsLoader: MacroTrendLoader` into `AppEnvironment`,
      instantiated once like every other loader, but deliberately NOT
      included in `refreshOnForeground()`'s batch -- it loads only when the
      Trends screen's own `.task` fires.
- [x] 3.3 Add `GarminFood/Trends/TrendsComponents.swift`:
      `MacroLineChartView` (one reusable actual-vs-goal line chart,
      parameterized per macro) and `HydrationTrendChartView` (a bar chart
      of daily hydration totals against the local goal), both in
      `WeightChartView`'s established Swift Charts style.
- [x] 3.4 Add `GarminFood/Trends/TrendsView.swift`: the screen itself --
      loading/error/empty states for the macro section, the four macro
      charts, the hydration streak stat + trend chart.
- [x] 3.5 Add `TrendsSummaryCard` + its `NavigationLink` to
      `ProgressViews.swift`'s `ProgressHomeView`, matching
      `WeightSummaryCard`/`HydrationSummaryCard`'s exact shape.

## 4. Verification

- [x] 4.1 Push a branch/PR so CI (`swift test` for `GarminKit`/ *Ticked 2026-09-26: merged to `main`, whose `Build iOS app` CI (package tests + app/widget build) is green (run on 0de2d46).*
      `FoodLogCore`, `xcodebuild` for the app) is the real correctness
      signal -- no local Swift toolchain to check this against first.
- [ ] 4.2 Device check (needs a real sideload): confirm
      `calorieSummaryDaily` actually decodes against the live account over
      a real 30-day range, and that a day with nothing logged renders as a
      genuine gap in the chart rather than a crash or a fabricated zero.

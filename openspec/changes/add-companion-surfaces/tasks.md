## 22. Fix the vault's Garmin nutrition read

- [ ] 22.1 Update `getNutritionLog(date)` in `scripts/lib/garmin.mjs` to call the route recorded in `establish-garmin-nutrition-contract`'s `docs/garmin-routes.json`, replacing the confirmed-dead `/nutrition-service/food/log/date/{date}` guess.
- [ ] 22.2 Update `parseNutrition()` and `parseMeals()` in `sync-nutrition.mjs` to match the real payload shape observed during that change's discovery, removing the speculative `??` fallback chains once the actual field names are known.
- [ ] 22.3 Add the loud-vs-quiet distinction: a 404 on the corrected route logs a visible `console.error` warning (route may have moved again), while a 200 with no meals logged for that date remains the current quiet "no data" behaviour.
- [ ] 22.4 Run `node scripts/sync-nutrition.mjs --days 30` against the live vault and confirm real data now populates daily-note frontmatter and `Dashboard/Nutrition.md`, where it has shown nothing since the sync was written.
- [ ] 22.5 Spot-check the corrected numbers against what the Garmin Connect app itself shows for the same day, to catch any remaining field-mapping mistake before trusting the historical backfill.

# Czech localization glossary

Shared vocabulary for translating GarminFood into Czech
(`openspec/changes/add-localization`). Every screen uses these terms so the
app reads as one voice. Add a term here before inventing a second
translation for it.

## Voice

- **Informal "ty"** throughout (`Zapiš jídlo`, `Máš 3 dny v řadě`), never
  "vy". It is a personal app for one owner.
- Short, direct labels; sentence case (only the first word capitalized).
- Units stay as symbols on screen: `kcal`, `g`, `ml`, `kg`, `min`. In
  VoiceOver text (`accessibilityLabel`/`Value`) spell them out and let
  the plural agree: "250 mililitrů", "1 kilogram", "350 kilokalorií".
- Numbers: never hard-code a separator in a translation. Displayed
  decimals come from `NumberDisplay` (FoodLogCore), which formats with the
  current locale, so Czech gets the decimal comma ("0,70") automatically.
  Typed input accepts both "," and "." (`DecimalInput`).
- Plurals use `variations.plural` with `one` / `few` / `many` / `other`
  (`1 den`, `2 dny`, `1,5 dne`, `5 dní`).
- Never glue a sentence from translated fragments; translate the whole
  sentence with placeholders (`%@`, `%lld`, `%lf`).

## Terms

| English | Czech | Notes |
|---|---|---|
| Breakfast | Snídaně | |
| Lunch | Oběd | |
| Dinner | Večeře | |
| Snack / Snacks | Svačina | Garmin's "Snacks" meal slot |
| Food log | Deník jídla | |
| Log (verb) | Zapsat | imperative "Zapiš"; noun "záznam" |
| Food (an item) | Jídlo / potravina | "jídlo" in UI copy; "potravina" only where "jídlo" would read as a meal |
| Meal (breakfast, lunch...) | Jídlo | a meal slot; "chod" only for a course within one meal, which the app does not use |
| Meal (a saved preset) | Jídlo | "Nové jídlo", "Jídla" (Log Food shelf); "surovina" / "suroviny" for its ingredients |
| Serving | Porce | |
| Calories / kcal | Kalorie / kcal | |
| Protein | Bílkoviny | |
| Carbs | Sacharidy | |
| Fat | Tuky | |
| Fiber | Vláknina | |
| Water / Hydration | Voda | |
| Weight | Váha | |
| Goal | Cíl | |
| Streak | Série | "série 5 dní" |
| Level | Úroveň | |
| Challenge | Výzva | |
| Badge / Achievement | Odznak | |
| Fast / Fasting | Půst | |
| Note | Poznámka | |
| Sync | Synchronizace | verb "synchronizovat" |
| Garmin / Garmin Connect | Garmin / Garmin Connect | never translated |

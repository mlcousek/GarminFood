# Czech localization glossary

Shared vocabulary for translating GarminFood into Czech
(`openspec/changes/add-localization`). Every screen uses these terms so the
app reads as one voice. Add a term here before inventing a second
translation for it.

## Voice

- **Informal "ty"** throughout (`Zapiš jídlo`, `Máš 3 dny v řadě`), never
  "vy". It is a personal app for one owner.
- Short, direct labels; sentence case (only the first word capitalized).
- Units stay as symbols: `kcal`, `g`, `ml`, `kg`, `min`.
- Numbers: do not change number formatting in translations (the decimal
  comma is a separate Wave 6 fix in `NumberDisplay`).
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

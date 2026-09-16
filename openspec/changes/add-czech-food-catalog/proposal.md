## Why

Garmin's food database (FatSecret-backed) has real gaps for Czech products — it's why barcode scanning got deprioritized earlier in this project. The owner asked for a second, Czech-focused source, similar in spirit to Kalorické tabulky (a well-known Czech nutrition site). That specific site's database is proprietary and not something this project can scrape or copy. **Open Food Facts** (openfoodfacts.org) is the legitimate equivalent: a free, openly-licensed (ODbL), crowdsourced product database with substantial real Czech coverage, confirmed live during this change's research (a country-filtered search for "tvaroh" returned 134 real Czech products from brands like Pilos and Milko z Poděbrad, with full per-100g macros).

The two catalogs need to work together, not just sit side by side: logging a Czech-database food should still end up correctly recorded in Garmin, since Garmin remains this project's single system of record (`garmin-sync`'s existing rule). That means searching Garmin for an equivalent food first, and only when nothing matches, creating a new food in Garmin with the Czech source's own values.

## What Changes

- Add an **Open Food Facts client**: search by term (optionally country-filtered to Czech Republic), using the confirmed-working legacy `/cgi/search.pl` endpoint — the only OFF endpoint that supports free-text search today; the modern v2/v3 API explicitly does not, and the newer full-text replacement (Search-a-licious) has no stable, confirmed request shape yet.
- Add a **two-source catalog UI**: Garmin results and Czech (Open Food Facts) results shown as clearly separated sections, never silently merged — the user always knows which database an item came from.
- Add **Garmin-equivalent matching**: when a Czech-database food is chosen to log, search Garmin by name for a candidate match before doing anything else.
- Add **create-in-Garmin as an explicit, confirmed fallback**: if no acceptable Garmin match exists, offer to create a new Garmin food with the Czech source's values — via Garmin's `createCustomFood` route, which is real (found in the decompiled Android client) but whose request body has never been reverse-engineered field-by-field, unlike the main food-log write. This is the same category of risk as the original food-log write, and gets the same treatment: real code, but never auto-triggered — the user sees and confirms exactly what will be created before it happens.

## Capabilities

### New Capabilities

- `czech-food-catalog` - searching and displaying Open Food Facts results, Czech-filterable, alongside Garmin's own catalog.
- `garmin-food-matching` - finding a Garmin-side equivalent for a Czech-database food, and creating one in Garmin (with explicit confirmation) when none exists.

### Modified Capabilities

- `food-catalog` - the search screen gains a second source; logging flow gains a matching/creation step for foods that originated from it. (See `add-food-log-core`'s existing capability — this change extends its UI and log-entry path, it does not replace them.)

## Non-goals

- **Scraping or mirroring any proprietary Czech nutrition database** (Kalorické tabulky or otherwise). Open Food Facts is the legitimate substitute, not an attempt to reproduce a specific competitor's dataset.
- **Bundling an offline copy of Open Food Facts.** It's queried live, the same way Garmin's own catalog already is — no local database ships with the app.
- **Automatic, unconfirmed creation of Garmin foods.** Every creation is a visible, user-confirmed action, exactly like the project's existing rule for the first real food-log write.
- **Fuzzy-merging Garmin and OFF results into one ranked list.** They stay visibly separate sources; blending them would hide which database backs a given result, which matters once creation-in-Garmin is involved.

## Impact

Affected surfaces: a new `OpenFoodFactsClient` (in `FoodLogCore`, alongside the existing `FoodCatalogSearch`), matching logic, the food catalog UI (`FoodCatalogView` gains a source picker/second section), and one new Garmin write path (`createCustomFood`) in `GarminKit`.

**Depends on**: `add-food-log-core` (extends its catalog and log-entry flow) and `add-garmin-auth-and-sync` (the new Garmin write goes through the existing `GarminClient`/`Outbox` machinery).

**Unblocks**: nothing further planned.

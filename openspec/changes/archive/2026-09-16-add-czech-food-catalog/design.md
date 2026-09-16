## Context

Two API surfaces are involved, both undocumented in different ways:

**Open Food Facts.** Its modern v2/v3 API is well-documented but explicitly does not support free-text search — only tag/field-filtered search. Free-text search only exists on the legacy `/cgi/search.pl` endpoint (marked "not recommended for new integrations" by OFF's own docs, but stable and long-lived) or the in-development Search-a-licious service (no confirmed request/response shape available). Confirmed live during this change's research (2026-09-16): `GET /cgi/search.pl?search_terms={term}&json=1&page_size={n}&fields={...}` returns real results; adding `&tagtype_0=countries&tag_contains_0=contains&tag_0=czech-republic` filters to Czech products specifically (134 real matches for "tvaroh", including brands Pilos and Milko z Poděbrad). A custom `User-Agent` header containing certain strings appears to trigger a block (returned an HTML challenge page instead of JSON in testing); the default fetch User-Agent worked. This needs re-verification with a proper, OFF-etiquette-compliant descriptive User-Agent once real device testing is possible — sending no identifying UA at all is not good API citizenship long-term, even though it worked in this test.

**Garmin's `createCustomFood`.** Found as a route in the decompiled Android client (`docs/garmin-routes.json`), but — unlike `createFoodLogEntry`, which had Kotlin `toString()` fragments hinting at field names — no field-level information was ever extracted for this route. Its request body is a genuine guess, informed only by what fields a "food" conceptually needs (name, serving unit, macros) and by the shape Garmin's own search results already use for other foods.

## Goals / Non-Goals

**Goals:**

- A Czech product search that actually finds real Czech items Garmin's own database misses.
- Logging a Czech-database food never leaves Garmin as an incomplete or inconsistent record — either it's logged against a real Garmin food, or a new one is created with matching values.
- The riskier operation (creating data in Garmin) is never silent.

**Non-Goals:**

- Perfect matching. A reasonable, explainable heuristic is enough; the user always sees what was matched (or that nothing was) before anything is logged.
- Confirming Open Food Facts data is more accurate than Garmin's — it isn't necessarily; it's a different crowdsourced source with its own gaps. The point is coverage, not authority.

## Decisions

### D1 — Open Food Facts over scraping a proprietary Czech site

Stated plainly: Kalorické tabulky's compiled database is their own property. Open Food Facts is openly licensed (ODbL) specifically so it can be used this way, and has genuine Czech coverage from Czech contributors and shoppers scanning real local products. This is the legitimate version of what was asked for, not a workaround.

### D2 — The legacy `/cgi/search.pl` endpoint, confirmed live, not the newer unconfirmed one

Free-text search is the whole point of this feature (searching by name, the same way Garmin's catalog already works) — v2/v3's tag-only search can't do that. Between the two text-search-capable options, the legacy endpoint was chosen because it was directly tested and confirmed working today, while Search-a-licious's exact request/response contract could not be confirmed from available documentation. If Search-a-licious matures into a documented, stable API, migrating is a contained change to one client file.

### D3 — Matching is name-based, case/diacritic-insensitive, and always shown to the user before logging

A Czech-database food is matched against Garmin search results for the same term by comparing normalized names (lowercased, diacritics stripped, common packaging words like sizes/quantities ignored) and, where available, a rough sanity check that calorie values are in the same neighborhood (within ~20%) — a name match with wildly different calories is more likely a false positive than a real equivalent. The result is always shown to the user as "Found a match: X" or "No match found" before either logging or offering creation — never resolved invisibly, so a bad match is caught by a human, not compounded silently.

### D4 — Creating a Garmin food is real code, gated exactly like the original write

The proposal states this; the mechanism: `GarminClient.createCustomFood(...)` exists and is wired into the outbox/delivery path the same way `createFoodLogEntry` already is, but the UI never calls it without the user explicitly tapping "Create in Garmin" after reviewing the exact name and macro values that will be sent. This mirrors `add-garmin-auth-and-sync` task 11.4's rule precisely: real code, first real invocation is a deliberate human action.

### D5 — Two visibly separate sections, not a merged list

Blending Garmin and OFF results by relevance would hide which database an item came from — and that distinction stops being cosmetic the moment matching/creation is involved, since the user needs to know whether picking a result means "log directly" (Garmin) or "match-or-create" (OFF). The catalog UI keeps two clearly labeled sections.

## Risks / Trade-offs

- **The legacy OFF endpoint could be deprecated or rate-limited without notice** → it's explicitly marked "not recommended for new integrations" by its own maintainers. Accepted for now since it's the only working free-text option; migrating to Search-a-licious once it's documented is a contained future change.
- **`createCustomFood`'s request body is a genuine guess** → if it's wrong, the create action will simply fail with an error the user sees (per this project's existing loud-failure convention), not silently corrupt data. Worth explicit user-facing wording that this is an experimental path.
- **Name-based matching will sometimes miss a real equivalent or suggest a wrong one** → mitigated by D3's always-show-before-acting rule, not by trying to make the heuristic perfect.

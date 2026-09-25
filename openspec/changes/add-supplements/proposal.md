## Why

The owner just ordered supplements (creatine, magnesium, vitamins C and D,
zinc, omega-3 …). They want to track them in the same app they already open
several times a day, with reminders, so the stack is actually taken
consistently. They also want to know whether a product is any good and how
much of each ingredient they get in total. Garmin Connect has no supplement
tracking, so the app can offer this without fighting Garmin, and it works
equally for the owner's fiancée in standalone mode.

## What Changes

- **Off by default.** A Settings switch "Supplements", off by default.
  Enabling it shows the Supplements screen, the Today quick-track card,
  reminders and supplement challenges and badges. Disabling hides all of it
  and keeps the data; badges already earned stay in Achievements.
- **My stack.** Products are added from:
  - a **built-in catalog** of common supplements (creatine monohydrate;
    magnesium citrate, bisglycinate and oxide; D3; D3+K2; C; zinc; omega-3
    from fish or algae; B12; iron; electrolytes; caffeine; beta-alanine…),
    with default serving, unit and a linked evidence card, in English and
    Czech;
  - a **custom product** with name, brand and ingredients per serving;
  - a **barcode scan** that prefills name and brand from Open Food Facts,
    falling back to the NIH DSLD database for US products. The user
    confirms or enters the ingredient amounts.

  Multi-ingredient products (multivitamin, ZMA) count toward each
  ingredient's daily total.
- **Schedule.** Each product has a dose, one or more **time slots**
  (morning, with breakfast, pre-workout, evening, or custom) and a pattern:
  - daily;
  - every N days;
  - chosen weekdays;
  - **training days**, from Garmin activities where available, plus days
    tagged "race";
  - **cycles**, e.g. a creatine loading week then maintenance, or 8 weeks on
    and 4 off.
- **Daily checklist.**
  - Tick items individually or "Take all" for a slot.
  - One-off extra doses can be logged.
  - Yesterday's checklist can be fixed from the Supplements screen.
  - A day where everything planned was taken counts as **stack complete**.
    Days with nothing planned are neutral.
- **Today card, placed with the layout editor.** Two layouts: *current slot
  checklist* (the next due slot with one-tap ticks and "Take all") or
  *whole day* pills.
- **Reminders per time slot.** Each slot has a reminder that is sent only if
  that slot isn't done yet, with a **"Taken" action** on the notification
  that ticks the slot without opening the app.
- **Stock and cost.**
  - Pack size and price per pack.
  - Each tick subtracts from stock.
  - A reorder reminder fires about N days before running out.
  - Cost per day and per month.
- **Insights.**
  - Adherence history: a calendar/heatmap per product and overall, with %
    taken over 7 and 30 days.
  - Today's **ingredient totals** from all products, against the user's
    target and upper limit.
  - A stock overview.
  - Cost.
- **Evidence and safety (informational only).**
  - Offline **evidence cards** per ingredient: what it's for, evidence
    strength, typical dose, best timing, and the safe upper limit. Sources
    cited (EFSA, NIH ODS, ISSN), with a "not medical advice" disclaimer.
  - **Upper-limit warnings** when the daily total of an ingredient goes over
    its limit. Limits are **user-editable**: EFSA defaults, and e.g. an
    endurance athlete can raise their magnesium or sodium limit.
- **"Label score" and certification.** No free external quality rating
  exists (see design D7). Instead:
  - a transparent in-app **label score** from label transparency, dose
    against the evidence, and headroom under the upper limit, with an
    explanation of how it was computed;
  - a **"Verify certification"** link to the NSF Certified for Sport,
    Informed Sport and Kölner Liste search pages, and a badge the user sets
    manually.
- **Gamification.**
  - A supplement **consistency streak** (stack-complete days), protected by
    the **same streak-freeze pool** as the food streak.
  - Badges, e.g. "30 days of creatine", "Sunshine" (60 days of D3 in
    Oct–Mar), "Full stack week".
  - Supplement challenges in the rotation, only while the feature is on.
  - A "vitamin alphabet" collection and a creatine journey (grams taken →
    milestones).
  - All XP is priced through `rebalance-xp-economy`, so enabling the feature
    doesn't speed up levelling.

## Capabilities

### New Capabilities

- `supplement-tracking` - enabling, stack management, schedules, daily
  checklist, Today card, stock and cost, adherence history.
- `supplement-reminders` - per-slot reminders with a "Taken" action and
  reorder reminders.
- `supplement-evidence` - evidence cards, ingredient totals, editable
  targets and upper limits, warnings, label score, certification links,
  barcode prefill.
- `supplement-gamification` - streak with the shared freeze pool, badges,
  challenges, collection and journey.

### Modified Capabilities

(none; the Today layout gains a card through the existing card registry)

## Non-goals

- Writing anything to Garmin. Supplements are local only. Calorie-bearing
  products such as protein powder are still logged as food.
- Medical advice, drug–supplement interaction checking, or telling the user
  to start or stop anything.
- Siri, Shortcuts or Control Center surfaces. The owner chose only the
  notification action.
- An external quality rating API. None is usable (design D7). Revisit if a
  licensable source appears.
- A per-day XP cap. That is owned by `rebalance-xp-economy`.
- "Skipped on purpose" marks. Not chosen; neutral days come from schedule
  patterns.

## Impact

- New `Supplements` area in FoodLogCore (pure models, schedule evaluation,
  totals, stores) and an app screen folder `GarminFood/Supplements/`.
- New stores registered in `AppServices`.
- New Today card id in AppearanceKit's card registry.
- New reminder kinds in `NotificationPlanning`.
- A new gamification feature in the registry.
- Czech and English strings throughout, with a new glossary section.
- **Depends on**:
  - `rebalance-xp-economy` (XP pricing);
  - `add-themes-and-layout` wave 3 (Today card registry; merged in #78);
  - `add-weekly-boss-and-streak-freezes` (freeze pool; PR #80);
  - `add-localization` (conventions).
- **Unblocks**: none planned.

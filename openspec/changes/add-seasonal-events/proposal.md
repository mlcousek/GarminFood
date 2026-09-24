## Why

The owner wants gamification *"like things from real word"*. Nothing is
more real-world for a Czech eater than the food calendar: koblihy at
Masopust, eggs and mazanec at Easter, strawberries in June, the summer grill,
mushroom picking in September, St. Martin's goose on 11 November, cukroví
through Advent, carp and potato salad on Štědrý den, chlebíčky on Silvestr and
lentils for luck on New Year's Day — plus his own name day (Jiří, 24 April).
Limited-time events give the app something new to look forward to through the
year, and a badge you can only earn in a short window feels special in a way a
permanent ladder never does.

## What Changes

- A catalog of **12 Czech seasonal and holiday events**, each with a date
  window computed per year (Easter-relative events use the Gregorian
  computus), one or more food "quests" matched by seasonal food tags, and
  its own **limited-edition badge** plus 50 XP per year completed.
- Events appear only inside their window (with a 3-day "coming soon"
  teaser): a banner on Today and an events card on the Progress tab.
- The owner's **name day**: first name derived from the Garmin profile's
  `fullName` ("Jiří Mlčoušek" → "Jiří"), looked up in a bundled Czech civil
  name-day calendar (Jiří → 24 April).
- Seasonal food tags (goose, carp, lentils, strawberries, mushrooms, cukroví,
  mazanec, chlebíček, …) in this change's own tag-rule file.
- Collector badges for completing events across seasons and a full year.

## Capabilities

### New Capabilities

- `seasonal-events` - limited-time Czech food events with date windows,
  quests, limited-edition badges, and a name-day event.

### Modified Capabilities

(none)

## Non-goals

- Religious or cultural instruction — flavour text is light and playful.
- Push-style reminders for events (the local-notification planner is not
  touched; a follow-up could add an "event starts today" reminder).
- Other countries' holidays or other people's name days.
- Changing the foundation's core tags; seasonal tags are declared here.

## Impact

Owned files only (see `add-gamification-signals` design, "Wave plan & file
ownership"): `Gamification/Sources/Gamification/Features/Seasonal/*`,
`FoodLogCore/Sources/FoodLogCore/Signals/FoodTagRules+Seasonal.swift` (stub
filled), `FoodLogCore/Sources/FoodLogCore/Signals/FoodTag+Seasonal.swift`
(new), `GarminFood/Progress/Slots/SeasonalSlotView.swift`,
`GarminFood/Today/Slots/SeasonalBannerSlot.swift`,
`GarminFood/Progress/Seasonal/*`, and tests.

**Depends on**: `add-gamification-signals` (tagger rule sets, signals,
`ProfileSignals.firstName`, feature seam, `RewardLedger`, limited-edition
badge metadata).

**Unblocks**: nothing.

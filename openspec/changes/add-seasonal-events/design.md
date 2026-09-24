## Context

Uses `add-gamification-signals`: `DaySignals` (entries with tags,
timestamps, logged date), `FoodTagRuleSet` slot `.seasonal` (stub file
`FoodTagRules+Seasonal.swift` owned here), `ProfileSignals.firstName`
(cached by `GamificationSignalsSync` from `GET
/userprofile-service/socialProfile`, confirmed 200 on 2026-09-23 — READ
only; this change adds no request), the feature seam, `RewardLedger`, and
`AchievementDefinition.edition = .limited(eventId:)`.

All dates are **logged dates** in the device's calendar (the engine's
`loggedDateBoundaryHour = 0`), so "on 1 January" means an entry whose
logged date is 1 January — a lentil soup at 00:30 on New Year's night counts
for 1 January; backfilling 1 January on 2 January also counts (the logged
date is what the owner chose).

## Decisions

### D1 — Easter by the Anonymous Gregorian computus

`SeasonalCalendar.easterSunday(year:) -> DateComponents` implements the
Meeus/Jones/Butcher algorithm (integer arithmetic only). Derived dates:
Zelený čtvrtek = Easter − 3, Velikonoční pondělí = Easter + 1, Popeleční
středa (Ash Wednesday) = Easter − 46, Masopustní úterý = Easter − 47,
Tučný čtvrtek = Easter − 52.

Test table (Western Easter Sunday): 2019-04-21, 2024-03-31, 2025-04-20,
2026-04-05, 2027-03-28, 2028-04-16, 2029-04-01, 2030-04-21, 2038-04-25.

### D2 — Event catalog (`SeasonalEventCatalog.swift`)

Each event: `id`, Czech `title` + English subtitle, `window(year) ->
ClosedRange<Date>`, `requiredQuests`, `bonusQuests`, `symbol`, badge.
A quest is `(id, title, rule)` where rule is one of
`tagOnAnyDay(FoodTag)`, `tagOnDays(FoodTag, count)`,
`tagOnDate(FoodTag, MonthDay or Easter offset)`,
`allOfTags([FoodTag]) within window`, `anyEntryOnDate`.

| id | Title | Window | Required quests | Bonus quests (+25 XP each) |
|---|---|---|---|---|
| `masopust` | Masopust | Easter −52 … −47 | a Masopust treat (koblihy, jitrnice, jelito, tlačenka, ovar, prejt, škvarky, prdelačka) | — |
| `easter` | Velikonoce | Easter −3 … +1 | eggs **and** ham (šunka/uzené) in the window | something green on Zelený čtvrtek (špenát, kopřivy, zelený salát…); mazanec or beránek |
| `name-day` | Svátek (e.g. "Jiří") | the owner's name day | log anything that day | something sweet or a cake (dort, zákusek, sweets) that day |
| `strawberries` | Jahodová sezóna | 1–30 Jun | strawberries on 5 days | — |
| `grill` | Grilovací sezóna | 21 Jun – 31 Aug | grill food (klobása, špekáček, steak, grilovaný…, čevapčiči, grilovací sýr/hermelín) on 4 days | — |
| `mushrooms` | Houbařská sezóna | 1 Sep – 31 Oct | mushrooms (houby, hříbky, smaženice, kulajda, houbová…, žampiony, bedla, hlíva) on 3 days | — |
| `st-martin` | Svatý Martin | 8–16 Nov | goose (husa, husí) | goose on 11 Nov itself; svatomartinský rohlíček |
| `mikulas` | Mikuláš | 5–6 Dec | a mandarin/orange **and** nuts or chocolate | — |
| `cukrovi` | Adventní cukroví | 1–23 Dec | cukroví (vanilkové rohlíčky, linecké, perníčky, vosí hnízda, pracny, kokosky, "cukroví") on 3 days | — |
| `stedry-den` | Štědrý den | 24 Dec | bramborový salát **and** (kapr, any fish, or řízek — both traditions count) | rybí polévka; vánočka |
| `silvestr` | Silvestr | 31 Dec | a chlebíček | jednohubky |
| `novy-rok` | Nový rok | 1 Jan | lentils (čočka) | — |

Windows never cross a year boundary, so an event instance is identified by
`(eventId, year)`.

### D3 — Seasonal tags (owned files)

`FoodTag+Seasonal.swift` declares `season.masopust, season.ham,
season.mazanec, season.greenThursday, season.strawberry, season.grill,
season.mushroom, season.goose, season.martinRohlicek, season.citrus,
season.chocolate, season.cukrovi, season.carp, season.potatoSalad,
season.fishSoup, season.vanocka, season.chlebicek, season.jednohubky,
season.lentils, season.cake`. `FoodTagRules+Seasonal.swift` fills the
`.seasonal` rule set with phrases and exclusions (e.g. "houba" in
"houbová polévka" yes, "mycí houba" no; "kapr" yes, "kapary" (capers) no;
"čočka" yes, "čočkový salát" yes). Core tags (`egg`, `fish`, `sweets`,
`nuts`, `vegetable`, `colour.green`, `schnitzel` is not core → declared
here as `season.rizek`) are reused where they fit.

### D4 — Name day

- `CzechNameDays.swift`: the Czech civil name-day calendar as a static
  `[MonthDay: [String]]` table (one or two names per day, 365 + 29 Feb
  entries), plus `nameDay(forFirstName:) -> MonthDay?` using
  `SearchText.fold` so "Jiří", "Jiri" and "JIŘÍ" all resolve.
- First name = `ProfileSignals.firstName` (first token of Garmin
  `fullName`). If unknown (never fetched, or name not in the table), the
  `name-day` event is simply absent that year and excluded from collector
  denominators.
- Known-answer tests: Jiří → 24 Apr, Jan → 24 Jun, Josef → 19 Mar,
  Václav → 28 Sep, Martin → 11 Nov, Marie → 12 Sep; an unknown name → nil.
- The event title shows the name: "Svátek má Jiří".

### D5 — Visibility

- `upcoming`: from 3 days before the window start → teaser ("Svatý Martin
  in 3 days — goose incoming").
- `active`: inside the window → Today banner (`SeasonalBannerSlot`) with
  quests and checkmarks; Progress slot shows the active event(s).
- `ended`: not shown on Today; the Progress events screen lists this year's
  finished events with their result.
- Several events can overlap (e.g. `grill` and `strawberries` in late June):
  the banner shows the one ending soonest, the Progress slot lists all.

### D6 — Rewards and persistence

- All required quests done in the window → `RewardGrant("event.<id>.<year>",
  .xp(50))`, unlock `event.<id>` (limited edition; unlocked once, ever),
  record the year in `SeasonalStore.completedYears[id]`, moment style
  `.event` ("Veselé Velikonoce! Limited badge earned").
- Each bonus quest → `event.<id>.<year>.bonus.<questId>` = 25 XP, once per
  year.
- Collector badges: `event.collector-4` (4 distinct events, rare),
  `event.collector-8` (8 distinct events, epic), `event.full-year` (every
  event available that calendar year, legendary).
- Quest progress is evaluated from signals inside the window only; once a
  required quest is satisfied it is recorded (sticky), like bingo.
- `SeasonalStore` (`features/seasonal/seasonal.json`):
  `{ completedYears: {id: [Int]}, questDone: {"<id>.<year>": {questId: day}} }`,
  Optional fields, quarantine helpers. Keeps quest progress for the current
  and previous year only.
- Badge detail shows "Earned 2026, 2027" from `completedYears`.

### D7 — Testing

- Computus table (D1); every derived date for 2026 and 2027.
- Window membership at boundaries (start day, end day, day after).
- Name-day lookups (D4) including folding.
- Tag rules golden cases (kapr/kapary, houby/mycí houba, čočka, špekáček,
  vosí hnízda, "Bramborový salát s majonézou", "Smažený kapr").
- Quest evaluation: Štědrý den with řízek + salát completes; salát alone
  does not; Easter needs both eggs and ham; St Martin bonus only on 11 Nov.
- Idempotency: same year twice → one grant; next year → new XP, same badge
  not re-unlocked, year appended.
- Name unknown → event absent and excluded from `event.full-year`.

## Risks / Trade-offs

- Fixed windows (e.g. mushroom season) are approximations of nature; wide
  windows keep them achievable.
- A family that eats řízek on Christmas Eve is common in Czechia; accepting
  both avoids a "wrong tradition" badge miss.
- The name-day table is data entry; the tests pin the owner's name and a
  handful of common ones.

## Open Questions

1. Should the owner be able to override the name (e.g. if Garmin's
   `fullName` changes)? Proposed: not now.
2. Add events for Velikonoční pondělí "pomlázka" or Valentine's day? Not in
   this change; easy to add as rows later.

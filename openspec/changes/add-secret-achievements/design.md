## Context

Replaces the `SecretAchievementsFeature` stub from
`add-gamification-signals`. Uses `SignalsSnapshot` (42 days), core tags,
`WeekKey`, `AchievementDefinition.visibility = .secret`, the feature seam
and `RewardLedger`. No network.

Definitions used below:
- **logged date** = the entry's day as the engine sees it
  (`loggedDateBoundaryHour = 0`).
- **completed day** = a logged date before today (its totals can no longer
  grow from normal use).
- Existing `achv-midnight` ("log at exactly midnight") stays as is; the
  fridge raid below is a different, wider rule.

## Decisions

### D1 — Hidden presentation

- Locked secret: tile shows a lock + "???"; title and subtitle are never
  rendered, not even to VoiceOver ("Secret achievement, locked").
- The count is shown: "3 of 15 secrets found".
- Unlocking: moment style `.secret` (distinct colour, a "reveal" flip
  animation; Reduce Motion → cross-fade), then the tile is a normal badge
  with unlock date.

### D2 — Rules (all `featureId: "secrets"` -- the registered feature id, `.featureEvaluated`)

| id | Title (revealed) | Exact rule | Rarity |
|---|---|---|---|
| `secret.fridge-raid` | Midnight Fridge Raid | an entry whose local timestamp is 00:00–03:59 **and** whose logged date equals that timestamp's calendar date (backfilling yesterday at 1 a.m. does not count) | uncommon |
| `secret.barista` | Barista Mode | ≥ 5 entries tagged `coffee` on one logged date | uncommon |
| `secret.pizza-friday` | Pizza Friday | a `pizza` entry on 4 consecutive Fridays (logged dates) | rare |
| `secret.bullseye` | Bullseye | a completed day with a calorie goal and ≥ 3 entries where round(total kcal) == round(goal kcal) | epic |
| `secret.palindrome` | Palindrome Day | a completed day with ≥ 3 entries whose round(total kcal) ≥ 1000 reads the same backwards (e.g. 1221, 2002) | rare |
| `secret.groundhog-breakfast` | Groundhog Breakfast | one `foodId` appears among breakfast entries on ≥ 30 of 35 consecutive days | epic |
| `secret.friday-13` | Friday the 13th | any entry on a logged date that is Friday the 13th (next: 2026-11-13, 2027-08-13) | rare |
| `secret.world-tour` | World Tour Week | ≥ 7 distinct `cuisine.*` tags within one ISO week | epic |
| `secret.pi-day` | Pi Day | a `pie` entry (koláč, štrúdl, pie, tart) on 14 March | rare |
| `secret.deja-vu` | Déjà Vu | two consecutive completed days with identical sets of foodIds, each with ≥ 3 distinct foods | uncommon |
| `secret.knedlik-marathon` | Knedlíkový maraton | a `knedlik` entry on 3 consecutive days | uncommon |
| `secret.gone-fishing` | Gone Fishing | a `fish` entry on 3 consecutive days | uncommon |
| `secret.vodnik` | Vodník's Apprentice | water ≥ 150 % of the water goal on one day (needs water data) | rare |
| `secret.dawn-patrol` | Dawn Patrol | an activity starting before 06:00 local and an entry within 60 min after it ends, same day (needs activities) | rare |
| `secret.answer-42` | The Answer | exactly 42 entries in one **completed** ISO week | rare |

Plus visible `secret.keeper` "Secret Keeper" — all 15 secrets unlocked
(legendary; `visibility: .normal`).

Rules deliberately avoid rewarding extremes (no "3,000 kcal day", no
"skipped dinner" secret). Adding a secret later is a table row plus one
rule function; ids are never reused.

### D3 — Evaluation

- Every run evaluates all locked secrets against the snapshot. Rules that
  need completed days/weeks ignore today/the current week.
- Retroactive within the 42-day snapshot: the first run can unlock
  secrets from recent history — a nice surprise.
- Several unlocks in one run → one combined `.secret` moment ("2 secrets
  revealed: Barista Mode, Gone Fishing").
- Rewards: unlock via the host (adds the standard
  `XPAward.achievementBonus`) plus `RewardGrant("secrets.<badge id>",
  .xp(XPAward.secretUnlocked = 50))`, e.g. `secrets.secret.barista`.
  The key MUST start with the feature's registered id `secrets` plus "."
  because `FeatureHost` drops any grant outside the feature's own
  namespace (an earlier draft said `secret.<id>`, which would have been
  silently dropped).
- No store of its own is needed: unlock state is `AchievementStore`; the
  rules are pure functions of the snapshot. (Pizza Friday and Groundhog
  Breakfast fit inside 42 days.)

### D4 — UI

- `SecretsSlotView` (Progress hub): "Secrets 3/15" with a keyhole symbol;
  taps into the Achievements screen scrolled to the Secret group (the group
  itself is rendered by the foundation's `AchievementsView`).

### D5 — Testing

One positive and at least one negative test per secret with literal
`DaySignals`, including: fridge raid backfill negative; Pizza Friday with a
gap Friday negative; Bullseye rounding (1999.6 vs goal 2000 → yes; 1998.4 →
no); palindrome 1221 yes / 999 no (under 1000) / 1231 no; Groundhog 29 of
35 no; Friday 13th on 2026-11-13 yes and 2026-03-14 no; World Tour 6
cuisines no; Déjà Vu with 2 foods no; Answer-42 in the current week no;
Vodník without water data no; combined moment for two unlocks; secret
keeper after all 15; ids unique and all marked secret except the keeper.

## Risks / Trade-offs

- Secret rules can depend on tagging quality (World Tour relies on cuisine
  tags); a missed tag only delays a surprise.
- Some secrets are rare by calendar (Pi Day, Friday the 13th) — intended.

## Open Questions

1. Should the owner get a subtle hint after, say, 6 months without new
   secrets? Default: no hints.

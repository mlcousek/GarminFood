## Context

Everything here is derived state — computed from `add-food-log-core`'s local log history and, for goal-hitting mechanics, the nutrition goals `garmin-sync` already fetches for the main display. Nothing in this change calls Garmin itself. That keeps it simple, keeps it fast (no network on the critical path of opening the progress screen), and keeps it consistent with `add-glanceable-surfaces` design.md D2's finding: none of this can ever reach a widget anyway, since a widget can't read the app's local data without an App Group.

The one real design risk worth naming up front: gamification mechanics are easy to over-build. A streak, a level curve, and a handful of challenges are enough to make logging feel rewarding. A points economy, streak insurance, seasonal events, and a badge wall are not — they're where solo projects stall. This change is scoped to the first group.

## Goals / Non-Goals

**Goals:**

- Opening the app after a logging streak shows it immediately and unambiguously — the flame and count are not buried.
- Missing one day doesn't erase weeks of consistency; the mechanic forgives being human without becoming meaningless.
- Leveling up and completing a challenge both produce a real, satisfying moment (haptic + motion), matching the config.yaml Design & UX principles.
- The whole system is a pure function of local log data — deterministic, testable without a device, no hidden server-side state.

**Non-Goals:**

- Perfect anti-gaming (someone could log a token entry just to keep a streak alive). Not worth defending against in a single-user personal app.
- Configurability (the owner tuning XP values via a settings screen). Values are constants for now; tune by changing code, not UI.

## Decisions

### D1 — The streak day boundary is the Garmin nutrition day, not local midnight

`establish-garmin-nutrition-contract` found the Garmin nutrition day is not a plain midnight-to-midnight window (`dayStartTime`/`dayEndTime` observed as 04:00–17:00 on the probed account). The streak SHALL use that same boundary rather than the device's calendar day, computed from the entry's own logged date rather than re-deriving it from a wall-clock timestamp. Two systems disagreeing about what "today" means is exactly the kind of inconsistency `garmin-sync`'s design already tries to avoid, and streaks are the mechanic most sensitive to an off-by-one day.

### D2 — A streak survives exactly one missed day per rolling week, not indefinite grace

A pure "any gap breaks it" streak is unforgiving; a streak that never breaks is meaningless. The rule: one missed day is forgiven per rolling 7-day window (a "streak shield," consumed automatically, not something the user manages or spends currency on — no monetization mechanic per the proposal's non-goals). A second miss within the same rolling week resets the streak to zero starting from the next logged day. This is simple enough to compute from the log history alone (no separate "shield inventory" state to persist) and forgiving enough to survive one bad day without becoming an achievement with no teeth.

### D3 — XP rewards consistency, not volume

Logging a food is worth a small flat XP amount — enough to feel earned, not so much that logging ten items in one sitting meaningfully outpaces logging steadily across days. Meaningfully larger XP comes from things that require actual consistency: extending the streak, hitting a day's nutrition goal, completing a challenge. The exact curve (level thresholds growing roughly geometrically) is an implementation-time tuning detail, not a spec-level requirement — the requirement is the *shape* of the incentive (reward consistency over volume), not the specific numbers.

### D4 — Challenges are a curated, hand-authored set that rotates, not a generator

V1 ships perhaps 10–15 challenge templates (streak-extension, goal-hitting, variety-seeking, per proposal.md's examples) with simple, locally-evaluable completion conditions. One or two are active at a time, rotating on completion or after a time window elapses. This is a data table plus an evaluation function, not an authoring engine — building a system flexible enough to define *arbitrary* future challenges without code changes is real complexity this change explicitly defers (per the proposal's non-goals) until there's evidence more than a curated set is actually needed.

### D5 — Level-up and challenge-completion are real UI moments, not log lines

Per config.yaml's Design & UX principles, these moments get an actual animated transition and haptic feedback (`UINotificationFeedbackGenerator.success` or similar), not a silently-updated number. This is a small, concrete requirement precisely because it's the kind of polish that's easy to skip under time pressure and is the entire point of adding gamification in the first place — a level-up nobody notices provides no motivation.

## Risks / Trade-offs

- **A streak tied to the Garmin nutrition-day boundary is more complex than local midnight** → accepted per D1; the alternative (local midnight) risks a day quietly not counting because it fell just after the Garmin day rolled over, which is a worse user experience than the extra complexity.
- **The one-miss-per-week grace rule needs a genuine edge-case test**: two misses in the same week, a miss immediately followed by a make-up day, a miss that straddles a week boundary. These are exactly the cases worth writing tests for before shipping (see tasks.md), not discovering from a confused "why did my streak reset" moment later.
- **Hand-authored challenges will feel repetitive after a few rotations** → acceptable for V1; expanding the template set is exactly the kind of "add-on" the owner explicitly wants room for later, and D4 deliberately keeps the architecture cheap to extend (add a row + an evaluation function) rather than requiring a rewrite.

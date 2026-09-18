## Why

A companion app that only removes friction from logging still loses to the boredom of logging. Apps like Duolingo and Snapchat proved that a streak, a sense of progress, and the occasional small challenge are what actually keep someone doing a small daily thing for months, not years of willpower. The owner asked directly for this: a fire-day streak, levels, challenges, "lots of add-ons" over time, and a genuinely modern, well-made feel — not a bare utility with a login screen bolted on. This change adds that layer on top of the logging core, computed entirely from data the app already has locally.

## What Changes

- Add a **streak**: consecutive days with at least one logged food entry, shown prominently (flame + count) with a defined grace mechanic for an occasional missed day, so one bad day doesn't erase months of consistency.
- Add **levels and XP**: small XP awards for logging, hitting nutrition goals, and maintaining a streak, accumulating toward levels with a deliberately unglamorous-to-grind curve — this rewards genuine consistency, not gaming the system.
- Add **challenges**: a curated, rotating set of short-horizon goals ("log breakfast 5 days this week," "try 3 new foods," "hit your protein goal 4 days running") with visible progress and a completion reward.
- Establish the **design system and motion language** this and every future screen uses — color, type, spacing, haptics, states — per `openspec/config.yaml`'s new Design & UX principles, so "modern and well-made" is a defined bar, not a vibe.

## Capabilities

### New Capabilities

- `streaks` - tracking and displaying consecutive-day logging consistency, with a grace mechanic.
- `levels` - XP accumulation and level progression from logging activity and goal-hitting.
- `challenges` - short-horizon, rotating goals with progress tracking and completion rewards.

### Modified Capabilities

None. Gamification reads from `add-food-log-core`'s local log history; it does not require that capability to change.

## Non-goals

- **Social features** (leaderboards, friends, sharing) — single-user app, no backend to support this, and not asked for.
- **Monetization mechanics** (streak-freeze purchases, premium challenges) — this is a personal app, not a product with a business model.
- **A general-purpose challenge-authoring engine.** V1 ships a curated, hand-written set of challenge templates. A dynamic/procedural challenge generator is future add-on territory, not this change.
- **Exercise-derived challenges** (e.g., combining Garmin workout data with nutrition). Worth doing later; this change is nutrition-data-only to keep scope real.
- **Widgets showing streak/level/XP.** Per `add-glanceable-surfaces` design.md D2, no widget can read the app's local data at all without an App Group — this applies to gamification state exactly as it applies to Garmin data. The streak lives in the app.

## Impact

Affected surfaces: a new `Gamification` module (streak/XP/challenge computation, all local, no network calls of its own beyond reading nutrition goals already fetched by `garmin-sync`), plus the app's main screen and a dedicated progress/challenges screen.

**Depends on**: `add-food-log-core` (needs a local log history to compute streaks from) and, loosely, `add-garmin-auth-and-sync`'s `garmin-sync` (goal-hitting challenges reference the daily nutrition goals already fetched for the main display).

**Unblocks**: nothing further planned; this can proceed in parallel with `add-glanceable-surfaces` and `add-companion-surfaces` once `add-food-log-core` exists.

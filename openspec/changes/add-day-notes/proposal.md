## Why

The owner wants a note at the bottom of each day, for things like "race",
"celebration" or "sick". When they look back they can then see why a day
looked the way it did. Garmin has no notes API, so notes stay on the phone.

In the 2026-09-23 grilling session the owner chose free text plus quick tags,
with tagged days marked in Trends.

## What Changes

- **Note card.** A "Note" card is added at the bottom of the home screen for the
  selected day, including past days reached with the day switcher. The card
  has:
  - A multi-line text field that saves as the user types (debounced), with no
    Save button.
  - Quick tags that toggle on tap: 🏃 Race, 🏋️ Training, 🎉 Celebration,
    🤒 Sick, ✈️ Travel, 🍺 Party, 😴 Rest day.
- **Trends markers.** Tagged days get a small emoji marker on the Trends
  screen's daily charts. Tapping a marker shows the note.
- **Storage.** Notes are stored locally in `DayNoteStore`, one record per
  nutrition day (`yyyy-MM-dd`), using the `PersistedJSON` quarantine loader.
  An empty note with no tags deletes the record.

## Non-goals

- Syncing to Garmin. There is no route for it.
- Custom user-defined tags. The fixed set covers the stated needs.
- Searching notes.

## Capabilities

### New Capabilities

- `day-notes`: per-day note and tags, and their markers in Trends.

## Impact

- **FoodLogCore:** a new `DayNote`/`DayNoteTag` and a `DayNoteStore` actor,
  with tests.
- **App:** `AppServices` (a new store instance), `AppEnvironment`, a new
  `DayNoteCard` on `TodayView`, and the Trends chart annotations.
- **Depends on**: nothing.
- **Unblocks**: nothing.

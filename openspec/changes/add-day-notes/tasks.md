## 1. Domain

- [x] 1.1 Add `DayNote` (day, text, tags, updatedAt), the `DayNoteTag` enum (emoji plus title), and a `DayNoteStore` actor using `PersistedJSON`. An empty note is deleted rather than stored. Tests.

## 2. App

- [x] 2.1 Register the store in `AppServices` and `AppEnvironment`.
- [x] 2.2 `DayNoteCard` at the bottom of `TodayView`: a text field with debounced save of about 600 ms, flushed when the view disappears or the app backgrounds, plus tag chips. It follows the selected day.
- [x] 2.3 Trends: `PointMark`/annotation emoji for tagged days, and tapping shows the note in a popover or sheet. (Built as a dashed `RuleMark` per tagged day with the emoji as a top-aligned annotation, so it also shows on a tagged day with nothing logged; tap opens a sheet, and VoiceOver gets one custom action per marker.)
- [x] 2.4 VoiceOver labels on the chips ("Race, selected").

## 3. Verify

- [ ] 3.1 CI green.
- [ ] 3.2 On device: write a note on a past day, reopen it, and check the Trends marker.

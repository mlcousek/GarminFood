# Data compatibility: never lose a user's data across versions

GarminFood keeps everything on the phone as JSON files under Application Support
(one small file per store, or one file per month for logs). A new build must
always read what an older build wrote. This page is the contract, and the recipe
for changing a store without breaking it. (`add-data-safety` design D1–D2.)

## The contract

1. **Additive only.** New fields are `Optional` or have a default in
   `init(from:)`. Never make an existing optional field required.
2. **Never rename or remove a key** without a decode shim that still reads the
   old key.
3. **Open enums for anything a later build may extend.** Store the raw string
   (see `IngredientID`, `DoseUnit`, `IntakeKind`) or decode an unknown case into
   a fallback (see `TimeSlot`, `SchedulePattern`). Never let one unknown value
   fail the whole file.
4. **Unreadable ≠ empty.** Load through `FoodLogCoreStorage.loadPersistedJSON`
   (or the package's equivalent):
   - A file that can't be **decoded** is moved aside (quarantined, #36), never
     overwritten.
   - A file that can't be **read** yet (before first unlock) is not latched as
     loaded. Reads throw and writes are refused (`ensureSafeToWrite`).
5. **Load before save.** Every mutation loads the file first, so a fresh
   process never writes over data it hasn't seen.
6. **Bump the store version** (`StoreCatalog`) only for a change an older build
   could misread. The backup compatibility check then refuses to restore a
   newer backup into an older build instead of losing fields.

## The safety nets

- **Old-format fixtures in CI.** `Tests/<Package>Tests/Fixtures/Stores/` holds
  one file per store, written exactly as the current code encodes it.
  `StoreFixtureTests` decodes each through the **real store** and checks the
  values. A change that can no longer read yesterday's files fails CI before it
  reaches a phone.
- **Coverage test.** `testEveryPersistedFileHasAFixture` scans the package
  sources for store file names:
  - literal `"name.json"`;
  - interpolated `"\(month).json"`.

  It fails when a store has no fixture, or when a fixture on disk isn't used by
  a test.
- **On-device snapshots.** A daily copy of all data and settings; the last 14
  are kept (Settings → Data). A restore always takes a safety snapshot first.
- **Export and import.** One backup file in Files or iCloud Drive. It survives
  deleting the app or moving to a new phone.

## Adding or changing a store: the recipe

1. Write the model change following the contract above.
2. **New store:**
   - add a fixture `Fixtures/Stores/<file name>` with realistic values, covering
     every optional field and at least one record with the optional fields
     missing;
   - list it in `allFixtures`;
   - write a `test<Store>FixtureDecodesThroughTheRealStore` that loads it
     through the real store and asserts the values.

   A month-sharded store (`"\(month).json"`) goes in `dynamicStoreFixtures`
   under that spelling.
3. **Changed store:** **never edit or delete an existing fixture.** It is the
   old format you promised to keep reading. Add a *new* fixture for the new
   shape if the test needs it, and keep the old test passing.
4. Add the store to `StoreCatalog` (id, location, schema version, backup area)
   so backups describe it.
5. Run CI. `StoreFixtureTests` in each package must pass.

## ADDED Requirements

### Requirement: Every Garmin call goes through the route registry

The MCP server SHALL only call Garmin routes listed in
`docs/garmin-routes.json`, SHALL look each route up by its `operation` name
at startup, and SHALL refuse to start a tool whose route is missing from the
registry. Each tool's description SHALL name the route and its
`lastVerified` date.

#### Scenario: Route removed from the registry

- **WHEN** the `dailyFoodLog` entry is removed from `docs/garmin-routes.json` and the server starts
- **THEN** `food.getDay` is not offered and the server's startup log names the missing operation

### Requirement: Reads use only routes verified as working

The MCP server SHALL read Garmin data only through read routes last
observed with status 200: `dailyFoodLog`
(`GET /nutrition-service/food/logs/{date}`, verified 2026-09-14),
`mealsForDate` (`GET /nutrition-service/meals/{date}`, verified
2026-09-16), `foodSearch` (`GET /nutrition-service/food/search`, verified
2026-09-23), `nutritionSettings` (`GET /nutrition-service/settings/{date}`,
verified 2026-09-23), `calorieSummaryDaily` (verified 2026-09-14),
`weighInsDayView` and `getWeighIns` (verified 2026-09-23),
`hydrationDaily` (verified 2026-09-23) and `recentFoods` (verified
2026-09-14).

#### Scenario: Today's totals

- **WHEN** Claude calls `food.getDay` for today
- **THEN** the tool returns each logged entry with meal, name, amount and macros, and the day's calorie total from `dailyNutritionContent.calories`, not from `consumedKilocalories`

### Requirement: Food-log creates use only the confirmed create route

The MCP server SHALL create food-log entries only with `createFoodLogEntry`
(`PUT /nutrition-service/food/logs`, confirmed on a device 2026-09-16),
resolving `mealId` from `mealsForDate` for the entry's date at send time,
inferring `source` from the food id when unknown, and rounding
`servingQty` to 3 decimals as the app does.

#### Scenario: Log a searched food

- **WHEN** `food.log` is confirmed for FatSecret food 12345, serving 678, quantity 1.5, meal DINNER, date 2026-10-02
- **THEN** exactly one PUT is sent with `mealDate` 2026-10-02, the DINNER `mealId` for that date, `source` FATSECRET and `servingQty` 1.5, and a read-back of that day lists the entry once

#### Scenario: Meal id not available

- **WHEN** `mealsForDate` fails for the entry's date
- **THEN** no create is sent and the tool returns an error naming the failed route

### Requirement: Direct food logs are adopted by the app

After every successful direct food-log create, the MCP server SHALL write a
`food.adopt` bridge command carrying the Garmin `logId` (read back after
the write), food id, serving id, quantity, meal, date and log time. The app
SHALL record that entry in its usage history (streak, XP, quick picks)
without enqueuing it for delivery, and SHALL treat a second adopt of the
same `logId` as already applied. If the bridge is not configured, the tool
SHALL say that the entry will not count toward streak or XP.

#### Scenario: Streak credit arrives later

- **WHEN** the owner logs lunch from the PC at 12:30 with the phone off, and opens the app at 18:00
- **THEN** Garmin shows the entry from 12:30, and after the app applies the adopt command the streak counts that day and no second copy is sent to Garmin

#### Scenario: Adopt never re-delivers

- **WHEN** a `food.adopt` command is applied
- **THEN** the food outbox gains no entry and Reconciliation never deletes the Garmin entry as a duplicate

### Requirement: Unconfirmed Garmin writes are off unless explicitly enabled

The MCP server SHALL NOT offer tools that use a write route whose registry
status is not a confirmed success (`createCustomFood`, `createCustomMeal`,
`quickAddFoodLogEntry`, `bulkCreateFoodLogEntries`, `calculateGoals`)
unless the environment variable `GARMINFOOD_MCP_EXPERIMENTAL_WRITES` names
that operation. When enabled, such a tool's description SHALL begin with
"EXPERIMENTAL — unconfirmed Garmin route", and every call SHALL require
`confirm: true` and log the full request and response to the server log.

#### Scenario: Default configuration

- **WHEN** the server starts without `GARMINFOOD_MCP_EXPERIMENTAL_WRITES`
- **THEN** the tool list contains no `garmin.createCustomFood`, `garmin.createCustomMeal` or `food.quickAdd` tool

### Requirement: Direct deletes and edits are gated and bounded

The MCP server SHALL delete food-log entries only with
`deleteFoodLogEntries` (`DELETE /nutrition-service/food/logs/{date}`,
modelled on a live-tested client, not yet exercised by this project as of
2026-09-16) and only after `confirm: true`, one date per call, for `logId`s
it has just read from that date. Until the registry records that route as
exercised by this project, the direct delete SHALL be hidden like an
experimental write, and edit/delete tools SHALL default to the bridge. An edit or move SHALL create the
replacement entry first and delete the old one only after the create
succeeded, matching the app's `replace` order.

#### Scenario: Create succeeds, delete fails

- **WHEN** `food.editEntry` creates the new entry and the delete then returns 500
- **THEN** the tool reports both the new entry and the old one still present, and does not retry the delete on its own

### Requirement: Garmin auth failures are loud and actionable

The MCP server SHALL turn a 401 or 403 from Garmin, a missing token file,
or a failed OAuth1→OAuth2 exchange into a tool error whose message says
that Garmin sign-in is needed and how to refresh the PC token, and SHALL
NOT return an empty result for it. It SHALL honour `Retry-After` on 429 and
stop, reporting the wait, instead of retrying.

#### Scenario: Expired token

- **WHEN** the token file's OAuth1 token is rejected
- **THEN** every Garmin tool call returns an error "Garmin sign-in needed on this PC" with the token path, and `bridge.status` still works

### Requirement: Garmin-direct tools refuse a standalone install

The MCP server SHALL refuse Garmin-direct write tools when the latest
bridge snapshot reports data mode `standalone`, and SHALL tell the caller
to use the bridge variant instead.

#### Scenario: Standalone snapshot

- **WHEN** `state.json` says `dataMode: standalone` and `food.log` is called with `via: "garmin"`
- **THEN** nothing is sent to Garmin and the error suggests `via: "bridge"`

# GarminFood MCP server (`tools/mcp/`)

A local MCP server that lets Claude on this PC read GarminFood's Garmin data.
It is planned in `openspec/changes/add-mcp-server`. This is wave 2: Garmin
reads only.

- It runs as a local Node process over **stdio**. It opens no network port
  and logs to stderr only.
- It calls only the Garmin routes listed in `docs/garmin-routes.json`, and
  only routes last observed with status 200. If a route is removed from
  that file, its tool disappears. `server_status` says why.
- It signs in the same way as `tools/garmin-get.mjs`: through
  `tools/lib/garmin-auth.mjs`, with the Obsidian vault's Garmin token.
- **Wave 2 writes nothing.** Food, weight and water written from the PC will
  go through the phone (the bridge), as the owner decided. The bridge tools
  come in waves 5–6.
- The generic `garmin` MCP server stays configured as it is. Its Garmin
  writes do not count toward the app's streak or XP.

## Install and build

Needs Node 22 or newer.

```powershell
cd C:\Git\Projects\GarminFood\tools\mcp
npm ci
npm run build     # compiles to dist\ (entry point: dist\src\index.js)
npm test          # builds, then runs the tests (fake HTTP, no Garmin calls)
```

Run `npm run build` again after every `git pull` that changes `tools/mcp/`.

## Configuration (environment variables)

| Variable | Meaning |
|---|---|
| `VAULT_ROOT` | The Obsidian vault that holds the Garmin token (`scripts\.garmin-tokens.json`, or the garmin-health-sync plugin's `data.json`). On this PC: `C:\Git\Projects\Jirkas_world`. |
| `GARMIN_TOKENS` | Optional. A token JSON file (`{ oauth1, oauth2 }`) to use instead of `VAULT_ROOT`. |
| `GARMINFOOD_BRIDGE_DIR` | The PC path of the bridge folder: `C:\Users\jmlcousek\iCloudDrive\GarminFood Bridge`. In wave 2 only `server_status` reads it. |
| `GARMINFOOD_MCP_EXPERIMENTAL_WRITES` | Optional. A comma-separated list of operations. Nothing uses it yet; the experimental writes come in wave 7. |

A missing token does not stop the server. The Garmin tools then fail with
"Garmin sign-in needed on this PC", and `server_status` and
`food_lookupBarcode` keep working.

## Claude Desktop (Windows)

Edit `%APPDATA%\Claude\claude_desktop_config.json`. Add `garminfood` next to
any servers already in `mcpServers`, such as the generic `garmin` one:

```json
{
  "mcpServers": {
    "garminfood": {
      "command": "node",
      "args": ["C:\\Git\\Projects\\GarminFood\\tools\\mcp\\dist\\src\\index.js"],
      "env": {
        "VAULT_ROOT": "C:\\Git\\Projects\\Jirkas_world",
        "GARMINFOOD_BRIDGE_DIR": "C:\\Users\\jmlcousek\\iCloudDrive\\GarminFood Bridge"
      }
    }
  }
}
```

Quit Claude Desktop completely (tray icon → Quit) and start it again. The
server's log is `%APPDATA%\Claude\logs\mcp-server-garminfood.log`.

## Claude Code

```powershell
claude mcp add garminfood --scope user `
  -e VAULT_ROOT=C:\Git\Projects\Jirkas_world `
  -e "GARMINFOOD_BRIDGE_DIR=C:\Users\jmlcousek\iCloudDrive\GarminFood Bridge" `
  -- node C:\Git\Projects\GarminFood\tools\mcp\dist\src\index.js
```

Check it with `claude mcp list`. Inside a session, `/mcp` shows the server
and its tools.

## Tools (wave 2)

Every tool is read-only. Each tool's description names the Garmin route it
uses and the date that route was last verified.

| Tool | Answers | Source |
|---|---|---|
| `server_status` | Whether a token file was found, the bridge folder, which tools are offered and which are not (and why), and the actions that can only be done on the phone | local, no network |
| `food_search` | Garmin food search: foods, servings and their ids. The search is diacritic-sensitive, so try "mleko" and "mléko". Region CZ by default | Garmin `foodSearch` |
| `food_getDay` | One nutrition day: meals, entries, totals and goals. The calorie total is `dailyNutritionContent.calories` | Garmin `dailyFoodLog` |
| `food_getRange` | Per-day totals and goals for up to 31 days | Garmin `calorieSummaryDaily` |
| `food_recent` | Garmin's recently logged foods. The response shape is not recorded yet, so it is read loosely | Garmin `recentFoods` |
| `weight_list` | Weigh-ins in kg with `samplePk`, up to 366 days | Garmin `getWeighIns` |
| `water_get` | The day's water total and goal in ml. Garmin keeps a day total only, not single drinks | Garmin `hydrationDaily` |
| `goals_get` | Calorie and macro goals, the weight goal and the day window (Garmin's goals only) | Garmin `nutritionSettings` |
| `food_lookupBarcode` | A product by its barcode: name, brand, nutrition per 100 g | Open Food Facts, not Garmin |

### Tool names

The design writes tool names as `area.verb`, for example `food.getDay`. The
server exposes them as `area_verb`, for example `food_getDay`. The Claude API
accepts only `[a-zA-Z0-9_-]` in tool names, so a name with a dot could be
rejected or rewritten by the client.

## Troubleshooting

- **"Garmin sign-in needed on this PC".** The token file is missing, Garmin
  rejected it (401/403), or the OAuth1 → OAuth2 exchange failed. The error
  names the token path. Get a fresh OAuth1 token with a browser sign-in (the
  vault's garmin-health-sync plugin stores it). Then check that `VAULT_ROOT`
  or `GARMIN_TOKENS` points at it, and restart the server.
- **"Garmin is rate-limiting this PC (HTTP 429)".** Wait as long as the error
  says. The server never retries on its own.
- **A tool is missing.** Run `server_status`. Under `tools.notOffered` it
  names the route that is missing from `docs/garmin-routes.json`, or that was
  not last seen with status 200.
- **`food_getDay` differs from the phone.** Entries the phone has queued but
  not yet delivered are not in Garmin yet. Garmin's nutrition day follows
  the account's day window, which is not always midnight to midnight.

## Development

- The source is in `src/`: `garmin/registry.ts`, `garmin/client.ts`,
  `garmin/auth.ts`, `tools/*.ts`, `server.ts` and `index.ts`. The tests are
  in `test/`, and their shape-only fixtures in `test/fixtures/`.
- The tests never call the live Garmin API. Every request goes through
  `test/fakeHttp.ts`, and a request with no canned reply fails the test.
  The fixtures use the field names recorded in `docs/garmin-routes.json`
  with made-up values.
- CI: `.github/workflows/mcp.yml` runs `npm ci`, `npm run build` and
  `npm test` on ubuntu with Node 22. It runs for changes to `tools/mcp/**`,
  `tools/lib/garmin-auth.mjs`, `docs/garmin-routes.json` and
  `docs/bridge-protocol/**`.

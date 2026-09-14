#!/usr/bin/env node
/**
 * probe-garmin-nutrition.mjs — READ-ONLY reconnaissance of Garmin's private
 * nutrition API for THIS account.
 *
 * This is Gate 0 of the GarminFood project. Everything else in the plan is
 * conditional on what this prints. It answers three questions:
 *
 *   1. Do our stored Garmin tokens still authenticate?        (auth alive?)
 *   2. Does /nutrition-service/ answer for this account?      (Connect+ gate?)
 *   3. Which nutrition sub-routes exist, and what shape is    (surface map)
 *      the food-log payload really in?
 *
 * It NEVER writes. No POST, PUT, PATCH or DELETE is issued. The route list
 * comes from ../docs/garmin-routes.json — the "write" entries there are never
 * probed here (see the garmin-route-registry spec's requirement that this
 * harness only ever issues GET), only the "read" routes that don't need a
 * placeholder value this script can't supply.
 *
 * Auth (OAuth1 -> OAuth2 exchange) is shared with the rest of tools/ via
 * ./lib/garmin-auth.mjs, not reimplemented here.
 *
 * Usage:
 *   node tools/probe-garmin-nutrition.mjs
 *   node tools/probe-garmin-nutrition.mjs --date 2026-09-10
 *   node tools/probe-garmin-nutrition.mjs --dump          # full JSON bodies
 *
 * Token sources, in priority order:
 *   1. $GARMIN_TOKENS            — path to a {oauth1, oauth2} JSON file
 *   2. $VAULT_ROOT               — reuses the Obsidian garmin-health-sync tokens
 *   3. ../Jirkas_world           — the default sibling-vault guess
 */
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { get, pause, loadTokens, getAccessToken } from './lib/garmin-auth.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

const args = process.argv.slice(2);
const DUMP = args.includes('--dump');
const DATE = args.includes('--date')
    ? args[args.indexOf('--date') + 1]
    : localDate(new Date());

function localDate(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

function fail(msg) {
    console.error(`\n\x1b[31m✗ ${msg}\x1b[0m\n`);
    process.exit(1);
}

// ── route list, from the registry rather than a hardcoded array ────────────────

/**
 * Substitute the one placeholder this script can supply a sensible value for
 * (a date). Entries whose path still contains an unresolved `{...}` after
 * that (barcode, custom-food id, etc.) are skipped — they need a specific
 * value only a targeted call (tools/garmin-get.mjs) makes sense for.
 */
function resolvePath(path, date) {
    return path
        .replace('{date}', date)
        .replace('{asOfDate}', date)
        .replace('{calendarDate}', date);
}

function buildProbes(date) {
    const registryPath = join(__dirname, '..', 'docs', 'garmin-routes.json');
    const registry = JSON.parse(readFileSync(registryPath, 'utf8'));

    const rows = [];
    for (const entry of registry.read ?? []) {
        const path = resolvePath(entry.path, date);
        if (/\{[^}]+\}/.test(path)) continue; // still has an unresolved placeholder — skip
        rows.push([entry.operation, path]);
    }
    return rows;
}

function classify(status) {
    if (status === 200) return '\x1b[32mOK\x1b[0m      ';
    if (status === 204) return '\x1b[32mEMPTY\x1b[0m   ';
    if (status === 400) return '\x1b[36mREQ\x1b[0m     ';
    if (status === 401) return '\x1b[31mAUTH\x1b[0m    ';
    if (status === 402 || status === 403) return '\x1b[33mGATED\x1b[0m   ';
    if (status === 404) return '\x1b[90mNONE\x1b[0m    ';
    if (status === 429) return '\x1b[35mTHROTTLE\x1b[0m';
    return `\x1b[31m${status}\x1b[0m     `;
}

// ── main ──────────────────────────────────────────────────────────────────────

async function run() {
    console.log('\n\x1b[1mGarmin nutrition API probe (read-only)\x1b[0m');
    console.log(`Date under test: ${DATE}\n`);

    const tokens = loadTokens();
    console.log(`  tokens     ${tokens.source}`);

    await getAccessToken(tokens);
    console.log('  auth       OK\n');

    const rows = buildProbes(DATE);
    const results = [];

    for (const [operation, path] of rows) {
        const r = await get(path);
        results.push({ operation, path, ...r });
        console.log(`  ${classify(r.status)} ${operation.padEnd(24)} ${path}`);
        if (r.status === 429) {
            console.log('  \x1b[35mRate limited — stopping early to stay polite.\x1b[0m');
            break;
        }
        // Deliberately unhurried: this is reconnaissance, not a sync. Staying
        // well under Garmin's throttle matters more than finishing fast.
        await pause(400);
    }

    // ── verdict ───────────────────────────────────────────────────────────────
    const log = results.find(r => r.operation === 'dailyFoodLog');
    const anyGated = results.some(r => r.status === 402 || r.status === 403);
    const live = results.filter(r => r.status === 200);

    console.log('\n\x1b[1mVerdict\x1b[0m');

    if (log?.status === 401) {
        console.log('  \x1b[31mAuth is dead.\x1b[0m Re-bootstrap tokens through a browser sign-in.');
    } else if (log?.status === 200 && log.body && Object.keys(log.body).length) {
        console.log('  \x1b[32mNutrition API is live for this account.\x1b[0m');
        console.log(`  ${live.length}/${rows.length} probed routes answered 200.`);
        console.log('  -> Gate 0 PASSED. Write route already documented in docs/garmin-food-log-contract.md.');
    } else if (log?.status === 200) {
        console.log('  \x1b[33mRoute exists but returned nothing for this date.\x1b[0m');
        console.log('  Log one food in the Garmin Connect app, then re-run with --date for that day.');
    } else if (log?.status === 404) {
        console.log('  \x1b[31mThe dailyFoodLog route itself 404\'d.\x1b[0m This is new — it worked on 2026-09-14.');
        console.log('  Garmin likely moved the route again. Re-run discover-nutrition-routes.mjs.');
    } else if (anyGated) {
        console.log('  \x1b[33mEndpoints are subscription-gated (402/403).\x1b[0m');
        console.log('  Nutrition requires Garmin Connect+. Without it, Gate 0 FAILS.');
    } else {
        console.log('  \x1b[31mNutrition routes did not answer as expected.\x1b[0m');
        console.log('  Gate 0 INCONCLUSIVE — see the status codes above.');
    }

    if (DUMP) {
        console.log('\n\x1b[1mFull bodies\x1b[0m');
        for (const r of results) {
            if (r.body == null) continue;
            console.log(`\n--- ${r.operation} (${r.status}) ---`);
            console.log(JSON.stringify(r.body, null, 2).slice(0, 4000));
        }
    } else {
        console.log('\n  Re-run with --dump to see full JSON payloads.');
    }

    if (log?.status === 200 && log.body) {
        console.log('\n\x1b[1mFood-log top-level keys\x1b[0m');
        console.log('  ' + Object.keys(log.body).join(', '));
    }

    console.log('');
}

run().catch(e => fail(e.stack || e.message));

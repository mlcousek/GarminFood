#!/usr/bin/env node
/**
 * garmin-get.mjs — issue an arbitrary authenticated GET against Garmin Connect
 * and pretty-print the answer.
 *
 * The workhorse of route discovery. The fixed-table probes (probe-garmin-
 * nutrition.mjs, discover-nutrition-routes.mjs) tell you *which* routes are
 * interesting; this one lets you interrogate a single route until it talks.
 *
 * Garmin runs Spring Boot behind these paths, and its 400s are unusually
 * generous — they name the controller method and the missing parameter, e.g.
 *   "'searchFood.arg0.searchExpression' searchExpression query parameter
 *    must be provided (provided value: null)"
 * That single line is worth more than an hour of guessing, so error bodies are
 * always printed in full.
 *
 * GET only, by construction. Discovering write paths is a separate, deliberate
 * act that does not belong in a tool this easy to run.
 *
 * Usage:
 *   node tools/garmin-get.mjs /nutrition-service/food/search?searchExpression=banana
 *   node tools/garmin-get.mjs /usersummary-service/usersummary/daily?calendarDate=2026-09-14
 *   node tools/garmin-get.mjs --keys /nutrition-service/food/search?searchExpression=rohlik
 *   node tools/garmin-get.mjs --web /modern/currentuser-service/user/info
 */
import { get, loadTokens, getAccessToken, CONNECTWEB } from './lib/garmin-auth.mjs';

const args = process.argv.slice(2);
const KEYS_ONLY = args.includes('--keys');
const USE_WEB = args.includes('--web');
const path = args.find(a => a.startsWith('/'));

if (!path) {
    console.error('Usage: node tools/garmin-get.mjs [--keys] [--web] /some-service/path?param=value');
    process.exit(2);
}

/** Describe a value's shape rather than printing it — useful for fat payloads. */
function shape(v, depth = 0, maxDepth = 3) {
    if (v === null) return 'null';
    if (Array.isArray(v)) {
        if (!v.length) return 'array(0)';
        return `array(${v.length}) of ${depth < maxDepth ? shape(v[0], depth + 1, maxDepth) : '...'}`;
    }
    if (typeof v === 'object') {
        if (depth >= maxDepth) return '{...}';
        const entries = Object.entries(v).map(([k, val]) => `${k}: ${shape(val, depth + 1, maxDepth)}`);
        return `{ ${entries.join(', ')} }`;
    }
    return typeof v;
}

async function run() {
    const tokens = loadTokens();
    await getAccessToken(tokens);

    const opts = USE_WEB ? { base: CONNECTWEB } : {};
    const r = await get(path, opts);

    const colour = r.status === 200 ? 32 : r.status === 400 ? 36 : 31;
    console.log(`\n\x1b[${colour}m${r.status}\x1b[0m ${USE_WEB ? CONNECTWEB : ''}${path}`);
    console.log(`\x1b[90m${r.contentType}\x1b[0m\n`);

    if (r.body == null) { console.log('(empty body)\n'); return; }

    // An HTML body from an API path means we were bounced to the sign-in page —
    // a 200 that is really a failure. Call it out rather than dumping markup.
    if (typeof r.body === 'string' && r.body.trimStart().startsWith('<')) {
        console.log('\x1b[33mHTML response — this is Garmin\'s sign-in page, not API data.\x1b[0m');
        console.log('This route does not serve the mobile OAuth2 token on this host.\n');
        return;
    }

    if (KEYS_ONLY) {
        console.log(shape(r.body));
        console.log('');
        return;
    }

    const json = JSON.stringify(r.body, null, 2);
    console.log(json.length > 20000 ? json.slice(0, 20000) + '\n... (truncated)' : json);
    console.log('');
}

run().catch(e => { console.error(`\n\x1b[31mX ${e.message}\x1b[0m\n`); process.exit(1); });

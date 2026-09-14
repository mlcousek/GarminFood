#!/usr/bin/env node
/**
 * discover-nutrition-routes.mjs — wide, READ-ONLY sweep for Garmin's nutrition
 * API surface.
 *
 * Why this exists: the first probe found that every guessed /nutrition-service/
 * path 404s except `/food/search`, which answers 400. A 404 means "no such
 * route"; a 400 means "route exists, your request is wrong". So there IS a
 * nutrition service — we just have the paths and parameters wrong.
 *
 * This script sweeps candidate service names, path shapes, query-parameter
 * spellings and host bases, and prints anything that is not a flat 404. Error
 * bodies are printed, because Garmin's 400s frequently name the field they
 * wanted, which is the cheapest possible source of truth.
 *
 * GET only. Nothing here mutates an account.
 *
 * Usage:
 *   node tools/discover-nutrition-routes.mjs
 *   node tools/discover-nutrition-routes.mjs --date 2026-09-13
 *   node tools/discover-nutrition-routes.mjs --all      # include 404s in output
 */
import { get, pause, loadTokens, getAccessToken, CONNECTWEB } from './lib/garmin-auth.mjs';

const args = process.argv.slice(2);
const SHOW_ALL = args.includes('--all');
const DATE = args.includes('--date')
    ? args[args.indexOf('--date') + 1]
    : new Date().toLocaleDateString('sv');

/** Build the probe table. Each entry: { group, label, path, opts } */
function buildProbes(date) {
    const p = [];
    const add = (group, label, path, opts) => p.push({ group, label, path, opts });

    // ── 0. Control: a route we KNOW works, to prove the harness + token are fine.
    add('control', 'daily summary (known-good)',
        `/usersummary-service/usersummary/daily?calendarDate=${date}`);

    // ── 1. The one confirmed-live route. Which query param does it want?
    for (const key of ['query', 'q', 'searchTerm', 'search', 'keyword', 'name', 'text', 'term', 'phrase']) {
        add('search-params', `food/search?${key}=`, `/nutrition-service/food/search?${key}=banana`);
    }
    add('search-params', 'food/search (no params)', '/nutrition-service/food/search');
    add('search-params', 'food/search + paging',
        '/nutrition-service/food/search?searchTerm=banana&start=0&limit=10');

    // ── 2. Sibling paths under the confirmed /nutrition-service/food/ prefix.
    for (const leaf of ['favorites', 'favourite', 'frequent', 'recent', 'recents',
                        'custom', 'personal', 'brands', 'barcode', 'all']) {
        add('food-leaves', `food/${leaf}`, `/nutrition-service/food/${leaf}`);
    }
    add('food-leaves', 'food/barcode/{ean}', '/nutrition-service/food/barcode/8594001020010');

    // ── 3. Log/diary path shapes. The vault assumed food/log/date/{d}; it 404s.
    const logShapes = [
        `/nutrition-service/food/log/${date}`,
        `/nutrition-service/food/log?date=${date}`,
        `/nutrition-service/food/log?calendarDate=${date}`,
        `/nutrition-service/foodlog/${date}`,
        `/nutrition-service/log/date/${date}`,
        `/nutrition-service/diary/${date}`,
        `/nutrition-service/diary/date/${date}`,
        `/nutrition-service/nutrition/daily/${date}`,
        `/nutrition-service/nutrition/${date}`,
        `/nutrition-service/daily/${date}`,
        `/nutrition-service/summary/${date}`,
        `/nutrition-service/food/daily/${date}`,
    ];
    for (const path of logShapes) add('log-shapes', path.split('nutrition-service')[1], path);

    // ── 4. Alternative service names entirely.
    const services = ['diary-service', 'food-service', 'meal-service', 'fooddiary-service',
                      'nutritionlog-service'];
    for (const svc of services) {
        add('other-services', `${svc} root probe`, `/${svc}/food/search?searchTerm=banana`);
    }
    add('other-services', 'wellness nutrition daily',
        `/wellness-service/wellness/dailyNutrition/${date}`);

    // ── 5. Is nutrition gated behind Connect+? Find the entitlement surface.
    const entitlements = [
        '/subscription-service/subscription',
        '/subscription-service/entitlements',
        '/subscription-service/account/entitlements',
        '/web-gateway/subscription/entitlements',
        '/userprofile-service/userprofile/settings',
        '/feature-service/features',
    ];
    for (const path of entitlements) add('entitlement', path, path);

    // ── 6. Same paths, different host. Some services only answer on the web host.
    add('web-host', 'food/search via connect.garmin.com',
        '/nutrition-service/food/search?searchTerm=banana', { base: CONNECTWEB });
    add('web-host', 'food/search via /modern/proxy',
        '/modern/proxy/nutrition-service/food/search?searchTerm=banana', { base: CONNECTWEB });

    return p;
}

function tag(status) {
    if (status === 200) return '\x1b[32m200 OK  \x1b[0m';
    if (status === 204) return '\x1b[32m204 --  \x1b[0m';
    if (status === 400) return '\x1b[36m400 REQ \x1b[0m';
    if (status === 401) return '\x1b[31m401 AUTH\x1b[0m';
    if (status === 402) return '\x1b[33m402 PAY \x1b[0m';
    if (status === 403) return '\x1b[33m403 DENY\x1b[0m';
    if (status === 404) return '\x1b[90m404 none\x1b[0m';
    if (status === 429) return '\x1b[35m429 RATE\x1b[0m';
    return `\x1b[31m${String(status).padEnd(3)} ??? \x1b[0m`;
}

function preview(body) {
    if (body == null) return '';
    const s = typeof body === 'string' ? body : JSON.stringify(body);
    return s.length > 220 ? s.slice(0, 220) + '...' : s;
}

async function run() {
    const tokens = loadTokens();
    console.log('\n\x1b[1mGarmin nutrition route discovery (read-only, GET only)\x1b[0m');
    console.log(`  tokens   ${tokens.source}`);
    await getAccessToken(tokens);
    console.log('  auth     OK');
    console.log(`  date     ${DATE}\n`);

    const probes = buildProbes(DATE);
    const interesting = [];
    let group = null;
    let rateLimited = false;

    for (const { group: g, label, path, opts } of probes) {
        if (g !== group) { group = g; console.log(`\x1b[1m  -- ${g} --\x1b[0m`); }

        const r = await get(path, opts);
        if (r.status === 429) rateLimited = true;

        const notable = r.status !== 404;
        if (notable) interesting.push({ group: g, label, path, ...r });

        if (notable || SHOW_ALL) {
            console.log(`  ${tag(r.status)} ${label}`);
            if (notable && r.body) console.log(`            \x1b[90m${preview(r.body)}\x1b[0m`);
        }

        if (rateLimited) {
            console.log('\n  \x1b[35mRate limited - stopping early to stay polite.\x1b[0m');
            break;
        }
        await pause(450);
    }

    // ── summary ───────────────────────────────────────────────────────────────
    console.log('\n\x1b[1mAnything that was not a 404\x1b[0m');
    if (!interesting.length) {
        console.log('  (nothing) - the nutrition surface is not reachable from this host/token.');
    }
    for (const r of interesting) {
        console.log(`  ${tag(r.status)} ${r.path}`);
    }

    const live = interesting.filter(r => r.status === 200 && r.group !== 'control');
    const exists = interesting.filter(r => r.status === 400);
    const gated = interesting.filter(r => r.status === 402 || r.status === 403);

    console.log('\n\x1b[1mRead\x1b[0m');
    console.log(`  ${live.length} route(s) returned data`);
    console.log(`  ${exists.length} route(s) exist but rejected the request (400 - wrong params)`);
    console.log(`  ${gated.length} route(s) refused on entitlement (402/403 - Connect+ gate)`);
    console.log('');
}

run().catch(e => { console.error(`\n\x1b[31mX ${e.message}\x1b[0m\n`); process.exit(1); });

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
 * It NEVER writes. No POST, PUT, PATCH or DELETE is issued — discovering the
 * write path is a separate, deliberate step that happens only after this one
 * comes back green. See the design notes under openspec/changes.
 *
 * Auth strategy is lifted verbatim from the vault's scripts/lib/garmin.mjs:
 * a long-lived OAuth1 token signs an exchange for a short-lived OAuth2 access
 * token. We do not attempt to log in — Garmin blocked scripted SSO login at the
 * Cloudflare level in March 2026, so login is a browser-only act.
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
import { readFileSync, existsSync } from 'fs';
import { join, dirname, resolve } from 'path';
import { fileURLToPath } from 'url';
import { createHmac, randomBytes } from 'crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));

const API = 'https://connectapi.garmin.com';
const UA = { 'User-Agent': 'com.garmin.android.apps.connectmobile' };

const args = process.argv.slice(2);
const DUMP = args.includes('--dump');
const DATE = args.includes('--date')
    ? args[args.indexOf('--date') + 1]
    : localDate(new Date());

function localDate(d) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// ── token discovery ───────────────────────────────────────────────────────────

function readJSON(path) {
    try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; }
}

/**
 * Find an OAuth1 token. The Obsidian plugin stores both tokens as JSON *strings*
 * nested inside its data.json, which is why they get double-parsed here.
 */
function loadTokens() {
    const explicit = process.env.GARMIN_TOKENS;
    if (explicit) {
        const t = readJSON(explicit);
        if (t?.oauth1) return { ...t, source: explicit };
        fail(`GARMIN_TOKENS points at ${explicit} but it has no .oauth1`);
    }

    const vault = process.env.VAULT_ROOT || resolve(__dirname, '..', '..', 'Jirkas_world');
    const candidates = [
        join(vault, 'scripts', '.garmin-tokens.json'),
        join(vault, '.obsidian', 'plugins', 'garmin-health-sync', 'data.json'),
    ];

    for (const path of candidates) {
        if (!existsSync(path)) continue;
        const raw = readJSON(path);
        if (!raw) continue;

        // Shape A: our own cache — { oauth1, oauth2 }
        if (raw.oauth1) return { oauth1: raw.oauth1, oauth2: raw.oauth2, source: path };

        // Shape B: plugin data.json — stringified tokens
        if (raw.garminOAuth1) {
            return {
                oauth1: JSON.parse(raw.garminOAuth1),
                oauth2: raw.garminOAuth2 ? JSON.parse(raw.garminOAuth2) : null,
                source: path,
            };
        }
    }

    fail(
        'No Garmin tokens found. Looked in:\n' +
        candidates.map(c => `    ${c}`).join('\n') +
        '\n  Set $GARMIN_TOKENS or $VAULT_ROOT to point at them.'
    );
}

// ── OAuth1 signing (HMAC-SHA1) ────────────────────────────────────────────────

let _consumer = null;
async function getConsumer() {
    if (_consumer) return _consumer;
    // Same public consumer credentials the Garmin mobile app ships with.
    const res = await fetch('https://thegarth.s3.amazonaws.com/oauth_consumer.json');
    if (!res.ok) fail(`Could not fetch OAuth consumer key: HTTP ${res.status}`);
    _consumer = await res.json();
    return _consumer;
}

function pctEncode(s) {
    return encodeURIComponent(s).replace(/[!'()*]/g, c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

function oauth1Header(method, url, consumer, token, tokenSecret) {
    const params = {
        oauth_consumer_key: consumer.consumer_key,
        oauth_token: token,
        oauth_nonce: randomBytes(16).toString('hex'),
        oauth_timestamp: String(Math.floor(Date.now() / 1000)),
        oauth_signature_method: 'HMAC-SHA1',
        oauth_version: '1.0',
    };
    const paramStr = Object.keys(params).sort()
        .map(k => `${pctEncode(k)}=${pctEncode(params[k])}`).join('&');
    const base = [method.toUpperCase(), pctEncode(url), pctEncode(paramStr)].join('&');
    const key = `${pctEncode(consumer.consumer_secret)}&${pctEncode(tokenSecret)}`;
    params.oauth_signature = createHmac('sha1', key).update(base).digest('base64');
    return 'OAuth ' + Object.keys(params).sort()
        .map(k => `${pctEncode(k)}="${pctEncode(params[k])}"`).join(', ');
}

async function getAccessToken(tokens) {
    const { oauth1, oauth2 } = tokens;
    if (oauth2?.access_token && Date.now() / 1000 < oauth2.expires_at - 300) {
        return { token: oauth2.access_token, refreshed: false };
    }
    if (!oauth1?.oauth_token) fail('No OAuth1 token — cannot mint an OAuth2 access token.');

    const consumer = await getConsumer();
    const url = `${API}/oauth-service/oauth/exchange/user/2.0`;
    const res = await fetch(url, {
        method: 'POST',
        headers: {
            ...UA,
            'Content-Type': 'application/x-www-form-urlencoded',
            Authorization: oauth1Header('POST', url, consumer, oauth1.oauth_token, oauth1.oauth_token_secret),
        },
    });
    if (!res.ok) {
        fail(
            `OAuth1 -> OAuth2 exchange failed: HTTP ${res.status}\n` +
            `  ${(await res.text()).slice(0, 300)}\n` +
            '  If this is 401, the OAuth1 token has expired (they last ~1 year).\n' +
            '  Re-bootstrap it by signing in through a real browser — see the plan.'
        );
    }
    const tok = await res.json();
    return { token: tok.access_token, refreshed: true, expiresIn: tok.expires_in };
}

// ── probing ───────────────────────────────────────────────────────────────────

/** GET a path and classify the answer. Never throws — a probe reports, it does not abort. */
async function probe(path, accessToken) {
    let res;
    try {
        res = await fetch(API + path, { headers: { ...UA, Authorization: `Bearer ${accessToken}` } });
    } catch (e) {
        return { path, status: 'ERR', note: e.message };
    }

    const ct = res.headers.get('content-type') || '';
    let body = null;
    if (ct.includes('json')) { try { body = await res.json(); } catch { /* empty body */ } }
    else { body = (await res.text()).slice(0, 200) || null; }

    return { path, status: res.status, body };
}

/**
 * Candidate routes. Read paths are inferred from the vault's working
 * getNutritionLog() plus Garmin's usual `<domain>-service` naming. Unknowns are
 * expected to 404 — that is data, not failure.
 */
function candidates(date) {
    return [
        ['food log (known-good)',   `/nutrition-service/food/log/date/${date}`],
        ['nutrition settings',      '/nutrition-service/nutrition/settings'],
        ['daily goals',             `/nutrition-service/nutrition/goals/${date}`],
        ['favourite foods',         '/nutrition-service/food/favorite'],
        ['recent foods',            '/nutrition-service/food/recent'],
        ['custom foods',            '/nutrition-service/food/custom'],
        ['meals',                   '/nutrition-service/meal'],
        ['food search',             '/nutrition-service/food/search?query=banana&limit=3'],
        ['water log',               `/nutrition-service/water/log/date/${date}`],
        ['subscription status',     '/subscription-service/entitlement'],
    ];
}

function classify(status) {
    if (status === 200) return '\x1b[32mOK\x1b[0m      ';
    if (status === 204) return '\x1b[32mEMPTY\x1b[0m   ';
    if (status === 401) return '\x1b[31mAUTH\x1b[0m    ';
    if (status === 402 || status === 403) return '\x1b[33mGATED\x1b[0m   ';
    if (status === 404) return '\x1b[90mNONE\x1b[0m    ';
    if (status === 429) return '\x1b[35mTHROTTLE\x1b[0m';
    return `\x1b[31m${status}\x1b[0m     `;
}

function fail(msg) {
    console.error(`\n\x1b[31m✗ ${msg}\x1b[0m\n`);
    process.exit(1);
}

// ── main ──────────────────────────────────────────────────────────────────────

async function run() {
    console.log('\n\x1b[1mGarmin nutrition API probe (read-only)\x1b[0m');
    console.log(`Date under test: ${DATE}\n`);

    const tokens = loadTokens();
    console.log(`  tokens     ${tokens.source}`);

    const { token, refreshed, expiresIn } = await getAccessToken(tokens);
    console.log(`  auth       OK${refreshed ? ` (minted a fresh OAuth2 token, valid ${expiresIn}s)` : ' (cached OAuth2 token still valid)'}\n`);

    const rows = candidates(DATE);
    const results = [];

    for (const [label, path] of rows) {
        const r = await probe(path, token);
        results.push({ label, ...r });
        console.log(`  ${classify(r.status)} ${label.padEnd(24)} ${path}`);
        // Deliberately unhurried: this is reconnaissance, not a sync. Staying
        // well under Garmin's throttle matters more than finishing fast.
        await new Promise(res => setTimeout(res, 400));
    }

    // ── verdict ───────────────────────────────────────────────────────────────
    const log = results.find(r => r.path.includes('/food/log/'));
    const anyGated = results.some(r => r.status === 402 || r.status === 403);
    const live = results.filter(r => r.status === 200);

    console.log('\n\x1b[1mVerdict\x1b[0m');

    if (log?.status === 401) {
        console.log('  \x1b[31mAuth is dead.\x1b[0m Re-bootstrap tokens through a browser sign-in.');
    } else if (log?.status === 200 && log.body && Object.keys(log.body).length) {
        console.log('  \x1b[32mNutrition API is live for this account.\x1b[0m');
        console.log(`  ${live.length}/${rows.length} probed routes answered 200.`);
        console.log('  -> Gate 0 PASSED. Proceed to write-path discovery.');
    } else if (log?.status === 200) {
        console.log('  \x1b[33mRoute exists but returned nothing for this date.\x1b[0m');
        console.log('  Log one food in the Garmin Connect app, then re-run with --date for that day.');
        console.log('  Until a real payload is seen, the field mapping stays unverified.');
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
            console.log(`\n--- ${r.label} (${r.status}) ---`);
            console.log(JSON.stringify(r.body, null, 2).slice(0, 4000));
        }
    } else {
        console.log('\n  Re-run with --dump to see full JSON payloads.');
    }

    // The food-log shape is the single most valuable artefact here: the vault's
    // parseNutrition() currently guesses at it with a stack of ?? fallbacks.
    if (log?.status === 200 && log.body) {
        console.log('\n\x1b[1mFood-log top-level keys\x1b[0m');
        console.log('  ' + Object.keys(log.body).join(', '));
    }

    console.log('');
}

run().catch(e => fail(e.stack || e.message));

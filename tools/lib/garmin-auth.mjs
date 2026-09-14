/**
 * garmin-auth.mjs — minimal Garmin Connect auth for reconnaissance tooling.
 *
 * Lifted from the vault's scripts/lib/garmin.mjs. A long-lived OAuth1 token
 * signs an exchange for a ~24h OAuth2 access token. We never attempt to log in:
 * Garmin put its SSO endpoints behind Cloudflare bot protection in March 2026,
 * so acquiring an OAuth1 token is a browser-only act. This module only ever
 * *uses* a token someone else already obtained.
 */
import { readFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { createHmac, randomBytes } from 'crypto';

const __dirname = dirname(fileURLToPath(import.meta.url));

export const CONNECTAPI = 'https://connectapi.garmin.com';
export const CONNECTWEB = 'https://connect.garmin.com';
export const UA = { 'User-Agent': 'com.garmin.android.apps.connectmobile' };

function readJSON(path) {
    try { return JSON.parse(readFileSync(path, 'utf8')); } catch { return null; }
}

/**
 * Locate an OAuth1 token.
 *
 * The Obsidian garmin-health-sync plugin stores each token as a JSON *string*
 * nested inside its data.json, hence the double parse.
 */
export function loadTokens() {
    const explicit = process.env.GARMIN_TOKENS;
    if (explicit) {
        const t = readJSON(explicit);
        if (t?.oauth1) return { oauth1: t.oauth1, oauth2: t.oauth2, source: explicit };
        throw new Error(`GARMIN_TOKENS points at ${explicit} but it has no .oauth1`);
    }

    // Relative to this file's own location, not the invoking shell's cwd —
    // so it resolves the same way regardless of where a script is run from.
    const vault = process.env.VAULT_ROOT || join(__dirname, '..', '..', '..', 'Jirkas_world');
    const candidates = [
        join(vault, 'scripts', '.garmin-tokens.json'),
        join(vault, '.obsidian', 'plugins', 'garmin-health-sync', 'data.json'),
    ];

    for (const path of candidates) {
        if (!existsSync(path)) continue;
        const raw = readJSON(path);
        if (!raw) continue;
        if (raw.oauth1) return { oauth1: raw.oauth1, oauth2: raw.oauth2, source: path };
        if (raw.garminOAuth1) {
            return {
                oauth1: JSON.parse(raw.garminOAuth1),
                oauth2: raw.garminOAuth2 ? JSON.parse(raw.garminOAuth2) : null,
                source: path,
            };
        }
    }

    throw new Error(
        'No Garmin tokens found. Looked in:\n' +
        candidates.map(c => `    ${c}`).join('\n') +
        '\n  Set $GARMIN_TOKENS or $VAULT_ROOT.'
    );
}

let _consumer = null;
async function getConsumer() {
    if (_consumer) return _consumer;
    const res = await fetch('https://thegarth.s3.amazonaws.com/oauth_consumer.json');
    if (!res.ok) throw new Error(`Could not fetch OAuth consumer key: HTTP ${res.status}`);
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

let _access = null;

/** A valid OAuth2 access token, minted from the OAuth1 token if needed. */
export async function getAccessToken(tokens = loadTokens()) {
    if (_access && Date.now() / 1000 < _access.expires_at - 300) return _access.access_token;

    const { oauth1, oauth2 } = tokens;
    if (oauth2?.access_token && Date.now() / 1000 < oauth2.expires_at - 300) {
        _access = oauth2;
        return oauth2.access_token;
    }
    if (!oauth1?.oauth_token) throw new Error('No OAuth1 token — cannot mint an OAuth2 access token.');

    const consumer = await getConsumer();
    const url = `${CONNECTAPI}/oauth-service/oauth/exchange/user/2.0`;
    const res = await fetch(url, {
        method: 'POST',
        headers: {
            ...UA,
            'Content-Type': 'application/x-www-form-urlencoded',
            Authorization: oauth1Header('POST', url, consumer, oauth1.oauth_token, oauth1.oauth_token_secret),
        },
    });
    if (!res.ok) {
        throw new Error(
            `OAuth1 -> OAuth2 exchange failed: HTTP ${res.status} ${(await res.text()).slice(0, 300)}\n` +
            '  A 401 here means the OAuth1 token expired (they last ~1 year).\n' +
            '  Re-bootstrap it via a real browser sign-in.'
        );
    }
    const tok = await res.json();
    tok.expires_at = Math.floor(Date.now() / 1000) + tok.expires_in;
    _access = tok;
    return tok.access_token;
}

/**
 * GET a path and classify the answer. Never throws — reconnaissance reports,
 * it does not abort. Returns { status, body, contentType }.
 */
export async function get(path, { base = CONNECTAPI, headers = {} } = {}) {
    const token = await getAccessToken();
    let res;
    try {
        res = await fetch(base + path, {
            headers: { ...UA, Authorization: `Bearer ${token}`, ...headers },
        });
    } catch (e) {
        return { status: 'ERR', body: e.message, contentType: null };
    }

    const contentType = res.headers.get('content-type') || '';
    let body = null;
    if (contentType.includes('json')) {
        try { body = await res.json(); } catch { /* empty */ }
    } else {
        body = (await res.text()).slice(0, 400) || null;
    }
    return { status: res.status, body, contentType };
}

/** Polite spacing between probes. Garmin throttles, and this is not a sync. */
export const pause = (ms = 400) => new Promise(r => setTimeout(r, ms));

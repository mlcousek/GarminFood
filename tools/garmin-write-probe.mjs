#!/usr/bin/env node
/**
 * garmin-write-probe.mjs — issue ONE authenticated write against Garmin
 * Connect, to characterise a route that docs/garmin-routes.json still records
 * as "documented, not exercised".
 *
 * WHY THIS IS A SEPARATE TOOL FROM garmin-get.mjs
 *
 * garmin-get.mjs is GET only "by construction", and its header says
 * discovering write paths is "a separate, deliberate act that does not belong
 * in a tool this easy to run". That judgement is kept here rather than
 * overruled: reads are free to repeat, writes land in a real person's real
 * food diary and have to be cleaned up by hand. So:
 *
 *   - It prints the exact request and sends NOTHING unless you pass --send.
 *   - It performs exactly one request per invocation. No loops, no sweeps.
 *   - It prints the full error body, because that is the entire point.
 *
 * Garmin's nutrition service is Spring Boot and its 400s name the offending
 * controller argument -- e.g. "'searchFood.arg0.searchExpression'
 * searchExpression query parameter must be provided". That one line is what
 * mapped half of garmin-routes.json's read section, and it is what will
 * settle the create-food-log request body without another device build.
 *
 * USAGE
 *
 *   # show what would be sent, send nothing (default)
 *   node tools/garmin-write-probe.mjs --body '{"date":"2026-09-16",...}'
 *
 *   # actually send it
 *   node tools/garmin-write-probe.mjs --body '{...}' --send
 *
 *   # other routes / verbs
 *   node tools/garmin-write-probe.mjs --path /nutrition-service/food/logs \
 *        --method DELETE --body '{"logIds":["..."]}' --send
 *
 * Tokens come from lib/garmin-auth.mjs's usual resolution (GARMIN_TOKENS, or
 * VAULT_ROOT/scripts/.garmin-tokens.json). On Git Bash for Windows, prefix
 * with MSYS_NO_PATHCONV=1 or a leading-slash --path is rewritten into a
 * Windows path before node ever sees it.
 *
 * CLEANING UP: a successful create can be removed with the delete route above,
 * using the `logId` from GET /nutrition-service/food/logs/{date}.
 */

import { CONNECTAPI, UA, getAccessToken } from './lib/garmin-auth.mjs';

const args = process.argv.slice(2);

function flag(name, fallback = null) {
    const i = args.indexOf(name);
    return i === -1 ? fallback : args[i + 1];
}

const path = flag('--path', '/nutrition-service/food/logs');
const method = (flag('--method', 'POST') || 'POST').toUpperCase();
const rawBody = flag('--body');
const send = args.includes('--send');

if (!rawBody) {
    console.error('Usage: node tools/garmin-write-probe.mjs --body \'{"json":"here"}\' [--path /p] [--method POST] [--send]');
    console.error('Without --send it prints the request and exits: nothing is written.');
    process.exit(2);
}

let body;
try {
    body = JSON.parse(rawBody);
} catch (e) {
    console.error(`--body is not valid JSON: ${e.message}`);
    process.exit(2);
}

const url = CONNECTAPI + path;

console.log(`${method} ${url}`);
console.log('Content-Type: application/json');
console.log('Authorization: Bearer <redacted>');
console.log(JSON.stringify(body, null, 2));

if (!send) {
    console.log('\nDRY RUN — nothing was sent. Re-run with --send to actually write.');
    process.exit(0);
}

const token = await getAccessToken();

let res;
try {
    res = await fetch(url, {
        method,
        headers: {
            ...UA,
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
    });
} catch (e) {
    console.error(`\nNETWORK ERROR: ${e.message}`);
    process.exit(1);
}

const contentType = res.headers.get('content-type') || '';
const text = await res.text();

console.log(`\n${res.status} ${res.statusText}`);
console.log(contentType || '(no content-type)');
// Printed in full and unconditionally: for an unexercised route the error body
// IS the deliverable, and truncating it is how you end up guessing instead.
console.log(text || '(empty body)');

process.exit(res.ok ? 0 : 1);

#!/usr/bin/env node
/**
 * probe-github-contents.mjs — read-only probe of GitHub's contents API for
 * the vault connection (openspec/changes/add-vault-connection, tasks 1.1-1.4).
 *
 * Why this exists: the app's vault transport (ios/VaultKit) leans on a few
 * GitHub behaviours that are documented but not yet OBSERVED on the owner's
 * repository -- that a raw-media-type GET returns an ETag, that
 * If-None-Match with it returns 304 without spending rate limit, the exact
 * name and date format of the token-expiry header, and the rate-limit
 * header names. design.md's Evidence table records them, dated, once this
 * has run on the owner's PC.
 *
 * THIS REPOSITORY IS PUBLIC. So the probe:
 *   - reads the token from VAULT_PROBE_TOKEN and the repository from
 *     VAULT_PROBE_REPO ("owner/name") -- never from a file, never from an
 *     argument (arguments end up in shell history);
 *   - refuses to run unless both are set;
 *   - only ever sends GET requests, to https://api.github.com only, and
 *     refuses to follow a redirect;
 *   - prints status codes, header NAMES, the few header values it needs
 *     (whether an ETag came back, the expiry header, rate-limit counters)
 *     and byte counts -- never a response body, never the token, never the
 *     repository name (it prints "<repo>").
 * Record its output in design.md by hand; do not paste anything it didn't
 * print. Never run it in CI.
 *
 * Steps (task 1.2-1.4):
 *   1. GET /repos/{repo}                                   (expect 200)
 *   2. GET the projection with Accept: application/vnd.github.raw+json
 *      (200, or 404 if the vault hasn't generated it -- then pass
 *      VAULT_PROBE_PATH=<another small committed file under the hub root>)
 *   3. the same GET with If-None-Match: <etag from 2>      (expect 304)
 *   4. GET /repos/{repo}-does-not-exist-<random>           (expect 404)
 *   5. GET /repos/{repo} with a deliberately wrong token   (expect 401)
 *
 * Usage (PowerShell):
 *   $env:VAULT_PROBE_TOKEN = "<paste>"; $env:VAULT_PROBE_REPO = "<owner>/<name>"
 *   node tools/probe-github-contents.mjs
 *   Remove-Item Env:VAULT_PROBE_TOKEN, Env:VAULT_PROBE_REPO
 *
 * Node >= 18 (global fetch), no dependencies.
 */

const HOST = 'https://api.github.com';
const HUB_ROOT = 'Sport/Training/_hub';
const DEFAULT_PATH = 'projection/projection.v1.json';
const API_VERSION = '2022-11-28';
const INTERESTING = [
  'etag',
  'last-modified',
  'github-authentication-token-expiration',
  'x-ratelimit-limit',
  'x-ratelimit-remaining',
  'x-ratelimit-used',
  'x-ratelimit-reset',
  'x-ratelimit-resource',
  'retry-after',
  'x-github-request-id',
];

const token = process.env.VAULT_PROBE_TOKEN?.trim();
const repo = process.env.VAULT_PROBE_REPO?.trim();
const hubPath = (process.env.VAULT_PROBE_PATH || DEFAULT_PATH).trim();

if (!token || !repo) {
  console.error('Refusing to run: set VAULT_PROBE_TOKEN and VAULT_PROBE_REPO ("owner/name") in the environment.');
  console.error('Nothing is read from files or arguments -- see this script\'s header.');
  process.exit(2);
}
if (!/^[A-Za-z0-9-]{1,39}\/[A-Za-z0-9._-]{1,100}$/.test(repo)) {
  console.error('VAULT_PROBE_REPO must look like owner/name.');
  process.exit(2);
}
if (!/^[A-Za-z0-9._-]+(\/[A-Za-z0-9._-]+)*$/.test(hubPath) || hubPath.split('/').some((s) => s === '.' || s === '..')) {
  console.error('VAULT_PROBE_PATH must be a normal hub-relative path.');
  process.exit(2);
}

/** Anything that could echo a secret or the repository is masked. */
function redact(text) {
  let out = String(text);
  if (token) out = out.split(token).join('<token>');
  out = out.split(repo).join('<repo>');
  for (const part of repo.split('/')) {
    if (part.length >= 3) out = out.split(part).join('<repo-part>');
  }
  return out;
}

async function probe(label, path, { accept = 'application/vnd.github+json', ifNoneMatch, authToken = token } = {}) {
  const headers = {
    Accept: accept,
    'X-GitHub-Api-Version': API_VERSION,
    'User-Agent': 'GarminFood-vault-probe',
    Authorization: `Bearer ${authToken}`,
  };
  if (ifNoneMatch) headers['If-None-Match'] = ifNoneMatch;

  let response;
  try {
    response = await fetch(HOST + path, { method: 'GET', headers, redirect: 'manual' });
  } catch (error) {
    console.log(`\n== ${label}\n   network error: ${redact(error?.cause?.code || error?.name || 'unknown')}`);
    return {};
  }
  const body = new Uint8Array(await response.arrayBuffer());
  const names = [...response.headers.keys()].sort();
  console.log(`\n== ${label}`);
  console.log(`   status: ${response.status}`);
  console.log(`   body bytes: ${body.length}`);
  console.log(`   header names: ${names.join(', ')}`);
  for (const name of INTERESTING) {
    const value = response.headers.get(name);
    if (value === null) continue;
    // The ETag is printed only as present/absent plus its weak/strong form.
    const shown = name === 'etag' ? `present (${value.startsWith('W/') ? 'weak' : 'strong'}, ${value.length} chars)` : redact(value);
    console.log(`   ${name}: ${shown}`);
  }
  if (response.status >= 300 && response.status < 400) {
    console.log('   redirect NOT followed (location header present: ' + (response.headers.get('location') !== null) + ')');
  }
  return { status: response.status, etag: response.headers.get('etag'), remaining: response.headers.get('x-ratelimit-remaining') };
}

const date = new Date().toISOString();
console.log(`probe-github-contents.mjs, ${date}`);
console.log(`repository: <repo>, hub path: ${HUB_ROOT}/${hubPath}`);

const repoPath = `/repos/${repo}`;
const contentsPath = `${repoPath}/contents/${HUB_ROOT}/${hubPath}`;

await probe('1. repository', repoPath);
const first = await probe('2. file, raw media type', contentsPath, { accept: 'application/vnd.github.raw+json' });
if (first.etag) {
  const second = await probe('3. same file, If-None-Match', contentsPath, { accept: 'application/vnd.github.raw+json', ifNoneMatch: first.etag });
  if (first.remaining && second.remaining) {
    console.log(`\n   x-ratelimit-remaining after 2: ${first.remaining}, after 3: ${second.remaining} ` +
      `(${first.remaining === second.remaining ? 'the 304 did NOT spend rate limit' : 'the 304 spent rate limit'})`);
  }
} else {
  console.log('\n== 3. skipped: step 2 returned no ETag (record that; design D2 fallback = unconditional GETs)');
}
const suffix = Math.random().toString(16).slice(2, 10);
await probe('4. a repository that does not exist', `${repoPath}-does-not-exist-${suffix}`);
await probe('5. a deliberately wrong token', repoPath, { authToken: 'github_pat_' + 'x'.repeat(40) });

console.log('\nDone. Record the status codes and header names above in design.md "Evidence", dated. Then clear the environment variables.');

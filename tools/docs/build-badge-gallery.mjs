// build-badge-gallery.mjs
//
// Writes docs/guide/badges.html (redesign-badge-art design D6): the page
// the owner approves the badge art on, in a browser on this PC, before any
// app drawing code changes. Every badge the guide's data knows
// (docs/guide/data/achievements.json, plus the level tiers) is shown with
// the frame and motif the app will use, at 44, 60 and 120 pt and locked,
// on light and dark, with a filter by family.
//
// A badge is resolved exactly as in the app: the tables are read from
// Gamification's BadgeArtCatalog.swift (check-badge-art.mjs), not copied.
// The SVG files are inlined once as <symbol>s, so the page opens from disk.
//
//   node tools/docs/build-badge-gallery.mjs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readCatalog, familyFor } from './check-badge-art.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const artDir = path.join(root, 'ios', 'BadgeArt');
const dataDir = path.join(root, 'docs', 'guide', 'data');
const outFile = path.join(root, 'docs', 'guide', 'badges.html');

const catalog = readCatalog();
const escape = (text) => String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');

const FAMILY_NAMES = {
  streak: 'Streak', logging: 'Logging', macros: 'Macros', levels: 'Levels', boss: 'Boss', bingo: 'Bingo',
  journeys: 'Journeys', records: 'Records', collections: 'Collections', seasonal: 'Seasonal',
  sportBody: 'Sport & body', supplements: 'Supplements', secrets: 'Secrets',
};
// Where the motif sits in the 64-unit frame: [x, y, size]. The app uses the
// same numbers (BadgeMedallion, wave 3).
const MOTIF_BOX = { records: [19.5, 14.5, 25], levels: [20.5, 22, 23], secrets: [19, 13, 26], journeys: [18.5, 15, 27], default: [18, 18, 28] };

// --- the art, once, as symbols ---------------------------------------------

function symbols(folder, size) {
  return fs.readdirSync(path.join(artDir, folder)).sort().map((name) => {
    const body = fs.readFileSync(path.join(artDir, folder, name), 'utf8').replace(/<svg[^>]*>/, '').replace('</svg>', '').trim();
    return `<symbol id="${name.replace(/\.svg$/, '')}" viewBox="0 0 ${size} ${size}">${body}</symbol>`;
  }).join('\n');
}

// --- the badges --------------------------------------------------------------

const achievements = JSON.parse(fs.readFileSync(path.join(dataDir, 'achievements.json'), 'utf8')).badges;
const tiers = JSON.parse(fs.readFileSync(path.join(dataDir, 'levels.json'), 'utf8')).tiers;

const badges = [
  ...achievements.map((b) => ({
    id: b.id, title: b.title.en, rarity: b.rarity, symbol: b.symbol, secret: b.secret,
    family: familyFor(catalog, b.id, b.category),
  })),
  ...tiers.map((t) => ({
    id: `tier ${t.from}-${t.to}`, title: `${t.title.en} (level tier)`, rarity: t.rarity, symbol: t.symbol, secret: false, family: 'levels',
  })),
].filter((b) => b.symbol);

function art(badge, size, locked) {
  const motif = catalog.motifs[badge.symbol];
  const [x, y, s] = MOTIF_BOX[badge.family] ?? MOTIF_BOX.default;
  const frame = `<use href="#frame-${badge.family}-${badge.rarity}"/>`;
  if (locked) {
    return `<span class="badge locked" style="width:${size}px;height:${size}px"><svg viewBox="0 0 64 64" width="${size}" height="${size}" aria-hidden="true">${frame}</svg><span class="lock" style="font-size:${Math.round(size * 0.3)}px">&#128274;</span></span>`;
  }
  const top = motif
    ? `<use href="#motif-${motif}" x="${x}" y="${y}" width="${s}" height="${s}"/>`
    : `<text x="32" y="37" text-anchor="middle" font-size="9" fill="#fff">?</text>`;
  return `<span class="badge" style="width:${size}px;height:${size}px"><svg viewBox="0 0 64 64" width="${size}" height="${size}" aria-hidden="true">${frame}${top}</svg></span>`;
}

function card(badge) {
  const row = `${art(badge, 44, false)}${art(badge, 60, false)}${art(badge, 120, false)}${art(badge, 60, true)}`;
  const motif = catalog.motifs[badge.symbol];
  return `<article class="card" data-family="${badge.family}">
  <h3>${escape(badge.title)}</h3>
  <p class="meta">${escape(badge.id)} · ${badge.rarity}${badge.secret ? ' · secret' : ''} · ${motif ? escape(motif) : `<strong>no motif for ${escape(badge.symbol)}</strong>`}</p>
  <div class="pair"><div class="light">${row}</div><div class="dark">${row}</div></div>
</article>`;
}

const families = catalog.families.filter((family) => badges.some((b) => b.family === family));
const sections = families.map((family) => {
  const members = badges.filter((b) => b.family === family);
  return `<section data-family="${family}"><h2>${FAMILY_NAMES[family]} <span class="count">${members.length}</span></h2>
<div class="grid">
${members.map(card).join('\n')}
</div></section>`;
}).join('\n');
const filters = ['all', ...families].map((family, i) =>
  `<button type="button" data-filter="${family}" aria-pressed="${i === 0}">${family === 'all' ? `All ${badges.length}` : FAMILY_NAMES[family]}</button>`).join('');
const motifNames = [...new Set(Object.values(catalog.motifs))].sort();
const motifCells = motifNames.map((name) =>
  `<figure>${art({ family: 'bingo', rarity: 'rare', symbol: Object.keys(catalog.motifs).find((k) => catalog.motifs[k] === name) }, 96, false)}<figcaption>${name}</figcaption></figure>`).join('');
const missing = badges.filter((b) => !catalog.motifs[b.symbol]).length;

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Badge art</title>
<style>
  :root { --bg: #f6f3ef; --fg: #1f1a17; --muted: #6b625c; --card: #ffffff; --line: #e4ddd5; --accent: #d9622b; }
  @media (prefers-color-scheme: dark) { :root { --bg: #171412; --fg: #f2ede8; --muted: #a59c94; --card: #211d1a; --line: #37312c; --accent: #f08a4b; } }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px 16px 64px; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 1200px; margin: 0 auto; }
  h1 { font-size: 28px; margin: 0 0 4px; }
  h2 { font-size: 20px; margin: 36px 0 12px; }
  h3 { font-size: 15px; margin: 0; }
  p { margin: 0 0 12px; color: var(--muted); max-width: 72ch; }
  .count { color: var(--muted); font-weight: 400; font-size: 15px; }
  .filters { display: flex; flex-wrap: wrap; gap: 8px; margin: 16px 0 0; position: sticky; top: 0; background: var(--bg); padding: 8px 0; z-index: 1; }
  .filters button { font: inherit; font-size: 14px; padding: 6px 12px; border-radius: 999px; border: 1px solid var(--line); background: var(--card); color: var(--fg); cursor: pointer; }
  .filters button[aria-pressed="true"] { background: var(--accent); border-color: var(--accent); color: #fff; }
  .filters button:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 360px), 1fr)); gap: 12px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 12px; min-width: 0; }
  .meta { font-size: 12px; margin: 2px 0 8px; overflow-wrap: anywhere; }
  .meta strong { color: #c0392b; }
  .pair { display: grid; gap: 6px; }
  .light, .dark { border-radius: 10px; padding: 8px; display: flex; align-items: center; gap: 8px; overflow-x: auto; }
  .light { background: #ffffff; border: 1px solid #e4ddd5; }
  .dark { background: #1c1c1e; border: 1px solid #37312c; }
  .badge { position: relative; display: inline-block; flex: none; }
  .badge svg { display: block; }
  .badge.locked > svg { filter: brightness(0) opacity(.2); }
  .dark .badge.locked > svg { filter: brightness(0) invert(1) opacity(.24); }
  .lock { position: absolute; inset: 0; display: grid; place-items: center; }
  .motifs { display: flex; flex-wrap: wrap; gap: 14px; }
  figure { margin: 0; text-align: center; width: 100px; }
  figcaption { font-size: 12px; color: var(--muted); margin-top: 4px; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
${symbols('frames', 64)}
${symbols('motifs', 24)}
</defs></svg>
<main>
  <h1>Badge art</h1>
  <p>Every badge with the picture the app will draw: the frame's shape is the badge's family, the trim around it is its rarity, and the drawing in the middle comes from the badge's symbol. Each card shows 44, 60 and 120 points and the locked look, on a light and a dark background.</p>
  <p>${badges.length} badges, ${families.length} families, ${motifNames.length} drawings${missing ? `, <strong>${missing} without a drawing</strong>` : ''}. A hidden secret badge shows the grey Secrets frame with a question mark until it is earned.</p>
  <div class="filters" role="group" aria-label="Filter by family">${filters}</div>

  <section data-family="all-only"><h2>The drawings <span class="count">${motifNames.length}</span></h2>
  <div class="motifs">${motifCells}</div></section>
${sections}
</main>
<script>
  const buttons = document.querySelectorAll('.filters button');
  buttons.forEach((button) => button.addEventListener('click', () => {
    const filter = button.dataset.filter;
    buttons.forEach((b) => b.setAttribute('aria-pressed', String(b === button)));
    document.querySelectorAll('main > section').forEach((section) => {
      section.hidden = filter !== 'all' && section.dataset.family !== filter;
    });
  }));
</script>
</body>
</html>
`;

fs.writeFileSync(outFile, html);
console.log(`wrote ${path.relative(root, outFile)} (${(Buffer.byteLength(html) / 1024).toFixed(0)} KB, ${badges.length} badges, ${missing} without a motif)`);

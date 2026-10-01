// build-badge-gallery.mjs
//
// Writes docs/guide/badges.html from the SVG files under ios/BadgeArt
// (redesign-badge-art design D6): the page the owner approves the badge
// style on, in a browser on this PC, before any app drawing code changes.
// It shows each frame with a motif at 44, 60 and 120 pt, unlocked and
// locked, on light and dark, in two style variants:
//
//   sticker  the files as drawn (dark outline, cel shading);
//   modern   the same files with the dark outline removed (a string
//            replace of the ink colour), so there is one set of drawings.
//
// The page is self-contained (the SVG is inlined), so it opens from disk.
//
//   node tools/docs/build-badge-gallery.mjs

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const artDir = path.join(root, 'ios', 'BadgeArt');
const outFile = path.join(root, 'docs', 'guide', 'badges.html');
const INK = '#2A1F1A';

const read = (folder) =>
  Object.fromEntries(
    fs.readdirSync(path.join(artDir, folder)).sort().map((name) => [
      name.replace(/\.svg$/, ''),
      fs.readFileSync(path.join(artDir, folder, name), 'utf8'),
    ]),
  );
const frames = read('frames');
const motifs = read('motifs');

/** The children of an SVG file, without its <svg> wrapper. */
const inner = (text) => text.replace(/<svg[^>]*>/, '').replace('</svg>', '').trim();
const modern = (text) => text.replaceAll(`stroke="${INK}"`, 'stroke="none"');

// A motif for each family in the sample (wave 2 replaces this with the
// real catalog from Gamification).
const SAMPLE_MOTIF = {
  streak: 'flame', logging: 'forkKnife', macros: 'plate', levels: 'star', boss: 'crown', bingo: 'star',
  journeys: 'moon', records: 'crown', collections: 'plate', seasonal: 'moon', sportBody: 'scale',
  supplements: 'capsule', secrets: 'question',
};
const FAMILY_NAMES = {
  streak: 'Streak', logging: 'Logging', macros: 'Macros', levels: 'Levels', boss: 'Boss', bingo: 'Bingo',
  journeys: 'Journeys', records: 'Records', collections: 'Collections', seasonal: 'Seasonal',
  sportBody: 'Sport & body', supplements: 'Supplements', secrets: 'Secrets',
};
// Where the motif sits in the 64-unit frame: [x, y, size].
const MOTIF_BOX = { records: [19.5, 14.5, 25], levels: [20.5, 22, 23], secrets: [19, 13, 26], journeys: [18.5, 15, 27], default: [18, 18, 28] };

function badge(frameKey, motifKey, { size, locked, style }) {
  const transform = style === 'modern' ? modern : (text) => text;
  const family = frameKey.split('-')[1];
  const [x, y, s] = MOTIF_BOX[family] ?? MOTIF_BOX.default;
  if (locked) {
    // The app draws the frame as a template image; here a CSS filter
    // flattens it to one grey, and the motif is hidden.
    return `<span class="badge locked" style="width:${size}px;height:${size}px"><svg viewBox="0 0 64 64" width="${size}" height="${size}" aria-hidden="true">${inner(transform(frames[frameKey]))}</svg><span class="lock" style="font-size:${Math.round(size * 0.3)}px">&#128274;</span></span>`;
  }
  return `<span class="badge" style="width:${size}px;height:${size}px"><svg viewBox="0 0 64 64" width="${size}" height="${size}" role="img" aria-label="${frameKey} with ${motifKey}">${inner(transform(frames[frameKey]))}<svg x="${x}" y="${y}" width="${s}" height="${s}" viewBox="0 0 24 24">${inner(transform(motifs[motifKey]))}</svg></svg></span>`;
}

function row(frameKey, motifKey, style) {
  const cells = [44, 60, 120].map((size) => badge(frameKey, motifKey, { size, locked: false, style })).join('');
  const locked = badge(frameKey, motifKey, { size: 60, locked: true, style });
  return `<div class="set">${cells}${locked}</div>`;
}

function card(frameKey, motifKey, title) {
  return `<article class="card"><h3>${title}</h3>
  <div class="variants">
    <div><p class="label">Sticker</p><div class="pair"><div class="light">${row(frameKey, motifKey, 'sticker')}</div><div class="dark">${row(frameKey, motifKey, 'sticker')}</div></div></div>
    <div><p class="label">Modern</p><div class="pair"><div class="light">${row(frameKey, motifKey, 'modern')}</div><div class="dark">${row(frameKey, motifKey, 'modern')}</div></div></div>
  </div></article>`;
}

const families = Object.keys(SAMPLE_MOTIF).filter((family) => frames[`frame-${family}-common`]);
// A different rarity per family, so the page also shows the colours.
const CYCLE = ['rare', 'uncommon', 'epic', 'legendary', 'common'];
const familyCards = families
  .map((family, i) => card(`frame-${family}-${CYCLE[i % CYCLE.length]}`, `motif-${SAMPLE_MOTIF[family]}`, FAMILY_NAMES[family]))
  .join('\n');
const rarityCards = ['common', 'uncommon', 'rare', 'epic', 'legendary']
  .filter((rarity) => frames[`frame-streak-${rarity}`])
  .map((rarity) => card(`frame-streak-${rarity}`, 'motif-flame', rarity[0].toUpperCase() + rarity.slice(1)))
  .join('\n');
const motifCells = Object.keys(motifs)
  .map((key) => `<figure>${badge('frame-bingo-common', key, { size: 60, locked: false, style: 'sticker' })}<figcaption>${key.replace('motif-', '')}</figcaption></figure>`)
  .join('');

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Badge art sample</title>
<style>
  :root { --bg: #f6f3ef; --fg: #1f1a17; --muted: #6b625c; --card: #ffffff; --line: #e4ddd5; --lock: #b9b2ab; }
  @media (prefers-color-scheme: dark) { :root { --bg: #171412; --fg: #f2ede8; --muted: #a59c94; --card: #211d1a; --line: #37312c; } }
  * { box-sizing: border-box; }
  body { margin: 0; padding: 24px 16px 64px; background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
  main { max-width: 1100px; margin: 0 auto; }
  h1 { font-size: 28px; margin: 0 0 4px; }
  h2 { font-size: 20px; margin: 40px 0 12px; }
  h3 { font-size: 16px; margin: 0 0 8px; }
  p { margin: 0 0 12px; color: var(--muted); max-width: 70ch; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 760px), 1fr)); gap: 16px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 14px; padding: 14px; }
  .variants { display: grid; gap: 10px; }
  .label { font-size: 12px; text-transform: uppercase; letter-spacing: .06em; margin: 0 0 4px; }
  .pair { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 340px), 1fr)); gap: 8px; }
  .light, .dark { border-radius: 10px; padding: 10px; overflow-x: auto; }
  .light { background: #ffffff; border: 1px solid #e4ddd5; }
  .dark { background: #1c1c1e; border: 1px solid #37312c; }
  .set { display: flex; align-items: center; gap: 10px; }
  .badge { position: relative; display: inline-block; flex: none; }
  .badge svg { display: block; }
  .badge.locked > svg { filter: brightness(0) opacity(.2); }
  .dark .badge.locked > svg { filter: brightness(0) invert(1) opacity(.24); }
  .lock { position: absolute; inset: 0; display: grid; place-items: center; }
  .motifs { display: flex; flex-wrap: wrap; gap: 16px; }
  figure { margin: 0; text-align: center; }
  figcaption { font-size: 12px; color: var(--muted); margin-top: 4px; }
</style>
</head>
<body>
<main>
  <h1>Badge art sample</h1>
  <p>First sample for the badge redesign. Each row shows a badge at 44, 60 and 120 points, then locked, on a light and a dark background. Pick a style: Sticker (dark outline) or Modern (no outline).</p>

  <h2>Rarity: the trim around one shape</h2>
  <p>Common is plain. Uncommon adds an inner ring, rare adds side gems, epic adds ribbon tails, legendary adds a crown.</p>
  <div class="grid">
${rarityCards}
  </div>

  <h2>Family: the shape of the frame</h2>
  <p>Each badge family has its own outline, so a family can be told apart without colour.</p>
  <div class="grid">
${familyCards}
  </div>

  <h2>Motifs</h2>
  <p>The first ten drawings that sit in the middle of a frame.</p>
  <div class="motifs">${motifCells}</div>
</main>
</body>
</html>
`;

fs.writeFileSync(outFile, html);
console.log(`wrote ${path.relative(root, outFile)} (${(Buffer.byteLength(html) / 1024).toFixed(0)} KB)`);

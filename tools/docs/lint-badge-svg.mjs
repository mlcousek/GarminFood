// lint-badge-svg.mjs
//
// Refuses badge art that Xcode's asset-catalog SVG support may draw
// differently from a browser (redesign-badge-art design D3). There is no
// Mac to look at the result before a sideload, so the art stays inside a
// small, boring subset: <svg> with <path> children only, absolute path
// commands M L C Z, solid fills and strokes (opacity allowed), and a fixed
// view box (64 for frames, 24 for motifs). Also reports the set's size
// against the 400 KB budget.
//
//   node tools/docs/lint-badge-svg.mjs
//
// Run by CI's localization job (no macOS needed).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const artDir = path.join(root, 'ios', 'BadgeArt');
const BUDGET_BYTES = 400 * 1024;

const ALLOWED_ATTRIBUTES = new Set([
  'd', 'fill', 'fill-opacity', 'stroke', 'stroke-opacity', 'stroke-width', 'stroke-linejoin', 'stroke-linecap',
]);
const COLOR = /^(none|#[0-9A-Fa-f]{6})$/;

const problems = [];
let total = 0;
let files = 0;

for (const [folder, size] of [['frames', 64], ['motifs', 24]]) {
  const dir = path.join(artDir, folder);
  if (!fs.existsSync(dir)) {
    problems.push(`${folder}: folder missing`);
    continue;
  }
  for (const name of fs.readdirSync(dir).sort()) {
    const file = `${folder}/${name}`;
    if (!name.endsWith('.svg')) {
      problems.push(`${file}: not an SVG file`);
      continue;
    }
    const text = fs.readFileSync(path.join(dir, name), 'utf8');
    total += Buffer.byteLength(text);
    files++;

    if (!text.includes(`viewBox="0 0 ${size} ${size}"`)) problems.push(`${file}: view box must be 0 0 ${size} ${size}`);
    const tags = [...text.matchAll(/<\/?([A-Za-z][\w:-]*)([^>]*)>/g)];
    for (const [, tag, attributes] of tags) {
      if (tag === 'svg') continue;
      if (tag !== 'path') {
        problems.push(`${file}: <${tag}> is not allowed (paths only)`);
        continue;
      }
      for (const [, key, value] of attributes.matchAll(/([\w:-]+)="([^"]*)"/g)) {
        if (!ALLOWED_ATTRIBUTES.has(key)) problems.push(`${file}: attribute ${key} is not allowed`);
        if ((key === 'fill' || key === 'stroke') && !COLOR.test(value)) problems.push(`${file}: ${key}="${value}" must be none or #RRGGBB`);
        if (key === 'd' && /[^MLCZ0-9 .\-]/.test(value)) problems.push(`${file}: path uses a command other than absolute M L C Z`);
      }
    }
  }
}

if (total > BUDGET_BYTES) problems.push(`the set is ${total} bytes, over the ${BUDGET_BYTES}-byte budget`);

if (problems.length) {
  console.error(`lint-badge-svg: ${problems.length} problem(s)`);
  for (const problem of problems) console.error(`  ${problem}`);
  process.exit(1);
}
console.log(`lint-badge-svg: OK (${files} files, ${(total / 1024).toFixed(1)} KB of ${BUDGET_BYTES / 1024} KB)`);

// write-badge-art.mjs
//
// The badge art's drawings (redesign-badge-art design D1-D3). The shapes
// below are written by hand as absolute SVG path data; this script only
// multiplies them out (frame shape x rarity colours + trim) and writes one
// SVG file per frame and per motif under ios/BadgeArt/. Those files are
// committed: they are what the gallery shows and what the app's asset
// catalog will be generated from. Re-run after editing a shape:
//
//   node tools/docs/write-badge-art.mjs
//
// Only the SVG subset the lint allows is produced (lint-badge-svg.mjs):
// paths with solid fills and strokes, no transforms, no gradients.
//
// ios/BadgeArt is deliberately OUTSIDE ios/GarminFood: XcodeGen globs that
// folder into the app bundle, and loose SVG files don't belong there.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const outDir = path.join(root, 'ios', 'BadgeArt');

const INK = '#2A1F1A';

// (top, bottom) per rarity: BadgeMedallion's RarityPalette, as hex.
export const RARITIES = {
  common: ['#B3B8C2', '#787D87'],
  uncommon: ['#6BB58A', '#307D59'],
  rare: ['#669EF0', '#2E61BF'],
  epic: ['#A875ED', '#703DBA'],
  legendary: ['#FCCC4D', '#EB8026'],
};

const r2 = (n) => Math.round(n * 100) / 100;

// --- path helpers (absolute M / L / C / Z only) ---------------------------

function poly(points) {
  return points.map(([x, y], i) => `${i ? 'L' : 'M'}${r2(x)} ${r2(y)}`).join(' ') + ' Z';
}

function circle(cx, cy, r) {
  const k = 0.5523 * r;
  return [
    `M${r2(cx)} ${r2(cy - r)}`,
    `C${r2(cx + k)} ${r2(cy - r)} ${r2(cx + r)} ${r2(cy - k)} ${r2(cx + r)} ${r2(cy)}`,
    `C${r2(cx + r)} ${r2(cy + k)} ${r2(cx + k)} ${r2(cy + r)} ${r2(cx)} ${r2(cy + r)}`,
    `C${r2(cx - k)} ${r2(cy + r)} ${r2(cx - r)} ${r2(cy + k)} ${r2(cx - r)} ${r2(cy)}`,
    `C${r2(cx - r)} ${r2(cy - k)} ${r2(cx - k)} ${r2(cy - r)} ${r2(cx)} ${r2(cy - r)}`,
    'Z',
  ].join(' ');
}

function roundRect(x, y, w, h, r) {
  const k = r * (1 - 0.5523);
  const x2 = x + w;
  const y2 = y + h;
  return [
    `M${r2(x + r)} ${r2(y)}`,
    `L${r2(x2 - r)} ${r2(y)}`,
    `C${r2(x2 - k)} ${r2(y)} ${r2(x2)} ${r2(y + k)} ${r2(x2)} ${r2(y + r)}`,
    `L${r2(x2)} ${r2(y2 - r)}`,
    `C${r2(x2)} ${r2(y2 - k)} ${r2(x2 - k)} ${r2(y2)} ${r2(x2 - r)} ${r2(y2)}`,
    `L${r2(x + r)} ${r2(y2)}`,
    `C${r2(x + k)} ${r2(y2)} ${r2(x)} ${r2(y2 - k)} ${r2(x)} ${r2(y2 - r)}`,
    `L${r2(x)} ${r2(y + r)}`,
    `C${r2(x)} ${r2(y + k)} ${r2(x + k)} ${r2(y)} ${r2(x + r)} ${r2(y)}`,
    'Z',
  ].join(' ');
}

/** Points on a circle with alternating radii (stars, gears, rosettes). */
function radial(cx, cy, radii, count, startDeg = -90) {
  const points = [];
  for (let i = 0; i < count; i++) {
    const a = ((startDeg + (360 / count) * i) * Math.PI) / 180;
    const r = radii[i % radii.length];
    points.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return points;
}

/** Scales every coordinate of an absolute path about (cx, cy). */
function scale(d, s, cx = 32, cy = 32) {
  let isX = true;
  return d.replace(/-?\d+(\.\d+)?/g, (n) => {
    const v = Number(n);
    const out = isX ? cx + (v - cx) * s : cy + (v - cy) * s;
    isX = !isX;
    return String(r2(out));
  });
}

function mirror(d) {
  let isX = true;
  return d.replace(/-?\d+(\.\d+)?/g, (n) => {
    const out = isX ? 64 - Number(n) : Number(n);
    isX = !isX;
    return String(r2(out));
  });
}

// --- frames: 64 x 64, the shape tells the family --------------------------
// `main` is the body; `behind` is drawn under it (horns, ribbons, leaves).

const SHAPES = {
  streak: { main: 'M32 5 L55 13 L55 31 C55 45 45 54 32 60 C19 54 9 45 9 31 L9 13 Z' },
  logging: { main: circle(32, 32, 27), ring: circle(32, 32, 16.5) },
  macros: { main: poly(radial(32, 32, [28], 6)) },
  levels: { main: poly(radial(32, 33, [30, 17], 10)) },
  boss: {
    main: 'M32 10 L52 16 L52 32 C52 45 43 53 32 59 C21 53 12 45 12 32 L12 16 Z',
    behind: ['M14 22 L3 3 L24 13 Z', mirror('M14 22 L3 3 L24 13 Z')],
  },
  bingo: { main: roundRect(7, 7, 50, 50, 12) },
  journeys: { main: 'M10 7 L54 7 L54 43 L32 59 L10 43 Z' },
  records: {
    main: poly(radial(32, 27, [25, 21.5], 24)),
    behind: ['M21 40 L14 62 L24 57 L30 63 L34 42 Z', mirror('M21 40 L14 62 L24 57 L30 63 L34 42 Z')],
  },
  collections: { main: poly(radial(32, 32, [29], 8, -67.5)) },
  seasonal: {
    main: circle(32, 32, 21),
    behind: radial(32, 32, [26], 12).map(([x, y], i) => {
      const a = ((-90 + 30 * i) * Math.PI) / 180;
      const tip = [x + 6 * Math.cos(a + 0.9), y + 6 * Math.sin(a + 0.9)];
      const left = [x + 3.4 * Math.cos(a - 1.2), y + 3.4 * Math.sin(a - 1.2)];
      const right = [x - 3.4 * Math.cos(a - 0.2), y - 3.4 * Math.sin(a - 0.2)];
      return poly([left, tip, right]);
    }),
  },
  sportBody: {
    main: poly(radial(32, 32, [29, 29, 23.5, 23.5], 32, -90 - 360 / 64)),
  },
  supplements: { main: roundRect(13, 4, 38, 56, 19) },
  secrets: {
    main: 'M32 4 C46 4 55 14 55 26 C55 34 51 40 45 44 L51 60 L13 60 L19 44 C13 40 9 34 9 26 C9 14 18 4 32 4 Z',
  },
};

// Body scale: leaves a margin for the rarity trim.
const BODY = 0.86;

function trim(rarity, top) {
  const behind = [];
  const front = [];
  const ink = `stroke="${INK}" stroke-width="2" stroke-linejoin="round"`;
  if (rarity === 'rare' || rarity === 'epic' || rarity === 'legendary') {
    // Side gems.
    const gem = 'M4.5 32 L9 26.5 L13.5 32 L9 37.5 Z';
    front.push(`<path d="${gem}" fill="${top}" ${ink}/>`, `<path d="${mirror(gem)}" fill="${top}" ${ink}/>`);
  }
  if (rarity === 'epic' || rarity === 'legendary') {
    // Ribbon tails, under the body.
    const tail = 'M16 42 L3 49 L9 53 L5 60 L21 56 Z';
    behind.push(`<path d="${tail}" fill="${top}" ${ink}/>`, `<path d="${mirror(tail)}" fill="${top}" ${ink}/>`);
  }
  if (rarity === 'legendary') {
    front.push(`<path d="M22 12 L20 1.5 L26.5 6.5 L32 1 L37.5 6.5 L44 1.5 L42 12 Z" fill="#FFE27A" ${ink}/>`);
  }
  return { behind, front };
}

function frameSVG(family, rarity) {
  const shape = SHAPES[family];
  const [top, bottom] = RARITIES[rarity];
  const body = scale(shape.main, BODY);
  const inner = scale(shape.main, BODY * 0.8);
  const { behind, front } = trim(rarity, top);
  const parts = [...behind];
  for (const d of shape.behind ?? []) {
    parts.push(`<path d="${scale(d, BODY)}" fill="${bottom}" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`);
  }
  parts.push(`<path d="${body}" fill="${bottom}" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/>`);
  parts.push(`<path d="${inner}" fill="${top}"/>`);
  if (shape.ring) {
    parts.push(`<path d="${scale(shape.ring, BODY)}" fill="none" stroke="${bottom}" stroke-width="1.5"/>`);
  }
  if (rarity !== 'common') {
    // The second ring: every rarity above common.
    parts.push(`<path d="${scale(shape.main, BODY * 0.68)}" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="1.2" stroke-linejoin="round"/>`);
  }
  // One highlight, top-left.
  parts.push(`<path d="${scale(circle(24, 21, 5), 1)}" fill="#FFFFFF" fill-opacity="0.3"/>`);
  parts.push(...front);
  return svg(64, parts);
}

// --- motifs: 24 x 24, what the badge is about -----------------------------

const TINT = '#FFD9A0';
const ink = `stroke="${INK}" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"`;
const white = (d) => `<path d="${d}" fill="#FFFFFF" ${ink}/>`;
const tint = (d) => `<path d="${d}" fill="${TINT}" ${ink}/>`;

const MOTIFS = {
  flame: [
    white('M12 2 C13 6 18 8 18 14 C18 18.5 15.5 22 12 22 C8.5 22 6 18.5 6 14 C6 11 7.5 9 9 7.5 C9.5 9.5 10.5 10.5 11.5 10.5 C11 7.5 11 4.5 12 2 Z'),
    tint('M12 13.5 C13.5 15.5 14.5 16.5 14.5 18 C14.5 19.6 13.4 20.5 12 20.5 C10.6 20.5 9.5 19.6 9.5 18 C9.5 16.5 11 15.5 12 13.5 Z'),
  ],
  forkKnife: [
    white('M5 2 L5 9 C5 10.7 6 11.6 7 12 L7 22 L9.5 22 L9.5 12 C10.5 11.6 11.5 10.7 11.5 9 L11.5 2 L10 2 L10 8 L9 8 L9 2 L7.5 2 L7.5 8 L6.5 8 L6.5 2 Z'),
    white('M15 22 L15 2 C18.5 3.5 20 8 20 13 L17.5 13 L17.5 22 Z'),
  ],
  plate: [white(circle(12, 12, 10)), tint(circle(12, 12, 5.5))],
  scale: [
    white(roundRect(3, 4, 18, 17, 4)),
    tint('M7 11 C8.5 7.5 15.5 7.5 17 11 L15 13 L9 13 Z'),
    `<path d="M12 12 L14 8.6" fill="none" ${ink}/>`,
  ],
  drop: [
    white('M12 2 C15 7 19 11 19 15 C19 19 16 22 12 22 C8 22 5 19 5 15 C5 11 9 7 12 2 Z'),
    `<path d="M8.5 15 C8.5 17.2 10 18.6 12 18.8" fill="none" stroke="${TINT}" stroke-width="1.8" stroke-linecap="round"/>`,
  ],
  moon: [
    white('M15 3 C10 4 6.5 8 6.5 12.5 C6.5 17.7 10.8 21.5 15.5 21.5 C17.5 21.5 19.3 20.9 20.8 19.8 C15 19.5 11.5 15.8 11.5 11 C11.5 7.7 12.8 4.9 15 3 Z'),
  ],
  star: [white(poly(radial(12, 12.6, [10.2, 4.6], 10)))],
  crown: [white('M3 17.5 L3 6.5 L8 11.5 L12 4 L16 11.5 L21 6.5 L21 17.5 Z'), tint(roundRect(3, 17.5, 18, 3.5, 1))],
  capsule: [
    white(roundRect(7, 2, 10, 20, 5)),
    tint('M7 12 L17 12 L17 17 C17 19.8 14.8 22 12 22 C9.2 22 7 19.8 7 17 Z'),
  ],
  question: [
    `<path d="M8 8 C8 5 9.8 3.5 12 3.5 C14.5 3.5 16 5.2 16 7.3 C16 10.5 12 10.6 12 14.5" fill="none" stroke="${INK}" stroke-width="5.4" stroke-linecap="round" stroke-linejoin="round"/>`,
    `<path d="M8 8 C8 5 9.8 3.5 12 3.5 C14.5 3.5 16 5.2 16 7.3 C16 10.5 12 10.6 12 14.5" fill="none" stroke="#FFFFFF" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>`,
    white(circle(12, 19.5, 1.9)),
  ],
};

function svg(size, parts) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">\n  ${parts.join('\n  ')}\n</svg>\n`;
}

// --- what this wave writes -------------------------------------------------
// Every shape x every rarity (13 x 5 frames) and the motifs drawn so far.

const ALL_RARITIES = true;

fs.rmSync(outDir, { recursive: true, force: true });
fs.mkdirSync(path.join(outDir, 'frames'), { recursive: true });
fs.mkdirSync(path.join(outDir, 'motifs'), { recursive: true });

let count = 0;
for (const family of Object.keys(SHAPES)) {
  const rarities = ALL_RARITIES || family === 'streak' ? Object.keys(RARITIES) : ['common'];
  for (const rarity of rarities) {
    fs.writeFileSync(path.join(outDir, 'frames', `frame-${family}-${rarity}.svg`), frameSVG(family, rarity));
    count++;
  }
}
for (const [name, parts] of Object.entries(MOTIFS)) {
  fs.writeFileSync(path.join(outDir, 'motifs', `motif-${name}.svg`), svg(24, parts));
  count++;
}
console.log(`wrote ${count} SVG files to ${path.relative(root, outDir)}`);

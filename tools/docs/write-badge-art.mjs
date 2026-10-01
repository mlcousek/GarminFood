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
const dark = (d) => `<path d="${d}" fill="${INK}"/>`;
/** A thin ink detail line. */
const line = (d) => `<path d="${d}" fill="none" ${ink}/>`;
const stroke = (d, color, width) =>
  `<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
/** A coloured line with an ink outline: the ink stroke under the colour. */
const outlined = (d, color, width, outline = width + 2.6) => [stroke(d, INK, outline), stroke(d, color, width)];

function mirror24(d) {
  let isX = true;
  return d.replace(/-?\d+(\.\d+)?/g, (n) => {
    const out = isX ? 24 - Number(n) : Number(n);
    isX = !isX;
    return String(r2(out));
  });
}

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
    white(roundRect(3, 4.5, 18, 16.5, 4)),
    tint(roundRect(7.5, 7.5, 9, 4.6, 1.6)),
    line('M12 12.1 L13.4 8.6'),
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
  leaf: [
    white('M12 2.5 C18 6 20 11 18 16 C16.5 19.5 13.5 21 12 21.5 C10.5 21 7.5 19.5 6 16 C4 11 6 6 12 2.5 Z'),
    line('M12 8 L12 21.5'),
    line('M12 13 L15 10.5'),
    line('M12 16 L9 13.5'),
  ],
  target: [white(circle(12, 12, 10)), tint(circle(12, 12, 6)), white(circle(12, 12, 2.4))],
  check: [white(circle(12, 12, 10)), ...outlined('M7.3 12.4 L10.7 15.8 L16.9 8.8', TINT, 2.4)],
  bolt: [white('M13.5 2 L5 13.5 L11 13.5 L9.5 22 L19 9.5 L13 9.5 Z')],
  party: [
    white('M3.5 21 L8.5 8 L16.5 16 Z'),
    tint('M5.6 15.6 L6.9 12.2 L12.3 17.6 L8.9 18.9 Z'),
    tint(circle(15.5, 5, 1.6)),
    white(circle(19.8, 9.5, 1.5)),
    tint(circle(11, 3.6, 1.2)),
    white(poly(radial(19.5, 16, [2.6, 1.1], 8))),
  ],
  calendar: [
    white(roundRect(3, 5, 18, 16, 3)),
    tint('M3 10 L21 10 L21 8 C21 6.3 19.7 5 18 5 L6 5 C4.3 5 3 6.3 3 8 Z'),
    line('M8 3 L8 7'),
    line('M16 3 L16 7'),
    line('M8.3 15.2 L10.8 17.6 L15.8 12.6'),
  ],
  gift: [
    white(roundRect(3.5, 10.5, 17, 10.5, 2)),
    white(roundRect(2.5, 6.5, 19, 4.5, 1.5)),
    tint(roundRect(10.3, 6.5, 3.4, 14.5, 0.5)),
    tint('M12 6.5 L7.5 2.5 L6 5.8 Z'),
    tint(mirror24('M12 6.5 L7.5 2.5 L6 5.8 Z')),
  ],
  grid: [
    white(roundRect(3, 3, 18, 18, 3)),
    tint(poly([[9, 9], [15, 9], [15, 15], [9, 15]])),
    line('M9 3 L9 21'),
    line('M15 3 L15 21'),
    line('M3 9 L21 9'),
    line('M3 15 L21 15'),
  ],
  cross: [
    stroke('M6.5 6.5 L17.5 17.5', INK, 6.4),
    stroke('M17.5 6.5 L6.5 17.5', INK, 6.4),
    stroke('M6.5 6.5 L17.5 17.5', '#FFFFFF', 3.4),
    stroke('M17.5 6.5 L6.5 17.5', '#FFFFFF', 3.4),
  ],
  spade: [
    white('M12 2.5 C15 7 20 9.5 20 14 C20 16.8 17.8 18.5 15.5 18.5 C14.3 18.5 13.3 18 12.7 17.2 L14.5 21.5 L9.5 21.5 L11.3 17.2 C10.7 18 9.7 18.5 8.5 18.5 C6.2 18.5 4 16.8 4 14 C4 9.5 9 7 12 2.5 Z'),
  ],
  figure: [
    white('M12 9.5 L17.5 5.5 L19 7.5 L14.2 11.5 L14.2 15 L17.5 21 L15 22 L12 17 L9 22 L6.5 21 L9.8 15 L9.8 11.5 L5 7.5 L6.5 5.5 Z'),
    white(circle(12, 5, 2.8)),
  ],
  shield: [
    white('M12 2.5 L20 5.5 L20 12 C20 16.5 16.5 19.8 12 21.5 C7.5 19.8 4 16.5 4 12 L4 5.5 Z'),
    tint('M12 2.5 L20 5.5 L20 12 C20 16.5 16.5 19.8 12 21.5 Z'),
  ],
  book: [
    white(roundRect(4, 3, 16, 18, 2)),
    tint('M8 3 L8 21 L6 21 C4.9 21 4 20.1 4 19 L4 5 C4 3.9 4.9 3 6 3 Z'),
    line('M11 8 L17 8'),
    line('M11 11.5 L17 11.5'),
  ],
  snowflake: [
    ...['M12 2.5 L12 21.5', 'M3.8 7.25 L20.2 16.75', 'M3.8 16.75 L20.2 7.25'].map((d) => stroke(d, INK, 4.8)),
    ...['M12 2.5 L12 21.5', 'M3.8 7.25 L20.2 16.75', 'M3.8 16.75 L20.2 7.25'].map((d) => stroke(d, '#FFFFFF', 2.2)),
  ],
  mountain: [white('M1.5 20.5 L9.5 5.5 L17.5 20.5 Z'), tint('M11 20.5 L16.5 11 L22.5 20.5 Z'), line('M6.8 10.6 L9.5 12.8 L12.2 10.6')],
  globe: [
    white(circle(12, 12, 10)),
    tint('M12 2 C7 6 7 18 12 22 C17 18 17 6 12 2 Z'),
    line('M2 12 L22 12'),
  ],
  sparkles: [white(poly(radial(10, 13.5, [8.5, 2.9], 8))), tint(poly(radial(18.5, 6, [4.2, 1.5], 8)))],
  waves: [
    ...['M2.5 8.5 C5.5 5 9 12 12 8.5 C15 5 18.5 12 21.5 8.5', 'M2.5 15.5 C5.5 12 9 19 12 15.5 C15 12 18.5 19 21.5 15.5'].map((d) => stroke(d, INK, 5)),
    stroke('M2.5 8.5 C5.5 5 9 12 12 8.5 C15 5 18.5 12 21.5 8.5', '#FFFFFF', 2.4),
    stroke('M2.5 15.5 C5.5 12 9 19 12 15.5 C15 12 18.5 19 21.5 15.5', TINT, 2.4),
  ],
  gauge: [
    white(circle(12, 12, 10)),
    line('M4.8 13 L6.8 13'),
    line('M17.2 13 L19.2 13'),
    line('M12 5 L12 7'),
    line('M12 13 L16.3 7.8'),
    tint(circle(12, 13, 2.2)),
  ],
  house: [white('M2.5 11.5 L12 2.8 L21.5 11.5 L18.5 11.5 L18.5 21 L5.5 21 L5.5 11.5 Z'), tint(roundRect(10, 14, 4, 7, 0.8))],
  trophy: [
    line('M6.5 5 C2.8 5 2.8 10.2 7.2 10.6'),
    line(mirror24('M6.5 5 C2.8 5 2.8 10.2 7.2 10.6')),
    white('M6.5 3 L17.5 3 L17.5 9 C17.5 12.5 15 14.5 12 14.5 C9 14.5 6.5 12.5 6.5 9 Z'),
    white(poly([[10.8, 14.5], [13.2, 14.5], [13.2, 18], [10.8, 18]])),
    tint(roundRect(7, 18, 10, 3.2, 1)),
  ],
  timer: [
    tint(roundRect(10, 1.8, 4, 3.4, 0.8)),
    white(circle(12, 13.5, 8.5)),
    line('M12 13.5 L12 8.5'),
    line('M12 13.5 L15.2 15.6'),
  ],
  rainbow: [
    white('M2.5 19 C2.5 9 7 4.5 12 4.5 C17 4.5 21.5 9 21.5 19 L17.5 19 C17.5 12 15 8.5 12 8.5 C9 8.5 6.5 12 6.5 19 Z'),
    tint('M6.5 19 C6.5 12 9 8.5 12 8.5 C15 8.5 17.5 12 17.5 19 L14 19 C14 14.5 13 12 12 12 C11 12 10 14.5 10 19 Z'),
  ],
  box: [
    white(poly([[3.5, 8], [12, 4], [20.5, 8], [20.5, 17], [12, 21], [3.5, 17]])),
    tint(poly([[3.5, 8], [12, 4], [20.5, 8], [12, 12]])),
    line('M12 12 L12 21'),
  ],
  mask: [
    white('M4 5 C9 7 15 7 20 5 L20 12 C20 17 16.5 21 12 21 C7.5 21 4 17 4 12 Z'),
    dark('M7 10.5 C8 9.3 9.5 9.3 10.5 10.5 C9.5 11.7 8 11.7 7 10.5 Z'),
    dark(mirror24('M7 10.5 C8 9.3 9.5 9.3 10.5 10.5 C9.5 11.7 8 11.7 7 10.5 Z')),
    line('M8.5 15 C10 17.5 14 17.5 15.5 15'),
  ],
  egg: [
    white('M12 2.5 C16 2.5 19.5 10 19.5 14.5 C19.5 18.8 16.2 21.5 12 21.5 C7.8 21.5 4.5 18.8 4.5 14.5 C4.5 10 8 2.5 12 2.5 Z'),
    tint('M4.8 12.5 L7.5 10.5 L10 13 L12 10.5 L14 13 L16.5 10.5 L19.2 12.5 L19.5 15.5 L16.5 13.8 L14 16.3 L12 13.8 L10 16.3 L7.5 13.8 L4.5 15.5 Z'),
  ],
  tree: [tint(roundRect(10.5, 17, 3, 4.5, 0.5)), white('M12 2 L18 9.5 L15.5 9.5 L20 17 L4 17 L8.5 9.5 L6 9.5 Z')],
  bird: [
    line('M9.5 19 L9.5 22'),
    line('M12.5 18.6 L12.5 22'),
    white('M4 13 C4 8.5 7.5 6 11 6 C13 6 14.5 6.8 15.5 8 L20.5 7 L17.5 10.5 C18 15.5 14.5 19 10 19 C6.5 19 4 16.5 4 13 Z'),
    tint('M7 12 C9 10.5 12 11 13.5 13 C12 15.5 9 16 7 12 Z'),
    dark(circle(13, 9.3, 0.8)),
  ],
  fish: [
    white('M2.5 12 C5.5 7 11 6 15 9 L20.5 6 L19.5 12 L20.5 18 L15 15 C11 18 5.5 17 2.5 12 Z'),
    dark(circle(7, 11, 0.9)),
    line('M11 9.5 C12 11 12 13 11 14.5'),
  ],
  fridge: [white(roundRect(6, 2, 12, 20, 2.5)), line('M6 9.5 L18 9.5'), line('M9 5 L9 7'), line('M9 12.5 L9 16')],
  cup: [
    line('M16.5 9 C20.8 8.5 20.8 14.2 16.2 14'),
    white('M4.5 7 L16.5 7 L16.5 13 C16.5 16.5 13.8 18.5 10.5 18.5 C7.2 18.5 4.5 16.5 4.5 13 Z'),
    tint(roundRect(3, 19, 15, 2.4, 1)),
    line('M8.5 2 C7.5 3 9.5 3.8 8.5 4.8'),
    line('M12.5 2 C11.5 3 13.5 3.8 12.5 4.8'),
  ],
  arrows: [
    white('M3 6 L14.5 6 L14.5 3 L21 7.5 L14.5 12 L14.5 9 L3 9 Z'),
    tint('M21 15 L9.5 15 L9.5 12 L3 16.5 L9.5 21 L9.5 18 L21 18 Z'),
  ],
  hash: [
    ...['M9 3.5 L7.5 20.5', 'M16.5 3.5 L15 20.5', 'M4 9 L20.5 9', 'M3.5 15 L20 15'].map((d) => stroke(d, INK, 4.6)),
    ...['M9 3.5 L7.5 20.5', 'M16.5 3.5 L15 20.5', 'M4 9 L20.5 9', 'M3.5 15 L20 15'].map((d) => stroke(d, '#FFFFFF', 2.1)),
  ],
  pie: [white(circle(12, 12, 10)), tint('M12 12 L12 2 C17.5 2 22 6.5 22 12 Z')],
  bars: [white(roundRect(3.5, 12, 4.5, 9, 1)), tint(roundRect(9.75, 7, 4.5, 14, 1)), white(roundRect(16, 3, 4.5, 18, 1))],
  sun: [tint(poly(radial(12, 12, [10.8, 7.2], 16))), white(circle(12, 12, 5))],
  key: [
    white('M10.5 11.5 L13 9 L21.5 17.5 L21.5 20.5 L18.5 20.5 L18.5 18.5 L16.5 18.5 L16.5 16.5 L14.5 16.5 Z'),
    white(circle(8, 8, 5.5)),
    tint(circle(7.3, 7.3, 1.8)),
  ],
  gear: [white(poly(radial(12, 12, [10.6, 10.6, 7.8, 7.8], 32, -90 - 360 / 64))), tint(circle(12, 12, 3.2))],
  heart: [
    white('M12 21 C5 16 2.5 12 2.5 8.5 C2.5 5.5 4.8 3.5 7.3 3.5 C9.3 3.5 11 4.6 12 6.3 C13 4.6 14.7 3.5 16.7 3.5 C19.2 3.5 21.5 5.5 21.5 8.5 C21.5 12 19 16 12 21 Z'),
  ],
  flag: [stroke('M5 2.5 L5 21.5', INK, 2.4), white('M5 4 L19.5 4 L16 8.5 L19.5 13 L5 13 Z')],
  dumbbell: [tint(roundRect(6, 10.5, 12, 3, 0.5)), white(roundRect(2.5, 6, 4.5, 12, 1.5)), white(roundRect(17, 6, 4.5, 12, 1.5))],
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

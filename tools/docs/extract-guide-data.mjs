#!/usr/bin/env node
// extract-guide-data.mjs
//
// Regenerates docs/guide/data/*.json -- the catalogs the interactive guide
// (docs/guide/index.html) renders -- straight from the Swift sources and
// the en/cs string tables, so the guide can never silently drift from the
// app. Node, no dependencies:
//
//     node tools/docs/extract-guide-data.mjs          # writes the JSON files
//     node tools/docs/extract-guide-data.mjs --embed  # ...and refreshes the
//                                                     # inline copy in index.html
//
// Reproducible: the output depends only on the files under ios/ (no dates,
// no randomness); `meta.json` records the last commit that touched ios/.
//
// How each catalog is read (also written into every file's "source" field):
//   - "parsed"   -- read from a literal Swift table (calls such as
//                   `BingoTask(...)`, `Spec(...)`, `static let` constants);
//   - "mirrored" -- the Swift code BUILDS the catalog in a loop (achievement
//                   families, challenge ladders, daily-challenge variants,
//                   the level curve, the XP budget). The loops' input arrays
//                   are parsed from the source; the loop body (id pattern,
//                   window / XP formula, English sentence) is mirrored here,
//                   and `expectIn` fails loudly when the Swift formula text
//                   this mirror depends on is no longer in the file;
//   - "hand-read" -- prose written from reading the code (rules, filters);
//                   each such block names the file it came from.
//
// Czech text comes from Gamification/Resources/cs.lproj/{Catalog,
// Localizable,Collections}.strings, FoodLogCore/Resources/cs.lproj/
// Localizable.strings(+dict) and GarminFood/Resources/Localizable.xcstrings.
// Any catalog string without a Czech translation is listed in
// data/l10n-gaps.json.
//
// Depends on: tools/docs/swift-lite.mjs.

import { writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  read, findCalls, splitTop, args, argMap, stringLiteral, arrayLiteral, literalValue,
  staticLets, declBlock, matchBracket, parseStrings, parseStringsDict, parseXcstrings,
} from './swift-lite.mjs';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');
const IOS = join(ROOT, 'ios');
const OUT = join(ROOT, 'docs', 'guide', 'data');
const GAM = join(IOS, 'Gamification/Sources/Gamification');
const FEAT = join(GAM, 'Features');
const FLC = join(IOS, 'FoodLogCore/Sources/FoodLogCore');

const rel = (p) => p.slice(ROOT.length + 1).replace(/\\/g, '/');
const src = (p) => read(p);
const lineOf = (text, idx) => text.slice(0, idx).split('\n').length;

function expectIn(text, needle, where) {
  if (!text.includes(needle)) {
    throw new Error(`mirror out of date: expected \`${needle}\` in ${where}. Update extract-guide-data.mjs to match the Swift code.`);
  }
}

// ------------------------------------------------------------ localization

const T = {
  catalogCs: parseStrings(src(join(GAM, 'Resources/cs.lproj/Catalog.strings'))),
  gamCs: parseStrings(src(join(GAM, 'Resources/cs.lproj/Localizable.strings'))),
  gamEn: parseStrings(src(join(GAM, 'Resources/en.lproj/Localizable.strings'))),
  collCs: parseStrings(src(join(GAM, 'Resources/cs.lproj/Collections.strings'))),
  collEn: parseStrings(src(join(GAM, 'Resources/en.lproj/Collections.strings'))),
  flcCs: parseStrings(src(join(FLC, 'Resources/cs.lproj/Localizable.strings'))),
  flcEn: parseStrings(src(join(FLC, 'Resources/en.lproj/Localizable.strings'))),
  flcDictCs: parseStringsDict(src(join(FLC, 'Resources/cs.lproj/Localizable.stringsdict'))),
  app: parseXcstrings(src(join(IOS, 'GarminFood/Resources/Localizable.xcstrings'))),
};

const gaps = []; // {key, table, where}

/** All format keys an English template with `\(x)` interpolations could have in a .strings table. */
function keyCandidates(template) {
  const parts = template.split(/\\\([^)]*\)/);
  const holes = parts.length - 1;
  if (holes === 0) return [template];
  const specs = ['%@', '%lld', '%d'];
  const out = [];
  const rec = (i, acc) => {
    if (i === holes) { out.push(acc + parts[holes]); return; }
    for (const s of specs) rec(i + 1, acc + parts[i] + s);
  };
  rec(0, '');
  return out;
}

/** Look `template` up in `tables` (Maps); returns {key, cs} or {key, cs: undefined}. */
function lookup(template, tables) {
  for (const key of keyCandidates(template)) {
    for (const t of tables) {
      if (t.has(key)) {
        const v = t.get(key);
        return { key, cs: typeof v === 'string' ? v : v.cs ?? v };
      }
    }
  }
  return { key: keyCandidates(template)[0], cs: undefined };
}

/** Substitutes `\(expr)` (English) and %@/%lld (format) holes in order. */
function fill(text, values) {
  if (text == null) return text;
  let i = 0;
  return text
    .replace(/\\\([^)]*\)/g, () => String(values[i++] ?? '…'))
    .replace(/%(\d\$)?(@|lld|ld|d|lf|f)/g, (m, pos) => {
      const idx = pos ? Number(pos[0]) - 1 : i++;
      return String(values[idx] ?? values[values.length - 1] ?? '…');
    });
}

/** Czech plural form for n (one: 1, few: 2-4, other: else). */
function czPlural(forms, n) {
  if (n === 1 && forms.one) return forms.one;
  if (n >= 2 && n <= 4 && forms.few) return forms.few;
  return forms.other ?? forms.many ?? forms.one;
}

/**
 * Resolves a Swift string expression to {en, cs}. `tables` = the Maps its
 * bundle can see (Gamification or FoodLogCore); `values` fill interpolation.
 */
function text(expr, tables, where, values = []) {
  expr = expr.trim();
  let m;
  if ((m = /^CatalogL10n\.(title|subtitle)\(\s*"([^"]+)"\s*,/.exec(expr))) {
    const a = args(expr.slice(expr.indexOf('(') + 1, matchBracket(expr, expr.indexOf('(')) - 1));
    const en = englishOf(a[1].value, values);
    const key = `${m[2]}.${m[1]}`;
    const cs = T.catalogCs.get(key);
    if (cs == null) gaps.push({ key, table: 'Gamification cs.lproj/Catalog.strings', where });
    return { en, cs: cs ?? null };
  }
  if ((m = /^CatalogL10n\.text\(\s*"([^"]+)"\s*,\s*english:/.exec(expr))) {
    const a = args(expr.slice(expr.indexOf('(') + 1, matchBracket(expr, expr.indexOf('(')) - 1));
    const en = englishOf(a[1].value, values);
    const cs = T.catalogCs.get(m[1]);
    if (cs == null) gaps.push({ key: m[1], table: 'Gamification cs.lproj/Catalog.strings', where });
    return { en, cs: cs ?? null };
  }
  expr = expr.replace(/^String\(\s*format:/, 'String(format:');
  if (expr.startsWith('String(format:')) {
    const inner = expr.slice(expr.indexOf('(') + 1, matchBracket(expr, expr.indexOf('(')) - 1);
    const a = args(inner);
    const fmt = text(a[0].value, tables, where, []);
    const vals = values.length ? values : a.slice(1).map((x) => x.value);
    return { en: fill(fmt.en, vals), cs: fmt.cs == null ? null : fill(fmt.cs, vals), template: fmt.en };
  }
  if (expr.startsWith('String(localized:')) {
    const inner = expr.slice(expr.indexOf('(') + 1, matchBracket(expr, expr.indexOf('(')) - 1);
    const lit = stringLiteral(args(inner)[0].value);
    const found = lookup(lit, tables);
    let cs = found.cs;
    if (cs == null) gaps.push({ key: found.key, table: tables.label ?? 'package Localizable.strings', where });
    if (cs && typeof cs === 'object') cs = czPlural(cs, Number(values[0]));
    const en = values.length ? fill(lit, values) : lit.replace(/\\\(([^)]*)\)/g, '{$1}');
    return { en, cs: cs == null ? null : (values.length ? fill(cs, values) : cs) };
  }
  if (expr.startsWith('"')) return { en: englishOf(expr, values), cs: null };
  return { en: expr, cs: null };
}

function englishOf(literalExpr, values) {
  const s = literalExpr.trim();
  if (s.startsWith('"')) {
    const lit = stringLiteral(s);
    return values.length ? fill(lit, values) : lit;
  }
  return s;
}

const GAM_TABLES = Object.assign([T.gamCs], { label: 'Gamification cs.lproj/Localizable.strings' });
const FLC_TABLES = Object.assign([T.flcCs, T.flcDictCs], { label: 'FoodLogCore cs.lproj/Localizable.strings(dict)' });

// ------------------------------------------------------------- utilities

function localArray(block, name) {
  const m = new RegExp(`let\\s+${name}\\s*(?::[^=]+)?=\\s*\\[`).exec(block);
  if (!m) throw new Error('array not found: ' + name);
  return arrayLiteral(block.slice(m.index + m[0].length - 1));
}

/** `case .a, .b: return X` switch → { a: X, b: X } (X raw text up to newline). */
function switchReturns(block) {
  const out = {};
  for (const m of block.matchAll(/case\s+((?:\.\w+\s*,?\s*)+):\s*return\s+([^\n]+)/g)) {
    for (const c of m[1].matchAll(/\.(\w+)/g)) out[c[1]] = m[2].trim();
  }
  return out;
}

/** The body text of `func name(` ... `}`. */
function funcBody(text, name) {
  const i = text.search(new RegExp(`func\\s+${name}\\s*\\(`));
  if (i < 0) throw new Error('func not found: ' + name);
  const brace = text.indexOf('{', text.indexOf(')', i));
  return text.slice(brace, matchBracket(text, brace));
}

/** Calls of `name(` excluding its own `func name(` declaration. */
function calls(text, name) {
  return findCalls(text, name).filter((c) => !/func\s+$/.test(text.slice(Math.max(0, c.start - 12), c.start)));
}

const enumCase = (v) => (v ?? '').trim().replace(/^\./, '');

// ---------------------------------------------------------------- rarity

const RARITIES = ['common', 'uncommon', 'rare', 'epic', 'legendary'];

function bucket(v, u, r, e, l) {
  if (v >= l) return 'legendary';
  if (v >= e) return 'epic';
  if (v >= r) return 'rare';
  if (v >= u) return 'uncommon';
  return 'common';
}

const rarityFile = join(GAM, 'AchievementRarity.swift');
const raritySrc = src(rarityFile);
// Mirror of AchievementRarity.derive(from:). The breakpoints are parsed.
const rarityBreaks = {};
for (const m of raritySrc.matchAll(/case \.(\w+)\(let \w+\)(?:,[^:]*)?:\s*\n\s*return bucket\([^,]+, uncommon: ([\d_]+), rare: ([\d_]+), epic: ([\d_]+), legendary: ([\d_]+)\)/g)) {
  rarityBreaks[m[1]] = m.slice(2, 6).map((x) => Number(x.replace(/_/g, '')));
}
{ // goalHitDaysAtLeast has two bindings (`(_, let count)`)
  const m = /case \.goalHitDaysAtLeast\(_, let count\):\s*\n\s*return bucket\([^,]+, uncommon: ([\d_]+), rare: ([\d_]+), epic: ([\d_]+), legendary: ([\d_]+)\)/.exec(raritySrc);
  rarityBreaks.goalHitDaysAtLeast = m.slice(1, 5).map((x) => Number(x.replace(/_/g, '')));
}
function deriveRarity(cond) {
  const b = rarityBreaks[cond.kind];
  switch (cond.kind) {
    case 'allChallengesCompleted': return 'legendary';
    case 'perfectCalendarMonth': case 'loggedOnLeapDay': case 'loggedOnNewYearsDay': case 'loggedAtMidnight': return 'rare';
    case 'unlockedFractionOfOthers': return cond.fraction >= 1 ? 'legendary' : cond.fraction >= 0.5 ? 'epic' : 'rare';
    case 'featureEvaluated': return 'uncommon';
    default: return bucket(cond.value, ...b);
  }
}

const medallionSrc = src(join(IOS, 'GarminFood/DesignSystem/BadgeMedallion.swift'));
const rarityColors = {};
for (const m of medallionSrc.matchAll(/case \.(\w+):\s*\n(?:\s*\/\/[^\n]*\n)*\s*return \(Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\), Color\(red: ([\d.]+), green: ([\d.]+), blue: ([\d.]+)\)\)/g)) {
  const hex = (r, g, b) => '#' + [r, g, b].map((x) => Math.round(Number(x) * 255).toString(16).padStart(2, '0')).join('');
  rarityColors[m[1]] = { top: hex(m[2], m[3], m[4]), bottom: hex(m[5], m[6], m[7]) };
}
const rarityNames = Object.fromEntries(RARITIES.map((r) => {
  const en = r[0].toUpperCase() + r.slice(1);
  return [r, { en, cs: T.gamCs.get(en) ?? null }];
}));

// ------------------------------------------------------ core achievements

const achFile = join(GAM, 'Achievements.swift');
const achSrc = src(achFile);
const macros = ['calories', 'protein', 'carbs', 'fat'];
const macroName = { calories: 'Calorie', protein: 'Protein', carbs: 'Carb', fat: 'Fat' };
const buckets = ['breakfast', 'lunch', 'snack', 'dinner'];
const bucketName = { breakfast: 'Breakfast', lunch: 'Lunch', snack: 'Snack', dinner: 'Dinner' };
expectIn(src(join(GAM, 'GoalStatus.swift')), 'case calories, protein, carbs, fat', 'GoalStatus.swift');
expectIn(src(join(GAM, 'ChallengeTemplates.swift')), 'case breakfast, lunch, snack, dinner', 'ChallengeTemplates.swift');

function cat(id, en) {
  const t = T.catalogCs.get(`${id}.title`);
  return t;
}

function coreBadge(id, titleEn, subEn, category, symbol, cond, extra = {}) {
  const title = { en: titleEn, cs: T.catalogCs.get(`${id}.title`) ?? null };
  const subtitle = { en: subEn, cs: T.catalogCs.get(`${id}.subtitle`) ?? null };
  if (title.cs == null) gaps.push({ key: `${id}.title`, table: 'Gamification cs.lproj/Catalog.strings', where: rel(achFile) });
  if (subtitle.cs == null) gaps.push({ key: `${id}.subtitle`, table: 'Gamification cs.lproj/Catalog.strings', where: rel(achFile) });
  return {
    id, feature: 'core', category, symbol, rarity: deriveRarity(cond), title, subtitle,
    condition: cond, rule: ruleText(cond), secret: false, source: 'mirrored', file: rel(achFile), ...extra,
  };
}

function ruleText(c) {
  switch (c.kind) {
    case 'streakAtLeast': return `Longest streak ever ≥ ${c.value} days`;
    case 'levelAtLeast': return `Level ≥ ${c.value}`;
    case 'totalLogsAtLeast': return `Lifetime log entries ≥ ${c.value.toLocaleString('en')}`;
    case 'distinctFoodsAtLeast': return `≥ ${c.value} distinct foods in the retained usage history`;
    case 'challengesCompletedAtLeast': return `≥ ${c.value} long-running challenges completed`;
    case 'allChallengesCompleted': return 'Every challenge in the rotation completed at least once (weight-0 ladder tiers and supplement templates excluded; activity templates excluded in standalone mode)';
    case 'dailyChallengesCompletedAtLeast': return `≥ ${c.value} daily challenges completed`;
    case 'goalHitDaysAtLeast': return `${c.macro} goal met on ≥ ${c.value} days (total, not consecutive)`;
    case 'singleDayCaloriesAtLeast': return `One nutrition day with ≥ ${c.value.toLocaleString('en')} kcal`;
    case 'totalCaloriesAtLeast': return `Lifetime calories ≥ ${c.value.toLocaleString('en')} kcal`;
    case 'perfectCalendarMonth': return 'Every day of one full calendar month logged';
    case 'loggedOnLeapDay': return 'Something logged on 29 February';
    case 'loggedOnNewYearsDay': return 'Something logged on 1 January';
    case 'loggedAtMidnight': return 'Something logged at exactly midnight';
    case 'anniversaryYears': return `${c.value} year(s) since the first log`;
    case 'unlockedFractionOfOthers': return `≥ ${Math.round(c.fraction * 100)}% of all other core (non-meta, non-feature) achievements unlocked`;
    default: return c.kind;
  }
}

const coreAchievements = [];
{
  const fam = (name) => declBlock(achSrc, name);
  const simple = (name, idp, category, symbol, kind, sub) => {
    const b = fam(name);
    const th = localArray(b, 'thresholds');
    const ti = localArray(b, 'titles');
    th.forEach((n, i) => coreAchievements.push(coreBadge(`${idp}${n}`, ti[i], sub(n), category, symbol, { kind, value: n })));
  };
  expectIn(achSrc, 'CatalogL10n.subtitle("achv-streak-\\(n)", "Reach a \\(n)-day streak.")', rel(achFile));
  simple('streakFamily', 'achv-streak-', 'streak', 'flame.fill', 'streakAtLeast', (n) => `Reach a ${n}-day streak.`);
  expectIn(achSrc, '"Reach level \\(n)."', rel(achFile));
  simple('levelFamily', 'achv-level-', 'level', 'star.fill', 'levelAtLeast', (n) => `Reach level ${n}.`);
  expectIn(achSrc, '"Log \\(n) entries in total."', rel(achFile));
  simple('lifetimeLogsFamily', 'achv-logs-', 'volume', 'fork.knife', 'totalLogsAtLeast', (n) => `Log ${n} entries in total.`);
  expectIn(achSrc, '"Log \\(n) different foods."', rel(achFile));
  simple('distinctFoodsFamily', 'achv-foods-', 'variety', 'leaf.fill', 'distinctFoodsAtLeast', (n) => `Log ${n} different foods.`);
  expectIn(achSrc, '"Complete \\(n) challenges."', rel(achFile));
  simple('challengesFamily', 'achv-challenges-', 'challenges', 'target', 'challengesCompletedAtLeast', (n) => `Complete ${n} challenges.`);
  {
    const c = calls(fam('challengesFamily'), 'AchievementDefinition').find((x) => x.inner.includes('"achv-challenges-all"'));
    const a = argMap(c.inner);
    coreAchievements.push(coreBadge('achv-challenges-all', text(a.title, [], '').en, text(a.subtitle, [], '').en, 'challenges', stringLiteral(a.badgeSymbol), { kind: 'allChallengesCompleted' }));
  }
  expectIn(achSrc, '"Complete \\(n) daily challenges in total."', rel(achFile));
  simple('dailyChallengesFamily', 'achv-daily-', 'dailyChallenges', 'checkmark.circle.fill', 'dailyChallengesCompletedAtLeast', (n) => `Complete ${n} daily challenges in total.`);
  {
    const b = fam('goalHitDaysFamily');
    const th = localArray(b, 'thresholds');
    const sf = localArray(b, 'suffixes');
    expectIn(b, '"Hit your \\(macro.rawValue) goal on \\(n) days, total."', rel(achFile));
    for (const macro of macros) th.forEach((n, i) => coreAchievements.push(coreBadge(`achv-goal-${macro}-${n}`, `${macroName[macro]} ${sf[i]}`, `Hit your ${macro} goal on ${n} days, total.`, 'goalHitting', 'checkmark.seal.fill', { kind: 'goalHitDaysAtLeast', macro, value: n })));
  }
  expectIn(achSrc, '"Log \\(n)+ kcal in a single day. Every feast deserves a badge."', rel(achFile));
  simple('extremeFamily', 'achv-extreme-', 'extreme', 'bolt.fill', 'singleDayCaloriesAtLeast', (n) => `Log ${n}+ kcal in a single day. Every feast deserves a badge.`);
  {
    const b = fam('funnyComparisonFamily');
    expectIn(b, '"You\'ve logged about \\(anchor.describe(multiple)) in total calories."', rel(achFile));
    for (const c of calls(b, 'Anchor').filter((x) => x.inner.includes('idSlug:'))) {
      const a = argMap(c.inner);
      const slug = stringLiteral(a.idSlug);
      const kcal = literalValue(a.kcalPerUnit);
      const multiples = arrayLiteral(a.multiples);
      const titles = arrayLiteral(a.titles);
      const describe = (n) => {
        const d = a.describe;
        const ec = /englishCount\(\$0, one: ("(?:[^"\\]|\\.)*"), other: ("(?:[^"\\]|\\.)*")\)/.exec(d);
        if (ec) return n === 1 ? stringLiteral(ec[1]) : fill(stringLiteral(ec[2]), [n]);
        const lit = /("(?:[^"\\]|\\.)*")/.exec(d);
        return fill(stringLiteral(lit[1]), [n]);
      };
      multiples.forEach((mult, i) => coreAchievements.push(coreBadge(`achv-funny-${slug}-${mult}`, titles[i], `You've logged about ${describe(mult)} in total calories.`, 'funnyFacts', 'party.popper.fill', { kind: 'totalCaloriesAtLeast', value: kcal * mult }, { note: `${mult} × ${kcal.toLocaleString('en')} kcal` })));
    }
  }
  for (const famName of ['calendarFamily', 'metaFamily']) {
    for (const c of calls(fam(famName), 'AchievementDefinition')) {
      const a = argMap(c.inner);
      const id = stringLiteral(a.id);
      const condRaw = a.condition;
      let cond;
      let m;
      if ((m = /^\.anniversaryYears\(years: (\d+)\)/.exec(condRaw))) cond = { kind: 'anniversaryYears', value: Number(m[1]) };
      else if ((m = /^\.unlockedFractionOfOthers\(fraction: ([\d.]+)\)/.exec(condRaw))) cond = { kind: 'unlockedFractionOfOthers', fraction: Number(m[1]) };
      else cond = { kind: condRaw.replace(/^\./, '') };
      coreAchievements.push(coreBadge(id, text(a.title, [], '').en, text(a.subtitle, [], '').en, enumCase(a.category), stringLiteral(a.badgeSymbol), cond, a.isMeta ? { meta: true } : {}));
    }
  }
  // Verify the family order of `AchievementCatalog.all`.
  expectIn(achSrc, 'streakFamily\n        + levelFamily\n        + lifetimeLogsFamily\n        + distinctFoodsFamily\n        + challengesFamily\n        + dailyChallengesFamily\n        + goalHitDaysFamily\n        + extremeFamily\n        + funnyComparisonFamily\n        + calendarFamily\n        + metaFamily', rel(achFile));
}

// ------------------------------------------------------------------ levels

const lcFile = join(GAM, 'LevelCurve.swift');
const lcSrc = src(lcFile);
const lc = staticLets(lcSrc);
const xpStoreSrc = src(join(GAM, 'XPStore.swift'));
const xpFeatSrc = src(join(FEAT, 'XPAward+Features.swift'));
const XP = {};
for (const s of [xpStoreSrc.slice(xpStoreSrc.indexOf('public enum XPAward'), xpStoreSrc.indexOf('public struct XPAwardResult')), xpFeatSrc]) {
  for (const m of s.matchAll(/public static let (\w+)(?::[^=]+)? = ([\d_]+)\s*$/gm)) XP[m[1]] = Number(m[2].replace(/_/g, ''));
}
{
  const m = /creativeChallengeRange: ClosedRange<Int> = (\d+)\.\.\.(\d+)/.exec(xpFeatSrc);
  XP.creativeChallengeRange = [Number(m[1]), Number(m[2])];
}
const base = lc.baseXPForFirstLevelUp;
const growth = lc.growthFactor;
const maxLevel = lc.maxLevel;
expectIn(lcSrc, 'let raw = baseXPForFirstLevelUp * pow(factor, Double(level - 1))', rel(lcFile));
const xpRequired = (level, f = growth) => Math.max(1, Math.round(base * Math.pow(f, level - 1)));
const threshold = (level) => { let t = 0; for (let l = 1; l < Math.min(level, maxLevel); l++) t += xpRequired(l); return t; };

const tierFile = join(GAM, 'LevelTier.swift');
const tierSrc = src(tierFile);
const tierSymbols = {};
for (const [r, v] of Object.entries(switchReturns(funcBodyVar(tierSrc, 'badgeSymbol')))) tierSymbols[r] = stringLiteral(v);
function funcBodyVar(text, name) {
  const i = text.search(new RegExp(`var\\s+${name}\\s*:`));
  const brace = text.indexOf('{', i);
  return text.slice(brace, matchBracket(text, brace));
}
const levelTiers = calls(declBlock(tierSrc, 'all'), 'localized').map((c) => {
  const a = args(c.inner);
  const [lo, hi] = a[2].value.split('...').map(Number);
  const rarity = bucket(lo, ...rarityBreaks.levelAtLeast);
  const tcs = T.catalogCs.get(`tier.${lo}.title`);
  const fcs = T.catalogCs.get(`tier.${lo}.flavor`);
  if (tcs == null) gaps.push({ key: `tier.${lo}.title`, table: 'Catalog.strings', where: rel(tierFile) });
  return {
    from: lo, to: hi, rarity, symbol: tierSymbols[rarity],
    title: { en: stringLiteral(a[0].value), cs: tcs ?? null },
    flavor: { en: stringLiteral(a[1].value), cs: fcs ?? null },
    xpAtStart: threshold(lo),
  };
});

// XP budget (mirror of XPBudget.lines)
const budgetFile = join(GAM, 'XPBudget.swift');
const budgetSrc = src(budgetFile);
const bLets = staticLets(budgetSrc);
const seasonalCatSrc = src(join(FEAT, 'Seasonal/SeasonalEventCatalog.swift'));
const bonusQuestXP = staticLets(seasonalCatSrc).bonusQuestXP;
const threeYears = 1095, year = 365, week = 7, month = 365 / 12;
const badgeXP = (n) => XP.achievementBonus * n / threeYears;
const defeatXP = (target) => XP.bossDefeatedBase + XP.bossDefeatedPerTargetDay * Math.max(0, target - 3);
for (const needle of ['Double(XPAward.flatPerLog) * 3.5', 'Double(XPAward.streakExtensionBonus) * 1.0', 'Double(XPAward.goalHitBonus) * 0.6',
  'Double(XPAward.dailyChallengeBonus) * 2 * 0.6', 'assumedMeanChallengeReward / 9', 'Double(XPAward.achievementBonus) * 15 / year',
  'Double(XPAward.bingoLine) * 1.5 / week', 'Double(XPAward.bingoFullCard) / (8 * week)', 'badgeXP(6)', 'Double(XPAward.seasonalEventCompleted) * 6',
  'Double(SeasonalEventCatalog.bonusQuestXP) * 3) / year', 'badgeXP(10)', 'Double(XPAward.collectionDiscovery) * 0.5 / week',
  'Double(XPAward.journeyMilestone) * 40 / threeYears + badgeXP(8)', 'Double(XPAward.personalRecord) * 3 / month + badgeXP(3)',
  'Double(XPAward.secretUnlocked + XPAward.achievementBonus) * 12 / threeYears', 'Double(XPAward.sportBadge + XPAward.achievementBonus) * 10 / threeYears',
  'Double(BossFight.defeatXP(target: 5)) * 0.5 / week + badgeXP(6)', 'Double(XPAward.supplementStackComplete) * 0.85',
  'Double(XPAward.journeyMilestone) * 5 / threeYears']) expectIn(budgetSrc, needle, rel(budgetFile));
const budgetLines = [
  { source: 'log', what: `flatPerLog (${XP.flatPerLog}) × 3.5 entries a day`, xp: XP.flatPerLog * 3.5 },
  { source: 'streak', what: `streakExtensionBonus (${XP.streakExtensionBonus}) every active day`, xp: XP.streakExtensionBonus * 1 },
  { source: 'goal', what: `goalHitBonus (${XP.goalHitBonus}) on 60% of days`, xp: XP.goalHitBonus * 0.6 },
  { source: 'dailyChallenge', what: `dailyChallengeBonus (${XP.dailyChallengeBonus}) × 2 a day × 60% completed`, xp: XP.dailyChallengeBonus * 2 * 0.6 },
  { source: 'challenge', what: `one completion every 9 days at the assumed mean reward (${bLets.assumedMeanChallengeReward})`, xp: bLets.assumedMeanChallengeReward / 9 },
  { source: 'achievement', what: `achievementBonus (${XP.achievementBonus}) × 15 core badges a year`, xp: XP.achievementBonus * 15 / year },
  { source: 'bingo', what: `line (${XP.bingoLine}) × 1.5/week + full card (${XP.bingoFullCard}) every 8 weeks + 6 badges over 3 years`, xp: XP.bingoLine * 1.5 / week + XP.bingoFullCard / (8 * week) + badgeXP(6) },
  { source: 'seasonal', what: `event (${XP.seasonalEventCompleted}) × 6/year + bonus quest (${bonusQuestXP}) × 3/year + 10 badges`, xp: (XP.seasonalEventCompleted * 6 + bonusQuestXP * 3) / year + badgeXP(10) },
  { source: 'collections', what: `discovery (${XP.collectionDiscovery}) every two weeks + 6 badges`, xp: XP.collectionDiscovery * 0.5 / week + badgeXP(6) },
  { source: 'journeys', what: `milestone (${XP.journeyMilestone}) × 40 in 3 years + 8 badges`, xp: XP.journeyMilestone * 40 / threeYears + badgeXP(8) },
  { source: 'records', what: `PR (${XP.personalRecord}) × 3 a month + 3 badges`, xp: XP.personalRecord * 3 / month + badgeXP(3) },
  { source: 'secrets', what: `(secretUnlocked ${XP.secretUnlocked} + badge ${XP.achievementBonus}) × 12 in 3 years`, xp: (XP.secretUnlocked + XP.achievementBonus) * 12 / threeYears },
  { source: 'sportBody', what: `(sportBadge ${XP.sportBadge} + badge ${XP.achievementBonus}) × 10 in 3 years`, xp: (XP.sportBadge + XP.achievementBonus) * 10 / threeYears },
  { source: 'boss', what: `defeat XP at target 5 (${defeatXP(5)}) every other week + 6 badges`, xp: defeatXP(5) * 0.5 / week + badgeXP(6) },
  { source: 'supplements', optional: true, what: `stack complete (${XP.supplementStackComplete}) on 85% of days + 5 creatine milestones (${XP.journeyMilestone}) + 10 badges — before the optional multiplier`, xp: XP.supplementStackComplete * 0.85 + XP.journeyMilestone * 5 / threeYears + badgeXP(10) },
];
const coreDaily = budgetLines.filter((l) => !l.optional).reduce((s, l) => s + l.xp, 0);

// Training lines (parsed from TrainingXPBudget.lines; add-training-gamification-and-150-levels D2):
// the curve is solved against the food core PLUS these.
const trainBudgetFile = join(FEAT, 'Training/TrainingXPBudget.swift');
const trainBudgetSrc = src(trainBudgetFile);
const xpTrainFile = join(FEAT, 'Training/XPAward+Training.swift');
const xpTrainSrc = src(xpTrainFile);
for (const m of xpTrainSrc.matchAll(/public static let (\w+)(?::[^=]+)? = ([\d_]+)\s*$/gm)) XP[m[1]] = Number(m[2].replace(/_/g, ''));
const streakDecl = xpTrainSrc.slice(xpTrainSrc.indexOf('static let trainingHabitStreakMilestones'));
const streakBlock = streakDecl.slice(streakDecl.indexOf('= [') + 3);
XP.trainingHabitStreakMilestones = [...streakBlock.slice(0, streakBlock.indexOf(']')).matchAll(/\((\d+), (\d+)\)/g)].map((m) => ({ days: Number(m[1]), xp: Number(m[2]) }));
if (XP.trainingHabitStreakMilestones.length === 0) throw new Error('mirror out of date: trainingHabitStreakMilestones');
const trainingBadgeCount = staticLets(trainBudgetSrc).badgeCount;
expectIn(trainBudgetSrc, 'case .span: return Double(XPBudget.targetDays)', rel(trainBudgetFile));
const trainingPeriodDays = { week, year, span: bLets.targetDays };
const trainingNumber = (expr) => {
  const e = expr.replace(/Double\(badgeCount\)/g, String(trainingBadgeCount)).trim();
  if (!/^[\d.\s*]+$/.test(e)) throw new Error(`mirror out of date: training frequency "${expr}"`);
  return e.split('*').reduce((p, f) => p * Number(f), 1);
};
const trainingLines = [...trainBudgetSrc.matchAll(/TrainingXPBudgetLine\("(\w+)", reward: (.+?), per: \.(\w+), typical: (.+?), poor: (.+?), perfect: (.+)\),\s*$/gm)].map((m) => {
  const reward = m[2] === 'habitStreakTotalXP'
    ? XP.trainingHabitStreakMilestones.reduce((s, x) => s + x.xp, 0)
    : XP[m[2].replace('XPAward.', '')];
  if (!Number.isFinite(reward) || !trainingPeriodDays[m[3]]) throw new Error(`mirror out of date: training line ${m[1]}`);
  const perDay = (count) => reward * count / trainingPeriodDays[m[3]];
  const [typical, poor, perfect] = [m[4], m[5], m[6]].map(trainingNumber);
  return { source: m[1], reward, per: m[3], typical, poor, perfect, xp: perDay(typical), poorXp: perDay(poor), perfectXp: perDay(perfect) };
});
if (trainingLines.length < 20) throw new Error('mirror out of date: TrainingXPBudget.lines');
const trainingDaily = trainingLines.reduce((s, l) => s + l.xp, 0);
const typicalDaily = coreDaily + trainingDaily;
expectIn(budgetSrc, 'solveGrowthFactor(targetLevel: targetLevel, days: targetDays, dailyXP: typicalDailyXP)', rel(budgetFile));
budgetLines.push({ source: 'training', trainingOnly: true, what: `training experience only: ${trainingLines.length} sources (check-ins, habits, sessions within the light, kept days and weeks, phases, races, badges)`, xp: trainingDaily });
function cumulative(target, f) { let t = 0, b = base; for (let i = 1; i < target; i++) { t += b; b *= f; } return t; }
function solve(target, days, daily) {
  const wanted = days * daily; let lo = 1, hi = 1.2;
  for (let i = 0; i < 200; i++) { const mid = (lo + hi) / 2; const r = cumulative(target, mid); if (Math.abs(r - wanted) <= wanted * 1e-9) return mid; if (r < wanted) lo = mid; else hi = mid; if (hi - lo < 1e-12) break; }
  return (lo + hi) / 2;
}
const optionalLine = budgetLines.find((l) => l.optional).xp;
const optionalMultiplier = Math.min(1, bLets.optionalPaceAllowance * coreDaily / optionalLine);
const scaledGrant = (xp, m) => (xp > 0 ? Math.max(1, Math.round(xp * Math.max(0, Math.min(1, m)))) : 0);

const levels = {
  source: 'mirrored', files: [rel(lcFile), rel(tierFile), rel(budgetFile), 'ios/Gamification/Sources/Gamification/XPStore.swift', rel(join(FEAT, 'XPAward+Features.swift')), rel(trainBudgetFile), rel(xpTrainFile)],
  curve: {
    baseXPForFirstLevelUp: base, growthFactor: growth, pastGrowthFactors: lc.pastGrowthFactors, curveVersion: lc.pastGrowthFactors.length + 1, maxLevel,
    formula: 'xpRequired(afterLevel L) = max(1, round(100 × growthFactor^(L−1))); level = the highest L whose cumulative threshold ≤ total XP; the displayed level is never below the highest level ever reached (peakLevel).',
    table: Array.from({ length: maxLevel }, (_, i) => { const L = i + 1; return { level: L, threshold: threshold(L), band: L < maxLevel ? xpRequired(L) : 0 }; }),
  },
  tiers: levelTiers,
  xpAwards: XP,
  budget: {
    targetLevel: bLets.targetLevel, targetDays: bLets.targetDays, assumedMeanChallengeReward: bLets.assumedMeanChallengeReward,
    lines: budgetLines.map((l) => ({ ...l, xp: Math.round(l.xp * 1000) / 1000 })),
    coreDailyXP: Math.round(coreDaily * 1000) / 1000,
    trainingDailyXP: Math.round(trainingDaily * 1000) / 1000,
    typicalDailyXP: Math.round(typicalDaily * 1000) / 1000,
    trainingLines: trainingLines.map((l) => ({ ...l, xp: Math.round(l.xp * 1000) / 1000, poorXp: Math.round(l.poorXp * 1000) / 1000, perfectXp: Math.round(l.perfectXp * 1000) / 1000 })),
    solvedGrowthFactor: Math.round(solve(bLets.targetLevel, bLets.targetDays, typicalDaily) * 1e6) / 1e6,
    optionalPaceAllowance: bLets.optionalPaceAllowance,
    optionalMultiplierWithSupplements: Math.round(optionalMultiplier * 10000) / 10000,
    supplementStackGrantAfterMultiplier: scaledGrant(XP.supplementStackComplete, optionalMultiplier),
    supplementBadgeBonusAfterMultiplier: scaledGrant(XP.achievementBonus, optionalMultiplier),
    supplementMilestoneAfterMultiplier: scaledGrant(XP.journeyMilestone, optionalMultiplier),
    // `days` = the training experience's typical day; `daysFoodFirst` = the food core alone.
    daysToReach: [5, 10, 20, 30, 50, 75, 100, 125, 150].filter((L) => L <= maxLevel).map((L) => ({ level: L, days: Math.round(threshold(L) / typicalDaily), daysFoodFirst: Math.round(threshold(L) / coreDaily) })),
  },
  bossDefeatXP: [3, 4, 5, 6, 7].map((t) => ({ target: t, xp: defeatXP(t) })),
};

// ----------------------------------------------------------------- streak

const streakSrc = src(join(GAM, 'StreakEngine.swift'));
const freezeBal = staticLets(src(join(GAM, 'StreakFreeze/FreezeBalance.swift')));
const freezePlan = staticLets(src(join(GAM, 'StreakFreeze/StreakFreezePlanner.swift')));
const boundary = staticLets(src(join(GAM, 'NutritionDayBoundary.swift')));
const streaks = {
  source: 'hand-read (constants parsed)',
  files: ['ios/Gamification/Sources/Gamification/StreakEngine.swift', 'ios/Gamification/Sources/Gamification/StreakFreeze/StreakFreezePlanner.swift', 'ios/Gamification/Sources/Gamification/StreakFreeze/FreezeBalance.swift', 'ios/Gamification/Sources/Gamification/Features/Supplements/SupplementStreak.swift', 'ios/Gamification/Sources/Gamification/NutritionDayBoundary.swift'],
  constants: {
    graceWindowDays: staticLets(streakSrc).graceWindowDays,
    freezeCap: freezeBal.cap,
    freezeMinimumProtectedLength: freezePlan.minimumProtectedLength,
    freezeLookbackDays: freezePlan.lookbackDays,
    loggedDateBoundaryHour: boundary.loggedDateBoundaryHour,
    legacyDefaultBoundaryHour: boundary.defaultBoundaryHour,
  },
};

// -------------------------------------------------------------- challenges

const ctFile = join(GAM, 'ChallengeTemplates.swift');
const ctSrc = src(ctFile);
const polFile = join(FEAT, 'ChallengeRotationPolicy.swift');
const polSrc = src(polFile);
const pol = staticLets(polSrc);
const allowlist = new Set(arrayLiteral(declBlock(polSrc, 'ladderAllowlist')));
const handIds = new Set();

function reqOfPredicate(t) {
  const r = new Set();
  if (/\.(goalMet|macroAtLeast|macroAtMost|mealMacroAtLeast)\b/.test(t)) r.add('macros');
  if (/\.waterGoalMet\b/.test(t)) r.add('water');
  if (/\.hasActivity\b/.test(t)) r.add('activities');
  if (/\.proteinAfterActivity\b/.test(t)) { r.add('activities'); r.add('macros'); }
  return [...r].sort();
}

const challenges = [];
function pushChallenge(t) {
  const signal = /^\.signal(Days|Week)\(/.test(t.kind);
  const supp = /^\.supplementDays\(/.test(t.kind);
  const requirement = signal ? reqOfPredicate(t.kind) : [];
  let weight;
  if (supp) weight = 0;
  else if (signal) weight = pol.signalWeight;
  else if (handIds.has(t.id)) weight = pol.handAuthoredWeight;
  else if (allowlist.has(t.id)) weight = pol.ladderWeight;
  else if (t.family) weight = 0;
  else weight = pol.handAuthoredWeight;
  challenges.push({
    ...t, requirement, staticWeight: weight, group: supp ? 'supplement' : signal ? 'signal' : t.family ? 'ladder' : 'hand-authored',
    offeredWhen: supp ? `supplements active${/slotBefore/.test(t.kind) ? ' and that slot completed on one of the last ' + pol.requirementLookbackDays + ' days' : ''} (weight ${pol.supplementWeight})` : null,
    standalone: !requirement.includes('activities'),
    inAllChallengesDenominator: weight > 0,
  });
}

function literalTemplates(block, file, family, tables = null) {
  for (const c of calls(block, 'ChallengeTemplate')) {
    const a = argMap(c.inner);
    if (!a.id || a.id.includes('\\(')) continue;
    const id = stringLiteral(a.id);
    const xp = /^\d+$/.test(a.xpReward) ? Number(a.xpReward) : XP[a.xpReward.replace('XPAward.', '')];
    pushChallenge({
      id, family, category: enumCase(a.category), windowDays: Number(a.windowDays), xp,
      title: text(a.title, tables ?? GAM_TABLES, rel(file)), subtitle: text(a.subtitle, tables ?? GAM_TABLES, rel(file)),
      kind: a.kind, source: 'parsed', file: rel(file), line: lineOf(src(file), src(file).indexOf(`"${id}"`)),
    });
  }
}

{
  const hand = declBlock(ctSrc, 'handAuthored');
  for (const c of calls(hand, 'ChallengeTemplate')) handIds.add(stringLiteral(argMap(c.inner).id));
  literalTemplates(hand, ctFile, null);
  const fam = (n) => declBlock(ctSrc, n);
  const cs = (id, part) => {
    const v = T.catalogCs.get(`${id}.${part}`);
    if (v == null) gaps.push({ key: `${id}.${part}`, table: 'Catalog.strings', where: rel(ctFile) });
    return v ?? null;
  };
  const mirror = (family, id, titleEn, subEn, category, windowDays, xp, kind) => pushChallenge({
    id, family, category, windowDays, xp, title: { en: titleEn, cs: cs(id, 'title') }, subtitle: { en: subEn, cs: cs(id, 'subtitle') },
    kind, source: 'mirrored', file: rel(ctFile),
  });
  const plural = (n, one, other) => (n === 1 ? one : other);
  // Each family: expected formula snippets, then the loop mirrored.
  let b = fam('logStreakFamily');
  ['windowDays: count + 2', 'xpReward: 20 + count * 6', '"Log something on \\(count) different days."'].forEach((s) => expectIn(b, s, 'logStreakFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('log-streak', `log-streak-${c}`, localArray(b, 'titles')[i], `Log something on ${c} different days.`, 'streakExtension', c + 2, 20 + c * 6, `.logOnDistinctDays(minCount: ${c})`));
  b = fam('extendStreakFamily');
  ['windowDays: day * 2 + 2', 'xpReward: 25 + day * 7'].forEach((s) => expectIn(b, s, 'extendStreakFamily'));
  localArray(b, 'days').forEach((d, i) => mirror('extend-streak', `extend-streak-${d}`, localArray(b, 'titles')[i], plural(d, 'Extend your streak by 1 more day.', `Extend your streak by ${d} more days.`), 'streakExtension', d * 2 + 2, 25 + d * 7, `.extendStreakBy(days: ${d})`));
  b = fam('goalHitDaysFamily');
  ['windowDays: count + 3', 'xpReward: 25 + count * 7'].forEach((s) => expectIn(b, s, 'goalHitDaysFamily'));
  for (const m of macros) localArray(b, 'counts').forEach((c, i) => mirror('goal-days', `goal-days-${m}-${c}`, `${macroName[m]} ${localArray(b, 'titles')[i]}`, `Hit your ${m} goal on ${c} days.`, 'goalHitting', c + 3, 25 + c * 7, `.goalHitDays(macro: .${m}, minCount: ${c})`));
  b = fam('anyGoalStreakFamily');
  ['windowDays: count + 3', 'xpReward: 25 + count * 8'].forEach((s) => expectIn(b, s, 'anyGoalStreakFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('goal-any-streak', `goal-any-streak-${c}`, localArray(b, 'titles')[i], `Hit any nutrition goal ${c} days running.`, 'goalHitting', c + 3, 25 + c * 8, `.goalHitStreak(macro: nil, minCount: ${c})`));
  b = fam('macroGoalStreakFamily');
  ['windowDays: count + 3', 'xpReward: 25 + count * 8'].forEach((s) => expectIn(b, s, 'macroGoalStreakFamily'));
  for (const m of macros) localArray(b, 'counts').forEach((c, i) => mirror('goal-macro-streak', `goal-${m}-streak-${c}`, `${macroName[m]} ${localArray(b, 'titles')[i]}`, `Hit your ${m} goal ${c} days running.`, 'goalHitting', c + 3, 25 + c * 8, `.goalHitStreak(macro: .${m}, minCount: ${c})`));
  b = fam('newFoodsFamily');
  ['windowDays: count * 2 + 3', 'xpReward: 20 + count * 8'].forEach((s) => expectIn(b, s, 'newFoodsFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('new-foods', `new-foods-${c}`, localArray(b, 'titles')[i], plural(c, "Log 1 food you haven't logged before.", `Log ${c} foods you haven't logged before.`), 'varietySeeking', c * 2 + 3, 20 + c * 8, `.newFoodsTried(minCount: ${c})`));
  b = fam('mealTimeFamily');
  ['windowDays: count + 2', 'xpReward: 20 + count * 6'].forEach((s) => expectIn(b, s, 'mealTimeFamily'));
  for (const k of buckets) localArray(b, 'counts').forEach((c, i) => mirror('meal-time', `meal-${k}-${c}`, `${bucketName[k]} Ritual: ${localArray(b, 'titles')[i]}`, `Log a ${k}-time entry on ${c} days.`, 'varietySeeking', c + 2, 20 + c * 6, `.mealTimeOnDistinctDays(bucket: .${k}, minCount: ${c})`));
  literalTemplates(fam('multiMealFamily'), ctFile, 'multi-meal');
  literalTemplates(fam('busyDaysFamily'), ctFile, 'busy-days');
  b = fam('mealSlotAbsentFamily');
  ['windowDays: count + 3', 'xpReward: 25 + count * 7'].forEach((s) => expectIn(b, s, 'mealSlotAbsentFamily'));
  for (const k of buckets) localArray(b, 'counts').forEach((c, i) => mirror('meal-absent', `absent-${k}-${c}`, `${bucketName[k]}-Free: ${localArray(b, 'titles')[i]}`, `Log something, but nothing in the ${k} window, on ${c} days.`, 'varietySeeking', c + 3, 25 + c * 7, `.mealSlotAbsent(bucket: .${k}, minDays: ${c})`));
  b = fam('allGoalsFamily');
  ['windowDays: count + 3', 'xpReward: 30 + count * 9'].forEach((s) => expectIn(b, s, 'allGoalsFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('all-goals', `all-goals-${c}`, localArray(b, 'titles')[i], plural(c, 'Hit calories, protein, carbs AND fat the same day, 1 time.', `Hit calories, protein, carbs AND fat the same day, ${c} times.`), 'goalHitting', c + 3, 30 + c * 9, `.allGoalsHitDays(minCount: ${c})`));
  b = fam('fullCourseFamily');
  ['windowDays: count + 3', 'xpReward: 30 + count * 10'].forEach((s) => expectIn(b, s, 'fullCourseFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('full-course', `full-course-${c}`, localArray(b, 'titles')[i], plural(c, 'Log breakfast, lunch, snack AND dinner in one day, 1 time.', `Log breakfast, lunch, snack AND dinner in one day, ${c} times.`), 'varietySeeking', c + 3, 30 + c * 10, `.allFourMealSlotsDays(minDays: ${c})`));
  b = fam('sameFoodFamily');
  ['windowDays: count + 3', 'xpReward: 25 + count * 8'].forEach((s) => expectIn(b, s, 'sameFoodFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('same-food', `same-food-${c}`, localArray(b, 'titles')[i], `Log the identical food ${c} days running.`, 'varietySeeking', c + 3, 25 + c * 8, `.sameFoodConsecutiveDays(minDays: ${c})`));
  b = fam('weekendStreakFamily');
  ['windowDays: count * 7 + 2', 'xpReward: 40 + count * 15'].forEach((s) => expectIn(b, s, 'weekendStreakFamily'));
  localArray(b, 'counts').forEach((c, i) => mirror('weekend-streak', `weekend-streak-${c}`, localArray(b, 'titles')[i], `Log both Saturday and Sunday, ${c} weekends in a row.`, 'varietySeeking', c * 7 + 2, 40 + c * 15, `.consecutiveWeekendsBothDays(weekends: ${c})`));
  const sigFile = join(FEAT, 'ChallengeTemplates+Signals.swift');
  literalTemplates(src(sigFile), sigFile, null);
  const supFile = join(FEAT, 'Supplements/ChallengeTemplates+Supplements.swift');
  literalTemplates(src(supFile), supFile, null);
  expectIn(ctSrc, '+ signalTemplates', rel(ctFile));
  expectIn(ctSrc, '+ supplementTemplates', rel(ctFile));
}

const dcFile = join(GAM, 'DailyChallenges.swift');
const dcSrc = src(dcFile);
const daily = [];
{
  const push = (id, titleEn, subEn, kind, family) => {
    const tcs = T.catalogCs.get(`${id}.title`), scs = T.catalogCs.get(`${id}.subtitle`);
    if (tcs == null) gaps.push({ key: `${id}.title`, table: 'Catalog.strings', where: rel(dcFile) });
    if (scs == null) gaps.push({ key: `${id}.subtitle`, table: 'Catalog.strings', where: rel(dcFile) });
    daily.push({ id, family, title: { en: titleEn, cs: tcs ?? null }, subtitle: { en: subEn, cs: scs ?? null }, kind, needsGoals: /Goal/.test(kind), xp: XP.dailyChallengeBonus, source: 'mirrored', file: rel(dcFile) });
  };
  const tiers = (block) => [...block.matchAll(/\((\d+), \[([^\]]*)\]\)/g)].map((m) => ({ n: Number(m[1]), variants: arrayLiteral(`[${m[2]}]`) }));
  const byBucket = (block) => Object.fromEntries([...block.matchAll(/\.(\w+): \[([^\]]*)\]/g)].map((m) => [m[1], arrayLiteral(`[${m[2]}]`)]));
  let b = declBlock(dcSrc, 'logAtLeastFamily');
  for (const t of tiers(b)) t.variants.forEach((v, i) => push(`daily-log-${t.n}-${i}`, v, t.n === 1 ? 'Log at least 1 entry today.' : `Log at least ${t.n} entries today.`, `.logAtLeast(count: ${t.n})`, 'log-at-least'));
  b = declBlock(dcSrc, 'logDistinctFoodsFamily');
  for (const t of tiers(b)) t.variants.forEach((v, i) => push(`daily-distinct-${t.n}-${i}`, v, `Log ${t.n} different foods today.`, `.logDistinctFoods(count: ${t.n})`, 'distinct-foods'));
  b = declBlock(dcSrc, 'logInMealSlotFamily');
  { const v = byBucket(b); for (const k of buckets) (v[k] ?? []).forEach((t, i) => push(`daily-meal-${k}-${i}`, t, `Log something during ${k} hours today.`, `.logInMealSlot(bucket: .${k})`, 'meal-slot')); }
  b = declBlock(dcSrc, 'avoidMealSlotFamily');
  { const v = byBucket(b); for (const k of buckets) (v[k] ?? []).forEach((t, i) => push(`daily-avoid-${k}-${i}`, t, `Log at least one thing today, but nothing during ${k} hours.`, `.avoidMealSlot(bucket: .${k})`, 'avoid-slot')); }
  b = declBlock(dcSrc, 'hitCalorieGoalFamily');
  localArray(b, 'titles').forEach((t, i) => push(`daily-calorie-goal-${i}`, t, 'Hit your calorie goal today.', '.hitCalorieGoal', 'calorie-goal'));
  b = declBlock(dcSrc, 'hitMacroGoalFamily');
  { const suf = localArray(b, 'variantSuffixes'); for (const m of ['protein', 'carbs', 'fat']) suf.forEach((s, i) => push(`daily-macro-${m}-${i}`, `${macroName[m]} ${s}`, `Hit your ${m} goal today.`, `.hitMacroGoal(macro: .${m})`, 'macro-goal')); expectIn(b, 'let macros: [GoalMacro] = [.protein, .carbs, .fat]', 'hitMacroGoalFamily'); }
  b = declBlock(dcSrc, 'hitAllGoalsFamily');
  localArray(b, 'titles').forEach((t, i) => push(`daily-all-goals-${i}`, t, 'Hit calories, protein, carbs AND fat today.', '.hitAllGoals', 'all-goals'));
  b = declBlock(dcSrc, 'tryNewFoodFamily');
  localArray(b, 'titles').forEach((t, i) => push(`daily-new-food-${i}`, t, "Log a food you haven't logged before.", '.tryNewFood', 'new-food'));
  b = declBlock(dcSrc, 'logAllFourSlotsFamily');
  localArray(b, 'titles').forEach((t, i) => push(`daily-full-course-${i}`, t, 'Log breakfast, lunch, snack AND dinner today.', '.logAllFourSlots', 'all-four-slots'));
  b = declBlock(dcSrc, 'earlyLogFamily');
  for (const t of tiers(b)) t.variants.forEach((v, i) => push(`daily-early-${t.n}-${i}`, v, `Log something before ${t.n}:00 today.`, `.earlyLog(beforeHour: ${t.n})`, 'early'));
  b = declBlock(dcSrc, 'lateLogFamily');
  for (const t of tiers(b)) t.variants.forEach((v, i) => push(`daily-late-${t.n}-${i}`, v, `Log something at or after ${t.n}:00 today.`, `.lateLog(afterHour: ${t.n})`, 'late'));
}
const dcStore = staticLets(src(join(GAM, 'DailyChallengeStore.swift')));
const chStore = staticLets(src(join(GAM, 'ChallengeStore.swift')));

const challengesOut = {
  source: 'mirrored + parsed',
  files: [rel(ctFile), rel(join(FEAT, 'ChallengeTemplates+Signals.swift')), rel(join(FEAT, 'Supplements/ChallengeTemplates+Supplements.swift')), rel(polFile), rel(dcFile)],
  mealTimeBuckets: [{ bucket: 'breakfast', hours: '04:00–10:59' }, { bucket: 'lunch', hours: '11:00–14:59' }, { bucket: 'snack', hours: '15:00–17:59' }, { bucket: 'dinner', hours: '18:00–03:59' }],
  policy: {
    handAuthoredWeight: pol.handAuthoredWeight, signalWeight: pol.signalWeight, ladderWeight: pol.ladderWeight, supplementWeight: pol.supplementWeight,
    requirementLookbackDays: pol.requirementLookbackDays, ladderAllowlist: [...allowlist], recentTemplateMemory: chStore.maxRecentTemplateIds,
  },
  daily: { perDay: dcStore.dailyChallengesPerDay, noRepeatDays: dcStore.noRepeatDays, maxStoredDays: dcStore.maxStoredDays, xpEach: XP.dailyChallengeBonus },
  longRunning: challenges,
  dailyTemplates: daily,
};
{
  const expectedTimeBuckets = ['case 4..<11: return .breakfast', 'case 11..<15: return .lunch', 'case 15..<18: return .snack'];
  expectedTimeBuckets.forEach((s) => expectIn(ctSrc, s, rel(ctFile)));
}

// ------------------------------------------------------------------ bingo

const bingoFile = join(FEAT, 'WeeklyBingo/BingoTaskCatalog.swift');
const bingoSrc = src(bingoFile);
const bingoConsts = staticLets(bingoSrc);
const genLets = staticLets(src(join(FEAT, 'WeeklyBingo/BingoCardGenerator.swift')));
const fishOrSeafood = /static let fishOrSeafood: DayPredicate = ([^\n]+)/.exec(bingoSrc)[1];
const bingoTasks = calls(bingoSrc, 'BingoTask').filter((c) => c.inner.includes('id:')).map((c) => {
  const a = argMap(c.inner);
  const scope = a.scope.replace(/fishOrSeafood/g, fishOrSeafood);
  const requirement = reqOfPredicate(scope);
  return {
    id: stringLiteral(a.id), difficulty: enumCase(a.difficulty), family: stringLiteral(a.family), symbol: stringLiteral(a.symbol),
    title: text(a.title, GAM_TABLES, rel(bingoFile)), detail: text(a.detail, GAM_TABLES, rel(bingoFile)),
    scope, requirement, standalone: !requirement.includes('activities'),
    judgesCompletedDaysOnly: a.judgesCompletedDaysOnly === 'true', line: lineOf(bingoSrc, c.start),
  };
});
function featureBadges(block, file, feature, mapArgs) {
  return calls(block, 'badge').map((c) => {
    const r = mapArgs(args(c.inner), argMap(c.inner));
    return { feature, secret: false, source: 'parsed', file: rel(file), line: lineOf(src(file), src(file).indexOf(r.idToken ?? r.id)), ...r, idToken: undefined };
  });
}
const resolveConst = (v, consts) => (v.trim().startsWith('"') ? stringLiteral(v) : consts[v.trim()] ?? v.trim());
const bingoBadges = featureBadges(declBlock(bingoSrc, 'badges'), bingoFile, 'bingo', (_, a) => ({
  id: resolveConst(a.id, bingoConsts), title: text(a.title, GAM_TABLES, rel(bingoFile)), subtitle: text(a.subtitle, GAM_TABLES, rel(bingoFile)),
  symbol: stringLiteral(a.symbol), rarity: enumCase(a.rarity), category: 'challenges',
}));
{
  const f = src(join(FEAT, 'WeeklyBingo/WeeklyBingoFeature.swift'));
  const rules = {};
  for (const m of f.matchAll(/if (\w+) >= (\d+) \{ ids\.append\(BingoTaskCatalog\.(\w+)\) \}/g)) rules[bingoConsts[m[3]]] = `${m[1]} ≥ ${m[2]}`;
  for (const b of bingoBadges) b.rule = rules[b.id] ?? null;
}
const bingo = {
  source: 'parsed', files: [rel(bingoFile), 'ios/Gamification/Sources/Gamification/Features/WeeklyBingo/BingoCardGenerator.swift', 'ios/Gamification/Sources/Gamification/Features/WeeklyBingo/BingoEvaluator.swift', 'ios/Gamification/Sources/Gamification/Features/WeeklyBingo/WeeklyBingoFeature.swift'],
  card: {
    size: genLets.cardSize, centreIndex: genLets.centreIndex, freeId: bingoConsts.freeId, eligibilityWindowDays: genLets.eligibilityWindowDays,
    quota: [...src(join(FEAT, 'WeeklyBingo/BingoCardGenerator.swift')).matchAll(/\(\.(\w+), (\d+)\)/g)].map((m) => ({ difficulty: m[1], count: Number(m[2]) })),
    maxLayoutAttempts: genLets.maxLayoutAttempts,
    lines: [...src(join(FEAT, 'WeeklyBingo/BingoEvaluator.swift')).matchAll(/BingoLine\(kind: \.(\w+), number: (\d), indices: \[([\d, ]+)\]\)/g)].map((m) => ({ kind: m[1], number: Number(m[2]), indices: m[3].split(',').map(Number) })),
    lineXP: XP.bingoLine, fullCardXP: XP.bingoFullCard, fullCardFreeze: true,
  },
  tasks: bingoTasks,
  badges: bingoBadges,
};

// ------------------------------------------------------------------ bosses

const bossFile = join(FEAT, 'Boss/BossCatalog.swift');
const bossSrc = src(bossFile);
const bossConsts = staticLets(bossSrc);
const bossRaw = Object.fromEntries([...bossSrc.matchAll(/case (\w+) = "([\w-]+)"/g)].map((m) => [m[1], m[2]]));
const adherence = {};
for (const m of funcBody(bossSrc, 'adherenceLine').matchAll(/case \.(\w+):\s*\n\s*return (String\(localized:[^\n]+)/g)) adherence[m[1]] = text(m[1] && m[2], GAM_TABLES, rel(bossFile), ['{percent}']);
// Hand-read from BossArchetype.isConsidered (same file).
const considered = {
  breakfastGoblin: 'days with at least one entry', beigeBeast: 'days with at least one entry', midnightMuncher: 'days with at least one entry', scurvyPirate: 'days with at least one entry',
  desertDragon: 'days with water data and a water goal > 0', proteinPoltergeist: 'days with a cached goal status', calorieKraken: 'days with a cached goal status',
  sodaLich: 'days with at least 2 entries', fibrePhantom: 'days with entries and a known fibre total', forgetfulGhost: 'every day (unlogged days count as misses)',
};
expectIn(bossSrc, 'case .breakfastGoblin, .beigeBeast, .midnightMuncher, .scurvyPirate:\n            return day.hasEntries', rel(bossFile));
const bosses = [];
for (const m of funcBody(bossSrc, 'archetype').matchAll(/case \.(\w+):\s*\n\s*return BossArchetype\(/g)) {
  const open = m.index + m[0].length - 1;
  const body = funcBody(bossSrc, 'archetype');
  const inner = body.slice(open + 1, matchBracket(body, open) - 1);
  const a = argMap(inner);
  const requirement = a.requirement === '[]' ? [] : [enumCase(a.requirement)];
  bosses.push({
    id: bossRaw[m[1]], kind: m[1], name: text(a.name, GAM_TABLES, rel(bossFile)), flavour: text(a.flavour, GAM_TABLES, rel(bossFile)), goal: text(a.goal, GAM_TABLES, rel(bossFile)),
    symbol: stringLiteral(a.symbol), requirement, judgesCompletedDaysOnly: a.judgesCompletedDaysOnly === 'true', goodDay: a.goodDay,
    adherenceLine: adherence[m[1]], consideredDays: considered[m[1]], consideredSource: 'hand-read', standalone: !requirement.includes('activities'),
  });
}
const bossBadges = featureBadges(declBlock(bossSrc, 'badges'), bossFile, 'boss', (a) => ({
  id: bossConsts[a[0].value] ?? a[0].value, title: text(a[1].value, GAM_TABLES, rel(bossFile)), subtitle: text(a[2].value, GAM_TABLES, rel(bossFile)),
  symbol: stringLiteral(a[3].value), category: enumCase(a[4].value), rarity: enumCase(a[5].value),
}));
const pickerSrc = src(join(FEAT, 'Boss/BossPicker.swift'));
expectIn(pickerSrc, 'return min(max(ceiling + 2, 3), 7)', 'BossPicker.swift');
const bossOut = {
  source: 'parsed', files: [rel(bossFile), 'ios/Gamification/Sources/Gamification/Features/Boss/BossPicker.swift', 'ios/Gamification/Sources/Gamification/Features/Boss/BossFight.swift', 'ios/Gamification/Sources/Gamification/Features/Boss/WeeklyBossFeature.swift'],
  rules: {
    minimumConsideredDays: bossConsts.minimumConsideredDays, newUserLoggedDays: bossConsts.newUserLoggedDays, analysisWindowDays: 28,
    target: 'clamp(ceil(adherence × 7) + 2, 3, 7)', defeatXP: levels.bossDefeatXP, defeatFreeze: true,
  },
  bosses,
  badges: bossBadges,
};

// ---------------------------------------------------------------- journeys

const jFile = join(FEAT, 'Journeys/JourneyCatalog.swift');
const jSrc = src(jFile);
const jConsts = staticLets(jSrc);
const journeys = [];
for (const kind of ['protein', 'water', 'road', 'passport']) {
  const block = declBlock(jSrc, kind);
  const build = calls(block, 'build')[0];
  const a = argMap(build.inner);
  const stages = [];
  let start = 0;
  for (const st of splitTop(a.stages.slice(1, -1))) {
    const t = argMap(st.trim().slice(1, -1));
    const ms = splitTop(t.milestones.slice(1, -1)).map((ms) => {
      let m;
      if ((m = /^stamps\((\d+)(?:, badge: "([^"]+)")?\)$/.exec(ms))) {
        const n = Number(m[1]);
        const nm = text(/String\(localized: "\\\(number\) stamps"[^\n]*\)/.exec(block)[0], GAM_TABLES, rel(jFile), [n]);
        return { id: `stamps-${n}`, name: nm, value: n, badgeId: m[2] ?? null };
      }
      const sa = args(ms.slice(ms.indexOf('(') + 1, -1));
      return { id: stringLiteral(sa[0].value), name: text(sa[1].value, GAM_TABLES, rel(jFile)), value: literalValue(sa[2].value), badgeId: sa[3] ? stringLiteral(sa[3].value) : null };
    });
    const length = Math.max(...ms.map((x) => x.value));
    stages.push({ name: text(t.name, GAM_TABLES, rel(jFile)), start, length, milestones: ms.map((x) => ({ ...x, threshold: start + x.value })) });
    start += length;
  }
  let endless = null;
  if (a.endless) {
    const e = argMap(calls(a.endless, 'JourneyEndlessGoal')[0].inner);
    endless = { name: text(e.name, GAM_TABLES, rel(jFile)), capacity: jConsts[e.capacity] ?? literalValue(e.capacity) };
  }
  const requirement = a.requirement === '[]' ? [] : [enumCase(a.requirement)];
  journeys.push({
    kind, name: text(a.name, GAM_TABLES, rel(jFile)), symbol: stringLiteral(a.symbol), unit: enumCase(a.unit), stages, endless,
    requirement, standalone: !requirement.includes('activities'), conversionLine: text(a.conversionLine, GAM_TABLES, rel(jFile)),
  });
}
const journeyBadges = featureBadges(declBlock(jSrc, 'badges'), jFile, 'journeys', (a) => {
  const id = stringLiteral(a[0].value);
  return { id, title: text(a[1].value, GAM_TABLES, rel(jFile)), subtitle: text(a[2].value, GAM_TABLES, rel(jFile)), symbol: stringLiteral(a[3].value), rarity: enumCase(a[4].value), category: id.startsWith('journey.passport') ? 'variety' : 'volume' };
});
const journeysOut = {
  source: 'parsed', files: [rel(jFile), 'ios/Gamification/Sources/Gamification/Features/Journeys/JourneysFeature.swift'],
  constants: { metresPerGramOfProtein: jConsts.metresPerGramOfProtein, fallbackWeightKg: jConsts.fallbackWeightKg, podoliPoolLitres: jConsts.podoliPoolLitres, milestoneXP: XP.journeyMilestone },
  journeys, badges: journeyBadges,
};

// ----------------------------------------------------------------- records

const rFile = join(FEAT, 'Records/PersonalRecordCatalog.swift');
const rSrc = src(rFile);
const rConsts = staticLets(rSrc);
const rRaw = Object.fromEntries([...rSrc.matchAll(/case (\w+) = "([\w-]+)"/g)].map((m) => [m[1], m[2]]));
const records = [];
{
  const body = funcBody(rSrc, 'definition');
  for (const m of body.matchAll(/case \.(\w+):\s*\n\s*return PersonalRecordDefinition\(/g)) {
    const open = m.index + m[0].length - 1;
    const a = argMap(body.slice(open + 1, matchBracket(body, open) - 1));
    const requirement = a.requirement === '[]' ? [] : [enumCase(a.requirement)];
    records.push({
      id: rRaw[m[1]], name: text(a.name, GAM_TABLES, rel(rFile)), symbol: stringLiteral(a.symbol), unit: enumCase(a.unit), direction: enumCase(a.direction),
      timing: enumCase(a.timing), minImprovement: a.minImprovement === '1.0 / 60.0' ? '1 minute' : Number(a.minImprovement), requirement, standalone: !requirement.includes('activities'),
    });
  }
}
const recordBadges = featureBadges(declBlock(rSrc, 'badges'), rFile, 'records', (a) => ({
  id: stringLiteral(a[0].value), title: text(a[1].value, GAM_TABLES, rel(rFile)), subtitle: text(a[2].value, GAM_TABLES, rel(rFile)), symbol: stringLiteral(a[3].value), rarity: enumCase(a[4].value), category: 'extreme',
}));
const recordsOut = {
  source: 'parsed', files: [rel(rFile), 'ios/Gamification/Sources/Gamification/Features/Records/RecordsEvaluator.swift'],
  constants: { warmUpDays: rConsts.warmUpDays, maxFastGapHours: rConsts.maxFastGapHours, onTargetTolerance: rConsts.onTargetTolerance, onTargetMinEntries: rConsts.onTargetMinEntries, fullHouseMinRecords: rConsts.fullHouseMinRecords, historyLimit: rConsts.historyLimit, prXP: XP.personalRecord },
  records, badges: recordBadges,
};

// ------------------------------------------------------------- collections

const cFile = join(FEAT, 'Collections/FoodCollectionCatalog.swift');
const cSrc = src(cFile);
const cConsts = staticLets(cSrc);
const collText = (key) => {
  const en = T.collEn.get(key) ?? null;
  const cs = T.collCs.get(key) ?? null;
  if (cs == null) gaps.push({ key, table: 'Gamification cs.lproj/Collections.strings', where: rel(cFile) });
  return { en, cs };
};
const collections = [];
for (const name of ['czechClassics', 'world', 'fermented', 'rainbow', 'czechBrands']) {
  const block = declBlock(cSrc, name);
  const a = argMap(block.slice(block.indexOf('(') + 1, -1));
  const id = cConsts[a.id];
  const entries = [...a.entries.matchAll(/\((?:"([^"]+)"|(\w+)), "([^"]+)", \.(\w+)\)/g)].map((m) => {
    const eid = m[1] ?? cConsts[m[2]];
    return { id: eid, emoji: m[3], tag: m[4], name: collText(`entry.${eid}.name`), hint: collText(`entry.${eid}.hint`) };
  });
  collections.push({ id, symbol: stringLiteral(a.symbol), badgePercents: arrayLiteral(a.badgePercents), title: collText(`collection.${id}.title`), subtitle: collText(`collection.${id}.subtitle`), entries });
}
const cbFile = join(FEAT, 'Collections/CollectionsBadges.swift');
const cbSrc = src(cbFile);
const cb = staticLets(cbSrc);
const collectionBadges = [];
{
  const def = (id, symbol, rarity, rule) => collectionBadges.push({ id, feature: 'collections', category: 'variety', symbol, rarity, title: collText(`badge.${id}.title`), subtitle: collText(`badge.${id}.subtitle`), rule, secret: false, source: 'mirrored', file: rel(cbFile) });
  expectIn(cbSrc, 'case ..<50: return .common', rel(cbFile));
  for (const c of collections) for (const p of c.badgePercents) def(`collection.${c.id}.${p}`, c.symbol, p < 50 ? 'common' : p < 100 ? 'rare' : 'epic', `${p}% of “${c.title.en}” discovered`);
  for (const t of cb.rainbowDayThresholds) def(t <= 1 ? 'collection.rainbow-day' : `collection.rainbow-day-${t}`, 'rainbow', t <= 1 ? 'rare' : 'epic', `${t} rainbow day(s)`);
  for (const t of cb.brandExplorerThresholds) def(`collection.brand-explorer-${t}`, 'cart.badge.plus', t < 25 ? 'uncommon' : t < 50 ? 'rare' : 'epic', `${t} distinct Czech brands`);
  for (const p of cb.pokedexPercents) def(`collection.pokedex-${p}`, p >= 100 ? 'crown.fill' : 'books.vertical.fill', p >= 100 ? 'legendary' : 'epic', `${p}% of all collection entries discovered`);
}
const collectionsOut = {
  source: 'parsed', files: [rel(cFile), rel(cbFile), 'ios/Gamification/Sources/Gamification/Resources/en.lproj/Collections.strings', 'ios/Gamification/Sources/Gamification/Resources/cs.lproj/Collections.strings', 'ios/FoodLogCore/Sources/FoodLogCore/Signals/FoodTagRules+Collections.swift'],
  discoveryXP: XP.collectionDiscovery, veproKnedloZeloId: cConsts.veproKnedloZeloId,
  collections, badges: collectionBadges,
};

// ---------------------------------------------------------------- seasonal

const sFile = join(FEAT, 'Seasonal/SeasonalEventCatalog.swift');
const sConsts = staticLets(seasonalCatSrc);
function easterSunday(year) { // Anonymous Gregorian algorithm (SeasonalCalendar.easterSunday)
  const a = year % 19, b = Math.floor(year / 100), c = year % 100, d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3);
  const h = (19 * a + b - d - g + 15) % 30, i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451);
  const month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1;
  return new Date(Date.UTC(year, month - 1, day));
}
const iso = (d) => d.toISOString().slice(0, 10);
function dayRef(t) {
  let m;
  if ((m = /^md\((\d+), (\d+)\)$/.exec(t.trim()))) return { month: Number(m[1]), day: Number(m[2]) };
  if ((m = /^\.easterOffset\((-?\d+)\)$/.exec(t.trim()))) return { easterOffset: Number(m[1]) };
  throw new Error('day ref ' + t);
}
function resolveRef(r, year) {
  if (r.easterOffset != null) { const d = easterSunday(year); d.setUTCDate(d.getUTCDate() + r.easterOffset); return iso(d); }
  return `${year}-${String(r.month).padStart(2, '0')}-${String(r.day).padStart(2, '0')}`;
}
const seasonalEvents = calls(declBlock(seasonalCatSrc, 'all'), 'SeasonalEvent').map((c) => {
  const a = argMap(c.inner);
  const id = a.id.startsWith('"') ? stringLiteral(a.id) : sConsts[a.id];
  let windowRule, windows = null;
  if (a.windowRule === '.ownerNameDay') windowRule = { kind: 'ownerNameDay' };
  else {
    const m = /^\.fixed\(start: (.+), end: (.+)\)$/.exec(a.windowRule);
    windowRule = { kind: 'fixed', start: dayRef(m[1]), end: dayRef(m[2]) };
    windows = [2026, 2027, 2028].map((y) => ({ year: y, start: resolveRef(windowRule.start, y), end: resolveRef(windowRule.end, y) }));
  }
  const quests = calls(a.quests, 'SeasonalQuest').map((q) => {
    const qa = argMap(q.inner);
    return { id: stringLiteral(qa.id), title: text(qa.title, GAM_TABLES, rel(sFile)), rule: qa.rule, bonus: qa.isBonus === 'true' };
  });
  return {
    id, title: text(a.title, GAM_TABLES, rel(sFile)), subtitle: a.subtitle ? text(a.subtitle, GAM_TABLES, rel(sFile)) : null, symbol: stringLiteral(a.symbol),
    windowRule, windows, quests, badgeId: `event.${id}`, badgeRarity: enumCase(a.badgeRarity), teaser: text(a.teaser, GAM_TABLES, rel(sFile)),
  };
});
const limitedKey = /String\(localized: "(Limited edition[^"]+)"/.exec(seasonalCatSrc)[1];
const limitedSub = { en: limitedKey, cs: T.gamCs.get(limitedKey) ?? null };
if (limitedSub.cs == null) gaps.push({ key: limitedKey, table: GAM_TABLES.label, where: rel(sFile) });
const seasonalBadges = [
  ...seasonalEvents.map((e) => ({ id: e.badgeId, feature: 'seasonal', category: 'calendar', symbol: e.symbol, rarity: e.badgeRarity, title: e.title, subtitle: { en: limitedSub.en.replace('%@', e.title.en), cs: limitedSub.cs?.replace('%@', e.title.cs ?? e.title.en) ?? null }, limitedEdition: e.id, secret: false, source: 'parsed', file: rel(sFile) })),
  ...calls(declBlock(seasonalCatSrc, 'collectorBadges'), 'AchievementDefinition').map((c) => {
    const a = argMap(c.inner);
    return { id: sConsts[a.id], feature: 'seasonal', category: enumCase(a.category), symbol: stringLiteral(a.badgeSymbol), rarity: enumCase(a.rarityOverride), title: text(a.title, GAM_TABLES, rel(sFile)), subtitle: text(a.subtitle, GAM_TABLES, rel(sFile)), secret: false, source: 'parsed', file: rel(sFile) };
  }),
];
const ndSrc = src(join(FEAT, 'Seasonal/CzechNameDays.swift'));
const nameDays = [];
{
  const rows = declBlock(ndSrc, 'rows');
  for (const month of splitTop(rows.slice(1, -1))) {
    const mm = /^(\d+):\s*\[/.exec(month);
    const inner = month.slice(month.indexOf('[') + 1, month.lastIndexOf(']'));
    for (const day of splitTop(inner)) {
      const dm = /^(\d+):\s*(\[[\s\S]*\])$/.exec(day);
      nameDays.push({ month: Number(mm[1]), day: Number(dm[1]), names: arrayLiteral(dm[2]) });
    }
  }
}
const seasonalOut = {
  source: 'parsed', files: [rel(sFile), 'ios/Gamification/Sources/Gamification/Features/Seasonal/SeasonalCalendar.swift', 'ios/Gamification/Sources/Gamification/Features/Seasonal/CzechNameDays.swift', 'ios/Gamification/Sources/Gamification/Features/Seasonal/SeasonalEventsFeature.swift'],
  constants: { bonusQuestXP: sConsts.bonusQuestXP, teaserDays: sConsts.teaserDays, eventCompletedXP: XP.seasonalEventCompleted },
  events: seasonalEvents, badges: seasonalBadges, nameDays,
};

// ----------------------------------------------------------------- secrets

const secFile = join(FEAT, 'Secret/SecretCatalog.swift');
const secSrc = src(secFile);
const secRaw = Object.fromEntries([...secSrc.matchAll(/case (\w+) = "(secret\.[\w-]+)"/g)].map((m) => [m[1], m[2]]));
const secRarity = Object.fromEntries(Object.entries(switchReturns(funcBody(secSrc, 'rarity'))).map(([k, v]) => [k, enumCase(v)]));
const secSymbol = Object.fromEntries(Object.entries(switchReturns(funcBody(secSrc, 'symbol'))).map(([k, v]) => [k, stringLiteral(v)]));
const secretBadges = [];
{
  const body = funcBody(secSrc, 'texts');
  for (const m of body.matchAll(/case \.(\w+):\s*\n\s*return \(/g)) {
    const open = m.index + m[0].length - 1;
    const a = splitTop(body.slice(open + 1, matchBracket(body, open) - 1));
    secretBadges.push({
      id: secRaw[m[1]], feature: 'secrets', category: 'funnyFacts', symbol: secSymbol[m[1]], rarity: secRarity[m[1]], secret: true,
      standalone: m[1] !== 'dawnPatrol', title: text(a[0], GAM_TABLES, rel(secFile)), subtitle: text(a[1], GAM_TABLES, rel(secFile)), source: 'parsed', file: rel(secFile),
    });
  }
  const k = argMap(calls(declBlock(secSrc, 'keeper'), 'AchievementDefinition')[0].inner);
  secretBadges.push({ id: staticLets(secSrc).keeperId, feature: 'secrets', category: 'meta', symbol: stringLiteral(k.badgeSymbol), rarity: enumCase(k.rarityOverride), secret: false, title: text(k.title, GAM_TABLES, rel(secFile)), subtitle: text(k.subtitle, GAM_TABLES, rel(secFile)), source: 'parsed', file: rel(secFile) });
}

// --------------------------------------------------------------- sport/body

const sbFile = join(FEAT, 'SportBody/SportBodyCatalog.swift');
const sbSrc = src(sbFile);
const sbConsts = staticLets(sbSrc);
const tierThreshold = Object.fromEntries([...sbSrc.matchAll(/Tier\(id: "([\w.-]+)", threshold: (\d+)\)/g)].map((m) => [m[1], Number(m[2])]));
const subtitleFns = {};
for (const fn of ['fuelSubtitle', 'recoverySubtitle', 'earnedSubtitle']) subtitleFns[fn] = /String\(\s*format: (String\(localized: "[^"]+"[^\n]*\)),/.exec(funcBody(sbSrc, fn))[1];
const sportBadges = calls(declBlock(sbSrc, 'badges'), 'define').map((c) => {
  const a = args(c.inner);
  const m = argMap(c.inner);
  const id = a[0].value.startsWith('"') ? stringLiteral(a[0].value) : sbConsts[a[0].value];
  let subtitle;
  const fm = /^(\w+Subtitle)\((\d+)\)$/.exec(a[2].value);
  if (fm) {
    const t = text(subtitleFns[fm[1]], GAM_TABLES, rel(sbFile));
    subtitle = { en: t.en.replace('{', '').replace('}', '').replace('%lld', fm[2]), cs: t.cs?.replace('%lld', fm[2]) ?? null };
    subtitle.en = stringLiteral(/"[^"]+"/.exec(subtitleFns[fm[1]])[0]).replace('%lld', fm[2]);
  } else subtitle = text(a[2].value, GAM_TABLES, rel(sbFile));
  return {
    id, feature: 'sportBody', category: m.category ? enumCase(m.category) : 'goalHitting', symbol: stringLiteral(m.symbol), rarity: enumCase(m.rarity),
    title: text(a[1].value, GAM_TABLES, rel(sbFile)), subtitle, threshold: tierThreshold[id] ?? null, secret: false, source: 'parsed', file: rel(sbFile),
  };
});
const sportRules = { ...staticLets(src(join(FEAT, 'SportBody/SportRules.swift'))), ...staticLets(src(join(FEAT, 'SportBody/BodyRules.swift'))), ...staticLets(src(join(FEAT, 'SportBody/SportActivityClass.swift'))) };
delete sportRules.epsilon;

// ------------------------------------------------------------- supplements

const supFeatFile = join(FEAT, 'Supplements/SupplementsCatalog.swift');
const supFeatSrc = src(supFeatFile);
const supConsts = staticLets(supFeatSrc);
const supplementBadges = featureBadges(declBlock(supFeatSrc, 'badges'), supFeatFile, 'supplements', (a) => ({
  id: supConsts[a[0].value], title: text(a[1].value, GAM_TABLES, rel(supFeatFile)), subtitle: text(a[2].value, GAM_TABLES, rel(supFeatFile)),
  symbol: stringLiteral(a[3].value), rarity: enumCase(a[4].value), category: 'supplements', optional: true,
}));

const evFile = join(FLC, 'Supplements/EvidenceCatalog.swift');
const evSrc = src(evFile);
const sources = {};
for (const m of evSrc.matchAll(/static let (\w+) = EvidenceSource\(\s*"([^"]+)",\s*"([^"]+)"\s*\)/g)) sources[m[1]] = { title: m[2], url: m[3] };
expectIn(evSrc, 'EvidenceSource("NIH Office of Dietary Supplements – \\(title) fact sheet", "https://ods.od.nih.gov/factsheets/\\(page)-HealthProfessional/")', rel(evFile));
const srcRef = (t) => {
  t = t.trim();
  const m = /^ods\("([^"]+)", "([^"]+)"\)$/.exec(t);
  if (m) return { title: `NIH Office of Dietary Supplements – ${m[1]} fact sheet`, url: `https://ods.od.nih.gov/factsheets/${m[2]}-HealthProfessional/` };
  return sources[t];
};
const modelsSrc = src(join(FLC, 'Supplements/SupplementModels.swift'));
const canonical = (ing) => {
  if (['creatine', 'betaAlanine'].includes(ing)) return 'g';
  if (['vitaminD', 'vitaminB12', 'selenium', 'vitaminK2'].includes(ing)) return 'µg';
  return 'mg';
};
expectIn(modelsSrc, 'case .creatine, .betaAlanine: return .g', 'SupplementModels.swift');
expectIn(modelsSrc, 'case .vitaminD, .vitaminB12, .selenium, .vitaminK2: return .ug', 'SupplementModels.swift');
const ingName = {};
for (const m of funcBody(evSrc, 'name').matchAll(/case \.(\w+): return (String\(localized:[^\n]+)/g)) ingName[m[1]] = text(m[2], FLC_TABLES, rel(evFile));
const ingTexts = {};
{
  const body = funcBody(evSrc, 'texts');
  for (const m of body.matchAll(/case \.(\w+):\s*\n\s*return Texts\(/g)) {
    const open = m.index + m[0].length - 1;
    const a = argMap(body.slice(open + 1, matchBracket(body, open) - 1));
    ingTexts[m[1]] = { purpose: text(a.purpose, FLC_TABLES, rel(evFile)), dose: text(a.dose, FLC_TABLES, rel(evFile)), timing: text(a.timing, FLC_TABLES, rel(evFile)) };
  }
}
const limitNotes = {};
for (const m of funcBody(evSrc, 'limitNote').matchAll(/case \.(\w+):\s*\n\s*return (String\(localized:[^\n]+)/g)) limitNotes[m[1]] = text(m[2], FLC_TABLES, rel(evFile));
const strengthTitle = Object.fromEntries(Object.entries(switchReturns(funcBodyVar(evSrc, 'title'))).map(([k, v]) => [k, text(v, FLC_TABLES, rel(evFile))]));
const evidence = calls(declBlock(evSrc, 'all'), 'EvidenceCard').map((c) => {
  const a = argMap(c.inner);
  const ing = enumCase(a.ingredient);
  const la = argMap(calls(a.limit, 'DefaultLimit')[0].inner);
  const num = (v) => (v == null ? null : Number(v));
  const range = a.effectiveRange === 'nil' ? null : a.effectiveRange.split('...').map(Number);
  return {
    ingredient: ing, name: ingName[ing], unit: canonical(ing), strength: enumCase(a.strength), strengthTitle: strengthTitle[enumCase(a.strength)],
    effectiveRange: range,
    limit: { kind: enumCase(la.kind), value: num(la.value), singleDose: num(la.singleDose), usFigure: num(la.usFigure), noConcernLevel: num(la.noConcernLevel), supplementalOnly: la.supplementalOnly === 'true', source: srcRef(la.source) },
    limitNote: limitNotes[ing] ?? null,
    sources: splitTop(a.sources.slice(1, -1)).map(srcRef),
    ...ingTexts[ing],
  };
});
const catFile = join(FLC, 'Supplements/SupplementCatalog.swift');
const catSrc = src(catFile);
const productName = {};
for (const m of funcBody(catSrc, 'name').matchAll(/case "(\w+)": return (String\(localized:[^\n]+)/g)) productName[m[1]] = text(m[2], FLC_TABLES, rel(catFile));
const servingText = (form, serving) => {
  let m;
  if ((m = /^\.scoop\(grams: (\d+)\)$/.exec(serving))) return text('String(localized: "\\(grams) g scoop", bundle: .module)', FLC_TABLES, rel(catFile), [Number(m[1])]);
  m = /^\.units\((\d+)\)$/.exec(serving);
  const n = Number(m[1]);
  const word = { capsule: 'capsules', tablet: 'tablets', gummy: 'gummies' }[form] ?? 'servings';
  return text(`String(localized: "\\(count) ${word}", bundle: .module)`, FLC_TABLES, rel(catFile), [n]);
};
const products = calls(declBlock(catSrc, 'all'), 'CatalogProduct').map((c) => {
  const a = argMap(c.inner);
  const id = stringLiteral(a.id);
  const ingredients = calls(a.ingredients, 'row').map((r) => {
    const ra = args(r.inner);
    const unit = enumCase(ra[2].value);
    return { ingredient: enumCase(ra[0].value), amount: Number(ra[1].value), unit: { ug: 'µg', iu: 'IU' }[unit] ?? unit, form: ra[3] ? enumCase(ra[3].value.replace('form:', '')) : null };
  });
  return { id, name: productName[id], form: enumCase(a.form), serving: servingText(enumCase(a.form), a.serving), ingredients, suggestedSlot: enumCase(a.suggestedSlot) };
});
const lsFile = join(FLC, 'Supplements/LabelScore.swift');
const lsLets = staticLets(src(lsFile));
const supplementsOut = {
  source: 'parsed', files: [rel(catFile), rel(evFile), rel(lsFile), rel(supFeatFile), 'ios/Gamification/Sources/Gamification/Features/Supplements/SupplementsFeature.swift', 'ios/Gamification/Sources/Gamification/Features/Supplements/SupplementStreak.swift'],
  disclaimer: text(/(String\(localized: "Information only[^\n]+)/.exec(evSrc)[1], FLC_TABLES, rel(evFile)),
  noEUUpperLimitText: text(/(String\(localized: "No EU upper limit set", bundle[^\n]+)/.exec(evSrc)[1], FLC_TABLES, rel(evFile)),
  vitaminDIUPerMicrogram: 40,
  products, evidence,
  labelScore: {
    source: 'parsed constants + hand-read rules (LabelScore.swift header)',
    parts: [
      { part: 'transparency', max: 40, rule: `40 × (ingredient rows with an amount ÷ rows), −${lsLets.blendPenalty} per proprietary blend, −${lsLets.missingFormPenalty} per magnesium row without a form; clamped to 0…40. No rows: 0.` },
      { part: 'dose', max: 40, rule: '40 × mean(per-ingredient score): 1 inside the evidence card’s effective range, 0.5 below or above it; ingredients without a range are not scored; nothing scorable → 20 (half).' },
      { part: 'headroom', max: 20, rule: '20 when the day’s total at the planned dose (plus the rest of the stack) stays under every upper limit, 0 when any of the product’s ingredients would be over.' },
    ],
  },
  gamification: {
    thresholds: { stackWeekDays: supConsts.stackWeekDays, fullStackMonthDays: supConsts.fullStackMonthDays, creatineDayThresholds: supConsts.creatineDayThresholds, sunshineDays: supConsts.sunshineDays, omegaRunDays: supConsts.omegaRunDays, neverRanOutRefills: supConsts.neverRanOutRefills, alphabetThresholds: supConsts.alphabetThresholds },
    alphabet: [...declBlock(supFeatSrc, 'alphabet').matchAll(/\.(\w+)/g)].map((m) => ({ ingredient: m[1], name: ingName[m[1]] })),
    creatineJourney: [...supFeatSrc.matchAll(/SupplementJourneyMilestone\(id: "([\w-]+)", grams: ([\d_]+)\)/g)].map((m) => ({ id: m[1], grams: Number(m[2].replace(/_/g, '')) })),
    collectionName: text(/(String\(localized: "Vitamin alphabet"[^\n]+)/.exec(supFeatSrc)[1], GAM_TABLES, rel(supFeatFile)),
    journeyName: text(/(String\(localized: "Creatine journey"[^\n]+)/.exec(supFeatSrc)[1], GAM_TABLES, rel(supFeatFile)),
    stackCompleteXPBeforeMultiplier: XP.supplementStackComplete,
  },
  badges: supplementBadges,
};

// ------------------------------------------------------ all badges, merged

const saSrc = src(join(FEAT, 'StandaloneAvailability.swift'));
expectIn(saSrc, 'for tiers in [SportBodyCatalog.fuelTiers, SportBodyCatalog.recoveryTiers, SportBodyCatalog.earnedTiers, SportBodyCatalog.raceDayTiers]', 'StandaloneAvailability.swift');
expectIn(saSrc, 'ids.formUnion([SportBodyCatalog.doubleDayId, SportBodyCatalog.gelGuruId, SportBodyCatalog.longHaulId, SportBodyCatalog.carbLoaderId])', 'StandaloneAvailability.swift');
const garminOnly = new Set([
  ...sportBadges.filter((b) => /^sport\.(fuel|recovery|earned|race-day)-/.test(b.id)).map((b) => b.id),
  sbConsts.doubleDayId, sbConsts.gelGuruId, sbConsts.longHaulId, sbConsts.carbLoaderId,
  'secret.dawn-patrol',
  ...journeys.find((j) => j.kind === 'road').stages.flatMap((s) => s.milestones.map((m) => m.badgeId)).filter(Boolean),
]);

const featureLabel = { core: 'Core', bingo: 'Weekly bingo', boss: 'Weekly boss', journeys: 'Journeys', records: 'Personal records', collections: 'Food collections', seasonal: 'Seasonal events', secrets: 'Secrets', sportBody: 'Sport & body', supplements: 'Supplements' };
const allBadges = [
  ...coreAchievements,
  ...bingoBadges, ...bossBadges, ...journeyBadges, ...recordBadges, ...collectionBadges, ...seasonalBadges, ...secretBadges, ...sportBadges, ...supplementBadges,
].map((b) => ({
  ...b,
  featureLabel: featureLabel[b.feature],
  garminOnly: garminOnly.has(b.id),
  optional: b.feature === 'supplements',
}));

const catNames = {};
{
  // AchievementCategory display names (app: Progress/AchievementsView.swift)
  const av = src(join(IOS, 'GarminFood/Progress/AchievementsView.swift'));
  for (const m of av.matchAll(/case \.(\w+): return (String\(localized: "[^"]+"[^\n]*\)|"[^"]+")/g)) {
    const lit = /"([^"]+)"/.exec(m[2])[1];
    const x = T.app.get(lit);
    catNames[m[1]] = { en: lit, cs: x?.cs ?? null };
  }
}

const achievementsOut = {
  source: 'mirrored (core families) + parsed (feature catalogs)',
  counts: Object.fromEntries(Object.keys(featureLabel).map((f) => [f, allBadges.filter((b) => b.feature === f).length])),
  total: allBadges.length,
  rarities: RARITIES.map((r) => ({ id: r, name: rarityNames[r], colors: rarityColors[r] })),
  categories: catNames,
  badges: allBadges,
};

// ------------------------------------------------------------------ write

mkdirSync(OUT, { recursive: true });
let lastIosCommit = null, lastIosDate = null, dirty = null;
try {
  lastIosCommit = execSync('git log -1 --format=%H -- ios', { cwd: ROOT }).toString().trim();
  lastIosDate = execSync('git log -1 --format=%cI -- ios', { cwd: ROOT }).toString().trim();
  dirty = execSync('git status --porcelain -- ios', { cwd: ROOT }).toString().trim().length > 0;
} catch { /* not a git checkout */ }

// Uniq gaps
const gapKey = new Set();
const uniqGaps = gaps.filter((g) => { const k = g.table + '|' + g.key; if (gapKey.has(k)) return false; gapKey.add(k); return true; });

// App-level string table statistics (Localizable.xcstrings)
const appStats = { total: 0, withCs: 0, missingCs: [] };
for (const [k, v] of T.app) {
  if (v.shouldTranslate === false || !k.trim()) continue;
  appStats.total++;
  if (v.cs != null) appStats.withCs++; else appStats.missingCs.push(k);
}

const meta = {
  generator: 'tools/docs/extract-guide-data.mjs',
  sourceCommit: lastIosCommit, sourceCommitDate: lastIosDate, sourceDirty: dirty,
  note: 'sourceCommit = the last commit that touched ios/. Regenerate with `node tools/docs/extract-guide-data.mjs --embed`.',
  counts: {
    achievementsTotal: allBadges.length, ...Object.fromEntries(Object.entries(achievementsOut.counts).map(([k, v]) => [`badges.${k}`, v])),
    levelTiers: levelTiers.length, longRunningChallenges: challenges.length,
    challengesInRotation: challenges.filter((c) => c.staticWeight > 0).length,
    signalChallenges: challenges.filter((c) => c.group === 'signal').length, supplementChallenges: challenges.filter((c) => c.group === 'supplement').length,
    dailyChallenges: daily.length, bingoTasks: bingoTasks.length, bosses: bosses.length, journeys: journeys.length,
    journeyMilestones: journeys.reduce((s, j) => s + j.stages.reduce((t, st) => t + st.milestones.length, 0), 0),
    personalRecords: records.length, collections: collections.length, collectionEntries: collections.reduce((s, c) => s + c.entries.length, 0),
    seasonalEvents: seasonalEvents.length, seasonalQuests: seasonalEvents.reduce((s, e) => s + e.quests.length, 0), nameDays: nameDays.length,
    supplementProducts: products.length, evidenceCards: evidence.length,
    catalogStringsMissingCzech: uniqGaps.length, appStringsMissingCzech: appStats.missingCs.length,
  },
};

const files = {
  meta, achievements: achievementsOut, levels, streaks, challenges: challengesOut, bingo, bosses: bossOut,
  journeys: journeysOut, records: recordsOut, collections: collectionsOut, seasonal: seasonalOut,
  sportBody: { source: 'parsed', files: [rel(sbFile), 'ios/Gamification/Sources/Gamification/Features/SportBody/SportRules.swift', 'ios/Gamification/Sources/Gamification/Features/SportBody/BodyRules.swift'], rules: sportRules, badges: sportBadges.map((b) => ({ id: b.id, threshold: b.threshold })) },
  supplements: supplementsOut,
  l10nGaps: { catalog: uniqGaps, app: appStats },
};
const json = (v) => JSON.stringify(v, null, 1) + '\n';
for (const [name, value] of Object.entries(files)) {
  const file = name.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
  writeFileSync(join(OUT, `${file}.json`), json(value));
}

if (process.argv.includes('--embed')) {
  const indexPath = join(ROOT, 'docs', 'guide', 'index.html');
  if (existsSync(indexPath)) {
    const html = readFileSync(indexPath, 'utf8');
    const payload = JSON.stringify(files).replace(/</g, '\\u003c');
    const re = /(<script id="guide-data" type="application\/json">)[\s\S]*?(<\/script>)/;
    if (!re.test(html)) throw new Error('index.html has no <script id="guide-data"> block');
    writeFileSync(indexPath, html.replace(re, (_, a, b) => a + payload + b));
    console.log('embedded data into docs/guide/index.html');
  }
}

console.log(JSON.stringify(meta.counts, null, 1));

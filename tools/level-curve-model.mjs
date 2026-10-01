#!/usr/bin/env node
/**
 * level-curve-model.mjs — the numeric model behind the 150-level curve
 * (openspec/changes/add-training-gamification-and-150-levels, design D1–D3).
 *
 * Why this exists: there is no Mac, so the Swift budget (`XPBudget`,
 * `TrainingXPBudget`) cannot be run locally. This script is a line-by-line
 * mirror of those two tables in plain JavaScript. It prints
 *   - expected XP/day per source for three scenarios: a poor week, a typical
 *     consistent day, a perfect week;
 *   - the growth factor that puts level 150 at TARGET_DAYS of typical play;
 *   - the level table (threshold, band, days) and the pace checks;
 *   - the migration check: no level threshold of the new curve is above the
 *     same level's threshold on any curve that shipped before.
 *
 * The Swift tests are the authority (XPBudgetTests pins the factor and the
 * three scenario totals); when a reward constant changes, change it in BOTH
 * places, run this, and paste the printed literals.
 *
 * Usage:
 *   node tools/level-curve-model.mjs            # the report
 *   node tools/level-curve-model.mjs --check    # exit 1 if a design rule fails
 *
 * Node >= 18, no dependencies. Synthetic numbers only: frequencies are
 * assumptions about "a typical user", not anyone's data.
 */

const CHECK = process.argv.includes('--check');

// ---------------------------------------------------------------- constants

/** XPAward (XPStore.swift, XPAward+Features.swift). */
const XP = {
  flatPerLog: 10,
  streakExtensionBonus: 20,
  goalHitBonus: 25,
  dailyChallengeBonus: 15,
  achievementBonus: 30,
  bingoLine: 25,
  bingoFullCard: 150,
  seasonalEventCompleted: 50,
  bonusQuestXP: 25,
  collectionDiscovery: 5,
  journeyMilestone: 40,
  personalRecord: 20,
  secretUnlocked: 50,
  sportBadge: 0,
  bossDefeatedBase: 150,
  bossDefeatedPerTargetDay: 25,
  // XPAward+Training.swift
  trainingCheckIn: 10,
  trainingPainLogged: 2,
  trainingHabitTick: 2,
  trainingHabitFullDay: 6,
  trainingHabitStreak: [20, 40, 80, 200], // 7, 30, 100, 365 days
  trainingLadderStep: 40,
  trainingSession: 20,
  trainingHonestCall: 8,
  trainingDayKept: 8,
  trainingSessionRPE: 2,
  trainingSessionNote: 1,
  trainingGateTest: 15,
  trainingTestRecorded: 20,
  trainingWeekApproved: 10,
  trainingWeekKept: 80,
  trainingEasyWeek: 30,
  trainingGymWeek: 20,
  trainingPhaseCompleted: 150,
  trainingSeasonCompleted: 300,
  trainingRacePrep: 40,
  trainingCarbLoadDay: 15,
  trainingRaceFinished: 100,
  trainingRaceReport: 60,
  trainingWiseCall: 100,
};

const BASE = 100; // LevelCurve.baseXPForFirstLevelUp
const MAX_LEVEL = 150; // LevelCurve.maxLevel
const TARGET_LEVEL = 150; // XPBudget.targetLevel
const TARGET_DAYS = 1540; // XPBudget.targetDays (about 4.2 years)
const PAST_FACTORS = [1.045, 1.0505, 1.05358]; // LevelCurve.pastGrowthFactors

const week = 7.0;
const month = 365.0 / 12.0;
const year = 365.0;
const threeYears = 1095.0;
const span = TARGET_DAYS; // one-offs of the training lines are spread over the target
const assumedMeanChallengeReward = 85.0;
const badgeXP = (count) => (XP.achievementBonus * count) / threeYears;
const bossDefeatXP = (target) => XP.bossDefeatedBase + XP.bossDefeatedPerTargetDay * Math.max(0, target - 3);

// ---------------------------------------------------- the food core (XPBudget)

/** [source, typical, poor, perfect] — XP per day. Typical = XPBudget.lines. */
const CORE = [
  ['log', XP.flatPerLog * 3.5, XP.flatPerLog * 2.5 * 4 / week, XP.flatPerLog * 4.5],
  ['streak', XP.streakExtensionBonus * 1.0, XP.streakExtensionBonus * 4 / week, XP.streakExtensionBonus * 1.0],
  ['goal', XP.goalHitBonus * 0.6, XP.goalHitBonus * 0.2, XP.goalHitBonus * 1.0],
  ['dailyChallenge', XP.dailyChallengeBonus * 2 * 0.6, XP.dailyChallengeBonus * 2 * 0.15, XP.dailyChallengeBonus * 2 * 1.0],
  ['challenge', assumedMeanChallengeReward / 9, assumedMeanChallengeReward / 21, assumedMeanChallengeReward / 7.5],
  ['achievement', XP.achievementBonus * 15 / year, XP.achievementBonus * 6 / year, XP.achievementBonus * 20 / year],
  ['bingo',
    XP.bingoLine * 1.5 / week + XP.bingoFullCard / (8 * week) + badgeXP(6),
    XP.bingoLine * 0.5 / week,
    XP.bingoLine * 3 / week + XP.bingoFullCard / (3 * week) + badgeXP(7)],
  ['seasonal',
    (XP.seasonalEventCompleted * 6 + XP.bonusQuestXP * 3) / year + badgeXP(10),
    (XP.seasonalEventCompleted * 2) / year,
    (XP.seasonalEventCompleted * 12 + XP.bonusQuestXP * 8) / year + badgeXP(10)],
  ['collections',
    XP.collectionDiscovery * 0.5 / week + badgeXP(6),
    XP.collectionDiscovery * 0.2 / week,
    XP.collectionDiscovery * 1.0 / week + badgeXP(6)],
  ['journeys',
    XP.journeyMilestone * 40 / threeYears + badgeXP(8),
    XP.journeyMilestone * 20 / threeYears,
    XP.journeyMilestone * 44 / threeYears + badgeXP(8)],
  ['records',
    XP.personalRecord * 3 / month + badgeXP(3),
    XP.personalRecord * 1 / month,
    XP.personalRecord * 4 / month + badgeXP(3)],
  ['secrets',
    (XP.secretUnlocked + XP.achievementBonus) * 12 / threeYears,
    (XP.secretUnlocked + XP.achievementBonus) * 4 / threeYears,
    (XP.secretUnlocked + XP.achievementBonus) * 16 / threeYears],
  ['sportBody',
    (XP.sportBadge + XP.achievementBonus) * 10 / threeYears,
    (XP.sportBadge + XP.achievementBonus) * 3 / threeYears,
    (XP.sportBadge + XP.achievementBonus) * 14 / threeYears],
  ['boss',
    bossDefeatXP(5) * 0.5 / week + badgeXP(6),
    0,
    bossDefeatXP(6) * 1.0 / week + badgeXP(7)],
];

// ------------------------------------------- training (TrainingXPBudget.lines)

const streakTotal = XP.trainingHabitStreak.reduce((a, b) => a + b, 0);

/**
 * [source, reward, unit, typical, poor, perfect] — the frequency is per
 * `unit` ('week', 'year' or 'span' = once over the target days).
 */
const TRAINING = [
  // Honest self-monitoring.
  ['checkIn', XP.trainingCheckIn, 'week', 6, 3, 7],
  ['painLogged', XP.trainingPainLogged, 'week', 6 * 0.4, 3 * 0.4, 7 * 0.4],
  ['sessionRPE', XP.trainingSessionRPE, 'week', 4, 1, 7],
  ['sessionNote', XP.trainingSessionNote, 'week', 2, 0, 7],
  ['gateTest', XP.trainingGateTest, 'week', 0.4, 0.2, 0.4],
  ['testRecorded', XP.trainingTestRecorded, 'week', 0.5, 0.25, 0.5],
  // Habits.
  ['habitTick', XP.trainingHabitTick, 'week', 22, 10, 28],
  ['habitFullDay', XP.trainingHabitFullDay, 'week', 3.5, 0.5, 7],
  ['habitStreak', streakTotal, 'span', 1, 0.2, 1],
  ['ladderStep', XP.trainingLadderStep, 'span', 8, 4, 8],
  // Following the plan.
  ['session', XP.trainingSession, 'week', 7 * 0.85, 4, 7],
  ['honestCall', XP.trainingHonestCall, 'week', 0.7, 0.3, 0.7],
  ['dayKept', XP.trainingDayKept, 'week', 5.5, 3, 7],
  ['weekApproved', XP.trainingWeekApproved, 'week', 0.95, 0.8, 1],
  ['weekKept', XP.trainingWeekKept, 'week', 0.6, 0, 1],
  ['easyWeek', XP.trainingEasyWeek, 'week', 0.25 * 0.75, 0, 0.25],
  ['gymWeek', XP.trainingGymWeek, 'week', 0.7, 0.25, 1],
  ['phaseCompleted', XP.trainingPhaseCompleted, 'year', 4, 3, 4],
  ['seasonCompleted', XP.trainingSeasonCompleted, 'year', 1, 1, 1],
  // Races: preparation and execution, never distance or pace.
  ['racePrep', XP.trainingRacePrep, 'year', 6, 1, 8],
  ['carbLoadDay', XP.trainingCarbLoadDay, 'year', 6, 0, 16],
  ['raceFinished', XP.trainingRaceFinished, 'year', 7, 3, 8],
  ['raceReport', XP.trainingRaceReport, 'year', 6, 1, 8],
  // A race stopped or not started for a good reason pays what a finish pays.
  ['wiseCall', XP.trainingWiseCall, 'span', 1, 1, 1],
  // Badges: 14 from add-winter-arc-nutrition-and-rewards + 41 new.
  ['badges', XP.achievementBonus, 'span', 40, 15, 55],
];

const perDay = (reward, unit, count) => {
  const days = unit === 'week' ? week : unit === 'year' ? year : span;
  return (reward * count) / days;
};
const trainingLines = TRAINING.map(([source, reward, unit, typical, poor, perfect]) => [
  source,
  perDay(reward, unit, typical),
  perDay(reward, unit, poor),
  perDay(reward, unit, perfect),
]);

// ------------------------------------------------------------------ the curve

const cumulative = (level, factor) => {
  let total = 0;
  let band = BASE;
  for (let i = 1; i < level; i += 1) {
    total += band;
    band *= factor;
  }
  return total;
};
const solve = (level, days, daily) => {
  const wanted = days * daily;
  let low = 1.0;
  let high = 1.2;
  for (let i = 0; i < 200; i += 1) {
    const mid = (low + high) / 2;
    if (cumulative(level, mid) < wanted) low = mid;
    else high = mid;
    if (high - low < 1e-12) break;
  }
  return (low + high) / 2;
};
const band = (level, factor) => Math.max(1, Math.round(BASE * Math.pow(factor, level - 1)));
const threshold = (level, factor) => {
  let total = 0;
  for (let i = 1; i < Math.min(level, MAX_LEVEL); i += 1) total += band(i, factor);
  return total;
};
const levelFor = (xp, factor, maxLevel = MAX_LEVEL) => {
  let level = 1;
  let reached = 0;
  while (level < maxLevel) {
    const width = band(level, factor);
    if (xp < reached + width) break;
    reached += width;
    level += 1;
  }
  return level;
};

// ------------------------------------------------------------------ the report

const sum = (lines, column) => lines.reduce((total, line) => total + line[column], 0);
const core = { typical: sum(CORE, 1), poor: sum(CORE, 2), perfect: sum(CORE, 3) };
const training = { typical: sum(trainingLines, 1), poor: sum(trainingLines, 2), perfect: sum(trainingLines, 3) };
const total = {
  typical: core.typical + training.typical,
  poor: core.poor + training.poor,
  perfect: core.perfect + training.perfect,
};
const solved = solve(TARGET_LEVEL, TARGET_DAYS, total.typical);
const FACTOR = Number(solved.toFixed(5)); // the literal for LevelCurve.growthFactor

const fmt = (value, digits = 2) => value.toFixed(digits).padStart(8);
const years = (days) => (days / 365.25).toFixed(2);
const out = [];
const print = (line = '') => out.push(line);

print('XP per day by source            typical     poor  perfect');
for (const line of CORE) print(`  ${line[0].padEnd(28)}${fmt(line[1])} ${fmt(line[2])} ${fmt(line[3])}`);
print(`  ${'= food core'.padEnd(28)}${fmt(core.typical)} ${fmt(core.poor)} ${fmt(core.perfect)}`);
for (const line of trainingLines) print(`  ${('training.' + line[0]).padEnd(28)}${fmt(line[1])} ${fmt(line[2])} ${fmt(line[3])}`);
print(`  ${'= training'.padEnd(28)}${fmt(training.typical)} ${fmt(training.poor)} ${fmt(training.perfect)}`);
print(`  ${'= training experience'.padEnd(28)}${fmt(total.typical)} ${fmt(total.poor)} ${fmt(total.perfect)}`);
print();
print(`solved growth factor: ${solved.toFixed(7)}  ->  LevelCurve.growthFactor = ${FACTOR}`);
const top = threshold(MAX_LEVEL, FACTOR);
print(`XP to level ${MAX_LEVEL}: ${top}`);

const mixed = (typicalWeeks, poorWeeks) => (typicalWeeks * total.typical + poorWeeks * total.poor) / (typicalWeeks + poorWeeks);
const scenarios = [
  ['perfect, every day', total.perfect],
  ['typical, every day', total.typical],
  ['3 typical weeks + 1 poor', mixed(3, 1)],
  ['1 typical week + 1 poor', mixed(1, 1)],
  ['food-first only, typical', core.typical],
  ['food-first only, perfect', core.perfect],
];
print();
print('scenario                        XP/day   days to 150   years');
for (const [name, daily] of scenarios) {
  const days = top / daily;
  print(`  ${name.padEnd(28)}${fmt(daily)} ${fmt(days, 0)}      ${years(days)}`);
}

print();
print('level   threshold     band   typical days (cumulative)   days for this level');
for (const level of [2, 5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 90, 100, 110, 125, 140, 149, 150]) {
  const reached = threshold(level, FACTOR);
  const width = level < MAX_LEVEL ? band(level, FACTOR) : 0;
  print(`${String(level).padStart(5)} ${String(reached).padStart(11)} ${String(width).padStart(8)} ${fmt(reached / total.typical, 1)}                  ${level < MAX_LEVEL ? fmt(width / total.typical, 1) : '       -'}`);
}

// ------------------------------------------------------------------ the checks

const failures = [];
const check = (ok, message) => {
  print(`${ok ? 'ok  ' : 'FAIL'}  ${message}`);
  if (!ok) failures.push(message);
};
print();
const typicalDays = top / total.typical;
const perfectDays = top / total.perfect;
const mixedDays = top / mixed(3, 1);
check(Math.abs(typicalDays - TARGET_DAYS) <= TARGET_DAYS * 0.01, `typical play reaches level 150 in ${typicalDays.toFixed(0)} days (target ${TARGET_DAYS} ±1 %)`);
check(perfectDays >= 2.9 * 365.25, `perfect play needs at least 2.9 years (${years(perfectDays)})`);
check(mixedDays <= 5 * 365.25, `three typical weeks and a poor one stay within 5 years (${years(mixedDays)})`);
const level10 = threshold(10, FACTOR) / total.typical;
check(level10 <= 21, `level 10 within three weeks of typical play (${level10.toFixed(1)} days)`);
const longest = band(MAX_LEVEL - 1, FACTOR) / total.typical;
check(longest <= 56, `no level takes more than 8 weeks of typical play (the last: ${longest.toFixed(1)} days)`);
let worst = null;
for (let level = 2; level <= MAX_LEVEL; level += 1) {
  for (const past of PAST_FACTORS) {
    let old = 0;
    for (let i = 1; i < level; i += 1) old += band(i, past);
    if (threshold(level, FACTOR) > old) worst = `level ${level} vs ${past}`;
  }
}
check(worst === null, `every threshold is at or below the same level's on every earlier curve${worst ? ` (${worst})` : ''}`);
let lowered = null;
for (let xp = 0; xp <= 600000 && lowered === null; xp += 137) {
  const now = levelFor(xp, FACTOR);
  for (const past of PAST_FACTORS) {
    if (Math.min(levelFor(xp, past, 200), MAX_LEVEL) > now) lowered = `${xp} XP under ${past}`;
  }
}
check(lowered === null, `no XP total maps to a lower level than before${lowered ? ` (${lowered})` : ''}`);
// A band within 1e-6 of a .5 boundary could round differently in Swift.
let fragile = null;
for (let level = 1; level < MAX_LEVEL; level += 1) {
  const raw = BASE * Math.pow(FACTOR, level - 1);
  if (Math.abs(raw - Math.floor(raw) - 0.5) < 1e-6) fragile = level;
}
check(fragile === null, `no band sits on a rounding boundary${fragile ? ` (level ${fragile})` : ''}`);

print();
print('literals for the Swift tests (XPBudgetTests, LevelCurveTests):');
print(`  growthFactor ${FACTOR}`);
print(`  coreDailyXP ${core.typical.toFixed(3)}  trainingDailyXP ${training.typical.toFixed(3)}  typicalDailyXP ${total.typical.toFixed(3)}`);
print(`  poorDailyXP ${total.poor.toFixed(3)}  perfectDailyXP ${total.perfect.toFixed(3)}`);
print(`  thresholds ${[2, 5, 10, 25, 50, 75, 100, 125, 150].map((level) => `${level}:${threshold(level, FACTOR)}`).join(' ')}`);
print(`  owner-like ledgers: ${[3000, 4210, 12000].map((xp) => `${xp} XP -> level ${levelFor(xp, FACTOR)} (was ${levelFor(xp, 1.05358, 200)} on 1.05358, ${levelFor(xp, 1.045, 200)} on 1.045)`).join('; ')}`);

console.log(out.join('\n'));
if (CHECK && failures.length > 0) {
  console.error(`\n${failures.length} design rule(s) failed.`);
  process.exit(1);
}

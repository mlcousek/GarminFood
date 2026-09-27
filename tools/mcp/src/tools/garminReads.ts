// garminReads.ts -- the Garmin-direct read tools of wave 2 (task 2.4).
//
// Why it exists: food log, totals, goals, weigh-ins and water already live
// in Garmin Connect, which this PC can read with the vault token (design
// D1), so these answer immediately without the phone. Each tool reads only
// verified routes through GarminClient (registry-gated, loud failures) and
// reshapes Garmin's JSON into a compact answer with units spelled out
// (Garmin sends weights in grams; nutrition "days" follow the account's
// day window, not midnight). Field names come from the shapes recorded in
// docs/garmin-routes.json; anything absent reads as null.
//
// No write lives here: food, weight and water writes from the PC go
// through the phone (owner answer Q2) and arrive with the bridge (waves 5-6).

import { z } from 'zod';
import { defineTool, type ToolDef } from './types.js';
import { arr, checkRange, dateSchema, gramsToKg, num, obj, round, str, type Json } from './shape.js';

const GARMIN_READ = 'Garmin Connect, read-only, answered immediately (the phone is not involved).';

function macros(content: Json | null) {
  return {
    calories: round(num(content?.calories), 0),
    protein: round(num(content?.protein)),
    carbs: round(num(content?.carbs)),
    fat: round(num(content?.fat)),
  };
}

/** One food as foodSearch (and, presumably, recentFoods) returns it. */
export function normalizeFood(raw: unknown) {
  const item = obj(raw);
  const meta = obj(item?.foodMetaData);
  return {
    foodId: str(meta?.foodId),
    name: str(meta?.foodName),
    brand: str(meta?.brandName),
    source: str(meta?.source),
    foodType: str(meta?.foodType),
    servings: arr(item?.nutritionContents).map((s) => {
      const serving = obj(s);
      return {
        servingId: str(serving?.servingId),
        unit: str(serving?.servingUnit),
        numberOfUnits: num(serving?.numberOfUnits),
        ...macros(serving),
        fiber: round(num(serving?.fiber)),
        sugar: round(num(serving?.sugar)),
      };
    }),
  };
}

export const foodSearch = defineTool({
  name: 'food_search',
  title: 'Search Garmin foods',
  summary:
    "Search Garmin Connect's food catalogue (FatSecret + Garmin foods). Returns each food's foodId, name, brand, source " +
    'and its servings with servingId and macros per serving -- the ids a later food log needs. The search is ' +
    'diacritic-sensitive ("mleko" and "mléko" differ): try both spellings for Czech foods. regionCode CZ (the ' +
    "app's default) returns Czech products; US returns the English catalogue. Your own custom foods and Open Food " +
    'Facts search come with the phone bridge; for a barcode use food_lookupBarcode.',
  acts: GARMIN_READ,
  garminOperations: ['foodSearch'],
  inputShape: {
    query: z.string().trim().min(1).max(100).describe('What to search for, e.g. "tvaroh" or "chicken breast".'),
    limit: z.number().int().min(1).max(50).default(20).describe('Results per page, 1-50 (Garmin refuses more than 50).'),
    page: z.number().int().min(0).max(20).default(0).describe('0-based page; use it while moreDataAvailable is true.'),
    regionCode: z.enum(['CZ', 'US']).default('CZ').describe('Catalogue region: CZ (Czech products, default) or US.'),
  },
  async run(args, ctx) {
    const body = obj(
      await ctx.garmin.read('foodSearch', {
        searchExpression: args.query,
        start: args.page * args.limit,
        limit: args.limit,
        regionCode: args.regionCode,
      }),
    );
    return {
      query: args.query,
      regionCode: args.regionCode,
      page: args.page,
      moreDataAvailable: body?.moreDataAvailable === true,
      results: arr(body?.results).map(normalizeFood),
    };
  },
});

export const foodGetDay = defineTool({
  name: 'food_getDay',
  title: "A day's food log",
  summary:
    'Everything logged in Garmin Connect for one nutrition day: each meal with its entries (logId, name, brand, ' +
    "foodId, servingQty, serving, and the macros Garmin reports on the entry), the meal totals, the day's totals " +
    "and the day's calorie/macro goals. The day's calorie total is Garmin's dailyNutritionContent.calories (the " +
    "number Garmin Connect shows), not the wellness summary's consumedKilocalories. Garmin's nutrition day follows " +
    "the account's day window (dayStart/dayEnd), which is not always midnight to midnight. Entries the phone has " +
    'queued but not delivered yet are not in Garmin and do not appear here.',
  acts: GARMIN_READ,
  garminOperations: ['dailyFoodLog'],
  inputShape: {
    date: dateSchema.optional().describe("Nutrition day, YYYY-MM-DD. Default: today on this PC."),
  },
  async run(args, ctx) {
    const date = args.date ?? ctx.today();
    const body = obj(await ctx.garmin.read('dailyFoodLog', { date }));
    const meals = arr(body?.mealDetails).map((m) => {
      const detail = obj(m);
      const meal = obj(detail?.meal);
      return {
        meal: str(meal?.mealName),
        mealId: num(meal?.mealId),
        totals: macros(obj(detail?.mealNutritionContent)),
        entries: arr(detail?.loggedFoods).map((f) => {
          const food = obj(f);
          const meta = obj(food?.foodMetaData);
          const content = obj(food?.nutritionContent);
          return {
            logId: str(food?.logId),
            name: str(meta?.foodName),
            brand: str(meta?.brandName),
            foodId: str(meta?.foodId),
            source: str(meta?.source),
            servingQty: num(food?.servingQty),
            servingId: str(content?.servingId),
            servingUnit: str(content?.servingUnit),
            numberOfUnits: num(content?.numberOfUnits),
            ...macros(content),
            loggedAt: str(food?.logTimestamp),
            loggedBy: str(food?.logSource),
          };
        }),
      };
    });
    const goals = obj(body?.dailyNutritionGoals);
    return {
      date,
      dayWindow: { start: str(body?.dayStartTime), end: str(body?.dayEndTime) },
      totals: macros(obj(body?.dailyNutritionContent)),
      goals: {
        calories: num(goals?.calories),
        adjustedCalories: num(goals?.adjustedCalories),
        protein: num(goals?.protein),
        carbs: num(goals?.carbs),
        fat: num(goals?.fat),
      },
      entryCount: meals.reduce((n, m) => n + m.entries.length, 0),
      meals,
    };
  },
});

export const foodGetRange = defineTool({
  name: 'food_getRange',
  title: 'Daily totals over a date range',
  summary:
    'Per-day calorie and macro totals and goals for up to 31 days in one call (trends, weekly averages). A day with ' +
    'nothing logged comes back as logged: false, not as zeros. Totals only -- use food_getDay for the entries.',
  acts: GARMIN_READ,
  garminOperations: ['calorieSummaryDaily'],
  inputShape: {
    startDate: dateSchema.describe('First day, YYYY-MM-DD.'),
    endDate: dateSchema.describe('Last day, YYYY-MM-DD (at most 31 days after startDate, inclusive).'),
  },
  async run(args, ctx) {
    checkRange(args.startDate, args.endDate, 31);
    const body = obj(await ctx.garmin.read('calorieSummaryDaily', { startDate: args.startDate, endDate: args.endDate }));
    const days = arr(body?.dailyNutritionContents).map((d) => {
      const day = obj(d);
      const content = obj(day?.nutritionContent);
      const goals = obj(day?.nutritionGoals);
      return {
        date: str(day?.mealDate),
        logged: content !== null,
        ...macros(content),
        goalCalories: num(goals?.calories),
        adjustedGoalCalories: num(goals?.adjustedCalories),
      };
    });
    const logged = days.filter((d) => d.logged && d.calories !== null);
    return {
      startDate: args.startDate,
      endDate: args.endDate,
      loggedDays: logged.length,
      averageCaloriesOnLoggedDays: logged.length ? round(logged.reduce((s, d) => s + (d.calories ?? 0), 0) / logged.length, 0) : null,
      days,
    };
  },
});

export const foodRecent = defineTool({
  name: 'food_recent',
  title: 'Recently logged foods (Garmin)',
  summary:
    "Foods Garmin Connect lists as recently logged on this account, as of a date. The route is verified working, " +
    'but its response shape has not been recorded field by field yet (docs/garmin-routes.json), so items that look ' +
    'like search results are normalised like food_search and anything else is passed through as Garmin sent it. ' +
    "The app's own quick picks (usage history) come with the phone bridge snapshot.",
  acts: GARMIN_READ,
  garminOperations: ['recentFoods'],
  inputShape: {
    asOfDate: dateSchema.optional().describe('YYYY-MM-DD. Default: today on this PC.'),
    limit: z.number().int().min(1).max(50).default(20).describe('At most this many items, 1-50.'),
  },
  async run(args, ctx) {
    const asOfDate = args.asOfDate ?? ctx.today();
    const body = await ctx.garmin.read('recentFoods', { asOfDate });
    const container = obj(body);
    const list = Array.isArray(body)
      ? body
      : (Object.values(container ?? {}).find((v) => Array.isArray(v)) as unknown[] | undefined) ?? [];
    const items = list.slice(0, args.limit).map((item) => (obj(item)?.foodMetaData ? normalizeFood(item) : item));
    return {
      asOfDate,
      count: items.length,
      totalAvailable: list.length,
      shapeNote: list.length === 0 && body !== null && !Array.isArray(body) ? `No list found; top-level keys: ${Object.keys(container ?? {}).join(', ')}` : undefined,
      items,
    };
  },
});

function weighIn(raw: unknown) {
  const s = obj(raw);
  const gmt = num(s?.timestampGMT);
  return {
    date: str(s?.calendarDate),
    samplePk: num(s?.samplePk),
    weightKg: gramsToKg(s?.weight),
    bmi: round(num(s?.bmi)),
    bodyFatPercent: round(num(s?.bodyFat)),
    sourceType: str(s?.sourceType),
    timestampUTC: gmt === null ? null : new Date(gmt).toISOString(),
  };
}

export const weightList = defineTool({
  name: 'weight_list',
  title: 'Weigh-ins over a date range',
  summary:
    'Every weigh-in Garmin Connect holds between two dates (newest first), in kilograms, with samplePk (the id a ' +
    'delete needs) and the source (MANUAL for ones typed in the app). Days without a weigh-in are simply absent. ' +
    'Also returns the last weigh-in before the range, if any. At most 366 days per call.',
  acts: GARMIN_READ,
  garminOperations: ['getWeighIns'],
  inputShape: {
    startDate: dateSchema.describe('First day, YYYY-MM-DD.'),
    endDate: dateSchema.describe('Last day, YYYY-MM-DD.'),
  },
  async run(args, ctx) {
    checkRange(args.startDate, args.endDate, 366);
    const body = obj(await ctx.garmin.read('getWeighIns', { startdate: args.startDate, enddate: args.endDate }));
    const weighIns = arr(body?.dailyWeightSummaries).flatMap((d) => arr(obj(d)?.allWeightMetrics).map(weighIn));
    const previous = obj(body?.previousDateWeight);
    return {
      startDate: args.startDate,
      endDate: args.endDate,
      count: weighIns.length,
      averageKg: gramsToKg(obj(body?.totalAverage)?.weight),
      weighIns,
      lastBeforeRange: previous ? weighIn(previous) : null,
    };
  },
});

export const waterGet = defineTool({
  name: 'water_get',
  title: "A day's water intake",
  summary:
    "The day's water total and goal in millilitres as Garmin Connect has them. Garmin keeps a day TOTAL only -- " +
    'there is no per-drink list. Drinks the phone has queued but not delivered yet are not included.',
  acts: GARMIN_READ,
  garminOperations: ['hydrationDaily'],
  inputShape: {
    date: dateSchema.optional().describe('YYYY-MM-DD. Default: today on this PC.'),
  },
  async run(args, ctx) {
    const date = args.date ?? ctx.today();
    const body = obj(await ctx.garmin.read('hydrationDaily', { date }));
    const total = num(body?.valueInML);
    const goal = num(body?.goalInML);
    return {
      date,
      totalMl: total,
      goalMl: goal,
      remainingMl: total !== null && goal !== null ? Math.max(0, goal - total) : null,
      lastEntryLocal: str(body?.lastEntryTimestampLocal),
      sweatLossMl: num(body?.sweatLossInML),
      activityIntakeMl: num(body?.activityIntakeInML),
    };
  },
});

export const goalsGet = defineTool({
  name: 'goals_get',
  title: 'Nutrition and weight goals (Garmin)',
  summary:
    "The account's Garmin nutrition settings for a date: calorie goal, macro goals in grams, the weight goal " +
    '(starting and target weight in kg, loss/gain, weekly rate) and the nutrition day window. This is the Garmin ' +
    "half of goals: the app's local goals (a weight or water override, a standalone plan) live on the phone and " +
    'arrive with the bridge snapshot.',
  acts: GARMIN_READ,
  garminOperations: ['nutritionSettings'],
  inputShape: {
    date: dateSchema.optional().describe('YYYY-MM-DD. Default: today on this PC.'),
  },
  async run(args, ctx) {
    const date = args.date ?? ctx.today();
    const body = obj(await ctx.garmin.read('nutritionSettings', { date }));
    const macroGoals = obj(body?.macroGoals);
    return {
      date,
      effectiveDate: str(body?.effectiveDate),
      calorieGoal: num(body?.calorieGoal),
      macroGoalsGrams: { protein: num(macroGoals?.protein), carbs: num(macroGoals?.carbs), fat: num(macroGoals?.fat) },
      weightGoal: {
        type: str(body?.weightChangeType),
        startingWeightKg: gramsToKg(body?.startingWeight),
        targetWeightKg: gramsToKg(body?.targetWeightGoal),
        weeklyChangeGrams: num(body?.weightChangeRate),
        targetDate: str(body?.targetDate),
      },
      dayWindow: { start: str(body?.dailyTimelineStartTime), end: str(body?.dailyTimelineEndTime) },
      status: str(body?.nutritionStatus),
      localGoals: 'Not available yet: local goals come from the phone bridge snapshot (add-mcp-server wave 5).',
    };
  },
});

export const garminReadTools: ToolDef[] = [foodSearch, foodGetDay, foodGetRange, foodRecent, weightList, waterGet, goalsGet];

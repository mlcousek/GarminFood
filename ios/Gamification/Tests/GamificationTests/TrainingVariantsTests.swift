// TrainingVariantsTests.swift
//
// add-training-gamification-and-150-levels (design D9): the training
// experience's variants of the weekly games.
//   - Boss: the Impatience Imp is judged from the plan's facts (kept plan
//     days, a rest day included), competes like any archetype, is never
//     chosen without those facts or in food-first, and is not needed for
//     the bestiary badge;
//   - Bingo: eight squares judged from the plan's facts, in the pool only
//     in the training experience; the 35 food tasks are untouched;
//   - Journeys: the road trip advances a fixed distance per kept plan day
//     instead of by active calories, and says so.
// Food-first behaviour is asserted unchanged beside each. Everything is
// synthetic: the boss and journey fixtures are the existing September 2026
// ones (BossTestSupport, JourneysTestSupport), the bingo ones October 2030
// (TrainingPlanTestSupport).

import XCTest
import FoodLogCore
@testable import Gamification

final class TrainingVariantsTests: XCTestCase {
    private typealias S = TrainingPlanSignals

    private let calendar = BT.calendar
    private let w39 = BT.week("2026-W39")

    // MARK: - Fixtures

    /// Plan facts for September 2026: of the days 7-20 Sep (the two weeks
    /// before W39) the first `keptBefore` are kept and the rest have a
    /// missed session; from the 21st up to yesterday every day is kept.
    private func septemberPlan(today: Int, keptBefore: Int, from first: Int = 7) -> S {
        var days: [S.Day] = []
        for (index, day) in (first...20).enumerated() {
            let session = index < keptBefore
                ? TP.session("s\(day)", trafficLight: false)
                : TP.session("s\(day)", done: false, trafficLight: false, missed: true)
            days.append(S.Day(day: BT.key(9, day), sessions: [session]))
        }
        if today > 21 {
            for day in 21..<today {
                days.append(S.Day(day: BT.key(9, day), sessions: [TP.session("w\(day)", trafficLight: false)]))
            }
        }
        return S(today: BT.key(9, today), days: days)
    }

    private func context(_ snapshot: SignalsSnapshot, now: Date, isTraining: Bool, plan: S?) -> FeatureContext {
        FeatureContext(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: [],
            isConfirmPath: false,
            isTrainingExperience: isTraining,
            trainingPlan: plan
        )
    }

    // MARK: - Boss: the Impatience Imp

    func testTheImpIsATrainingOnlyArchetype() {
        XCTAssertTrue(BossKind.impatienceImp.isTrainingOnly)
        XCTAssertEqual(BossKind.allCases.filter(\.isTrainingOnly), [.impatienceImp])
        XCTAssertEqual(BossCatalog.training.map(\.kind), [.impatienceImp])
        XCTAssertEqual(BossCatalog.foodKinds.count, 10)
        XCTAssertFalse(BossCatalog.all.contains { $0.kind.isTrainingOnly }, "the bestiary's ten are the food archetypes")

        let imp = BossCatalog.archetype(.impatienceImp)
        XCTAssertFalse(imp.name.isEmpty)
        XCTAssertFalse(imp.goal.isEmpty)
        // Never judged from food data.
        let day = BT.day(BT.date(9, 1), breakfast: true)
        XCTAssertFalse(imp.isConsidered(day))
        XCTAssertFalse(imp.isGood(day, history: BT.snapshot([day], today: BT.date(9, 1)), calendar: calendar))
        XCTAssertEqual(BossFight.hitDays(.impatienceImp, week: w39, snapshot: BT.snapshot([day], today: BT.date(9, 27)), calendar: calendar), [])
    }

    func testThePickerChoosesTheImpWhenKeepingThePlanIsTheWeakestHabit() {
        // Breakfast on 12 of 28 days (43 %) is the weakest food habit.
        let snapshot = BT.snapshot(BT.weakBreakfastWindow(), today: BT.date(9, 21))
        let keys = BossPicker.analysisDayKeys(before: w39, calendar: calendar)

        let weakPlan = septemberPlan(today: 21, keptBefore: 4)
        XCTAssertEqual(BossPicker.trainingAdherence(dayKeys: keys, plan: weakPlan), BossPicker.Adherence(good: 4, considered: 14))
        let pick = BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar, training: weakPlan)
        XCTAssertEqual(pick.kind, .impatienceImp, "4 of 14 plan days kept (29 %) is weaker than breakfast")
        XCTAssertEqual(pick.goodDays, 4)
        XCTAssertEqual(pick.consideredDays, 14)
        XCTAssertEqual(pick.target, 4, "ceil(4/14 * 7) + 2")

        // Keeping the plan well: the weakest FOOD habit is the boss.
        let strongPlan = septemberPlan(today: 21, keptBefore: 12)
        XCTAssertEqual(BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar, training: strongPlan).kind, .breakfastGoblin)
        // Never twice in a row.
        XCTAssertEqual(BossPicker.pick(week: w39, previous: .impatienceImp, snapshot: snapshot, calendar: calendar, training: weakPlan).kind, .breakfastGoblin)
        // Fewer than ten judged plan days: not enough to go by.
        let shortPlan = septemberPlan(today: 21, keptBefore: 0, from: 12)
        XCTAssertEqual(BossPicker.trainingAdherence(dayKeys: keys, plan: shortPlan).considered, 9)
        XCTAssertEqual(BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar, training: shortPlan).kind, .breakfastGoblin)
    }

    func testWithoutThePlanTheImpIsNeverChosen() {
        let snapshot = BT.snapshot(BT.weakBreakfastWindow(), today: BT.date(9, 21))
        XCTAssertEqual(BossPicker.pick(week: w39, previous: nil, snapshot: snapshot, calendar: calendar).kind, .breakfastGoblin)
        let keys = BossPicker.analysisDayKeys(before: w39, calendar: calendar)
        let value = BossPicker.adherence(.impatienceImp, dayKeys: keys, snapshot: snapshot, calendar: calendar)
        XCTAssertEqual(value.considered, 0)
        XCTAssertFalse(BossPicker.isEligible(.impatienceImp, adherence: value, dayKeys: keys, snapshot: snapshot))
    }

    func testKeptPlanDaysBeatTheImp() async {
        var days = BT.weakBreakfastWindow()
        days += BT.history(from: BT.date(9, 21), through: BT.date(9, 25), breakfastOn: { _ in false })
        let snapshot = BT.snapshot(days, today: BT.date(9, 25))
        // Mon 21 - Thu 24 kept; today is Friday.
        let plan = septemberPlan(today: 25, keptBefore: 4)
        XCTAssertEqual(BossFight.trainingHitDays(week: w39, plan: plan, calendar: calendar), [BT.key(9, 21), BT.key(9, 22), BT.key(9, 23), BT.key(9, 24)])

        let feature = WeeklyBossFeature(directory: BT.tempDirectory("boss-imp"))
        let update = await feature.update(context(snapshot, now: BT.date(9, 25), isTraining: true, plan: plan))
        let boss = await feature.currentBoss()
        XCTAssertEqual(boss?.archetype.kind, .impatienceImp)
        XCTAssertEqual(boss?.target, 4)
        XCTAssertEqual(boss?.hits, 4)
        XCTAssertEqual(boss?.outcome, .defeated)
        XCTAssertTrue(boss?.whyLine.contains("Plan days kept") ?? false)
        XCTAssertTrue(update.grants.contains(RewardGrant(key: "boss.defeat.2026-W39", kind: .xp(175))), "150 + 25 for a target of 4: the usual reward")
        XCTAssertTrue(update.grants.contains(RewardGrant(key: "boss.freeze.2026-W39", kind: .streakFreeze)))
        XCTAssertEqual(update.moments.filter { $0.style == .boss }.count, 2, "the intro and the defeat")

        // The bestiary lists it in the training experience.
        let bestiary = await feature.bestiary()
        XCTAssertEqual(bestiary.count, 11)
        XCTAssertEqual(bestiary.filter(\.isDefeated).map(\.archetype.kind), [.impatienceImp])
    }

    func testARestDayIsAHit() {
        // Monday: a session done. Tuesday: a rest day. Wednesday: an
        // unplanned run on a rest day. Thursday: a missed session.
        let plan = S(today: BT.key(9, 25), days: [
            S.Day(day: BT.key(9, 21), sessions: [TP.session("a", trafficLight: false)]),
            S.Day(day: BT.key(9, 22)),
            S.Day(day: BT.key(9, 23), hasUnplannedRun: true),
            S.Day(day: BT.key(9, 24), sessions: [TP.session("b", done: false, trafficLight: false, missed: true)]),
        ])
        XCTAssertEqual(BossFight.trainingHitDays(week: w39, plan: plan, calendar: calendar), [BT.key(9, 21), BT.key(9, 22)])
        XCTAssertEqual(BossFight.trainingHitDays(week: w39, plan: nil, calendar: calendar), [])
    }

    func testFoodFirstNeverMeetsTheImp() async {
        let snapshot = BT.snapshot(BT.weakBreakfastWindow(), today: BT.date(9, 21))
        let plan = septemberPlan(today: 21, keptBefore: 4)
        // The plan's facts are ignored outside the training experience.
        let foodFirst = WeeklyBossFeature(directory: BT.tempDirectory("boss-food"))
        _ = await foodFirst.update(context(snapshot, now: BT.date(9, 21), isTraining: false, plan: plan))
        let boss = await foodFirst.currentBoss()
        XCTAssertEqual(boss?.archetype.kind, .breakfastGoblin)
        let bestiary = await foodFirst.bestiary()
        XCTAssertEqual(bestiary.count, 10)

        // In the training experience without a plan: a food boss as well.
        let noPlan = WeeklyBossFeature(directory: BT.tempDirectory("boss-noplan"))
        _ = await noPlan.update(context(snapshot, now: BT.date(9, 21), isTraining: true, plan: nil))
        let other = await noPlan.currentBoss()
        XCTAssertEqual(other?.archetype.kind, .breakfastGoblin)
    }

    func testTheBestiaryBadgeNeedsOnlyTheFoodArchetypes() {
        let foodOnly = BossState(defeatCount: 10, defeatedIds: BossCatalog.foodKinds.map(\.rawValue))
        XCTAssertTrue(WeeklyBossFeature.badgeIds(state: foodOnly, consumptions: []).contains(BossCatalog.bestiaryBadge))
        let missingOne = BossState(defeatCount: 10, defeatedIds: BossCatalog.foodKinds.dropLast().map(\.rawValue) + [BossKind.impatienceImp.rawValue])
        XCTAssertFalse(WeeklyBossFeature.badgeIds(state: missingOne, consumptions: []).contains(BossCatalog.bestiaryBadge))
    }

    // MARK: - Bingo: the training squares

    func testTheTrainingSquaresAreASeparatePool() {
        let training = BingoTaskCatalog.training
        XCTAssertEqual(training.count, 8)
        XCTAssertEqual(training.filter { $0.difficulty == .easy }.count, 3)
        XCTAssertEqual(training.filter { $0.difficulty == .medium }.count, 3)
        XCTAssertEqual(training.filter { $0.difficulty == .hard }.count, 2)
        let ids = training.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("t-") })
        XCTAssertTrue(training.allSatisfy { $0.scope.isTraining && $0.requirement.isEmpty && $0.family.hasPrefix("training-") })
        XCTAssertTrue(training.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })

        // The food catalog is untouched, and a stored id of either pool resolves.
        XCTAssertEqual(BingoTaskCatalog.all.count, 35)
        XCTAssertTrue(Set(BingoTaskCatalog.all.map(\.id)).isDisjoint(with: ids))
        XCTAssertFalse(BingoTaskCatalog.all.contains { $0.scope.isTraining })
        XCTAssertNotNil(BingoTaskCatalog.task(id: "t-gym-2"))
        XCTAssertNotNil(BingoTaskCatalog.task(id: "e-fruit"))
        XCTAssertFalse(TrainingExperienceAvailability.judgesFixedCalorieTarget(training[0]))
    }

    /// W43 of 2030, on Friday the 25th.
    private func bingoPlan() -> S {
        TP.signals(today: 25, days: [
            TP.day(21, light: .greenLight, expected: ["h1"], done: ["h1"], sessions: [TP.session("mon", trafficLight: false, rpe: true)]),
            TP.day(22, light: .greenLight, expected: ["h1"], done: ["h1"]),
            TP.day(23, light: .greenLight, expected: ["h1"], sessions: [TP.session("gym-1", trafficLight: false, strength: true)]),
            TP.day(24, light: .greenLight, expected: ["h1"], done: ["h1"], sessions: [TP.session("gym-2", trafficLight: false, strength: true)]),
            TP.day(25, light: .greenLight, expected: ["h1"], sessions: [TP.session("fri", done: false, trafficLight: false)]),
        ])
    }

    func testTrainingSquaresAreJudgedFromThePlansFacts() {
        let plan = bingoPlan()
        let week = BT.week("2030-W43")
        let keys = week.dayKeys(calendar: calendar).filter { $0 <= plan.today }
        XCTAssertEqual(keys, (21...25).map { TP.key($0) })

        func day(_ rule: TrainingBingoRule) -> String? {
            BingoEvaluator.trainingCompletionDay(rule, dayKeys: keys, plan: plan)
        }
        XCTAssertEqual(day(.checkInDays(5)), TP.key(25), "the fifth check-in")
        XCTAssertNil(day(.checkInDays(7)))
        XCTAssertEqual(day(.fullHabitDays(1)), TP.key(21))
        XCTAssertEqual(day(.fullHabitDays(3)), TP.key(24), "Monday, Tuesday, Thursday")
        XCTAssertEqual(day(.keptDays(1)), TP.key(21))
        XCTAssertEqual(day(.keptDays(4)), TP.key(24), "a rest day counts")
        XCTAssertNil(day(.keptDays(5)), "Friday's session is still open")
        XCTAssertEqual(day(.strengthSessions(2)), TP.key(24))
        XCTAssertEqual(day(.ratedSessions(1)), TP.key(21))
        XCTAssertNil(day(.ratedSessions(2)))
        XCTAssertNil(day(.keptDays(0)), "a rule without a target is never done")
    }

    func testCardCompletionsWithAndWithoutThePlan() {
        let plan = bingoPlan()
        let week = BT.week("2030-W43")
        let taskIds = ["t-habit-day", "t-day-kept", "t-rpe", "t-checkin-5", BingoTaskCatalog.freeId, "t-habit-days-3", "t-gym-2", "t-checkin-7", "t-days-kept-5"]
        let snapshot = SignalsSnapshot(days: [:], today: plan.today, windowDays: [])

        let done = BingoEvaluator.completions(taskIds: taskIds, week: week, today: plan.today, snapshot: snapshot, calendar: calendar, stored: [:], plan: plan)
        XCTAssertEqual(done, [0: TP.key(21), 1: TP.key(21), 2: TP.key(21), 3: TP.key(25), 5: TP.key(24), 6: TP.key(24)])

        // Without the plan's facts a training square simply stays open.
        let open = BingoEvaluator.completions(taskIds: taskIds, week: week, today: plan.today, snapshot: snapshot, calendar: calendar, stored: [:])
        XCTAssertEqual(open, [:])

        // The whole-day pass (last week's card on Monday) judges every
        // training square once more: the plan's facts can arrive late, and a
        // Sunday rest day is only kept once it is over.
        let settled = BingoEvaluator.completions(taskIds: taskIds, week: week, today: plan.today, snapshot: snapshot, calendar: calendar, stored: [:], onlyCompletedDayTasks: true, plan: plan)
        XCTAssertEqual(settled, done)
        XCTAssertFalse(BingoTaskCatalog.training.contains(where: \.judgesCompletedDaysOnly), "no training square needs the whole-day flag for that")

        // Stored completions are sticky.
        let sticky = BingoEvaluator.completions(taskIds: taskIds, week: week, today: plan.today, snapshot: snapshot, calendar: calendar, stored: [7: TP.key(22)], plan: nil)
        XCTAssertEqual(sticky, [7: TP.key(22)])
    }

    func testOnlyTrainingCardsDrawTrainingSquares() async {
        // Twelve Mondays of autumn 2030: with 8 training squares in a pool of
        // about 40, a card without any is rare and twelve in a row are not
        // going to happen; food-first cards must never hold one.
        let mondays: [(month: Int, day: Int)] = [
            (10, 7), (10, 14), (10, 21), (10, 28), (11, 4), (11, 11), (11, 18), (11, 25), (12, 2), (12, 9), (12, 16), (12, 23),
        ]
        var trainingSquares = 0
        for monday in mondays {
            let now = TestClock.date(2030, monday.month, monday.day)
            let today = TP.key(monday.day, month: monday.month)
            let snapshot = SignalsSnapshot(days: [:], today: today, windowDays: [today])

            let training = WeeklyBingoFeature(directory: BT.tempDirectory("bingo-training"))
            _ = await training.update(context(snapshot, now: now, isTraining: true, plan: S(today: today, days: [S.Day(day: today)])))
            let trainingCard = await training.currentCard(now: now, calendar: calendar)
            XCTAssertEqual(trainingCard?.squares.count, 9)
            trainingSquares += trainingCard?.squares.filter { $0.task?.scope.isTraining == true }.count ?? 0

            let foodFirst = WeeklyBingoFeature(directory: BT.tempDirectory("bingo-food"))
            _ = await foodFirst.update(context(snapshot, now: now, isTraining: false, plan: S(today: today, days: [S.Day(day: today)])))
            let foodCard = await foodFirst.currentCard(now: now, calendar: calendar)
            XCTAssertEqual(foodCard?.squares.count, 9)
            XCTAssertEqual(foodCard?.squares.filter { $0.task?.scope.isTraining == true }.count, 0, "week of \(today)")

            // The training experience without the plan's facts, or with a
            // file that holds no written day: no training square either
            // (nothing could ever tick a kept-day square).
            for emptyPlan in [nil, S(today: today), S(today: today, days: [S.Day(day: today, isInPlan: false)])] {
                let noPlan = WeeklyBingoFeature(directory: BT.tempDirectory("bingo-noplan"))
                _ = await noPlan.update(context(snapshot, now: now, isTraining: true, plan: emptyPlan))
                let noPlanCard = await noPlan.currentCard(now: now, calendar: calendar)
                XCTAssertEqual(noPlanCard?.squares.filter { $0.task?.scope.isTraining == true }.count, 0, "week of \(today)")
            }
        }
        XCTAssertGreaterThan(trainingSquares, 0, "training cards draw from the training squares")
    }

    // MARK: - Journeys: the road trip by kept plan days

    func testTheRoadTripAdvancesByKeptPlanDaysNotByActiveCalories() {
        let snapshot = JR.snapshot([
            JR.day(1, activeKcal: 2_100),
            JR.day(5, activeKcal: 700),
        ], today: 10)
        // Food-first: active kcal / 70 kg.
        let byCalories = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: snapshot).state
        XCTAssertEqual(byCalories.total(.road), 40, accuracy: 0.0001)

        // The training experience: 8 km for each kept plan day, however
        // active the day was -- and nothing for a day that was not kept.
        let kept = [JR.key(1): 8.0, JR.key(2): 8.0, JR.key(9): 8.0]
        let byPlan = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: snapshot, roadKilometresByDay: kept).state
        XCTAssertEqual(byPlan.total(.road), 24, accuracy: 0.0001)
        XCTAssertEqual(JourneyCatalog.kilometresPerKeptPlanDay, 8)

        // Run again: every day is still counted once.
        let again = JourneysEvaluator.evaluate(state: byPlan, snapshot: snapshot, roadKilometresByDay: kept).state
        XCTAssertEqual(again.total(.road), 24, accuracy: 0.0001)
        // An empty map (no kept day) moves nothing.
        let none = JourneysEvaluator.evaluate(state: JourneysState(), snapshot: snapshot, roadKilometresByDay: [:]).state
        XCTAssertEqual(none.total(.road), 0)
    }

    func testTheJourneysFeatureUsesThePlanInTheTrainingExperience() async {
        let snapshot = JR.snapshot([JR.day(8, activeKcal: 3_500)], today: 10)
        let plan = S(today: JR.key(10), days: [
            S.Day(day: JR.key(8), sessions: [TP.session("s", trafficLight: false)]),
            S.Day(day: JR.key(9)),
            S.Day(day: JR.key(10)),
        ])
        let training = JourneysFeature(directory: JR.tempDirectory())
        _ = await training.update(context(snapshot, now: TestClock.date(2026, 9, 10), isTraining: true, plan: plan))
        let trainingJourneys = await training.journeys()
        let road = trainingJourneys.first { $0.kind == .road }
        XCTAssertEqual(road?.total ?? -1, 16, accuracy: 0.0001, "a session day and a rest day; today's rest day is not over")
        XCTAssertEqual(road?.isAvailable, true)
        XCTAssertEqual(road?.definition.conversionLine, JourneyCatalog.trainingRoadConversionLine)
        XCTAssertEqual(road?.definition.milestones, JourneyCatalog.road.milestones, "the same journey")

        // Food-first: the active-calorie rule and its own line.
        let foodFirst = JourneysFeature(directory: JR.tempDirectory())
        _ = await foodFirst.update(context(snapshot, now: TestClock.date(2026, 9, 10), isTraining: false, plan: plan))
        let foodJourneys = await foodFirst.journeys()
        let foodRoad = foodJourneys.first { $0.kind == .road }
        XCTAssertEqual(foodRoad?.total ?? -1, 50, accuracy: 0.0001, "3,500 kcal at the 70 kg fallback")
        XCTAssertEqual(foodRoad?.definition.conversionLine, JourneyCatalog.road.conversionLine)
        XCTAssertNotEqual(JourneyCatalog.trainingRoadConversionLine, JourneyCatalog.road.conversionLine)
        XCTAssertEqual(JourneyCatalog.definition(.protein, trainingRoad: true), JourneyCatalog.definition(.protein), "only the road trip changes")

        // The training experience with a file that holds no written day:
        // nothing could be "kept", so the active-calorie rule stays.
        let noDays = JourneysFeature(directory: JR.tempDirectory())
        _ = await noDays.update(context(snapshot, now: TestClock.date(2026, 9, 10), isTraining: true, plan: S(today: JR.key(10))))
        let noDaysJourneys = await noDays.journeys()
        XCTAssertEqual(noDaysJourneys.first { $0.kind == .road }?.total ?? -1, 50, accuracy: 0.0001)
    }
}

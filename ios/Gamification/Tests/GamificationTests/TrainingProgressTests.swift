// TrainingProgressTests.swift
//
// add-training-gamification-and-150-levels (design D8, D10): the training
// feature paying XP from the plan's facts, the 41 new badges and their
// ladders, the store behind them, and the Progress tab's training section.
//   - TrainingProgressCatalog: ids, ownership, one tier = one badge, the
//     badge count the XP budget assumes;
//   - TrainingRewardsFeature with `context.trainingPlan`: grants, recorded
//     counts, badges, the summary; nothing new on a second run; counts and
//     the habit streak outliving the plan window; one moment for a newly
//     kept week, none on the first run; the secret reveal;
//   - TrainingProgressModel: this week, streaks, ladder rows.
// The rules themselves are in TrainingXPRulesTests; the original five
// ladders in TrainingRewardsTests. Everything is synthetic.

import XCTest
import FoodLogCore
@testable import Gamification

final class TrainingProgressTests: XCTestCase {
    private typealias S = TrainingPlanSignals

    /// W43 (21-27 Oct): every day checked in green, one session done as
    /// planned, the one expected habit done; the week closed and kept.
    private func keptWeekSignals(today: Int = 28, weekClosed: Bool = true, easy: Bool = false) -> S {
        let days = (21...27).map { day in
            TP.day(day, light: .greenLight, expected: ["h1"], done: ["h1"], sessions: [TP.session("s\(day)", trafficLight: false)])
        }
        let week = weekClosed
            ? TP.closedWeek("2030-W43", easy: easy, target: 50, km: 48)
            : S.Week(week: "2030-W43", isClosed: false, isApproved: true, isEasy: easy, runKmTarget: 50, runKm: 48)
        return TP.signals(today: today, days: days, weeks: [week], activeHabits: ["h1"])
    }

    private func xp(_ update: FeatureUpdate, _ key: String) -> Int? {
        for grant in update.grants where grant.key == key {
            if case .xp(let amount) = grant.kind { return amount }
        }
        return nil
    }

    // MARK: - The catalog

    func testTheNewBadgesAreUniqueOwnedAndCounted() {
        let badges = TrainingProgressCatalog.badges
        let ids = badges.map(\.id)
        XCTAssertEqual(ids.count, 41)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(badges.allSatisfy { $0.featureId == TrainingRewardsFeature.id && $0.condition == .featureEvaluated })
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("training.") })
        XCTAssertTrue(Set(ids).isDisjoint(with: TrainingRewardsCatalog.badges.map(\.id)))
        XCTAssertEqual(badges.filter(\.isSecret).map(\.id), [TrainingProgressCatalog.wiseCallBadgeId], "the wise call is the one secret")
        XCTAssertTrue(badges.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })

        // The XP budget's badge line assumes exactly this many.
        XCTAssertEqual(TrainingRewardsCatalog.badges.count + badges.count, TrainingXPBudget.badgeCount)
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        XCTAssertEqual(feature.badges.count, TrainingXPBudget.badgeCount)
    }

    func testEveryTierOfEveryLadderIsABadge() {
        let known = Set((TrainingRewardsCatalog.badges + TrainingProgressCatalog.badges).map(\.id))
        var tierIds: [String] = []
        for ladder in TrainingProgressCatalog.ladders {
            XCTAssertFalse(ladder.tiers.isEmpty, ladder.id)
            XCTAssertEqual(ladder.tiers.map(\.threshold), ladder.tiers.map(\.threshold).sorted(), "\(ladder.id): tiers ascend")
            XCTAssertEqual(ladder.isListed, !ladder.title.isEmpty, "\(ladder.id): a listed ladder has a name")
            tierIds.append(contentsOf: ladder.tiers.map(\.id))
        }
        XCTAssertEqual(Set(tierIds), known, "every tier has a badge and every badge a tier")
        XCTAssertEqual(tierIds.count, Set(tierIds).count)
        let ladderIds = TrainingProgressCatalog.ladders.map(\.id)
        XCTAssertEqual(Set(ladderIds).count, ladderIds.count)
        XCTAssertEqual(TrainingProgressCatalog.ladders.filter(\.isListed).count, 20)
    }

    func testReachedBadgesFollowTheCounts() {
        XCTAssertEqual(TrainingProgressCatalog.reachedBadgeIds(counts: .zero, progress: .zero), [])
        let progress = TrainingProgress(
            setCounts: [
                TrainingSetKey.session.rawValue: 100,
                TrainingSetKey.dayKept.rawValue: 29,
                TrainingSetKey.easyWeek.rawValue: 4,
                TrainingSetKey.wiseCall.rawValue: 1,
                TrainingSetKey.planEdit.rawValue: 9,
                TrainingSetKey.raceGoal.rawValue: 1,
            ],
            habitStreak: TrainingHabitStreak(current: 0, best: 30)
        )
        // The original ladders' counts do not unlock anything here.
        let counts = TrainingRewardCounts(checkInDays: 100, honestCalls: 10, habitTicks: 300, gymWeeks: 12, keptWeeks: 12)
        XCTAssertEqual(Set(TrainingProgressCatalog.reachedBadgeIds(counts: counts, progress: progress)), [
            "training.session-25", "training.session-100",
            "training.easy-week-1", "training.easy-week-4",
            "training.habit-streak-7", "training.habit-streak-30",
            "training.wise-call", "training.plan-edit-1", "training.race-goal",
        ])
    }

    // MARK: - The feature with the plan's facts

    func testThePlansFactsPayXPAndFillTheLadders() async {
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        let update = await feature.update(TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28)))

        XCTAssertEqual(xp(update, "training.week-kept.2030-W43"), XPAward.trainingWeekKept)
        XCTAssertEqual(xp(update, "training.week-approved.2030-W43"), XPAward.trainingWeekApproved)
        XCTAssertEqual(xp(update, "training.session.s21"), XPAward.trainingSession)
        XCTAssertEqual(xp(update, "training.day.2030-10-27"), XPAward.trainingDayKept)
        XCTAssertEqual(xp(update, "training.ladder-step.h1"), XPAward.trainingLadderStep)
        XCTAssertEqual(xp(update, "training.checkin.2030-10-27"), XPAward.trainingCheckIn)
        XCTAssertNil(xp(update, "training.checkin.2030-10-21"), "a week ago: outside the grace window")
        XCTAssertEqual(xp(update, "training.habit-streak.7"), 20, "seven days with the habits done")
        XCTAssertNil(xp(update, "training.habit-streak.30"))
        XCTAssertTrue(update.grants.allSatisfy { $0.key.hasPrefix("training.") })

        XCTAssertEqual(Set(update.unlockBadgeIds), ["training.checkin-7", "training.week-kept-1", "training.habit-streak-7"])
        XCTAssertTrue(Set(update.unlockBadgeIds).isSubset(of: Set(feature.badges.map(\.id))))
        XCTAssertTrue(update.moments.isEmpty, "the first run takes in the whole window: no moments")
        XCTAssertNotNil(update.summary)

        let counts = await feature.counts()
        XCTAssertEqual(counts, TrainingRewardCounts(checkInDays: 7, honestCalls: 0, habitTicks: 7, gymWeeks: 0, keptWeeks: 1))
        let progress = await feature.progress()
        XCTAssertEqual(progress.count(.session), 7)
        XCTAssertEqual(progress.count(.dayKept), 7)
        XCTAssertEqual(progress.count(.approvedWeek), 1)
        XCTAssertEqual(progress.count(.ladderStep), 1)
        XCTAssertEqual(progress.habitStreak, TrainingHabitStreak(current: 7, best: 7))
        XCTAssertEqual(progress.checkInStreak, 7)
        XCTAssertEqual(progress.keptWeekStreak, 1)
    }

    func testASecondRunRecordsAndCelebratesNothingNew() async {
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        let context = TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28))
        let first = await feature.update(context)
        let before = await feature.progress()
        let second = await feature.update(context)
        let after = await feature.progress()
        XCTAssertEqual(second.grants, first.grants, "the same keys are re-emitted; the ledger pays each once")
        XCTAssertEqual(after, before, "nothing is counted twice")
        XCTAssertTrue(second.moments.isEmpty)
        let counts = await feature.counts()
        XCTAssertEqual(counts.checkInDays, 7)
    }

    func testANewlyKeptWeekIsCelebratedOnce() async {
        let directory = TP.tempDirectory()
        let feature = TrainingRewardsFeature(directory: directory)
        // While the week is still open, nothing is kept yet.
        let open = await feature.update(TP.context(plan: keptWeekSignals(today: 27, weekClosed: false), now: TestClock.date(2030, 10, 27)))
        XCTAssertNil(xp(open, "training.week-kept.2030-W43"))
        XCTAssertTrue(open.moments.isEmpty)

        // The plan closes it.
        let closed = await feature.update(TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28)))
        XCTAssertEqual(xp(closed, "training.week-kept.2030-W43"), XPAward.trainingWeekKept)
        XCTAssertEqual(closed.moments.count, 1)
        XCTAssertEqual(closed.moments.first?.title, "Week kept within plan")
        XCTAssertEqual(closed.moments.first?.xpAwarded, XPAward.trainingWeekKept)
        XCTAssertEqual(closed.moments.first?.style, .celebration)

        let again = await feature.update(TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28)))
        XCTAssertTrue(again.moments.isEmpty, "once")

        // A new process: still not celebrated again.
        let reloaded = TrainingRewardsFeature(directory: directory)
        let afterRestart = await reloaded.update(TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28)))
        XCTAssertTrue(afterRestart.moments.isEmpty)
    }

    func testAnEasyWeekRespectedGetsItsOwnMoment() async {
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        _ = await feature.update(TP.context(plan: keptWeekSignals(today: 27, weekClosed: false, easy: true), now: TestClock.date(2030, 10, 27)))
        let closed = await feature.update(TP.context(plan: keptWeekSignals(easy: true), now: TestClock.date(2030, 10, 28)))
        XCTAssertEqual(xp(closed, "training.easy-week.2030-W43"), XPAward.trainingEasyWeek)
        XCTAssertEqual(closed.moments.map(\.title), ["Easy week respected"])
        XCTAssertEqual(closed.moments.first?.xpAwarded, XPAward.trainingWeekKept + XPAward.trainingEasyWeek)
        XCTAssertTrue(closed.unlockBadgeIds.contains("training.easy-week-1"))
    }

    func testCountsOutliveThePlanWindow() async {
        let directory = TP.tempDirectory()
        func week(_ range: ClosedRange<Int>, today: Int) -> S {
            TP.signals(today: today, days: range.map { TP.day($0, sessions: [TP.session("s\($0)", trafficLight: false)]) })
        }
        let first = TrainingRewardsFeature(directory: directory)
        _ = await first.update(TP.context(plan: week(1...7, today: 7)))
        // A later run, in a new process, sees only the next days.
        let second = TrainingRewardsFeature(directory: directory)
        _ = await second.update(TP.context(plan: week(8...14, today: 14)))
        let progress = await second.progress()
        XCTAssertEqual(progress.count(.session), 14)
        XCTAssertEqual(progress.count(.dayKept), 14)
        let ids = await second.store.ids(.session)
        XCTAssertEqual(ids.first, "s1")
        XCTAssertEqual(ids.last, "s14")
    }

    /// The plan file carries about two weeks back; the streak milestones
    /// need 30, 100 and 365 days, so the store keeps its own day records.
    func testTheHabitStreakGrowsAcrossSlidingWindows() async {
        func key(_ offset: Int) -> String {
            offset < 31 ? TP.key(offset + 1) : TP.key(offset - 30, month: 11)
        }
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        var last = FeatureUpdate.empty
        for todayOffset in [13, 20, 27, 34] {
            let days = ((todayOffset - 13)...todayOffset).map { offset in
                S.Day(day: key(offset), habitsExpected: ["h1", "h2"], habitsDone: ["h1", "h2"])
            }
            let signals = S(today: key(todayOffset), days: days)
            last = await feature.update(TP.context(plan: signals))
        }
        let progress = await feature.progress()
        XCTAssertEqual(progress.habitStreak, TrainingHabitStreak(current: 35, best: 35))
        XCTAssertEqual(xp(last, "training.habit-streak.7"), 20)
        XCTAssertEqual(xp(last, "training.habit-streak.30"), 40)
        XCTAssertNil(xp(last, "training.habit-streak.100"))
        XCTAssertTrue(last.unlockBadgeIds.contains("training.habit-streak-30"))
        XCTAssertFalse(last.unlockBadgeIds.contains("training.habit-streak-100"))

        // An un-ticked day inside the window breaks it; the best stays.
        let broken = ((34 - 13)...34).map { offset in
            S.Day(day: key(offset), habitsExpected: ["h1", "h2"], habitsDone: offset == 30 ? [] : ["h1", "h2"])
        }
        _ = await feature.update(TP.context(plan: S(today: key(34), days: broken)))
        let after = await feature.progress()
        XCTAssertEqual(after.habitStreak, TrainingHabitStreak(current: 4, best: 30))
    }

    func testTheWiseCallIsRevealedOnce() async {
        let signals = TP.signals(
            today: 23,
            days: [TP.day(22, light: .redLight, sessions: [TP.session("race", done: false, trafficLight: false, missed: true, race: "race-a")])],
            races: [S.Race(id: "race-a", day: TP.key(22))]
        )
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        let update = await feature.update(TP.context(plan: signals))
        XCTAssertEqual(xp(update, "training.wise-call.race-a"), XPAward.trainingWiseCall)
        XCTAssertTrue(update.unlockBadgeIds.contains(TrainingProgressCatalog.wiseCallBadgeId))
        let reveal = update.moments.filter { $0.style == .secret }
        XCTAssertEqual(reveal.count, 1, "the host shows no generic moment for a secret badge")
        XCTAssertEqual(reveal.first?.message, "Lived to Run Another Day")

        let later = await feature.update(TP.context(plan: signals, unlocked: [TrainingProgressCatalog.wiseCallBadgeId]))
        XCTAssertFalse(later.unlockBadgeIds.contains(TrainingProgressCatalog.wiseCallBadgeId))
        XCTAssertTrue(later.moments.isEmpty)
    }

    /// A device that already used the five original ladders has a
    /// `training.json` without `sets`: its first run with the plan's facts
    /// still takes in the whole window quietly.
    func testAnUpgradedStoreIsNotCelebratedItemByItem() async {
        let directory = TP.tempDirectory()
        let original = TrainingSignals(
            today: TP.key(20),
            currentWeek: "2030-W42",
            days: [TrainingSignals.Day(day: TP.key(20), checkedIn: true, honestLightFollowed: false, strengthSessionsDone: 0, habitTicks: 2)],
            weeks: []
        )
        let before = TrainingRewardsFeature(directory: directory)
        _ = await before.update(TP.context(plan: nil, training: original))
        let stored = await before.counts()
        XCTAssertEqual(stored.checkInDays, 1)

        let after = TrainingRewardsFeature(directory: directory)
        let firstPlanRun = await after.update(TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28)))
        XCTAssertNotNil(firstPlanRun.grants.first { $0.key == "training.week-kept.2030-W43" })
        XCTAssertTrue(firstPlanRun.moments.isEmpty, "the first run with the plan's facts shows no moment")
        let counts = await after.counts()
        XCTAssertEqual(counts.checkInDays, 8, "the stored day and the plan's seven")
    }

    /// A file without a plan yet records nothing, so the plan's arrival is
    /// still the first recording; from then on a new kept week is shown.
    func testAnEmptyPlanDoesNotUseUpTheQuietFirstRun() async {
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        let empty = await feature.update(TP.context(plan: TP.signals(today: 20), now: TestClock.date(2030, 10, 20)))
        XCTAssertTrue(empty.grants.isEmpty)
        XCTAssertTrue(empty.moments.isEmpty)

        let arrival = await feature.update(TP.context(plan: keptWeekSignals(), now: TestClock.date(2030, 10, 28)))
        XCTAssertNotNil(xp(arrival, "training.week-kept.2030-W43"))
        XCTAssertTrue(arrival.moments.isEmpty, "the whole window at once: still quiet")
    }

    func testNothingOutsideTheTrainingExperience() async {
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        let foodFirst = await feature.update(TP.context(plan: keptWeekSignals(), isTraining: false))
        XCTAssertEqual(foodFirst, .empty)
        let noPlan = await feature.update(TP.context(plan: nil))
        XCTAssertEqual(noPlan, .empty)
        let progress = await feature.progress()
        XCTAssertEqual(progress.setCounts, [:], "nothing was recorded")
        let counts = await feature.counts()
        XCTAssertEqual(counts, .zero)
    }

    func testThePlansFactsDecideHonestCallsAndKeptWeeksForTheOriginalLadders() async {
        // The original signals call this week kept; the plan's facts do not
        // (an unplanned run took it over its target). The plan's facts win.
        let old = TrainingSignals(
            today: TP.key(28),
            currentWeek: "2030-W44",
            days: [TrainingSignals.Day(day: TP.key(21), checkedIn: true, honestLightFollowed: true, strengthSessionsDone: 0, habitTicks: 5)],
            weeks: [TrainingSignals.Week(week: "2030-W43", isClosed: true, keptWithinPlan: true, strengthSessionsDone: 2)]
        )
        let plan = TP.signals(
            today: 28,
            days: TP.cleanWeekDays(),
            weeks: [TP.closedWeek("2030-W43", target: 50, km: 52, unplanned: 5)]
        )
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        _ = await feature.update(TP.context(plan: plan, training: old))
        let counts = await feature.counts()
        XCTAssertEqual(counts.keptWeeks, 0)
        XCTAssertEqual(counts.honestCalls, 0)
        XCTAssertEqual(counts.checkInDays, 0, "the plan's facts are the one source when they are there")
    }

    // MARK: - The Progress tab's training section

    func testLadderRows() {
        let counts = TrainingRewardCounts(checkInDays: 31, honestCalls: 0, habitTicks: 300, gymWeeks: 3, keptWeeks: 12)
        let progress = TrainingProgress(
            setCounts: [TrainingSetKey.session.rawValue: 31, TrainingSetKey.dayKept.rawValue: 30, TrainingSetKey.wiseCall.rawValue: 1],
            habitStreak: TrainingHabitStreak(current: 4, best: 8),
            checkInStreak: 5,
            keptWeekStreak: 2
        )
        let model = TrainingProgressModel.build(counts: counts, progress: progress, plan: nil)
        XCTAssertTrue(model.thisWeek.isEmpty, "no plan facts, no week")
        XCTAssertEqual(model.ladders.count, 20)
        XCTAssertEqual(model.ladders.first?.id, "checkin")
        XCTAssertFalse(model.ladders.contains { $0.id == "wise-call" || $0.id == "race-goal" }, "one-offs and the secret are not listed")

        func row(_ id: String) -> TrainingProgressModel.LadderRow? { model.ladders.first { $0.id == id } }
        let sessions = row("session")
        XCTAssertEqual(sessions?.count, 31)
        XCTAssertEqual(sessions?.nextThreshold, 100)
        XCTAssertEqual(sessions?.fraction ?? -1, 6.0 / 75.0, accuracy: 1e-9, "from 25 toward 100")
        XCTAssertEqual(sessions?.detail, "31 · next: 100")
        XCTAssertEqual(sessions?.tiersReached, 1)
        XCTAssertEqual(sessions?.tierCount, 4)
        XCTAssertEqual(sessions?.title, "Sessions as planned")

        let habits = row("habits")
        XCTAssertEqual(habits?.isComplete, true)
        XCTAssertEqual(habits?.fraction, 1)
        XCTAssertEqual(habits?.detail, "300 · complete")
        XCTAssertEqual(habits?.tiersReached, 3)

        let honest = row("honest")
        XCTAssertEqual(honest?.count, 0)
        XCTAssertEqual(honest?.fraction, 0)
        XCTAssertEqual(honest?.detail, "0 · next: 1")

        XCTAssertEqual(row("habit-streak")?.count, 8, "the best streak, not the current one")
        XCTAssertEqual(row("day-kept")?.nextThreshold, 100)

        // The compact card shows the unfinished ladders closest to a badge.
        XCTAssertEqual(model.highlights(limit: 2).map(\.id), ["gym", "session"], "3 of 4 gym weeks, then 31 of 100 sessions")
        XCTAssertFalse(model.highlights(limit: 30).contains { $0.isComplete })
        XCTAssertTrue(model.highlights(limit: 0).isEmpty)

        XCTAssertEqual(model.streaks.map(\.id), ["checkin-streak", "habit-streak", "week-streak"])
        XCTAssertEqual(model.streaks.map(\.value), ["5", "4", "2"])
        XCTAssertEqual(model.tiersReached, model.ladders.reduce(0) { $0 + $1.tiersReached })
        XCTAssertGreaterThan(model.tierCount, model.tiersReached)
    }

    func testThisWeek() {
        let plan = TP.signals(today: 23, days: [
            TP.day(20, light: .greenLight, sessions: [TP.session("last-week", trafficLight: false, strength: true)]),
            TP.day(21, light: .greenLight, sessions: [TP.session("mon")]),
            TP.day(22),
            TP.day(23, light: .amberLight, sessions: [TP.session("gym", trafficLight: false, strength: true), TP.session("run", option: .g)]),
        ])
        let model = TrainingProgressModel.build(counts: .zero, progress: .zero, plan: plan)
        XCTAssertEqual(model.thisWeek.map(\.id), ["checkins", "kept", "gym"])
        XCTAssertEqual(model.thisWeek.map(\.value), ["2/7", "2/7", "1/2"], "Sunday the 20th is last week; today's run was over the amber light")
        XCTAssertTrue(model.thisWeek.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
    }

    func testTheFeatureHandsOutTheModel() async {
        let feature = TrainingRewardsFeature(directory: TP.tempDirectory())
        let before = await feature.progressModel()
        XCTAssertTrue(before.thisWeek.isEmpty)
        XCTAssertEqual(before.ladders.count, 20)
        XCTAssertEqual(before.tiersReached, 0)

        _ = await feature.update(TP.context(plan: keptWeekSignals(today: 27, weekClosed: false), now: TestClock.date(2030, 10, 27)))
        let model = await feature.progressModel()
        XCTAssertEqual(model.thisWeek.map(\.value), ["7/7", "7/7", "0/2"])
        XCTAssertEqual(model.ladders.first { $0.id == "session" }?.count, 7)
        XCTAssertEqual(model.streaks.first { $0.id == "checkin-streak" }?.value, "7")
    }
}

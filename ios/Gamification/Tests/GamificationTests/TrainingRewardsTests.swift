// TrainingRewardsTests.swift
//
// add-winter-arc-nutrition-and-rewards (D1): the training experience's
// rewards and what goes quiet there.
//   - TrainingRewardsFeature: nothing outside the training experience or
//     without the plan's facts; counts accumulate in its store across runs
//     and instances; each ladder unlocks at its threshold, once; no grants.
//   - TrainingExperienceAvailability: fixed-calorie-target challenges,
//     daily challenges and bingo squares are not offered; fasting and
//     weight-goal badges are hidden unless earned (and training badges
//     outside the experience); the active-kcal and fasting records stay
//     quiet; the food-first experience is unchanged.
//   - XPBudget: one optional line, inside the 0.5 % allowance.
// Everything is synthetic.

import XCTest
import FoodLogCore
@testable import Gamification

final class TrainingRewardsTests: XCTestCase {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("training-rewards-\(UUID().uuidString)", isDirectory: true)
    }

    private func context(
        training: TrainingSignals?,
        isTraining: Bool = true,
        unlocked: Set<String> = []
    ) -> FeatureContext {
        FeatureContext(
            snapshot: .empty,
            now: TestClock.date(2030, 10, 23),
            calendar: TestClock.calendar,
            streak: StreakEngine.Status(length: 0, hasLoggedToday: false, isAtRiskToday: false, lastLoggedDay: nil),
            level: 1,
            unlockedBadgeIds: unlocked,
            isConfirmPath: false,
            isTrainingExperience: isTraining,
            training: training
        )
    }

    /// `count` consecutive October days, all checked in with `ticks` ticks.
    private func days(_ range: ClosedRange<Int>, checkedIn: Bool = true, honest: Bool = false, ticks: Int = 0, month: Int = 10) -> [TrainingSignals.Day] {
        range.map { d in
            TrainingSignals.Day(day: String(format: "2030-%02d-%02d", month, d), checkedIn: checkedIn, honestLightFollowed: honest, strengthSessionsDone: 0, habitTicks: ticks)
        }
    }

    private func signals(days: [TrainingSignals.Day], weeks: [TrainingSignals.Week] = []) -> TrainingSignals {
        TrainingSignals(today: "2030-10-23", currentWeek: "2030-W43", days: days, weeks: weeks)
    }

    // MARK: - The feature

    func testNothingOutsideTheTrainingExperienceOrWithoutAPlan() async {
        let feature = TrainingRewardsFeature(directory: tempDirectory())
        let facts = signals(days: days(1...10))
        let foodFirst = await feature.update(context(training: facts, isTraining: false))
        XCTAssertEqual(foodFirst, .empty)
        let noPlan = await feature.update(context(training: nil))
        XCTAssertEqual(noPlan, .empty)
        let counts = await feature.counts()
        XCTAssertEqual(counts, .zero, "nothing was recorded")
    }

    func testLaddersUnlockAtTheirThresholdsAndNeverPayGrants() async {
        let feature = TrainingRewardsFeature(directory: tempDirectory())
        let facts = signals(
            days: days(1...6, ticks: 2) + days(7...7, honest: true, ticks: 13),
            weeks: [
                TrainingSignals.Week(week: "2030-W41", isClosed: true, keptWithinPlan: true, strengthSessionsDone: 2),
                TrainingSignals.Week(week: "2030-W42", isClosed: true, keptWithinPlan: false, strengthSessionsDone: 1),
            ]
        )
        let update = await feature.update(context(training: facts))
        XCTAssertTrue(update.grants.isEmpty, "badges only: the host pays each badge once")
        XCTAssertEqual(Set(update.unlockBadgeIds), [
            "training.checkin-7", "training.honest-1", "training.gym-week-1", "training.habits-25", "training.week-kept-1",
        ])
        let declared = Set(feature.badges.map(\.id))
        XCTAssertTrue(Set(update.unlockBadgeIds).isSubset(of: declared))
        XCTAssertNotNil(update.summary)
    }

    func testAnUnlockedBadgeIsNotRequestedAgain() async {
        let feature = TrainingRewardsFeature(directory: tempDirectory())
        let update = await feature.update(context(training: signals(days: days(1...7)), unlocked: ["training.checkin-7"]))
        XCTAssertFalse(update.unlockBadgeIds.contains("training.checkin-7"))
    }

    func testCountsOutliveTheProjectionWindow() async {
        let directory = tempDirectory()
        let first = TrainingRewardsFeature(directory: directory)
        _ = await first.update(context(training: signals(days: days(1...5))))
        // A later run (a new process) sees only the latest days.
        let second = TrainingRewardsFeature(directory: directory)
        let update = await second.update(context(training: signals(days: days(4...8))))
        let counts = await second.counts()
        XCTAssertEqual(counts.checkInDays, 8, "days 1-8, each once")
        XCTAssertTrue(update.unlockBadgeIds.contains("training.checkin-7"))
    }

    func testAHabitDayKeepsItsLatestCount() async {
        let feature = TrainingRewardsFeature(directory: tempDirectory())
        _ = await feature.update(context(training: signals(days: days(1...1, checkedIn: false, ticks: 3))))
        _ = await feature.update(context(training: signals(days: days(1...1, checkedIn: false, ticks: 2))))
        let counts = await feature.counts()
        XCTAssertEqual(counts.habitTicks, 2, "an un-ticked habit lowers the day again")
    }

    func testAGymWeekNeedsBothSessions() {
        XCTAssertEqual(TrainingRewardsFeature.gymSessionsPerWeek, 2)
        XCTAssertEqual(TrainingRewardsCatalog.reachedBadgeIds(TrainingRewardCounts(checkInDays: 6, honestCalls: 0, habitTicks: 24, gymWeeks: 0, keptWeeks: 0)), [])
        XCTAssertEqual(
            TrainingRewardsCatalog.reachedBadgeIds(TrainingRewardCounts(checkInDays: 100, honestCalls: 10, habitTicks: 300, gymWeeks: 12, keptWeeks: 12)).count,
            TrainingRewardsCatalog.badges.count,
            "every badge has a ladder"
        )
    }

    func testTheSummaryCountsThisWeek() {
        let facts = TrainingSignals(
            today: "2030-10-23",
            currentWeek: "2030-W43",
            days: days(19...23), // Sat 19, Sun 20 are W42
            weeks: [TrainingSignals.Week(week: "2030-W43", isClosed: false, keptWithinPlan: false, strengthSessionsDone: 1)]
        )
        let summary = TrainingRewardsFeature.summary(facts)
        XCTAssertEqual(summary.fraction, 0.5)
        XCTAssertTrue(summary.subtitle.contains("3"), summary.subtitle)
        XCTAssertEqual(TrainingRewardsCatalog.isoWeek(ofDay: "2030-10-20"), "2030-W42")
        XCTAssertEqual(TrainingRewardsCatalog.isoWeek(ofDay: "2030-10-21"), "2030-W43")
    }

    func testTheBadgesAreUniqueAndOwned() {
        let ids = TrainingRewardsCatalog.badges.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(TrainingRewardsCatalog.badges.allSatisfy { $0.featureId == TrainingRewardsFeature.id && $0.condition == .featureEvaluated })
    }

    // MARK: - What goes quiet

    func testFixedCalorieTargetChallengesAreNotOfferedInTraining() {
        let calorieTemplates = ChallengeCatalog.all.filter { TrainingExperienceAvailability.judgesFixedCalorieTarget($0) }
        XCTAssertFalse(calorieTemplates.isEmpty)
        let foodFirst = ChallengeRotationPolicy()
        let training = ChallengeRotationPolicy(isTrainingExperience: true)
        for template in calorieTemplates {
            XCTAssertEqual(training.weight(for: template), 0, template.id)
        }
        for template in ChallengeCatalog.all where !TrainingExperienceAvailability.judgesFixedCalorieTarget(template) {
            XCTAssertEqual(training.weight(for: template), foodFirst.weight(for: template), template.id)
        }
        XCTAssertTrue(calorieTemplates.contains { $0.id == "goal-calories-streak-3" })
    }

    func testDailyCalorieChallengesAreFilteredInTraining() {
        let catalog = DailyChallengeCatalog.all
        XCTAssertEqual(TrainingExperienceAvailability.dailyCatalog(catalog, isTraining: false), catalog)
        let training = TrainingExperienceAvailability.dailyCatalog(catalog, isTraining: true)
        XCTAssertFalse(training.isEmpty)
        XCTAssertLessThan(training.count, catalog.count)
        XCTAssertFalse(training.contains { template in
            switch template.kind {
            case .hitCalorieGoal, .hitAllGoals: return true
            default: return false
            }
        })
    }

    func testBingoCalorieSquaresAreFilteredInTraining() {
        let tasks = BingoTaskCatalog.all
        let training = TrainingExperienceAvailability.bingoTasks(tasks, isTraining: true)
        XCTAssertFalse(training.contains { $0.id == "m-calories-2" })
        XCTAssertLessThan(training.count, tasks.count)
        XCTAssertEqual(TrainingExperienceAvailability.bingoTasks(tasks, isTraining: false), tasks)
    }

    func testBadgeVisibility() {
        let catalog = SportBodyCatalog.badges + TrainingRewardsCatalog.badges
        let fastId = SportBodyCatalog.fastingTiers[0].id
        let weightId = SportBodyCatalog.weightMilestoneIds[0]
        let training = TrainingExperienceAvailability.visibleBadges(catalog, isTraining: true, unlockedIds: [weightId]).map(\.id)
        XCTAssertFalse(training.contains(fastId))
        XCTAssertTrue(training.contains(weightId), "an earned badge stays")
        XCTAssertTrue(training.contains("training.checkin-7"))

        let foodFirst = TrainingExperienceAvailability.visibleBadges(catalog, isTraining: false, unlockedIds: ["training.honest-1"]).map(\.id)
        XCTAssertTrue(foodFirst.contains(fastId))
        XCTAssertFalse(foodFirst.contains("training.checkin-7"))
        XCTAssertTrue(foodFirst.contains("training.honest-1"), "an earned badge stays")
    }

    func testActiveKcalRecordIsQuietInTraining() {
        let baseline = (1...9).map { JR.day($0, activeKcal: 500) }
        let first = RecordsEvaluator.evaluate(state: RecordsState(), snapshot: JR.snapshot(baseline, today: 10))
        let today = JR.day(10, activeKcal: 900)
        let foodFirst = RecordsEvaluator.evaluate(state: first.state, snapshot: JR.snapshot(baseline + [today], today: 10))
        XCTAssertEqual(foodFirst.announced.map(\.id), [.activeKcalDay])

        let training = RecordsEvaluator.evaluate(
            state: first.state,
            snapshot: JR.snapshot(baseline + [today], today: 10),
            quiet: TrainingExperienceAvailability.quietRecords
        )
        XCTAssertTrue(training.announced.isEmpty)
        XCTAssertEqual(training.state.record(.activeKcalDay).current?.value, 900, "the value is still kept")
        XCTAssertEqual(training.state.record(.activeKcalDay).prCount ?? 0, 0)
    }

    // MARK: - XP budget

    func testTheTrainingLineIsOptionalAndInsideTheAllowance() throws {
        let line = try XCTUnwrap(XPBudget.lines.first { $0.source == TrainingRewardsFeature.id })
        XCTAssertTrue(line.optional)
        XCTAssertTrue(XPBudget.isOptional(source: TrainingRewardsFeature.id))
        XCTAssertEqual(XPBudget.optionalMultiplier(enabledOptionalSources: [TrainingRewardsFeature.id]), 1, "alone it fits the 0.5 % allowance")
        XCTAssertLessThanOrEqual(line.expectedDailyXP, XPBudget.optionalPaceAllowance * XPBudget.coreDailyXP)
    }
}

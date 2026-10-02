// TrainingProgressCatalog.swift
//
// add-training-gamification-and-150-levels (design D8): the training
// experience's ladders and the 41 badges this change adds beside the 14 of
// TrainingRewardsCatalog (add-winter-arc-nutrition-and-rewards).
//
// A LADDER is one counted fact with its badge tiers: the five original ones
// (check-ins, honest calls, gym weeks, habit ticks, kept weeks -- their
// badges stay in TrainingRewardsCatalog) and the new ones below. `ladders`
// lists them all in display order: it is what `reachedBadgeIds` unlocks from
// and what the Progress tab's training section shows, so the screen and the
// badges can never disagree about a count.
//
// What is counted is always "the plan was followed" or "it was written
// down", never an amount of training: sessions done WITHIN the plan and the
// morning light, plan days kept (rest days count), easy weeks respected,
// races FINISHED (not how far or how fast). Goal reached and personal
// record are one-off badges with no XP of their own, and stay dormant until
// the plan publishes a race result. The wise call -- a race stopped, or not
// started, for a good reason -- is a secret badge.
//
// Ids are persisted in AchievementStore and are never reused. Display text
// is localized at use (Resources/<lang>.lproj, keys = English source text);
// tier subtitles are count-first ("Sessions done within the plan: 100"), so
// no Czech plural form is needed.
//
// Depends on: AchievementDefinition, SportBodyCatalog.Tier, TrainingSetKey,
// TrainingRewardCounts / TrainingProgress, TrainingRewardsCatalog.
// Depended on by: TrainingRewardsFeature, TrainingProgressModel,
// TrainingXPBudget.badgeCount. Tests: TrainingProgressTests.

import Foundation

/// One counted fact and the badge tiers it unlocks.
public struct TrainingLadder: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        // The five original counts (TrainingRewardCounts).
        case checkInDays
        case honestCalls
        case gymWeeks
        case habitTicks
        case keptWeeks
        /// The ids counted under a `TrainingSetKey`.
        case set(TrainingSetKey)
        /// The best habit streak, in days.
        case habitStreakBest
    }

    public let id: String
    /// The row title on the Progress tab ("Sessions as planned").
    public let title: String
    /// An SF Symbol name.
    public let symbol: String
    public let source: Source
    public let tiers: [SportBodyCatalog.Tier]
    /// One-off and secret ladders are not listed on the Progress tab.
    public let isListed: Bool

    public func count(counts: TrainingRewardCounts, progress: TrainingProgress) -> Int {
        switch source {
        case .checkInDays: return counts.checkInDays
        case .honestCalls: return counts.honestCalls
        case .gymWeeks: return counts.gymWeeks
        case .habitTicks: return counts.habitTicks
        case .keptWeeks: return counts.keptWeeks
        case .set(let key): return progress.count(key)
        case .habitStreakBest: return progress.habitStreak.best
        }
    }
}

public enum TrainingProgressCatalog {
    public static let wiseCallBadgeId = "training.wise-call"

    // MARK: - Tiers

    private static func tiers(_ prefix: String, _ thresholds: [Int]) -> [SportBodyCatalog.Tier] {
        thresholds.map { SportBodyCatalog.Tier(id: "\(prefix)-\($0)", threshold: $0) }
    }

    public static let habitStreakTiers = tiers("training.habit-streak", [7, 30, 100, 365])
    public static let ladderStepTiers = tiers("training.ladder", [3, 6])
    public static let sessionTiers = tiers("training.session", [25, 100, 300, 1_000])
    public static let dayKeptTiers = tiers("training.day-kept", [30, 100, 365])
    public static let easyWeekTiers = tiers("training.easy-week", [1, 4, 12])
    public static let feedbackTiers = tiers("training.feedback", [25, 100])
    public static let gateTiers = tiers("training.gate", [1, 8])
    public static let testTiers = tiers("training.test", [1, 5])
    public static let plannedTiers = tiers("training.planned", [12, 52])
    public static let phaseTiers = tiers("training.phase", [1, 4])
    public static let planEditTiers = tiers("training.plan-edit", [1])
    public static let racePrepTiers = tiers("training.race-prep", [1, 5])
    public static let carbLoadTiers = tiers("training.carb-load", [2, 10])
    public static let raceFinishTiers = tiers("training.race-finish", [1, 5, 15])
    public static let raceReportTiers = tiers("training.race-report", [1, 5])
    public static let raceGoalTiers = [SportBodyCatalog.Tier(id: "training.race-goal", threshold: 1)]
    public static let racePRTiers = [SportBodyCatalog.Tier(id: "training.race-pr", threshold: 1)]
    public static let wiseCallTiers = [SportBodyCatalog.Tier(id: wiseCallBadgeId, threshold: 1)]
    public static let seasonTiers = tiers("training.season", [1, 3])

    // MARK: - Ladders

    /// Every training ladder, in display order: self-monitoring, habits,
    /// following the plan, races.
    public static var ladders: [TrainingLadder] {
        func ladder(
            _ id: String, _ title: String, _ symbol: String,
            _ source: TrainingLadder.Source, _ tiers: [SportBodyCatalog.Tier], listed: Bool = true
        ) -> TrainingLadder {
            TrainingLadder(id: id, title: title, symbol: symbol, source: source, tiers: tiers, isListed: listed)
        }
        return [
            ladder("checkin", String(localized: "Morning check-ins", bundle: .module, comment: "Training ladder name on the Progress tab: days with a morning check-in."),
                   "sunrise.fill", .checkInDays, TrainingRewardsCatalog.checkInTiers),
            ladder("honest", String(localized: "Honest calls", bundle: .module, comment: "Training ladder name: amber or red mornings followed by their easier option."),
                   "ear.fill", .honestCalls, TrainingRewardsCatalog.honestTiers),
            ladder("feedback", String(localized: "Sessions rated", bundle: .module, comment: "Training ladder name: sessions with an effort rating (RPE)."),
                   "gauge.medium", .set(.rated), feedbackTiers),
            ladder("gate", String(localized: "Gate tests", bundle: .module, comment: "Training ladder name: weekly gate tests done."),
                   "checkmark.shield.fill", .set(.gateWeek), gateTiers),
            ladder("test", String(localized: "Tests recorded", bundle: .module, comment: "Training ladder name: test sessions with a recorded result."),
                   "chart.line.uptrend.xyaxis", .set(.test), testTiers),

            ladder("habits", String(localized: "Habits done", bundle: .module, comment: "Training ladder name: habit ticks in total."),
                   "checklist", .habitTicks, TrainingRewardsCatalog.habitTiers),
            ladder("habit-streak", String(localized: "Best habit streak", bundle: .module, comment: "Training ladder name: the longest run of days with the habits done."),
                   "flame.fill", .habitStreakBest, habitStreakTiers),
            ladder("ladder", String(localized: "Ladder steps", bundle: .module, comment: "Training ladder name: steps of the habit ladder unlocked."),
                   "stairs", .set(.ladderStep), ladderStepTiers),

            ladder("session", String(localized: "Sessions as planned", bundle: .module, comment: "Training ladder name: planned sessions done within the plan and the morning light."),
                   "figure.run", .set(.session), sessionTiers),
            ladder("day-kept", String(localized: "Plan days kept", bundle: .module, comment: "Training ladder name: days on which the plan was followed, rest days included."),
                   "calendar", .set(.dayKept), dayKeptTiers),
            ladder("gym", String(localized: "Gym weeks", bundle: .module, comment: "Training ladder name: weeks with both strength sessions done."),
                   "dumbbell.fill", .gymWeeks, TrainingRewardsCatalog.gymTiers),
            ladder("week-kept", String(localized: "Weeks kept", bundle: .module, comment: "Training ladder name: weeks closed within the plan."),
                   "calendar.badge.checkmark", .keptWeeks, TrainingRewardsCatalog.keptWeekTiers),
            ladder("easy-week", String(localized: "Easy weeks respected", bundle: .module, comment: "Training ladder name: deload, taper and recovery weeks kept at or under their target."),
                   "tortoise.fill", .set(.easyWeek), easyWeekTiers),
            ladder("planned", String(localized: "Weeks approved", bundle: .module, comment: "Training ladder name: weeks of the plan that were approved."),
                   "calendar.badge.plus", .set(.approvedWeek), plannedTiers),
            ladder("phase", String(localized: "Phases closed", bundle: .module, comment: "Training ladder name: plan phases closed with a recap."),
                   "book.closed.fill", .set(.phase), phaseTiers),
            ladder("season", String(localized: "Seasons completed", bundle: .module, comment: "Training ladder name."),
                   "trophy.fill", .set(.season), seasonTiers),

            ladder("race-prep", String(localized: "Race preps", bundle: .module, comment: "Training ladder name: race preparations completed before race day."),
                   "doc.text.fill", .set(.racePrep), racePrepTiers),
            ladder("carb-load", String(localized: "Carb-load days", bundle: .module, comment: "Training ladder name: carbohydrate-loading days whose carb goal was met."),
                   "fuelpump.fill", .set(.carbLoadDay), carbLoadTiers),
            ladder("race-finish", String(localized: "Races finished", bundle: .module, comment: "Training ladder name."),
                   "flag.checkered", .set(.raceFinish), raceFinishTiers),
            ladder("race-report", String(localized: "Race reports", bundle: .module, comment: "Training ladder name: race reports written."),
                   "square.and.pencil", .set(.raceReport), raceReportTiers),

            // One-offs: unlocked like any tier, not listed as a ladder.
            ladder("plan-edit", "", "arrow.left.arrow.right", .set(.planEdit), planEditTiers, listed: false),
            ladder("race-goal", "", "target", .set(.raceGoal), raceGoalTiers, listed: false),
            ladder("race-pr", "", "stopwatch.fill", .set(.racePR), racePRTiers, listed: false),
            ladder("wise-call", "", "hand.raised.fill", .set(.wiseCall), wiseCallTiers, listed: false),
        ]
    }

    /// Every NEW badge id the counts reach, in ladder order (the five
    /// original ladders are `TrainingRewardsCatalog.reachedBadgeIds`).
    public static func reachedBadgeIds(counts: TrainingRewardCounts, progress: TrainingProgress) -> [String] {
        let original = Set(TrainingRewardsCatalog.badges.map(\.id))
        var ids: [String] = []
        for ladder in ladders {
            let count = ladder.count(counts: counts, progress: progress)
            for tier in ladder.tiers where count >= tier.threshold && !original.contains(tier.id) {
                ids.append(tier.id)
            }
        }
        return ids
    }

    // MARK: - Badges

    public static var badges: [AchievementDefinition] {
        var result: [AchievementDefinition] = []
        func add(
            _ id: String, _ title: String, _ subtitle: String, _ symbol: String, _ rarity: AchievementRarity,
            category: AchievementCategory = .goalHitting, secret: Bool = false
        ) {
            result.append(AchievementDefinition(
                id: id,
                title: title,
                subtitle: subtitle,
                category: category,
                badgeSymbol: symbol,
                condition: .featureEvaluated,
                visibility: secret ? .secret : nil,
                rarityOverride: rarity,
                featureId: TrainingRewardsFeature.id
            ))
        }

        // Habit streak.
        add("training.habit-streak-7", String(localized: "Habit Week", bundle: .module, comment: "Training badge title: a 7-day habit streak."),
            habitStreakSubtitle(7), "flame.fill", .common, category: .streak)
        add("training.habit-streak-30", String(localized: "Habit Month", bundle: .module, comment: "Training badge title: a 30-day habit streak."),
            habitStreakSubtitle(30), "flame.fill", .uncommon, category: .streak)
        add("training.habit-streak-100", String(localized: "Hundred Days of Habits", bundle: .module, comment: "Training badge title: a 100-day habit streak."),
            habitStreakSubtitle(100), "flame.fill", .epic, category: .streak)
        add("training.habit-streak-365", String(localized: "A Year of Habits", bundle: .module, comment: "Training badge title: a 365-day habit streak."),
            habitStreakSubtitle(365), "crown.fill", .legendary, category: .streak)

        // Ladder steps.
        add("training.ladder-3", String(localized: "Three Rungs Up", bundle: .module, comment: "Training badge title: three steps of the habit ladder unlocked."),
            ladderSubtitle(3), "stairs", .uncommon)
        add("training.ladder-6", String(localized: "Top of the Ladder", bundle: .module, comment: "Training badge title: six steps of the habit ladder unlocked."),
            ladderSubtitle(6), "arrow.up.to.line", .epic)

        // Sessions within the plan and the light.
        add("training.session-25", String(localized: "As Written", bundle: .module, comment: "Training badge title: 25 sessions done as planned."),
            sessionSubtitle(25), "figure.run", .common)
        add("training.session-100", String(localized: "Hundred by the Book", bundle: .module, comment: "Training badge title: 100 sessions done as planned."),
            sessionSubtitle(100), "figure.run", .uncommon)
        add("training.session-300", String(localized: "Reliable Engine", bundle: .module, comment: "Training badge title: 300 sessions done as planned."),
            sessionSubtitle(300), "gearshape.fill", .rare)
        add("training.session-1000", String(localized: "A Thousand as Planned", bundle: .module, comment: "Training badge title: 1,000 sessions done as planned."),
            sessionSubtitle(1_000), "crown.fill", .legendary)

        // Plan days kept.
        add("training.day-kept-30", String(localized: "Month of Discipline", bundle: .module, comment: "Training badge title: 30 plan days kept."),
            dayKeptSubtitle(30), "calendar", .common)
        add("training.day-kept-100", String(localized: "Hundred Good Days", bundle: .module, comment: "Training badge title: 100 plan days kept."),
            dayKeptSubtitle(100), "checkmark.circle.fill", .rare)
        add("training.day-kept-365", String(localized: "A Year on Plan", bundle: .module, comment: "Training badge title: 365 plan days kept."),
            dayKeptSubtitle(365), "checkmark.seal.fill", .epic)

        // Easy weeks respected.
        add("training.easy-week-1", String(localized: "Less Is More", bundle: .module, comment: "Training badge title: one easy (deload) week respected."),
            easyWeekSubtitle(1), "tortoise.fill", .common)
        add("training.easy-week-4", String(localized: "Master of Rest", bundle: .module, comment: "Training badge title: four easy weeks respected."),
            easyWeekSubtitle(4), "bed.double.fill", .rare)
        add("training.easy-week-12", String(localized: "Rested and Ready", bundle: .module, comment: "Training badge title: twelve easy weeks respected."),
            easyWeekSubtitle(12), "moon.zzz.fill", .epic)

        // Sessions rated.
        add("training.feedback-25", String(localized: "Honest Effort", bundle: .module, comment: "Training badge title: 25 sessions rated."),
            feedbackSubtitle(25), "gauge.medium", .common)
        add("training.feedback-100", String(localized: "Knows the Body", bundle: .module, comment: "Training badge title: 100 sessions rated."),
            feedbackSubtitle(100), "waveform.path.ecg", .rare)

        // Gate tests.
        add("training.gate-1", String(localized: "Tested, Not Guessed", bundle: .module, comment: "Training badge title: the first weekly gate test."),
            gateSubtitle(1), "checkmark.shield.fill", .common)
        add("training.gate-8", String(localized: "Gatekeeper", bundle: .module, comment: "Training badge title: eight weekly gate tests."),
            gateSubtitle(8), "lock.shield.fill", .rare)

        // Tests recorded.
        add("training.test-1", String(localized: "Baseline", bundle: .module, comment: "Training badge title: the first recorded test session."),
            testSubtitle(1), "ruler.fill", .common)
        add("training.test-5", String(localized: "Data, Not Feelings", bundle: .module, comment: "Training badge title: five recorded test sessions."),
            testSubtitle(5), "chart.line.uptrend.xyaxis", .rare)

        // Weeks approved.
        add("training.planned-12", String(localized: "Planner", bundle: .module, comment: "Training badge title: twelve weeks of the plan approved."),
            plannedSubtitle(12), "calendar.badge.plus", .uncommon)
        add("training.planned-52", String(localized: "A Year of Plans", bundle: .module, comment: "Training badge title: 52 weeks of the plan approved."),
            plannedSubtitle(52), "calendar.circle.fill", .epic)

        // Phases.
        add("training.phase-1", String(localized: "Chapter Closed", bundle: .module, comment: "Training badge title: a plan phase closed with its recap."),
            phaseSubtitle(1), "book.closed.fill", .uncommon)
        add("training.phase-4", String(localized: "Full Cycle", bundle: .module, comment: "Training badge title: four plan phases closed with their recaps."),
            phaseSubtitle(4), "arrow.triangle.2.circlepath", .epic)

        // The first applied plan change (no ladder: edits are never farmed).
        add("training.plan-edit-1", String(localized: "Plans Change", bundle: .module, comment: "Training badge title: the first plan change made on the phone and applied."),
            String(localized: "Change the plan from the phone and have it applied.", bundle: .module, comment: "Training badge description."),
            "arrow.left.arrow.right", .common)

        // Races: preparation and execution.
        add("training.race-prep-1", String(localized: "Homework Done", bundle: .module, comment: "Training badge title: one race preparation completed before race day."),
            racePrepSubtitle(1), "doc.text.fill", .common)
        add("training.race-prep-5", String(localized: "Always Prepared", bundle: .module, comment: "Training badge title: five race preparations completed before race day."),
            racePrepSubtitle(5), "backpack.fill", .rare)
        add("training.carb-load-2", String(localized: "Tank Full", bundle: .module, comment: "Training badge title: two carb-load days hit."),
            carbLoadSubtitle(2), "fuelpump.fill", .common)
        add("training.carb-load-10", String(localized: "Pasta Party Pro", bundle: .module, comment: "Training badge title: ten carb-load days hit."),
            carbLoadSubtitle(10), "fork.knife", .rare)
        add("training.race-finish-1", String(localized: "Finisher", bundle: .module, comment: "Training badge title: the first race finished."),
            raceFinishSubtitle(1), "flag.checkered", .common)
        add("training.race-finish-5", String(localized: "Five Finish Lines", bundle: .module, comment: "Training badge title: five races finished."),
            raceFinishSubtitle(5), "flag.checkered", .rare)
        add("training.race-finish-15", String(localized: "Seasoned Racer", bundle: .module, comment: "Training badge title: fifteen races finished."),
            raceFinishSubtitle(15), "flag.checkered.2.crossed", .epic)
        add("training.race-report-1", String(localized: "Lessons Learned", bundle: .module, comment: "Training badge title: the first race report written."),
            raceReportSubtitle(1), "square.and.pencil", .common)
        add("training.race-report-5", String(localized: "Chronicler", bundle: .module, comment: "Training badge title: five race reports written."),
            raceReportSubtitle(5), "books.vertical.fill", .rare)
        add("training.race-goal", String(localized: "On Target", bundle: .module, comment: "Training badge title: a race goal reached (a rare one-off)."),
            String(localized: "Reach the goal you set for a race.", bundle: .module, comment: "Training badge description."),
            "target", .epic)
        add("training.race-pr", String(localized: "Personal Best", bundle: .module, comment: "Training badge title: a personal record in a race (a rare one-off)."),
            String(localized: "Set a personal record in a race.", bundle: .module, comment: "Training badge description."),
            "stopwatch.fill", .epic)
        add(wiseCallBadgeId, String(localized: "Lived to Run Another Day", bundle: .module, comment: "Secret training badge title: a race stopped, or not started, because a stop rule said so."),
            String(localized: "Stop a race, or stay home, when the rules say so.", bundle: .module, comment: "Secret training badge description."),
            "hand.raised.fill", .rare, secret: true)

        // Seasons.
        add("training.season-1", String(localized: "Full Season", bundle: .module, comment: "Training badge title: one season completed."),
            seasonSubtitle(1), "trophy.fill", .rare)
        add("training.season-3", String(localized: "Three Seasons Strong", bundle: .module, comment: "Training badge title: three seasons completed."),
            seasonSubtitle(3), "trophy.circle.fill", .legendary)
        return result
    }

    // Count-first wording ("…: 30"), so no Czech plural form is needed.
    private static func habitStreakSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Days in a row with your habits done: %lld", bundle: .module, comment: "Training badge description; %lld = the habit streak needed in days (7, 30, 100 or 365)."), count)
    }

    private static func ladderSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Habit ladder steps unlocked: %lld", bundle: .module, comment: "Training badge description; %lld = steps of the habit ladder needed (3 or 6)."), count)
    }

    private static func sessionSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Sessions done within the plan: %lld", bundle: .module, comment: "Training badge description; %lld = planned sessions done within the plan and the morning light (25, 100, 300 or 1000)."), count)
    }

    private static func dayKeptSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Plan days kept, rest days included: %lld", bundle: .module, comment: "Training badge description; %lld = days on which the plan was followed (30, 100 or 365)."), count)
    }

    private static func easyWeekSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Easy weeks kept at or under their target: %lld", bundle: .module, comment: "Training badge description; %lld = deload, taper or recovery weeks respected (1, 4 or 12)."), count)
    }

    private static func feedbackSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Sessions rated after they were done: %lld", bundle: .module, comment: "Training badge description; %lld = sessions with an effort rating (25 or 100)."), count)
    }

    private static func gateSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Weekly gate tests done: %lld", bundle: .module, comment: "Training badge description; %lld = weeks with a gate test (1 or 8)."), count)
    }

    private static func testSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Test sessions with a recorded result: %lld", bundle: .module, comment: "Training badge description; %lld = test sessions recorded (1 or 5)."), count)
    }

    private static func plannedSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Weeks of the plan approved: %lld", bundle: .module, comment: "Training badge description; %lld = approved weeks (12 or 52)."), count)
    }

    private static func phaseSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Phases closed with a recap: %lld", bundle: .module, comment: "Training badge description; %lld = plan phases closed with their recap (1 or 4)."), count)
    }

    private static func racePrepSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Race preps completed before race day: %lld", bundle: .module, comment: "Training badge description; %lld = race preparations completed in time (1 or 5)."), count)
    }

    private static func carbLoadSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Carb-load days with the carb goal met: %lld", bundle: .module, comment: "Training badge description; %lld = carbohydrate-loading days hit (2 or 10)."), count)
    }

    private static func raceFinishSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Races finished: %lld", bundle: .module, comment: "Training badge description; %lld = races finished (1, 5 or 15)."), count)
    }

    private static func raceReportSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Race reports written: %lld", bundle: .module, comment: "Training badge description; %lld = race reports written (1 or 5)."), count)
    }

    private static func seasonSubtitle(_ count: Int) -> String {
        String(format: String(localized: "Seasons completed: %lld", bundle: .module, comment: "Training badge description; %lld = seasons completed (1 or 3)."), count)
    }
}

// XPAward+Training.swift
//
// add-training-gamification-and-150-levels (design D3, D7): every XP amount
// the training experience pays, in one place, like XPAward+Features.swift
// for the food features.
//
// The one principle behind the numbers: reward FOLLOWING THE PLAN and honest
// self-monitoring, never doing more than the plan. So there is no amount
// here per kilometre, per minute, per extra session or per hard day in a
// row; a rest day pays what a training day pays (`trainingDayKept`), and a
// race stopped for a good reason pays what a finish pays
// (`trainingWiseCall == trainingRaceFinished`). Races pay a FIXED amount --
// never by distance, pace or priority.
//
// Each constant feeds one sub-line of `TrainingXPBudget` (constant x assumed
// frequency), whose sum is the `training` line of `XPBudget`, and
// `LevelCurve.growthFactor` is solved from the whole table. Changing a value
// here fails `XPBudgetTests` until the factor is re-solved (the failure
// prints the new literal) -- and `tools/level-curve-model.mjs` mirrors these
// numbers, so change them there too.
//
// Depends on: XPAward (XPStore.swift). Depended on by: TrainingXPRules,
// TrainingXPBudget, the app's level screen.

import Foundation

extension XPAward {
    // MARK: Honest self-monitoring

    /// Once per day with a morning check-in.
    public static let trainingCheckIn = 10
    /// Once per day whose check-in carried a pain answer (asked only while
    /// the plan's pain mode is on; "nothing hurts" is an answer too).
    public static let trainingPainLogged = 2
    /// Once per done session with an RPE.
    public static let trainingSessionRPE = 2
    /// Once per done session with a note.
    public static let trainingSessionNote = 1
    /// Once per ISO week with a fresh gate test.
    public static let trainingGateTest = 15
    /// Once per test session with a recorded result.
    public static let trainingTestRecorded = 20

    // MARK: Habits

    /// Per habit done on a day (at most `trainingHabitTickCapPerDay`).
    public static let trainingHabitTick = 2
    public static let trainingHabitTickCapPerDay = 8
    /// Once per day with every expected habit done.
    public static let trainingHabitFullDay = 6
    /// One-offs when the best habit streak reaches a milestone.
    public static let trainingHabitStreakMilestones: [(days: Int, xp: Int)] = [
        (7, 20), (30, 40), (100, 80), (365, 200),
    ]
    /// Once per habit that became an active ladder step.
    public static let trainingLadderStep = 40

    // MARK: Following the plan

    /// Once per planned session done within the plan and the morning light.
    public static let trainingSession = 20
    /// Once per day an amber or red morning was followed by its option.
    public static let trainingHonestCall = 8
    /// Once per kept plan day -- a rest day included.
    public static let trainingDayKept = 8
    /// Once per approved week.
    public static let trainingWeekApproved = 10
    /// Once per closed week kept within plan.
    public static let trainingWeekKept = 80
    /// On top, for a kept deload / taper / recovery / transition week at or
    /// under its run target.
    public static let trainingEasyWeek = 30
    /// Once per week with both strength sessions done.
    public static let trainingGymWeek = 20
    /// Once per phase closed with a recap.
    public static let trainingPhaseCompleted = 150
    /// Once per season whose period ended.
    public static let trainingSeasonCompleted = 300

    // MARK: Races (fixed amounts: never distance, pace or priority)

    public static let trainingRacePrep = 40
    /// Per carb-load day whose carbohydrate goal was met.
    public static let trainingCarbLoadDay = 15
    /// Dormant until the vault says whether the fuel plan was followed.
    public static let trainingRaceFuelPlan = 30
    public static let trainingRaceFinished = 100
    public static let trainingRaceReport = 60
    /// A race stopped, or not started, for a good reason pays what a finish
    /// pays -- so there is never a reason to push through.
    public static let trainingWiseCall = 100
}

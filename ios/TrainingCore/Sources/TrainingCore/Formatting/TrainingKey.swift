// TrainingKey.swift
//
// Every string TrainingCore shows, as a case whose raw value is the English
// text -- the key in Resources/<lang>.lproj/Localizable.strings(dict)
// (TrainingText.swift). Generated together with those four tables from one
// list, so a case, its English and its Czech cannot drift apart;
// TrainingTextTests resolves every case in both languages. Plural keys
// (`.stringsdict`) are the English "other" form.
//
// Add a string: add the case here and the entry to BOTH lproj folders (en
// and cs), with the same format specifiers.
//
// Depended on by: TrainingText and every formatter and builder.

import Foundation

public enum TrainingKey: String, CaseIterable, Sendable {
    /// Sport name.
    case sportRun = "Run"
    /// Sport name (cycling).
    case sportRide = "Ride"
    /// Sport name.
    case sportWalk = "Walk"
    /// Sport name.
    case sportSwim = "Swim"
    /// Sport name, also the strength session type.
    case sportStrength = "Strength"
    /// Sport name, also the mobility session type.
    case sportMobility = "Mobility"
    /// Sport name.
    case sportWinter = "Winter sport"
    /// Sport name for anything else.
    case sportOther = "Other sport"
    /// Session type.
    case typeEasy = "Easy"
    /// Session type (long run).
    case typeLong = "Long"
    /// Session type.
    case typeTempo = "Tempo"
    /// Session type.
    case typeThreshold = "Threshold"
    /// Session type.
    case typeIntervals = "Intervals"
    /// Session type.
    case typeVO2max = "VO2max"
    /// Session type.
    case typeCross = "Cross-training"
    /// Session type for anything else.
    case typeOther = "Other"
    /// Session type, week kind and workout step (easy recovery).
    case recovery = "Recovery"
    /// Session type, week kind and the race badge.
    case race = "Race"
    /// Badge on a test session.
    case badgeTest = "Test"
    /// Session slot: before noon.
    case slotAM = "Morning"
    /// Session slot: after noon.
    case slotPM = "Afternoon"
    /// Session status.
    case statusPlanned = "Planned"
    /// Session status.
    case statusDone = "Done"
    /// Session status.
    case statusMissed = "Missed"
    /// Session status.
    case statusSkipped = "Skipped"
    /// Week row: done, with the option letter (G, A or R).
    case doneWithOption = "Done · %@"
    /// Marks today's date in the plan.
    case today = "Today"
    /// Week status: not yet approved.
    case weekProposed = "Proposed"
    /// Week status.
    case weekApproved = "Approved"
    /// Week status: finished.
    case weekClosed = "Closed"
    /// Week kind in the outline.
    case kindBuild = "Build"
    /// Week kind in the outline: an easier week.
    case kindDeload = "Deload"
    /// Week kind in the outline: before a race.
    case kindTaper = "Taper"
    /// Week kind in the outline.
    case kindTransition = "Transition"
    /// What option G means.
    case optionPlanned = "Planned session"
    /// What option A means.
    case optionEasier = "Easier"
    /// What option R means (no running).
    case optionAlternative = "Alternative"
    /// VoiceOver for an option card: letter, meaning, label.
    case a11yOption = "Option %@, %@: %@"
    /// VoiceOver: this option matches the morning traffic light.
    case a11yMatchesLight = "Matches your morning check"
    /// Session detail: the option that was done, letter and meaning.
    case doneOptionMeaning = "Option %@ · %@"
    /// Session detail: done, but the app can't tell which option.
    case optionNotIdentified = "Option not identified"
    /// The option's state on the watch.
    case watchLine = "Watch: %@"
    /// Morning traffic light.
    case lightGreen = "Green"
    /// Morning traffic light.
    case lightAmber = "Amber"
    /// Morning traffic light.
    case lightRed = "Red"
    /// The morning traffic light of a day.
    case lightLine = "Morning check: %@"
    /// A carb-loading day before a race: grams and grams per kilogram.
    case fuelCarbLoad = "Carb load: %@ g carbs (%@ g/kg)"
    /// A carb-loading day, grams only.
    case fuelCarbLoadGrams = "Carb load: %@ g carbs"
    /// A carb-loading day, grams per kilogram only.
    case fuelCarbLoadPerKg = "Carb load: %@ g/kg"
    /// Carbohydrate to take per hour during a session.
    case fuelPerHour = "Fuel: %@ g carbs/h"
    /// Race countdown: the race is today.
    case countdownToday = "today"
    /// Race countdown: the race is tomorrow.
    case countdownTomorrow = "tomorrow"
    /// Race countdown for an approximate date.
    case countdownAboutToday = "about today"
    /// Race countdown for an approximate date.
    case countdownAboutTomorrow = "about tomorrow"
    /// Race countdown. Plural.
    case countdownInDays = "in %lld days"
    /// Race countdown for an approximate date. Plural.
    case countdownInAboutDays = "in about %lld days"
    /// A race on this day; the race's name.
    case raceDayLine = "Race day: %@"
    /// Freshness line: the day the plan describes.
    case noticePlanAsOf = "Plan as of %@"
    /// Freshness line: the plan has no date.
    case noticePlanDateUnknown = "Plan date unknown"
    /// Freshness line: no sync for a day or more. Plural.
    case noticeLastSynced = "Last synced %lld days ago"
    /// The latest plan file could not be read.
    case noticeUnreadable = "Couldn't read the latest plan"
    /// The latest plan file could not be read; the date of the plan still shown.
    case noticeUnreadableShowing = "Couldn't read the latest plan; showing %@"
    /// The plan file is newer than this app version. The app name stays in English.
    case noticeUpdateApp = "Update Jirka's Arc to read this plan"
    /// Quiet hint that a newer app reads more.
    case noticeNewerVersion = "A newer app version reads more of your plan"
    /// Empty state while the first plan downloads.
    case stateFetchingTitle = "Fetching your plan…"
    /// Empty state while the first plan downloads.
    case stateFetchingMessage = "The first time takes a moment."
    /// Empty state: the vault hasn't published a plan.
    case stateNotGeneratedTitle = "No plan data yet"
    /// Empty state: the vault hasn't published a plan.
    case stateNotGeneratedMessage = "Your vault hasn't published it."
    /// Empty state: no training phase.
    case stateNoActivePlanTitle = "No active plan"
    /// Empty state: no training phase.
    case stateNoActivePlanMessage = "Your vault has no training phase right now."
    /// Nothing planned on a day.
    case stateRestDayTitle = "Rest day"
    /// Nothing planned on a day.
    case stateRestDayMessage = "Nothing is planned for this day."
    /// The week exists only in the outline.
    case stateWeekNotWrittenTitle = "Week not written yet"
    /// A week outside every phase.
    case stateNoPlanWeekTitle = "No plan for this week"
    /// A week outside every phase.
    case stateNoPlanWeekMessage = "This week is outside every phase of the season."
    /// Plan week view of an outline-only week.
    case weekNotWrittenMessage = "Sessions for this week aren't written yet"
    /// ISO week number, short (Czech: T for tyden).
    case weekNumber = "W%lld"
    /// ISO week number and its date range.
    case weekLabel = "W%lld · %@"
    /// Week header: kilometres run, no target.
    case weekRun = "Run %@ km"
    /// Week header: kilometres run of the target.
    case weekRunOfTarget = "Run %@ of %@ km"
    /// Week header: the week's running target.
    case weekRunTarget = "Run target %@ km"
    /// Week header: sessions done, missed, of planned.
    case weekSessionsDoneMissed = "%lld done · %lld missed of %lld"
    /// Week header of a week that hasn't started.
    case weekSessionsPlanned = "Sessions planned: %lld"
    /// An activity that matched no planned session.
    case unplanned = "Unplanned"
    /// Workout step.
    case stepWarmUp = "Warm-up"
    /// Workout step.
    case stepCoolDown = "Cool-down"
    /// Workout step: rest between exercises.
    case stepRest = "Rest"
    /// Workout step: an isometric hold.
    case stepHold = "Hold"
    /// Interval step: the recovery after each repeat, a duration.
    case stepRecoveryAfter = "%@ recovery"
    /// The workout has no steps in the plan.
    case stepsNotPublished = "Steps not published"
    /// Exercise side.
    case sideEach = "each side"
    /// Exercise side.
    case sideLeft = "left"
    /// Exercise side.
    case sideRight = "right"
    /// Exercise side.
    case sideBoth = "both sides"
    /// How the done option was recognised.
    case recognisedSport = "Inferred from the sport"
    /// How the session was recognised as done.
    case recognisedTest = "Recorded as a test result"
    /// How the activity was matched to the session.
    case recognisedDateSport = "Matched by date and sport"
    /// Where a session came from: a date.
    case originMovedFrom = "Moved from %@"
    /// Where a session came from.
    case originRule = "Changed by a rule"
    /// Where a session came from.
    case originChanged = "Changed after planning"
    /// A test before it was done.
    case testNoResult = "No result yet"
    /// The previous result of a test, with its unit.
    case testPrevious = "Previous %@"
    /// Test result against the previous one.
    case testImproved = "Improved"
    /// Test result against the previous one.
    case testWorse = "Worse"
    /// Test result against the previous one.
    case testUnchanged = "Unchanged"
    /// Habit ladder state.
    case habitActive = "Active"
    /// Habit ladder state.
    case habitNext = "Next"
    /// Habit ladder state.
    case habitLater = "Later"
    /// A habit's 14-day adherence has no data.
    case habitNotRecorded = "not recorded yet"
    /// A habit's 14-day adherence: done of expected and percent.
    case habitWindow = "%lld of %lld · %lld %%"
    /// A habit's adherence covers fewer days than the window. Plural.
    case habitRecordedDays = "over %lld recorded days"
    /// A habit done today, of the times expected.
    case habitTodayCount = "Today: %lld of %lld"
    /// The adherence gate for the next habit.
    case habitGate = "Gate: %lld %% · %lld-day window"
    /// The active habit met its gate.
    case habitGateMet = "Gate met: the next habit can start at your Sunday review"
    /// When a habit started: a date.
    case habitStarted = "Started %@"
    /// When a habit can start: a date.
    case habitEarliest = "Earliest start %@"
    /// The plan has no habit ladder.
    case habitsNone = "No habits in this plan"
    /// Habit schedule.
    case scheduleEveryDay = "Every day"
    /// Habit schedule: times a day.
    case scheduleTimesPerDay = "%lld× a day"
    /// Habit schedule.
    case scheduleOnceAWeek = "Once a week"
    /// Habit schedule: times a week.
    case scheduleTimesPerWeek = "%lld× a week"
    /// Habit schedule. Plural.
    case scheduleEveryNWeeks = "every %lld weeks"
    /// Habit schedule: after these session types.
    case scheduleWithSessions = "After sessions: %@"

    /// Keys that live in `.stringsdict` (plural forms).
    public var isPlural: Bool {
        switch self {
        case .countdownInDays, .countdownInAboutDays, .noticeLastSynced, .habitRecordedDays, .scheduleEveryNWeeks: return true
        default: return false
        }
    }
}

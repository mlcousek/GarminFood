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
    /// Watch push: the option is on the training calendar (not necessarily on the watch yet).
    case watchScheduled = "On Garmin calendar"
    /// Watch push: the option waits to be sent.
    case watchPending = "Not on Garmin calendar yet"
    /// Watch push: the last attempt failed.
    case watchFailed = "Couldn't send to Garmin calendar"
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
    /// How the done option was recognised: the option letter at the start of the activity's name.
    case recognisedName = "Recognised from the activity's name"
    /// How the session was recognised as done.
    case recognisedTest = "Recorded as a test result"
    /// How the activity was matched to the session.
    case recognisedDateSport = "Matched by date and sport"
    /// Where a session came from: a date.
    case originMovedFrom = "Moved from %@"
    /// Session detail: the session swapped days with another; its old date.
    case originSwappedFrom = "Swapped from %@"
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
    /// add-training-checkins: the check-in row on Today's training card.
    case checkInTitle = "Morning check-in"
    /// VoiceOver for a check-in button: the light and what its option means.
    case a11yCheckInButton = "Morning check-in %@, %@"
    /// A check-in, tick, RPE or note is stored on the phone, not uploaded yet.
    case deliverySaved = "Saved on phone"
    /// A check-in, tick, RPE or note has been uploaded to the vault.
    case deliverySent = "Sent"
    /// The vault has read the event (its projection acknowledged it).
    case deliveryReceived = "Received by the vault"
    /// Reminder title before a run day's check-in.
    case reminderCheckInTitle = "How do you feel today?"
    /// Reminder body before a run day's check-in.
    case reminderCheckInBody = "Check in green, amber or red before you run."
    /// Reminder title for the evening habits.
    case reminderHabitsTitle = "Evening habits"
    /// Reminder body for the evening habits.
    case reminderHabitsBody = "Tick today's habits before bed."

    /// Season screen: the vault has published no season.
    case seasonNoneTitle = "No season yet"
    /// Season screen: the vault has published no season.
    case seasonNoneMessage = "Your vault hasn't published a season."
    /// Season timeline: a stretch of the season no phase covers.
    case seasonNoPhase = "No phase planned"
    /// How many weeks a phase has. Plural.
    case weeksCount = "%lld weeks"
    /// A race in the past. Plural.
    case countdownDaysAgo = "%lld days ago"
    /// A race with an approximate date in the past. Plural.
    case countdownAboutDaysAgo = "about %lld days ago"
    /// The season's hero race (its main goal).
    case raceHero = "Hero race"
    /// A race no training phase prepares for yet.
    case raceUnanchored = "No phase covers this race yet"
    /// Race priority A (a goal race).
    case racePriorityA = "A race"
    /// Race priority B.
    case racePriorityB = "B race"
    /// Race priority C (a training race).
    case racePriorityC = "C race"
    /// Race checkpoint: food and drink.
    case aidFull = "Full aid"
    /// Race checkpoint: water only.
    case aidWater = "Water"
    /// Race checkpoint: nothing to eat or drink.
    case aidNone = "No aid"
    /// Training phase kind.
    case phaseKindBase = "Base"
    /// Training phase kind: race-specific preparation.
    case phaseKindSpecific = "Specific"
    /// Training phase status: not started, still being written.
    case phaseDraft = "Draft"
    /// Phase header: the phase is over.
    case phaseFinished = "Finished"
    /// Phase header: a phase that hasn't started. Plural.
    case phaseStartsIn = "Starts in %lld days"
    /// Phase header: which week of the phase today is.
    case phaseWeekOf = "Week %lld of %lld"
    /// Phase header: days to the phase's end. Plural.
    case phaseDaysLeft = "%lld days left"
    /// Phase weeks: a past week the plan file no longer carries, so its distance isn't known here.
    case weekOutsideWindow = "Not in the app's window"
    /// Phase screen of a phase other than the current one.
    case phaseRestricted = "Goals and rules are published for the current phase only."
    /// Phase recap: kilometres run against the plan, over the weeks with known distance.
    case recapRun = "Ran %@ of %@ km planned"
    /// Phase recap: weeks whose distance was within ten percent of the target.
    case recapWithinTen = "%lld of %lld weeks within 10 %% of target"
    /// Phase recap: the week with the most kilometres and its ISO week number.
    case recapBiggest = "Biggest week: %@ km (W%lld)"
    /// Race: start time.
    case raceStart = "Start %@"
    /// Race or checkpoint: the time limit (duration and clock time).
    case raceCutoff = "Cutoff %@"
    /// A race checkpoint without a name.
    case checkpointNumber = "Checkpoint %lld"
    /// Race checkpoint: the planned arrival (duration and clock time).
    case checkpointTarget = "Target %@"
    /// Race checkpoint: time between the planned arrival and the cutoff.
    case checkpointBuffer = "Buffer %@"
    /// Race checkpoint: the planned arrival is after the cutoff by this much.
    case checkpointOverCutoff = "%@ after the cutoff"
    /// Race fuel: carbohydrate per hour.
    case raceFuelCarbs = "%@ g carbs/h"
    /// Race fuel: how often to eat.
    case raceFuelEvery = "Every %lld min"
    /// Race fuel: fluid per hour.
    case raceFuelFluid = "%@ ml fluid/h"
    /// Race fuel: carbohydrate over the planned finish time.
    case raceFuelTotalCarbs = "About %@ g carbs to the finish"
    /// Race fuel: fluid over the planned finish time, in litres.
    case raceFuelTotalFluid = "About %@ l fluid to the finish"
    /// Carb load on the race day itself.
    case raceDay = "Race day"
    /// Carb load: days before the race. Plural.
    case carbLoadDaysBefore = "%lld days before"
    /// Carb load: days after the race. Plural.
    case carbLoadDaysAfter = "%lld days after"
    /// Carb load day: grams of carbohydrate and grams per kilogram.
    case carbLoadAmount = "%@ g carbs · %@ g/kg"
    /// Carb load day: grams of carbohydrate.
    case carbLoadGrams = "%@ g carbs"
    /// Carb load day: grams of carbohydrate per kilogram of body weight.
    case carbLoadPerKg = "%@ g/kg"
    /// Carb load day without an amount.
    case carbLoadUnknown = "Amount not set"
    /// Carb load: the grams come from the plan file.
    case carbLoadFromPlan = "From your plan"
    /// Carb load: grams worked out from the body weight in the plan.
    case carbLoadEstimate = "Estimated for %@ kg"
    /// Carb load: grams can't be worked out without a body weight.
    case carbLoadNoWeight = "No body weight in the plan to count grams"
    /// Race gear that is required.
    case gearMandatory = "Mandatory"
    /// Race gear that is not required.
    case gearOptional = "Optional"
    /// Race screen: the race has no preparation yet.
    case raceStub = "Race prep not written yet"
    /// Race screen: the vault has a report for the race.
    case raceReported = "Race report written"
    /// Statistics scope: the whole season.
    case statsWholeSeason = "Whole season"
    /// Statistics: share of the sessions due so far that were done (a percentage).
    case statsAdherence = "Done %@ of the sessions due so far"
    /// Statistics: nothing has been due in the scope yet.
    case statsNoneDue = "No sessions due yet"
    /// Statistics: started weeks the plan file no longer carries (a list of week numbers); not counted.
    case statsOutsideWindow = "Not in the app's window: %@"
    /// Statistics: sessions done, missed and still planned.
    case statsCounts = "%lld done · %lld missed · %lld planned"
    /// Statistics: sessions skipped.
    case statsSkipped = "%lld skipped"
    /// Statistics: a number of sessions. Plural.
    case statsSessions = "%lld sessions"
    /// Statistics: no done session with G/A/R options in the scope.
    case statsNoOptions = "No traffic-light session done yet"
    /// Statistics: kilometres run of the week's target.
    case statsOfTarget = "%@ of %@ km"
    /// Statistics: the run target summed over the weeks.
    case statsPlannedTotal = "Planned %@ km in total"
    /// Statistics: mean kilometres per week with a known distance.
    case statsMeanWeekly = "Average %@ km a week"
    /// Statistics: a test never done.
    case statsNoResults = "No results yet"
    /// Statistics: a test's left and right values (L = left, R = right).
    case statsLeftRight = "L %@ · R %@"
    /// Statistics: the difference between left and right as a percentage.
    case statsAsymmetry = "Asymmetry %@"
    /// Keys that live in `.stringsdict` (plural forms).
    public var isPlural: Bool {
        switch self {
        case .countdownInDays, .countdownInAboutDays, .noticeLastSynced, .habitRecordedDays, .scheduleEveryNWeeks, .weeksCount, .countdownDaysAgo, .countdownAboutDaysAgo, .phaseStartsIn, .phaseDaysLeft, .carbLoadDaysBefore, .carbLoadDaysAfter, .statsSessions: return true
        default: return false
        }
    }
}

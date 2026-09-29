// TrainingModel.swift
//
// The plan as Today and Plan read it (add-training-today-and-plan task 4.1,
// design D12): a thin `@MainActor @Observable` holder of TrainingCore's
// `TrainingSource` -- still fetching, not published, unreadable, or a
// loaded `TrainingSnapshot` with its freshness. Every rule (decoding, the
// last good copy, freshness, the training day, what each card shows) lives
// in TrainingCore and is tested there; this only gathers the inputs and
// hands out builders in the app's language.
//
// Inputs: the last good projection (`ProjectionStore`, decoded off the main
// actor, no network), the refused-file reason, and VaultKit's status (the
// last successful sync, a 404 on the file). A rejection is remembered
// across launches in UserDefaults while VaultKit still holds a refused
// ETag -- the store keeps it in memory only, and after a relaunch the same
// refused file answers 304, so without this the loud "Update Jirka's Arc"
// would vanish while the file is still too new.
//
// Rebuilt: at launch and every foreground (AppEnvironment), after each
// projection refresh and disconnect (VaultController.onProjectionRefresh),
// and on day change. Views re-run the builders on each render; they are
// cheap and pure.
//
// add-training-checkins: it also carries the phone's own events
// (TrainingEventsService's overlay) and what the app may record
// (`TrainingCapabilities.checkIns(enabled:)`: connection on and a device
// id) into the snapshot, turns taps into events (check-in, habit tick, RPE,
// note -- local, durable, never waiting for the network), and re-plans the
// training reminders after each change.
//
// Owned by AppEnvironment (`environment.training`); read by the Today
// training cards and the Plan tab.

import Foundation
import Observation
import TrainingCore
import VaultKit
import GarminKit

@MainActor
@Observable
final class TrainingModel {
    static let rejectionKey = "training.projection.rejection.v1"

    private(set) var source: TrainingSource = .waitingForFirstSync
    private(set) var hasLoaded = false
    /// add-training-checkins: the last recording error, for an alert.
    var actionError: String?
    /// The app's language (Settings -> Language), fixed for the process.
    let language: TrainingLanguage

    @ObservationIgnored private let store: ProjectionStore
    @ObservationIgnored private let vault: VaultController
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var didRestoreRejection = false
    @ObservationIgnored private let events: TrainingEventsService

    /// add-training-checkins D8: the training reminders switch (default on,
    /// tasks 0.2).
    static let remindersKey = "training.reminders.enabled.v1"

    init(store: ProjectionStore, vault: VaultController, events: TrainingEventsService, defaults: UserDefaults = .standard) {
        self.store = store
        self.vault = vault
        self.events = events
        self.defaults = defaults
        self.language = TrainingLanguage.from(preferredLocalizations: Bundle.main.preferredLocalizations)
        events.onChange = { [weak self] in
            await self?.reload()
        }
    }

    // MARK: Recording (add-training-checkins)

    /// The morning check-in for `date` (Today's row).
    func checkIn(_ light: MorningLight, date: LocalDate, sessionID: String?) async {
        await perform(.morningCheckIn(MorningCheckInPayload(date: date, light: light, sessionId: sessionID)))
    }

    /// Habit on/off for `date` (decision A42).
    func setHabit(_ habitID: String, done: Bool, date: LocalDate) async {
        await perform(.habitTick(HabitTickPayload(date: date, habitId: habitID, done: done)))
    }

    func rate(sessionID: String, date: LocalDate, rpe: Int) async {
        await perform(.sessionRPE(SessionRPEPayload(date: date, sessionId: sessionID, rpe: rpe)))
    }

    func saveNote(sessionID: String, date: LocalDate, text: String) async {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(SessionNotePayload.maxLength))
        await perform(.sessionNote(SessionNotePayload(date: date, sessionId: sessionID, text: trimmed)))
    }

    /// Records locally (durable), then the service schedules delivery and
    /// calls back into `reload`. A failure is shown, never swallowed.
    private func perform(_ payload: HubEventPayload) async {
        do {
            try await events.record(payload)
        } catch {
            DiagnosticsLog.log(.error, category: "training", "recording \(payload.type.rawValue) failed: \(error)")
            actionError = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't save that on the phone. Try again.", comment: "Training: recording a check-in, tick, RPE or note failed.")
        }
    }

    // MARK: Reminders (add-training-checkins D8)

    var remindersEnabled: Bool {
        defaults.object(forKey: Self.remindersKey) as? Bool ?? true
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        defaults.set(enabled, forKey: Self.remindersKey)
        await syncReminders()
    }

    /// Re-plans the training reminders from the current snapshot; none when
    /// the switch is off or the connection can't record.
    func syncReminders(now: Date = Date()) async {
        let allowed = remindersEnabled && events.isConnectionOn()
        let reminders = allowed
            ? TrainingReminderPlanner.plan(snapshot: source.snapshot, today: today(now: now), now: now, timeZone: .current, language: language)
            : []
        await NotificationScheduler.shared.syncTrainingReminders(reminders, now: now)
    }

    // MARK: Days

    private var athlete: Athlete {
        source.snapshot?.athlete ?? Athlete()
    }

    /// The current training day (athlete.tz and day boundary, D6).
    func today(now: Date = Date()) -> LocalDate {
        TrainingDay.current(now: now, boundaryHour: athlete.dayBoundaryHour, timeZone: athlete.timeZone(fallback: .current))
    }

    /// The plan day for the day switcher's selection (Today follows it).
    func trainingDay(selectedDate: Date, isToday: Bool, now: Date = Date()) -> LocalDate {
        TrainingDay.resolve(
            selectedDate: LocalDate(date: selectedDate, timeZone: .current),
            isToday: isToday,
            now: now,
            athlete: athlete,
            deviceTimeZone: .current
        )
    }

    // MARK: Builders

    var todayBuilder: TodayTrainingBuilder {
        TodayTrainingBuilder(source: source, language: language)
    }

    func planBuilder(now: Date = Date()) -> PlanBuilder {
        PlanBuilder(source: source, language: language, today: today(now: now))
    }

    // MARK: Loading

    func reload(now: Date = Date()) async {
        if !didRestoreRejection {
            didRestoreRejection = true
            if let raw = defaults.string(forKey: Self.rejectionKey),
               let rejection = ProjectionRejection(reportReason: raw),
               await store.hasRejectedCopy() {
                await store.restoreRejection(rejection)
            }
        }
        let cached = await store.loadCached()
        let rejection = await store.rejection
        if let rejection {
            defaults.set(rejection.description, forKey: Self.rejectionKey)
        } else {
            defaults.removeObject(forKey: Self.rejectionKey)
        }

        let status = vault.status
        let availability = ProjectionAvailability.evaluate(
            cached: cached,
            rejection: rejection,
            fileNotFound: status.lastOutcome == .fileNotFound
        )
        let athlete = cached?.projection.athlete ?? Athlete()
        let trainingToday = TrainingDay.current(
            now: now,
            boundaryHour: athlete.dayBoundaryHour,
            timeZone: athlete.timeZone(fallback: .current)
        )
        let freshness = TrainingFreshness.evaluate(
            asOf: cached?.projection.asOf,
            trainingToday: trainingToday,
            lastSuccessAt: status.lastSuccessAt ?? cached?.fetchedAt,
            now: now,
            rejection: rejection,
            hasNewerVersionHint: cached?.projection.supersededBy != nil
        )
        // add-training-checkins: the phone's events over the plan, and
        // whether it may record at all.
        let checkIns = await events.recorder.overlay()
        let canRecord = await events.canRecord()
        source = TrainingSource.from(availability, freshness: freshness, checkIns: checkIns, capabilities: .checkIns(enabled: canRecord))
        hasLoaded = true
        await syncReminders(now: now)
    }
}

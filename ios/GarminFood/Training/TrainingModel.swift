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
// add-plan-editing: it also carries the phone's plan commands
// (`PendingOverlay`, folded with the cached projection's `acks` and
// `outcomes`) into the snapshot, with `TrainingCapabilities.recording`
// turning plan edits on under the same guard, and turns Move, Swap, Skip,
// Undo the skip, Override the rule and Withdraw into commands built by
// TrainingCore's PlanEditPolicy (which refuses what the vault would
// refuse) and recorded like a check-in.
//
// add-checkin-pain-score: the pain step's Save records the row's check-in
// again with `pains` (`recordPain`), which replaces the day's answer; a
// light alone keeps it (TrainingCore's CheckInOverlay).
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

    /// add-checkin-pain-score: the check-in with the morning pain, built by
    /// TrainingCore's `PainStepModel.payload` (same light, session and
    /// option as the row).
    func recordPain(_ payload: MorningCheckInPayload) async {
        await perform(.morningCheckIn(payload))
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

    // MARK: Plan edits (add-plan-editing D3, D6)

    func moveSession(_ sessionID: String, to date: LocalDate) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.move(sessionID: sessionID, to: date, snapshot: snapshot, today: today)
        }
    }

    func swapSession(_ sessionID: String, with partnerID: String) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.swap(sessionID: sessionID, with: partnerID, snapshot: snapshot, today: today)
        }
    }

    func skipSession(_ sessionID: String, reason: String?) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.skip(sessionID: sessionID, reason: reason, snapshot: snapshot, today: today)
        }
    }

    func unskipSession(_ sessionID: String) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.unskip(sessionID: sessionID, snapshot: snapshot, today: today)
        }
    }

    /// Decision A17: called only after the warning was confirmed.
    func overrideRule(_ rule: String, sessionID: String) async {
        await performEdit { snapshot, today in
            try PlanEditPolicy.overrideRule(rule, sessionID: sessionID, snapshot: snapshot, today: today)
        }
    }

    /// Retracts this phone's pending command (or applied override).
    func withdrawPlanChange(_ commandID: String) async {
        await performEdit { snapshot, _ in
            try PlanEditPolicy.withdraw(commandID: commandID, snapshot: snapshot)
        }
    }

    /// Builds the command from the current snapshot and training day, then
    /// records it like any other event. A refusal means the plan changed
    /// under the screen; it is said, never swallowed.
    private func performEdit(_ make: (TrainingSnapshot, LocalDate) throws -> HubEventPayload) async {
        guard let snapshot = source.snapshot else { return }
        let payload: HubEventPayload
        do {
            payload = try make(snapshot, today())
        } catch {
            DiagnosticsLog.log(.error, category: "training", "plan edit not offered any more: \(error)")
            actionError = String(localized: "That change isn't possible any more: the plan has changed. Have another look.", comment: "add-plan-editing: a plan change was refused on the phone because the plan changed under the screen.")
            return
        }
        Haptics.success()
        await perform(payload)
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
            // fix-review-findings-2026-09 finding 11: a week ahead, from the
            // cached projection (the same 7 days as the food reminders,
            // NotificationPlanning.windowDays), so reminders outlive a
            // closed app.
            ? TrainingReminderPlanner.plan(snapshot: source.snapshot, today: today(now: now), now: now, timeZone: .current, language: language, days: 7)
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
        let checkIns = await events.recorder.overlay(acks: cached?.projection.acks ?? [:])
        // add-plan-editing: the phone's plan commands and the vault's
        // answers; plan edits under the same guard as the check-ins.
        let planEdits = await events.recorder.planEdits(acks: cached?.projection.acks ?? [:], outcomes: cached?.projection.outcomes ?? [])
        let canRecord = await events.canRecord()
        source = TrainingSource.from(availability, freshness: freshness, checkIns: checkIns, planEdits: planEdits, capabilities: .recording(enabled: canRecord))
        hasLoaded = true
        await syncReminders(now: now)
    }
}

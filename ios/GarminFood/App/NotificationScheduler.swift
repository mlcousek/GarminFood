// NotificationScheduler.swift
//
// Owns every `UNUserNotificationCenter` call. `FoodLogCore.NotificationPlanning.
// plan(...)` decides WHAT should be scheduled right now (pure, testable);
// this type is the side-effecting half that actually asks for permission and
// syncs the system's pending requests to match.
//
// Local notifications can't dynamically ask "has this already happened" at
// fire time -- there is no Notification Service Extension hook for LOCAL
// notifications (only remote/push ones), and this project has no push
// capability anyway (free-tier constraint). So instead of one long-lived
// repeating request per reminder, each planned notification becomes a
// SINGLE, date-scoped request for TODAY only (identifier
// "<kind>.<yyyy-MM-dd>"). `sync(...)` is called on every foreground, right
// after logging something, and after a notification setting changes -- it
// re-plans from current state and diffs against what's actually pending:
// anything no longer planned (already logged, disabled, or a stale date) is
// removed, anything newly planned and not yet pending is added, and anything
// pending whose title/body differs from the plan (e.g. scheduled before a
// language switch -- add-localization 3.3b) is re-added with the current
// text. The diff itself is `NotificationPlanning.diff` (FoodLogCore, unit
// tested). This is the
// same "replan and reconcile" shape `Reconciliation`/`Outbox` already use
// for Garmin delivery, applied to local notifications instead.
//
// `syncFastingReminders(...)` is a second, independent replan-and-diff
// cycle for the "fast ends soon" / "fast starts soon" reminders
// (redesign-fasting-schedule 2.5). Kept separate from `sync(...)` because
// these are REPEATING daily requests anchored to the fixed daily fasting
// window, not today-only ones (see `NotificationPlanning.
// PlannedFastingReminder`'s header for why that exception to design D2 is
// safe here): they have no "skip it today" condition, so a repeating
// trigger keeps them firing even on days the app isn't opened.

import Foundation
import UserNotifications
import FoodLogCore
import GarminKit

@MainActor
final class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let center: UNUserNotificationCenter
    /// Every identifier this scheduler ever creates carries this prefix, so
    /// `sync` can tell "ours, possibly stale" apart from anything else that
    /// might one day schedule a local notification, without needing its own
    /// separate bookkeeping of what it scheduled last time.
    private static let identifierPrefix = "reminder."

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Requests permission if not already determined. Returns the resulting
    /// authorization status so the caller (`NotificationSettingsView`) can
    /// show a "notifications are off in Settings" note when denied, per this
    /// project's existing loud-failure convention (auth banners, delivery
    /// failures) -- a reminder the user just turned on that silently never
    /// fires would be exactly the kind of silent failure this app's own
    /// history (the vault's nutrition sync) already learned to avoid.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> UNAuthorizationStatus {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
        return await center.notificationSettings().authorizationStatus
    }

    /// `true` while a sync is in flight -- `AppEnvironment` calls `sync`
    /// from several independent triggers (foreground, right after a log,
    /// every reminder-setting change), so two calls can legitimately
    /// overlap. Same reentrancy guard `AppEnvironment.drainAndReconcile()`
    /// already uses for the exact same reason (a 2026-09-22 review found
    /// two callers could both be mid-flight against the same `await
    /// center.pendingNotificationRequests()` snapshot, each computing a
    /// diff that's stale by the time it writes -- self-healing on the next
    /// call, but worth closing off rather than relying on that).
    private var isSyncing = false

    /// The newest `sync` arguments not yet applied. A call arriving while
    /// one is in flight can't just be dropped: its caller captured its
    /// arguments AFTER the in-flight call's (a meal just logged, a reminder
    /// time just changed), so the in-flight pass is planning from older
    /// state. They're parked here instead and the in-flight call runs one
    /// more pass with them -- newest wins, however many arrived meanwhile.
    /// Same coalescing as `AppEnvironment.refreshGarminHealth`'s queued flag.
    private var pendingSync: SyncRequest?

    private struct SyncRequest {
        let preferences: NotificationPreferences
        let mealsLoggedToday: Set<MealType>
        let isStreakAtRiskToday: Bool
        let now: Date
    }

    /// Re-plans and re-syncs pending notifications against current state.
    /// Idempotent and safe to call often -- a no-op when nothing changed.
    /// While another call is in flight this one returns at once, and the
    /// in-flight call re-runs with these (newer) arguments when it's done.
    func sync(
        preferences: NotificationPreferences,
        mealsLoggedToday: Set<MealType>,
        isStreakAtRiskToday: Bool,
        now: Date = Date()
    ) async {
        pendingSync = SyncRequest(
            preferences: preferences,
            mealsLoggedToday: mealsLoggedToday,
            isStreakAtRiskToday: isStreakAtRiskToday,
            now: now
        )
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        while let request = pendingSync {
            pendingSync = nil
            await performSync(
                preferences: request.preferences,
                mealsLoggedToday: request.mealsLoggedToday,
                isStreakAtRiskToday: request.isStreakAtRiskToday,
                now: request.now
            )
        }
    }

    /// One replan-and-diff pass; only ever run by `sync`'s loop.
    private func performSync(
        preferences: NotificationPreferences,
        mealsLoggedToday: Set<MealType>,
        isStreakAtRiskToday: Bool,
        now: Date
    ) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let planned = NotificationPlanning.plan(
            preferences: preferences,
            mealsLoggedToday: mealsLoggedToday,
            isStreakAtRiskToday: isStreakAtRiskToday
        )
        let dateKey = NutritionDate.string(from: now)
        var plannedByIdentifier: [String: NotificationPlanning.PlannedNotification] = [:]
        for item in planned {
            plannedByIdentifier[Self.identifierPrefix + item.id + "." + dateKey] = item
        }

        let pending = await pendingTexts()
        let diff = NotificationPlanning.diff(
            planned: plannedByIdentifier.mapValues(\.text),
            pending: pending,
            ownedPrefix: Self.identifierPrefix
        )
        if !diff.toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.toRemove)
        }

        // New requests, and pending ones whose text changed (e.g. after a
        // language switch): adding under a pending identifier replaces it.
        for identifier in diff.toAdd {
            guard let item = plannedByIdentifier[identifier] else { continue }
            guard let fireDate = Self.fireDate(hour: item.hour, minute: item.minute, on: now), fireDate > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let interval = max(fireDate.timeIntervalSince(now), 1)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                DiagnosticsLog.log(.warning, category: "NotificationScheduler", "couldn't schedule \(identifier): \(error)")
            }
        }
    }

    private static func fireDate(hour: Int, minute: Int, on date: Date) -> Date? {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
    }

    /// Every pending request's identifier -> the text it will show, for
    /// `NotificationPlanning.diff` (add-localization 3.3b): comparing text,
    /// not just identifiers, is what replaces reminders scheduled in the
    /// previous language.
    private func pendingTexts() async -> [String: NotificationPlanning.NotificationText] {
        let requests = await center.pendingNotificationRequests()
        var texts: [String: NotificationPlanning.NotificationText] = [:]
        for request in requests {
            texts[request.identifier] = NotificationPlanning.NotificationText(
                title: request.content.title,
                body: request.content.body
            )
        }
        return texts
    }

    // MARK: - Fasting reminders

    /// Deliberately does NOT start with `identifierPrefix` ("reminder.") --
    /// `sync(...)`'s own stale-cleanup above matches anything with THAT
    /// prefix that isn't in ITS plan and removes it, so a shared prefix
    /// would make `sync(...)` delete these requests out from under this
    /// cycle every time it runs. A disjoint prefix keeps the two identifier
    /// namespaces -- and the two independent replan cycles -- apart.
    ///
    /// Each planned reminder's `id` already encodes its fire time and the
    /// boundary it warns about, so any change to the schedule or a lead
    /// time yields a different identifier and the stale request is removed
    /// by the diff below. Requests left over from the retired
    /// manual-session reminder ("fastingReminder.<epoch>") share this
    /// prefix and are cleaned up by the same diff on the first run.
    private static let fastingIdentifierPrefix = "fastingReminder."

    /// Reentrancy guard, same reasoning as `isSyncing` above -- `sync` and
    /// this are called back to back from `AppEnvironment.syncNotifications()`
    /// but are independent identifier namespaces, so this needs its own flag
    /// rather than sharing `isSyncing`.
    private var isSyncingFasting = false

    /// The newest fasting arguments not yet applied -- same coalescing as
    /// `pendingSync`. Dropping them instead lost real edits: every "Fast
    /// until" picker change fires its own sync, so moving 12:00 -> 13:00
    /// while the 12:00 pass was still in flight left the repeating reminder
    /// saying "ends at 12:00" until the next foreground replan.
    private var pendingFastingSync: FastingSyncRequest?

    private struct FastingSyncRequest {
        let schedule: FastingSchedule?
        let endsSoon: FastingReminderSetting
        let startsSoon: FastingReminderSetting
    }

    /// - Parameter schedule: the ACTIVE fasting window (`nil` while fasting
    ///   is off, which removes both reminders).
    func syncFastingReminders(
        schedule: FastingSchedule?,
        endsSoon: FastingReminderSetting,
        startsSoon: FastingReminderSetting
    ) async {
        pendingFastingSync = FastingSyncRequest(schedule: schedule, endsSoon: endsSoon, startsSoon: startsSoon)
        guard !isSyncingFasting else { return }
        isSyncingFasting = true
        defer { isSyncingFasting = false }

        while let request = pendingFastingSync {
            pendingFastingSync = nil
            await performFastingSync(schedule: request.schedule, endsSoon: request.endsSoon, startsSoon: request.startsSoon)
        }
    }

    /// One fasting replan-and-diff pass; only ever run by
    /// `syncFastingReminders`'s loop.
    private func performFastingSync(
        schedule: FastingSchedule?,
        endsSoon: FastingReminderSetting,
        startsSoon: FastingReminderSetting
    ) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let planned = NotificationPlanning.planFastingReminders(schedule: schedule, endsSoon: endsSoon, startsSoon: startsSoon)
        var plannedByIdentifier: [String: NotificationPlanning.PlannedFastingReminder] = [:]
        for item in planned {
            plannedByIdentifier[Self.fastingIdentifierPrefix + item.id] = item
        }

        let pending = await pendingTexts()
        let diff = NotificationPlanning.diff(
            planned: plannedByIdentifier.mapValues(\.text),
            pending: pending,
            ownedPrefix: Self.fastingIdentifierPrefix
        )
        if !diff.toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.toRemove)
        }

        // Repeating requests never expire on their own, so this text
        // comparison is what moves them to a new language (3.3b); the add
        // replaces the pending request with the same identifier.
        for identifier in diff.toAdd {
            guard let item = plannedByIdentifier[identifier] else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            // Wall-clock hour/minute, repeating daily -- the system keeps it
            // on the same clock time across DST changes by itself.
            var components = DateComponents()
            components.hour = item.hour
            components.minute = item.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                DiagnosticsLog.log(.warning, category: "NotificationScheduler", "couldn't schedule \(identifier): \(error)")
            }
        }
    }

    // MARK: - Supplement reminders (add-supplements D5)

    /// Slot reminders: dated one-shot requests (`slot.<day>.<slotKey>`) for
    /// today and tomorrow, re-planned and diffed like `sync(...)`, so a
    /// ticked slot's reminder is removed. Their own prefix keeps the other
    /// cycles' stale-cleanup away from them.
    private static let supplementSlotPrefix = "supplementSlot."

    /// Restock reminders are sent at most once per pack, so they are
    /// add-only: once scheduled the pack is marked reminded, drops out of
    /// the plan, and must NOT then be diffed away before it fires. They're
    /// removed only when the feature is turned off.
    private static let supplementRestockPrefix = "supplementRestock."

    private var isSyncingSupplements = false

    /// Applies the planned supplement reminders. Returns the products whose
    /// restock reminder was scheduled now (the caller marks their pack as
    /// reminded).
    func syncSupplementReminders(
        slots: [PlannedSupplementReminder],
        restock: [PlannedSupplementReminder],
        isEnabled: Bool,
        now: Date = Date()
    ) async -> [UUID] {
        // A pass already running plans from state at most a moment older;
        // the next trigger (every tick and foreground) catches up.
        guard !isSyncingSupplements else { return [] }
        isSyncingSupplements = true
        defer { isSyncingSupplements = false }

        registerSupplementCategory()
        let pending = await pendingTexts()

        if !isEnabled {
            let ours = pending.keys.filter { $0.hasPrefix(Self.supplementSlotPrefix) || $0.hasPrefix(Self.supplementRestockPrefix) }
            if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(ours)) }
            return []
        }

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return [] }

        // Slots: replan and diff.
        var plannedSlots: [String: PlannedSupplementReminder] = [:]
        for item in slots {
            plannedSlots[Self.supplementSlotPrefix + item.id] = item
        }
        let diff = NotificationPlanning.diff(
            planned: plannedSlots.mapValues(\.text),
            pending: pending,
            ownedPrefix: Self.supplementSlotPrefix
        )
        if !diff.toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: diff.toRemove)
        }
        for identifier in diff.toAdd {
            guard let item = plannedSlots[identifier],
                  let fireDate = Self.fireDate(day: item.day, hour: item.hour, minute: item.minute),
                  fireDate > now
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = NotificationPlanning.supplementSlotCategory
            content.userInfo = item.userInfo
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(fireDate.timeIntervalSince(now), 1), repeats: false)
            await add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }

        // Restock: add-only, once per pack.
        var scheduled: [UUID] = []
        for item in restock {
            guard case .restock(let productId) = item.kind else { continue }
            let identifier = Self.supplementRestockPrefix + item.id
            guard pending[identifier] == nil else { continue }
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            // Its time today, or in a minute when that has passed.
            let fireDate = Self.fireDate(day: item.day, hour: item.hour, minute: item.minute) ?? now
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(fireDate.timeIntervalSince(now), 60), repeats: false)
            if await add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)) {
                scheduled.append(productId)
            }
        }
        return scheduled
    }

    /// The slot reminder's category, with its "Taken" action: ticks the
    /// slot in the background, without opening the app (design D5).
    private func registerSupplementCategory() {
        let taken = UNNotificationAction(
            identifier: NotificationPlanning.supplementTakenAction,
            title: String(localized: "Taken", comment: "Button on a supplement reminder: ticks every item of the slot."),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationPlanning.supplementSlotCategory,
            actions: [taken],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    @discardableResult
    private func add(_ request: UNNotificationRequest) async -> Bool {
        do {
            try await center.add(request)
            return true
        } catch {
            DiagnosticsLog.log(.warning, category: "NotificationScheduler", "couldn't schedule \(request.identifier): \(error)")
            return false
        }
    }

    /// `hour:minute` on the calendar day `day` (`yyyy-MM-dd`).
    private static func fireDate(day: String, hour: Int, minute: Int) -> Date? {
        guard let noon = SupplementDay.date(day) else { return nil }
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: noon)
    }
}

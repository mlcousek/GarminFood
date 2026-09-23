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
// removed, anything newly planned and not yet pending is added. This is the
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

    /// Re-plans and re-syncs pending notifications against current state.
    /// Idempotent and safe to call often -- a no-op when nothing changed,
    /// and a no-op (not queued) when another call is already in flight,
    /// since the in-flight call already reflects whatever triggered this
    /// one by the time it finishes reading `preferences`/`mealsLoggedToday`
    /// fresh on its own next invocation.
    func sync(
        preferences: NotificationPreferences,
        mealsLoggedToday: Set<MealType>,
        isStreakAtRiskToday: Bool,
        now: Date = Date()
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

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

        let pending = await center.pendingNotificationRequests()
        let ourStaleIdentifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && plannedByIdentifier[$0] == nil }
        if !ourStaleIdentifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ourStaleIdentifiers)
        }

        let alreadyPending = Set(pending.map(\.identifier))
        for (identifier, item) in plannedByIdentifier where !alreadyPending.contains(identifier) {
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

    /// - Parameter schedule: the ACTIVE fasting window (`nil` while fasting
    ///   is off, which removes both reminders).
    func syncFastingReminders(
        schedule: FastingSchedule?,
        endsSoon: FastingReminderSetting,
        startsSoon: FastingReminderSetting
    ) async {
        guard !isSyncingFasting else { return }
        isSyncingFasting = true
        defer { isSyncingFasting = false }

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        let planned = NotificationPlanning.planFastingReminders(schedule: schedule, endsSoon: endsSoon, startsSoon: startsSoon)
        var plannedByIdentifier: [String: NotificationPlanning.PlannedFastingReminder] = [:]
        for item in planned {
            plannedByIdentifier[Self.fastingIdentifierPrefix + item.id] = item
        }

        let pending = await center.pendingNotificationRequests()
        let ourPending = pending.map(\.identifier).filter { $0.hasPrefix(Self.fastingIdentifierPrefix) }
        let stale = ourPending.filter { plannedByIdentifier[$0] == nil }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let alreadyPending = Set(ourPending)
        for (identifier, item) in plannedByIdentifier where !alreadyPending.contains(identifier) {
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
}

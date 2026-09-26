// SupplementNotificationHandler.swift
//
// add-supplements D5, task 4.2: the app's `UNUserNotificationCenterDelegate`,
// set in `GarminFoodApp.init` (a delegate must be in place before launch
// finishes, or an action that launched the app in the background is lost).
//
// Its one job is a slot reminder's "Taken" button: it ticks that slot's
// planned items for the reminder's day in the background, without opening
// the app, through FoodLogCore's `SupplementSlotTaking.take` -- idempotent,
// so a double tap or a replay never logs twice. The day and slot travel in
// the notification's userInfo.
//
// If the store can't be written (e.g. the phone is locked before first
// unlock, so the file is unreadable), the failure is logged to
// DiagnosticsLog and a follow-up notification asks the user to open the app
// and tick the slot there -- never a silent loss (CLAUDE.md).
//
// Every other notification keeps today's behaviour: no banner while the
// app is in the foreground, and a tap simply opens the app.
//
// Depends on: AppServices (stores), FoodLogCore (SupplementSlotTaking,
// SupplementTrainingDays, NotificationPlanning), GarminKit (DiagnosticsLog).
// Depended on by: GarminFoodApp (delegate), AppEnvironment (`onTaken`).

import Foundation
import UserNotifications
import FoodLogCore
import GarminKit

final class SupplementNotificationHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SupplementNotificationHandler()

    /// Set by AppEnvironment: reload what's on screen and re-plan the
    /// reminders after a background tick.
    @MainActor var onTaken: (() async -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        []
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == NotificationPlanning.supplementTakenAction,
              let target = SupplementSlotTaking.parse(response.notification.request.content.userInfo)
        else { return }
        await take(slotKey: target.slotKey, day: target.day)
    }

    @MainActor
    private func take(slotKey: String, day: String) async {
        let services = AppServices.shared
        let trainingDays = await SupplementTrainingDays.load(
            from: day,
            to: day,
            activityCache: services.activityCacheStore,
            dayNotes: services.dayNoteStore,
            mode: DataMode.effective(in: .standard)
        )
        do {
            try await SupplementSlotTaking.take(
                slotKey: slotKey,
                on: day,
                planStore: services.supplementPlanStore,
                intakeStore: services.supplementIntakeStore,
                trainingDays: trainingDays,
                today: NutritionDate.string(from: Date()),
                now: Date()
            )
            await onTaken?()
        } catch {
            DiagnosticsLog.log(.error, category: "Supplements", "Taken action failed for \(slotKey) on \(day): \(error.localizedDescription)")
            await postFallback()
        }
    }

    /// "Couldn't tick it -- open the app" (design D5's fallback).
    private func postFallback() async {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Couldn't tick your supplements", comment: "Notification after the Taken action failed (e.g. phone locked).")
        content.body = String(localized: "Open GarminFood to tick them.", comment: "Notification after the Taken action failed.")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "supplementTakenFailed." + UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}

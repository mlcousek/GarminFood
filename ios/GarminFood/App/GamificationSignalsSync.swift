// GamificationSignalsSync.swift
//
// add-gamification-signals 7.3: the only NEW Garmin reads gamification
// makes, both READ-ONLY and confirmed live (docs/garmin-routes.json):
//   - activities for the last 14 days (`activitiesSearch`, limit 20), at
//     most every 30 minutes, cached in `ActivityCacheStore`;
//   - the Garmin display name (`socialProfile`), at most once a day, only
//     to cache the FIRST NAME for friendly copy (`ProfileSignals.firstName`),
//     kept in UserDefaults so the offline path still has it.
// Run on foreground refresh only (`AppEnvironment.refreshOnForeground`) --
// never on a log confirm, never blocking anything the user waits for.
//
// Failures degrade quietly: logged to `DiagnosticsLog` (category
// "signals"), the cache keeps its last good copy. An AUTH failure is
// returned to the caller, which hands it to `GarminAuthState.report` -- the
// existing loud banner (auth failures are never silent).
//
// Truncation guard: when the response holds exactly `activityLimit` items
// the oldest days may be missing activities, so only the days from the
// oldest returned activity onward are marked as covered.
//
// Depends on: GarminKit (GarminClient, DiagnosticsLog, GarminAuthError),
// FoodLogCore (ActivityCacheStore, ProfileSignals, NutritionDate).
// Depended on by: AppEnvironment (caller), FeatureHost (cachedFirstName).

import Foundation
import GarminKit
import FoodLogCore

@MainActor
final class GamificationSignalsSync {
    static let minimumInterval: TimeInterval = 30 * 60
    static let lookbackDays = 14
    /// The probe body was truncated at 20 KB (~20 items); keep it small.
    static let activityLimit = 20

    private enum Key {
        static let lastActivitiesRead = "signals.activities.lastRead"
        static let firstName = "signals.profile.firstName"
        static let firstNameDay = "signals.profile.firstNameDay"
    }

    private let client: GarminClient
    private let activityCache: ActivityCacheStore
    private let defaults: UserDefaults
    private var isRunning = false

    init(client: GarminClient, activityCache: ActivityCacheStore, defaults: UserDefaults = .standard) {
        self.client = client
        self.activityCache = activityCache
        self.defaults = defaults
    }

    /// The cached first name ("Jiří"), or `nil` before the first read.
    static func cachedFirstName(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: Key.firstName)
    }

    /// Reads what is due. Returns an auth error for the loud banner, else `nil`.
    func refreshIfDue(now: Date = Date(), calendar: Calendar = .current) async -> GarminAuthError? {
        guard !isRunning else { return nil }
        isRunning = true
        defer { isRunning = false }

        var authError: GarminAuthError?
        if let error = await refreshActivitiesIfDue(now: now, calendar: calendar) {
            authError = error
        }
        if authError == nil, let error = await refreshFirstNameIfDue(now: now, calendar: calendar) {
            authError = error
        }
        return authError
    }

    private func refreshActivitiesIfDue(now: Date, calendar: Calendar) async -> GarminAuthError? {
        if let last = defaults.object(forKey: Key.lastActivitiesRead) as? Date,
           now.timeIntervalSince(last) < Self.minimumInterval, now >= last {
            return nil
        }
        let today = calendar.startOfDay(for: now)
        let days: [String] = (0..<Self.lookbackDays).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { NutritionDate.string(from: $0, calendar: calendar) }
        }
        guard let startDate = days.first, let endDate = days.last else { return nil }

        do {
            let activities = try await client.activities(startDate: startDate, endDate: endDate, limit: Self.activityLimit)
            var covered = days
            if activities.count >= Self.activityLimit {
                let placed = activities.compactMap(ActivitySummary.init(garmin:))
                if let oldest = placed.map(\.day).min() {
                    covered = days.filter { $0 >= oldest }
                }
            }
            try await activityCache.recordActivities(fromGarmin: activities, coveringDays: covered, now: now)
            defaults.set(now, forKey: Key.lastActivitiesRead)
            return nil
        } catch {
            return Self.note(error, reading: "activities")
        }
    }

    private func refreshFirstNameIfDue(now: Date, calendar: Calendar) async -> GarminAuthError? {
        let today = NutritionDate.string(from: now, calendar: calendar)
        guard defaults.string(forKey: Key.firstNameDay) != today else { return nil }
        do {
            let profile = try await client.socialProfile()
            if let first = ProfileSignals.firstName(fromFullName: profile.fullName) {
                defaults.set(first, forKey: Key.firstName)
            }
            defaults.set(today, forKey: Key.firstNameDay)
            return nil
        } catch {
            return Self.note(error, reading: "profile name")
        }
    }

    /// Auth errors go back to the caller (loud path); everything else is
    /// logged and otherwise ignored.
    private static func note(_ error: Error, reading what: String) -> GarminAuthError? {
        if let auth = error as? GarminAuthError {
            switch auth {
            case .longLivedTokenExpired:
                DiagnosticsLog.log(.error, category: "signals", "\(what): Garmin sign-in expired")
                return auth
            case .notSignedIn:
                return auth
            case .consumerKeyFetchFailed, .exchangeFailed:
                break
            }
        }
        DiagnosticsLog.log(.error, category: "signals", "couldn't read \(what): \(String(describing: error).prefix(300))")
        return nil
    }
}

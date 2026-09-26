// GarminSyncPlan.swift
//
// Which Garmin work a foreground, a day change or a trip to the background
// may do, per data mode (add-standalone-mode D10, task 5.3). Pulled out of
// `AppEnvironment.refreshOnForeground` so the rule "standalone mode makes
// no Garmin call at all" is one tested value instead of a scatter of `if`s
// -- the spec's "Standalone foreground: no request goes to
// connectapi.garmin.com" is exactly `GarminSyncPlan.for(.standalone)`
// being empty.
//
// Garmin mode keeps every step, so the owner's phone does exactly what it
// did before (spec "Garmin mode unchanged"). Local work -- the day log,
// gamification, notifications, the offline Czech index -- is not listed
// here: it runs in both modes.
//
// Depended on by: AppEnvironment (foreground, background), BackgroundRefresh.
// Tests: GarminSyncPlanTests.

import Foundation

public struct GarminSyncPlan: Sendable, Equatable {
    public enum Step: String, Sendable, CaseIterable {
        /// `GarminAuthState.refresh` (Keychain + token check).
        case authRefresh
        /// Food/weight/water outbox drains and reconciliation.
        case drainAndReconcile
        /// Weigh-ins, water total and weight goal read from Garmin.
        case healthRefresh
        /// Social profile and nutrition settings.
        case profileRefresh
        /// The one-time usage-meal backfill from Garmin day logs.
        case usageMealBackfill
        /// Activities / first-name reads for gamification signals.
        case gamificationSignalReads
        /// Scheduling a `BGAppRefreshTask` to deliver in the background.
        case backgroundDelivery
    }

    public let steps: Set<Step>

    public init(steps: Set<Step>) {
        self.steps = steps
    }

    public func allows(_ step: Step) -> Bool {
        steps.contains(step)
    }

    /// Every step in Garmin-connected mode; none in standalone mode.
    public static func `for`(_ mode: DataMode) -> GarminSyncPlan {
        switch mode {
        case .garminConnected: return GarminSyncPlan(steps: Set(Step.allCases))
        case .standalone: return GarminSyncPlan(steps: [])
        }
    }
}

// GarminActivities.swift
//
// Wire DTO for the READ-ONLY activities list route
// `GET /activitylist-service/activities/search/activities?startDate=&endDate=&limit=`
// (docs/garmin-routes.json `activitiesSearch`, probed 200 against the
// owner's live account 2026-09-24, read-only). Exists for
// `add-gamification-signals`: FoodLogCore's `ActivityCacheStore` turns
// these into plain `ActivitySummary` values so the Gamification package
// (which must not import GarminKit) can reason about "a run happened
// before this meal" without naming a GarminKit type.
//
// The real payload has ~78 keys per item; only the handful this project
// reads are modelled, every one Optional, and unknown keys are ignored by
// `Decodable` -- so a Garmin-side addition cannot break decoding, and a
// removed field degrades to `nil` rather than a thrown error. Observed
// shapes: `activityId` (number), `startTimeLocal` / `startTimeGMT`
// ("2026-09-23 19:22:08", no zone designator), `activityType.typeKey`
// ("walking", "mobility", "running", ...), `duration` (seconds, double),
// `calories`, `distance` (metres; absent for e.g. mobility).
//
// Called only by `GarminClient.activities(startDate:endDate:limit:)`,
// which inherits the client's single signed-GET choke point (DiagnosticsLog
// + 401 retry + auth error propagation).

import Foundation

public struct GarminActivity: Decodable, Sendable, Equatable {
    public struct ActivityType: Decodable, Sendable, Equatable {
        public let typeKey: String?

        public init(typeKey: String?) {
            self.typeKey = typeKey
        }
    }

    public let activityId: Int?
    public let activityName: String?
    /// "yyyy-MM-dd HH:mm:ss" in the watch's local time at the activity --
    /// decides which calendar day the activity belongs to.
    public let startTimeLocal: String?
    /// Same format, UTC -- the instant used for before/after-activity
    /// windows, so time-zone travel cannot shift them.
    public let startTimeGMT: String?
    public let activityType: ActivityType?
    /// Seconds.
    public let duration: Double?
    public let calories: Double?
    /// Metres.
    public let distance: Double?

    public init(
        activityId: Int? = nil,
        activityName: String? = nil,
        startTimeLocal: String? = nil,
        startTimeGMT: String? = nil,
        activityType: ActivityType? = nil,
        duration: Double? = nil,
        calories: Double? = nil,
        distance: Double? = nil
    ) {
        self.activityId = activityId
        self.activityName = activityName
        self.startTimeLocal = startTimeLocal
        self.startTimeGMT = startTimeGMT
        self.activityType = activityType
        self.duration = duration
        self.calories = calories
        self.distance = distance
    }

    /// Convenience for `activityType?.typeKey`.
    public var typeKey: String? { activityType?.typeKey }
}

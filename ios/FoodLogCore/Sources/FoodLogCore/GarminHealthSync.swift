// GarminHealthSync.swift
//
// The READ half of sync-weight-hydration-with-garmin (tasks 3.1/2.4,
// design.md D2 + "Fallback when routes break"): one refresh that asks
// Garmin for the weigh-ins, today's water total and the weight plan, and
// writes every successful answer into `GarminHealthCacheStore`. WHY it is
// its own type in FoodLogCore rather than code in the app's loaders: the
// "which reads, how often, what happens when one fails" rules are exactly
// the kind of logic this project keeps out of the untestable UI target
// (CLAUDE.md "Pure logic lives in the SPM packages"), and the views must
// reach Garmin through FoodLogCore, never GarminKit directly.
//
// Contract:
//   - Never throws. A failed read leaves that part of the cache untouched
//     (the cards keep rendering the last good values) and is reported in
//     `GarminHealthRefreshOutcome` so the UI can show a quiet "couldn't
//     refresh" caption; the error goes to `DiagnosticsLog`.
//   - An AUTH failure is surfaced separately (`authError`), so the app can
//     hand it to `GarminAuthState.report` -- auth failures are loud
//     (CLAUDE.md hard constraint), everything else degrades quietly.
//   - Read-only: nothing here writes to the Garmin account. The three
//     routes were live-probed read-only 2026-09-23 (docs/garmin-routes.json
//     `getWeighIns`, `hydrationDaily`, `nutritionSettings`).
//   - Never on a confirm/save path: callers run it on foreground, screen
//     appear and pull-to-refresh only.
//
// `GarminHealthReading` is the seam: `GarminClient` conforms below, tests
// use a fake (FoodLogCoreTests/GarminHealthSyncTests.swift) against a real
// `GarminHealthCacheStore` on a temp file. Used by the app's
// `AppEnvironment.refreshGarminHealth(force:)`.

import Foundation
import GarminKit

/// The weight-goal half of Garmin's nutrition settings, in Garmin's own
/// units: grams, and (presumed) grams per week for the rate. Live-verified
/// 2026-09-23: startingWeight 80400, targetWeightGoal 76000,
/// weightChangeType LOSS, weightChangeRate 250.
public struct GarminWeightPlan: Sendable, Equatable {
    public var startingWeightGrams: Double?
    public var targetWeightGrams: Double?
    public var weightChangeRateGramsPerWeek: Double?
    public var weightChangeType: String?

    public init(
        startingWeightGrams: Double?,
        targetWeightGrams: Double?,
        weightChangeRateGramsPerWeek: Double?,
        weightChangeType: String?
    ) {
        self.startingWeightGrams = startingWeightGrams
        self.targetWeightGrams = targetWeightGrams
        self.weightChangeRateGramsPerWeek = weightChangeRateGramsPerWeek
        self.weightChangeType = weightChangeType
    }
}

extension CachedWeightGoal {
    public init(plan: GarminWeightPlan, fetchedAt: Date) {
        self.init(
            startingWeightGrams: plan.startingWeightGrams,
            targetWeightGrams: plan.targetWeightGrams,
            weightChangeRateGramsPerWeek: plan.weightChangeRateGramsPerWeek,
            weightChangeType: plan.weightChangeType,
            fetchedAt: fetchedAt
        )
    }
}

/// The three Garmin reads a refresh needs. Dates are `yyyy-MM-dd`.
public protocol GarminHealthReading: Sendable {
    /// Every weigh-in from `startDate` through `endDate`, inclusive.
    func weighInSamples(startDate: String, endDate: String) async throws -> [GarminWeighIn]
    /// Garmin's water total + goal for one day.
    func hydrationDaily(date: String) async throws -> HydrationDaily
    /// The weight goal from nutrition settings.
    func weightPlan(date: String) async throws -> GarminWeightPlan
}

/// `hydrationDaily(date:)` is `GarminClient`'s own method, unchanged.
extension GarminClient: GarminHealthReading {
    /// One `weight/range` call (design.md D2's confirmed path), flattened.
    public func weighInSamples(startDate: String, endDate: String) async throws -> [GarminWeighIn] {
        try await weighInRange(startDate: startDate, endDate: endDate).allWeighIns
    }

    public func weightPlan(date: String) async throws -> GarminWeightPlan {
        let settings = try await nutritionSettings(date: date)
        return GarminWeightPlan(
            startingWeightGrams: settings.startingWeight,
            targetWeightGrams: settings.targetWeightGoal,
            weightChangeRateGramsPerWeek: settings.weightChangeRate,
            weightChangeType: settings.weightChangeType
        )
    }
}

/// What one refresh managed to read.
public struct GarminHealthRefreshOutcome: Sendable, Equatable {
    public var weighInsFailed: Bool
    public var hydrationFailed: Bool
    public var goalFailed: Bool
    /// Set when a read failed because the Garmin sign-in itself is missing
    /// or dead -- the app reports this loudly instead of as a quiet caption.
    public var authError: GarminAuthError?

    public init(weighInsFailed: Bool = false, hydrationFailed: Bool = false, goalFailed: Bool = false, authError: GarminAuthError? = nil) {
        self.weighInsFailed = weighInsFailed
        self.hydrationFailed = hydrationFailed
        self.goalFailed = goalFailed
        self.authError = authError
    }

    /// Whether the weight card should show "couldn't refresh".
    public var weightFailed: Bool { weighInsFailed || goalFailed }
}

public struct GarminHealthSync: Sendable {
    /// How old the cached weight plan may get before it is re-read. It
    /// changes only when the owner edits the plan in Garmin Connect.
    public static let goalMaxAge: TimeInterval = 6 * 60 * 60

    private let cache: GarminHealthCacheStore
    private let reader: any GarminHealthReading

    public init(cache: GarminHealthCacheStore, reader: any GarminHealthReading) {
        self.cache = cache
        self.reader = reader
    }

    /// Reads what `GarminHealthRefreshPlan` says is due (the full 90-day
    /// history at most once a day or when `force`d, else today+yesterday),
    /// today's water, and the weight plan when stale; caches every success.
    /// The three reads run concurrently. `now` doubles as the cache's
    /// `fetchedAt`: taken BEFORE the reads start, so an outbox delivery
    /// racing a read is treated as "not in Garmin's answer yet" -- the safe
    /// side for the merge rules (`WeightHistoryMerge` rule 4,
    /// `HydrationDayTotal`).
    public func refresh(now: Date = Date(), force: Bool = false, calendar: Calendar = .current) async -> GarminHealthRefreshOutcome {
        let snapshot = await cache.current()
        let window = GarminHealthRefreshPlan.weighInWindow(
            lastFullRangeFetchAt: snapshot.lastFullWeightRangeFetchAt,
            now: now,
            force: force,
            calendar: calendar
        )
        let today = NutritionDate.string(from: now, calendar: calendar)
        let needsGoal = force || Self.isGoalStale(snapshot.weightGoal, now: now)

        async let weighInsRead = readWeighIns(window)
        async let hydrationRead = readHydration(today)
        async let goalRead = readGoal(today, needed: needsGoal)

        var outcome = GarminHealthRefreshOutcome()

        switch await weighInsRead {
        case .success(let samples):
            do {
                try await cache.storeWeighIns(samples, coveringDays: window.days, fetchedAt: now, isFullRange: window.isFullRange)
            } catch {
                DiagnosticsLog.log(.warning, category: "GarminHealthSync", "couldn't cache weigh-ins: \(error)")
            }
        case .failure(let error):
            outcome.weighInsFailed = true
            Self.note(error, reading: "weigh-ins \(window.startDate)..\(window.endDate)", into: &outcome)
        }

        switch await hydrationRead {
        case .success(let daily):
            do {
                try await cache.storeHydration(daily, for: today, fetchedAt: now)
            } catch {
                DiagnosticsLog.log(.warning, category: "GarminHealthSync", "couldn't cache hydration: \(error)")
            }
        case .failure(let error):
            outcome.hydrationFailed = true
            Self.note(error, reading: "hydration \(today)", into: &outcome)
        }

        switch await goalRead {
        case .success(let plan)?:
            do {
                try await cache.storeWeightGoal(CachedWeightGoal(plan: plan, fetchedAt: now))
            } catch {
                DiagnosticsLog.log(.warning, category: "GarminHealthSync", "couldn't cache weight goal: \(error)")
            }
        case .failure(let error)?:
            outcome.goalFailed = true
            Self.note(error, reading: "weight goal \(today)", into: &outcome)
        case nil:
            break
        }

        return outcome
    }

    static func isGoalStale(_ goal: CachedWeightGoal?, now: Date) -> Bool {
        guard let goal else { return true }
        return now.timeIntervalSince(goal.fetchedAt) > goalMaxAge || goal.fetchedAt > now
    }

    // MARK: - Reads (never throw; each returns its own Result)

    private func readWeighIns(_ window: GarminHealthRefreshPlan.WeighInWindow) async -> Result<[GarminWeighIn], Error> {
        do {
            return .success(try await reader.weighInSamples(startDate: window.startDate, endDate: window.endDate))
        } catch {
            return .failure(error)
        }
    }

    private func readHydration(_ day: String) async -> Result<HydrationDaily, Error> {
        do {
            return .success(try await reader.hydrationDaily(date: day))
        } catch {
            return .failure(error)
        }
    }

    /// `nil` when the cached plan is still fresh (no request made).
    private func readGoal(_ day: String, needed: Bool) async -> Result<GarminWeightPlan, Error>? {
        guard needed else { return nil }
        do {
            return .success(try await reader.weightPlan(date: day))
        } catch {
            return .failure(error)
        }
    }

    /// Auth errors are collected for the loud path; `notSignedIn` isn't
    /// logged (a signed-out user would otherwise get three lines per
    /// foreground). Everything else goes to the in-app diagnostics log.
    private static func note(_ error: Error, reading what: String, into outcome: inout GarminHealthRefreshOutcome) {
        if let auth = error as? GarminAuthError {
            switch auth {
            case .longLivedTokenExpired:
                outcome.authError = .longLivedTokenExpired
                DiagnosticsLog.log(.error, category: "GarminHealthSync", "\(what): Garmin sign-in expired")
                return
            case .notSignedIn:
                if outcome.authError == nil { outcome.authError = .notSignedIn }
                return
            case .consumerKeyFetchFailed, .exchangeFailed:
                break
            }
        }
        DiagnosticsLog.log(.warning, category: "GarminHealthSync", "couldn't read \(what): \(String(describing: error).prefix(300))")
    }
}

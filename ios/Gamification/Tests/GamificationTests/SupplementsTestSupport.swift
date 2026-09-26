// SupplementsTestSupport.swift
//
// add-supplements wave 6: literal `SupplementSignals` builders for the
// supplements feature, supplement streak and shared-freeze tests. The
// digest is FoodLogCore's own value type (built there from real stores and
// tested in SupplementSignalsTests), so here it is written out day by day:
// what the feature sees is exactly what the host hands it. Day keys are
// `yyyy-MM-dd`; September 2026 (Mon 21 - Sun 27 is one ISO week).

import Foundation
import FoodLogCore
@testable import Gamification

enum ST {
    static let calendar = TestClock.calendar

    /// `2026-09-<day>` (or another month).
    static func key(_ day: Int, month: Int = 9, year: Int = 2026) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// One digest day. Counts follow the status (complete 1/1, partial
    /// 2/1, missed 1/0, neutral 0/0).
    static func day(
        _ key: String,
        _ status: SupplementDayStatus,
        ingredients: [IngredientID: Double] = [:],
        grantsXP: Bool = true,
        slotMinutes: [String: Int] = [:]
    ) -> SupplementDaySignal {
        let counts: (Int, Int)
        switch status {
        case .complete: counts = (1, 1)
        case .partial: counts = (2, 1)
        case .missed: counts = (1, 0)
        case .neutral: counts = (0, 0)
        }
        return SupplementDaySignal(
            day: key,
            status: status,
            plannedCount: counts.0,
            takenCount: counts.1,
            ingredients: ingredients,
            grantsXP: grantsXP,
            slotMinutes: slotMinutes
        )
    }

    /// Consecutive days starting at `start`, one per status.
    static func days(from start: String, _ statuses: [SupplementDayStatus]) -> [SupplementDaySignal] {
        var result: [SupplementDaySignal] = []
        var cursor = start
        for status in statuses {
            result.append(day(cursor, status))
            cursor = SupplementDate.adding(1, to: cursor) ?? cursor
        }
        return result
    }

    static func signals(
        today: String,
        days: [SupplementDaySignal],
        isEnabled: Bool = true,
        hasPlan: Bool = true,
        refillsBeforeEmpty: Int = 0,
        frozenDays: Set<String> = []
    ) -> SupplementSignals {
        SupplementSignals(
            isEnabled: isEnabled,
            hasPlan: hasPlan,
            today: today,
            days: days,
            refillsBeforeEmpty: refillsBeforeEmpty,
            frozenDays: frozenDays
        )
    }

    /// A feature context at noon of `today` carrying `supplements`.
    static func context(_ supplements: SupplementSignals?, today: String, isConfirmPath: Bool = false) -> FeatureContext {
        let parts = today.split(separator: "-").compactMap { Int($0) }
        let now = TestClock.date(parts[0], parts[1], parts[2])
        return FeatureContext(
            snapshot: .empty,
            now: now,
            calendar: calendar,
            streak: StreakEngine.status(loggedDays: [], today: calendar.startOfDay(for: now), calendar: calendar),
            level: 1,
            unlockedBadgeIds: [],
            isConfirmPath: isConfirmPath,
            supplements: supplements
        )
    }

    static func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("supplements-\(UUID().uuidString)", isDirectory: true)
    }
}

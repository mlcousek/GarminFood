import FoodLogCore
import Foundation

// ChallengeEngine.swift
//
// Challenges spec's "Challenge progress is evaluated from the log history
// alone" requirement (design.md D4, task 25.1/25.4): pure evaluation
// functions, one per `ChallengeKind` case, each reading only the usage
// history and (for goal-hitting kinds) the locally cached `GoalStatus`
// snapshot -- no network call is made or awaited by anything in this file.

/// A challenge instance actually running, i.e. one template plus the
/// context captured at the moment it was activated. Codable so
/// `ChallengeStore` can persist it verbatim.
public struct ActiveChallenge: Sendable, Equatable, Codable {
    public let templateId: String
    public let startedAt: Date
    /// The streak length at activation -- `extendStreakBy` needs this
    /// baseline; every other kind ignores it.
    public let baselineStreakLength: Int

    public init(templateId: String, startedAt: Date, baselineStreakLength: Int) {
        self.templateId = templateId
        self.startedAt = startedAt
        self.baselineStreakLength = baselineStreakLength
    }
}

public struct ChallengeProgress: Sendable, Equatable {
    public let current: Int
    public let target: Int

    public init(current: Int, target: Int) {
        self.current = min(current, target)
        self.target = target
    }

    public var isComplete: Bool { target > 0 && current >= target }
    public var fraction: Double { target > 0 ? Double(current) / Double(target) : 0 }
}

public enum ChallengeEngine {
    /// The inclusive `[start, end]` nutrition-day range a challenge's
    /// window covers.
    public static func window(
        for active: ActiveChallenge,
        template: ChallengeTemplate,
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let start = NutritionDayBoundary.nutritionDay(for: active.startedAt, boundaryHour: boundaryHour, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: template.windowDays - 1, to: start) ?? start
        return (start, end)
    }

    /// Challenges spec's "also rotates after a time window" requirement.
    public static func isWindowElapsed(
        active: ActiveChallenge,
        template: ChallengeTemplate,
        now: Date,
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> Bool {
        let (_, end) = window(for: active, template: template, boundaryHour: boundaryHour, calendar: calendar)
        let today = NutritionDayBoundary.nutritionDay(for: now, boundaryHour: boundaryHour, calendar: calendar)
        return today > end
    }

    public static func progress(
        for template: ChallengeTemplate,
        active: ActiveChallenge,
        events: [UsageEvent],
        goalStatuses: [DailyGoalStatus],
        now: Date,
        boundaryHour: Int = NutritionDayBoundary.defaultBoundaryHour,
        calendar: Calendar = .current
    ) -> ChallengeProgress {
        let (windowStart, windowEnd) = window(for: active, template: template, boundaryHour: boundaryHour, calendar: calendar)
        let today = NutritionDayBoundary.nutritionDay(for: now, boundaryHour: boundaryHour, calendar: calendar)
        let evaluableEnd = min(windowEnd, today)
        guard evaluableEnd >= windowStart else { return ChallengeProgress(current: 0, target: targetCount(for: template.kind)) }

        // Nutrition-day -> events logged that day, restricted to the
        // window so a distant unrelated log never counts toward a
        // challenge's progress.
        var eventsByDay: [Date: [UsageEvent]] = [:]
        for event in events {
            let day = NutritionDayBoundary.nutritionDay(for: event.timestamp, boundaryHour: boundaryHour, calendar: calendar)
            guard day >= windowStart, day <= evaluableEnd else { continue }
            eventsByDay[day, default: []].append(event)
        }
        let loggedDays = Set(eventsByDay.keys)

        var goalByDay: [String: DailyGoalStatus] = [:]
        for status in goalStatuses { goalByDay[status.date] = status }

        switch template.kind {
        case .logOnDistinctDays(let minCount):
            return ChallengeProgress(current: loggedDays.count, target: minCount)

        case .extendStreakBy(let days):
            let currentStreak = StreakEngine.status(events: events, now: now, boundaryHour: boundaryHour, calendar: calendar).length
            let gained = max(0, currentStreak - active.baselineStreakLength)
            return ChallengeProgress(current: gained, target: days)

        case .goalHitDays(let macro, let minCount):
            // `day` here is already a nutrition-day marker (eachDay walks
            // windowStart/evaluableEnd, both already through
            // NutritionDayBoundary.nutritionDay()) -- format it directly,
            // don't re-shift it through dayString(for:).
            let hitDays = eachDay(from: windowStart, to: evaluableEnd, calendar: calendar).filter { day in
                guard let status = goalByDay[NutritionDayBoundary.string(forNutritionDay: day, calendar: calendar)] else { return false }
                return status.met(macro)
            }
            return ChallengeProgress(current: hitDays.count, target: minCount)

        case .goalHitStreak(let macro, let minCount):
            var longest = 0
            var running = 0
            for day in eachDay(from: windowStart, to: evaluableEnd, calendar: calendar) {
                let status = goalByDay[NutritionDayBoundary.string(forNutritionDay: day, calendar: calendar)]
                let met = macro.map { status?.met($0) ?? false } ?? (status?.anyGoalMet ?? false)
                if met {
                    running += 1
                    longest = max(longest, running)
                } else {
                    running = 0
                }
            }
            return ChallengeProgress(current: longest, target: minCount)

        case .newFoodsTried(let minCount):
            // "New" means: this foodId's earliest occurrence in the WHOLE
            // provided history (not just the window) falls inside the
            // window -- i.e. genuinely first logged during the challenge,
            // not merely first logged this week because older history
            // already rolled off the 500-event cap.
            var firstSeen: [String: Date] = [:]
            for event in events {
                let day = NutritionDayBoundary.nutritionDay(for: event.timestamp, boundaryHour: boundaryHour, calendar: calendar)
                if let existing = firstSeen[event.foodId] {
                    if day < existing { firstSeen[event.foodId] = day }
                } else {
                    firstSeen[event.foodId] = day
                }
            }
            let newFoodIds = firstSeen.filter { $0.value >= windowStart && $0.value <= evaluableEnd }.keys
            return ChallengeProgress(current: Set(newFoodIds).count, target: minCount)

        case .mealTimeOnDistinctDays(let bucket, let minCount):
            let matchingDays = eventsByDay.filter { _, dayEvents in
                dayEvents.contains { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) == bucket }
            }
            return ChallengeProgress(current: matchingDays.count, target: minCount)

        case .multiMealDays(let minBucketsPerDay, let minDays):
            let qualifyingDays = eventsByDay.filter { _, dayEvents in
                Set(dayEvents.map { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) }).count >= minBucketsPerDay
            }
            return ChallengeProgress(current: qualifyingDays.count, target: minDays)

        case .busyDays(let minEntriesPerDay, let minDays):
            let qualifyingDays = eventsByDay.filter { _, dayEvents in dayEvents.count >= minEntriesPerDay }
            return ChallengeProgress(current: qualifyingDays.count, target: minDays)

        case .weekendBothDays:
            // `loggedDays` is already restricted to `[windowStart,
            // evaluableEnd]` (built from `eventsByDay` above), so a
            // not-yet-arrived Sunday correctly reads as "not logged" rather
            // than needing a separate future-date check here.
            var best = 0
            for day in eachDay(from: windowStart, to: windowEnd, calendar: calendar) {
                guard calendar.component(.weekday, from: day) == 7 else { continue } // Saturday
                guard let sunday = calendar.date(byAdding: .day, value: 1, to: day), sunday <= windowEnd else { continue }
                let satLogged = loggedDays.contains(day)
                let sunLogged = loggedDays.contains(sunday)
                best = max(best, (satLogged ? 1 : 0) + (sunLogged ? 1 : 0))
            }
            return ChallengeProgress(current: best, target: 2)
        }
    }

    private static func targetCount(for kind: ChallengeKind) -> Int {
        switch kind {
        case .logOnDistinctDays(let minCount): return minCount
        case .extendStreakBy(let days): return days
        case .goalHitDays(_, let minCount): return minCount
        case .goalHitStreak(_, let minCount): return minCount
        case .newFoodsTried(let minCount): return minCount
        case .mealTimeOnDistinctDays(_, let minCount): return minCount
        case .multiMealDays(_, let minDays): return minDays
        case .busyDays(_, let minDays): return minDays
        case .weekendBothDays: return 2
        }
    }

    private static func eachDay(from start: Date, to end: Date, calendar: Calendar) -> [Date] {
        guard start <= end else { return [] }
        var days: [Date] = []
        var cursor = start
        while cursor <= end {
            days.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
        }
        return days
    }
}

/// A deterministic, hash-of-`now`-based pick -- deliberately not
/// `Array.randomElement()`, so rotation stays a pure function of local data
/// (design.md's "no hidden server-side state" goal) and is exactly as
/// testable as everything else in this package: the same `now` and
/// `excludedIds` always produce the same pick.
public enum ChallengeRotation {
    public static func pickNext(
        from catalog: [ChallengeTemplate],
        excluding excludedIds: Set<String>,
        now: Date
    ) -> ChallengeTemplate {
        precondition(!catalog.isEmpty, "the challenge catalog must not be empty")
        let candidates = catalog.filter { !excludedIds.contains($0.id) }
        let pool = (candidates.isEmpty ? catalog : candidates).sorted { $0.id < $1.id }
        let index = Int(now.timeIntervalSince1970.rounded()) % pool.count
        return pool[index]
    }
}

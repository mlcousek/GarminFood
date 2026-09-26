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
        signals: SignalsSnapshot? = nil,
        supplements: SupplementSignals? = nil,
        frozenDays: Set<Date> = [],
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
            let day = NutritionDayBoundary.nutritionDay(for: event, boundaryHour: boundaryHour, calendar: calendar)
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
            // `frozenDays`: the same streak-freeze days the app's displayed
            // streak (and so `baselineStreakLength`) walks with -- without
            // them a freeze-saved streak reads as reset here and the
            // challenge could never progress past its baseline.
            let currentStreak = StreakEngine.status(events: events, frozenDays: frozenDays, now: now, boundaryHour: boundaryHour, calendar: calendar).length
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
                let day = NutritionDayBoundary.nutritionDay(for: event, boundaryHour: boundaryHour, calendar: calendar)
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

        case .mealSlotAbsent(let bucket, let minDays):
            // `eventsByDay` only has keys for days with >=1 entry (built
            // above), so a fully empty day never appears here and never
            // trivially counts.
            let qualifyingDays = eventsByDay.filter { _, dayEvents in
                !dayEvents.contains { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) == bucket }
            }
            return ChallengeProgress(current: qualifyingDays.count, target: minDays)

        case .allGoalsHitDays(let minCount):
            let hitDays = eachDay(from: windowStart, to: evaluableEnd, calendar: calendar).filter { day in
                guard let status = goalByDay[NutritionDayBoundary.string(forNutritionDay: day, calendar: calendar)] else { return false }
                return status.metCalorieGoal && status.metProteinGoal && status.metCarbGoal && status.metFatGoal
            }
            return ChallengeProgress(current: hitDays.count, target: minCount)

        case .allFourMealSlotsDays(let minDays):
            let qualifyingDays = eventsByDay.filter { _, dayEvents in
                Set(dayEvents.map { MealTimeBucket.bucket(for: $0.timestamp, calendar: calendar) }).count == MealTimeBucket.allCases.count
            }
            return ChallengeProgress(current: qualifyingDays.count, target: minDays)

        case .sameFoodConsecutiveDays(let minDays):
            // "Identical foodId" means a single fixed food, not a chain of
            // pairwise-overlapping days -- so this is computed per-foodId
            // (the longest run of consecutive days THAT food was logged),
            // taking the best across every food seen in the window.
            var daysByFood: [String: Set<Date>] = [:]
            for (day, dayEvents) in eventsByDay {
                for event in dayEvents {
                    daysByFood[event.foodId, default: []].insert(day)
                }
            }
            var longest = 0
            for (_, days) in daysByFood {
                var running = 0
                for day in eachDay(from: windowStart, to: evaluableEnd, calendar: calendar) {
                    if days.contains(day) {
                        running += 1
                        longest = max(longest, running)
                    } else {
                        running = 0
                    }
                }
            }
            return ChallengeProgress(current: longest, target: minDays)

        case .consecutiveWeekendsBothDays(let weekends):
            var completeWeekendStarts: [Date] = []
            for day in eachDay(from: windowStart, to: windowEnd, calendar: calendar) {
                guard calendar.component(.weekday, from: day) == 7 else { continue } // Saturday
                guard let sunday = calendar.date(byAdding: .day, value: 1, to: day), sunday <= windowEnd else { continue }
                if loggedDays.contains(day), loggedDays.contains(sunday) {
                    completeWeekendStarts.append(day)
                }
            }
            var longest = completeWeekendStarts.isEmpty ? 0 : 1
            var running = longest
            for index in 1..<completeWeekendStarts.count {
                let gap = calendar.dateComponents([.day], from: completeWeekendStarts[index - 1], to: completeWeekendStarts[index]).day ?? 0
                running = (gap == 7) ? running + 1 : 1
                longest = max(longest, running)
            }
            return ChallengeProgress(current: longest, target: weekends)

        case .signalDays(let predicate, let minDays):
            // add-gamification-signals D11: a day counts only when the rule
            // definitely holds -- a day with unknown data (e.g. an entry
            // without fibre) simply doesn't count, it is never "failed".
            guard let signals else { return ChallengeProgress(current: 0, target: minDays) }
            let days = signalDays(signals, from: windowStart, to: evaluableEnd, calendar: calendar)
            let count = SignalEvaluator.daysSatisfying(predicate, in: days, history: signals, calendar: calendar).count
            return ChallengeProgress(current: count, target: minDays)

        case .signalWeek(let predicate):
            guard let signals else { return ChallengeProgress(current: 0, target: predicate.target) }
            let days = signalDays(signals, from: windowStart, to: evaluableEnd, calendar: calendar)
            let count = SignalEvaluator.progress(predicate, over: days, history: signals, calendar: calendar)
            return ChallengeProgress(current: count, target: predicate.target)

        case .supplementDays(let rule, let minDays):
            // add-supplements D9: days of the window on which the rule holds
            // in the supplement digest (keyed by the same yyyy-MM-dd day).
            guard let supplements else { return ChallengeProgress(current: 0, target: minDays) }
            let count = eachDay(from: windowStart, to: evaluableEnd, calendar: calendar).filter { day in
                let key = NutritionDayBoundary.string(forNutritionDay: day, calendar: calendar)
                return supplements.day(key).map(rule.holds) ?? false
            }.count
            return ChallengeProgress(current: count, target: minDays)
        }
    }

    /// The data-bearing signal days whose `yyyy-MM-dd` key falls on one of
    /// the window's nutrition days.
    private static func signalDays(_ signals: SignalsSnapshot, from start: Date, to end: Date, calendar: Calendar) -> [DaySignals] {
        let keys = eachDay(from: start, to: end, calendar: calendar).map {
            NutritionDayBoundary.string(forNutritionDay: $0, calendar: calendar)
        }
        return signals.days(keys)
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
        case .mealSlotAbsent(_, let minDays): return minDays
        case .allGoalsHitDays(let minCount): return minCount
        case .allFourMealSlotsDays(let minDays): return minDays
        case .sameFoodConsecutiveDays(let minDays): return minDays
        case .consecutiveWeekendsBothDays(let weekends): return weekends
        case .signalDays(_, let minDays): return minDays
        case .signalWeek(let predicate): return predicate.target
        case .supplementDays(_, let minDays): return minDays
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
///
/// add-gamification-signals D11: the pick is WEIGHTED by
/// `ChallengeRotationPolicy` (hand-authored 2, creative signal 3, allowlisted
/// ladder tiers 1, everything else 0), still deterministic -- seeded by the
/// same `now` through the shared `DeterministicRandom`. Fallbacks, in order:
/// any non-excluded template with weight > 0; else any non-excluded
/// template (plain seeded index, as before); else the whole catalog.
public enum ChallengeRotation {
    public static func pickNext(
        from catalog: [ChallengeTemplate],
        excluding excludedIds: Set<String>,
        now: Date,
        policy: ChallengeRotationPolicy = ChallengeRotationPolicy()
    ) -> ChallengeTemplate {
        precondition(!catalog.isEmpty, "the challenge catalog must not be empty")
        let seconds = Int(now.timeIntervalSince1970.rounded())
        let candidates = catalog.filter { !excludedIds.contains($0.id) }.sorted { $0.id < $1.id }

        var random = DeterministicRandom(seed: String(seconds))
        if let picked = random.weightedPick(candidates, weight: { policy.weight(for: $0) }) {
            return picked
        }
        let pool = candidates.isEmpty ? catalog.sorted { $0.id < $1.id } : candidates
        let index = ((seconds % pool.count) + pool.count) % pool.count
        return pool[index]
    }
}

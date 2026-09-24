// SeasonalEvaluator.swift
//
// add-seasonal-events design D5/D6: pure functions from (event, year,
// today, signals, stored progress) to the state the feature rewards and the
// UI shows -- phase (later / upcoming teaser / active / ended), per-quest
// progress and completion. No I/O, so every boundary is a unit test.
//
// Progress is a set of "marks" per quest, unioned with what was stored
// before (sticky, like bingo): a day key for day-counting quests, "g<i>"
// for each satisfied group of an `allOfTags` quest. A quest is done when it
// has `quest.target` marks. Only entries whose LOGGED day falls inside the
// window count (design Context: logged dates, not timestamps).
//
// Depends on: SeasonalCalendar, SeasonalEventCatalog, FoodLogCore signals.
// Depended on by: SeasonalEventsFeature, tests.

import Foundation
import FoodLogCore

public struct SeasonalQuestStatus: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let isBonus: Bool
    public let progress: Int
    public let target: Int

    public var isDone: Bool { progress >= target }
}

public struct SeasonalEventStatus: Sendable, Equatable, Identifiable {
    public enum Phase: String, Sendable, Equatable, CaseIterable {
        /// More than `teaserDays` before the window.
        case later
        /// The "coming soon" teaser.
        case upcoming
        case active
        case ended
    }

    public let eventId: String
    public let year: Int
    /// With the owner's name for the name-day event.
    public let title: String
    public let subtitle: String
    public let teaser: String
    public let symbol: String
    public let badgeId: String
    public let start: SeasonalDate
    public let end: SeasonalDate
    public let phase: Phase
    public let quests: [SeasonalQuestStatus]
    /// Every year this event was ever completed, ascending.
    public let completedYears: [Int]
    /// Days from today to the window start (negative once it started).
    public let daysUntilStart: Int
    /// Days left including today (0 once ended).
    public let daysLeft: Int

    public var id: String { SeasonalStore.instanceKey(eventId: eventId, year: year) }
    public var requiredQuests: [SeasonalQuestStatus] { quests.filter { !$0.isBonus } }
    public var bonusQuests: [SeasonalQuestStatus] { quests.filter(\.isBonus) }
    /// All required quests done (this year's instance).
    public var isCompleted: Bool { !requiredQuests.isEmpty && requiredQuests.allSatisfy(\.isDone) }
}

public enum SeasonalEvaluator {
    public static func phase(today: SeasonalDate, window: ClosedRange<SeasonalDate>, teaserDays: Int = SeasonalEventCatalog.teaserDays) -> SeasonalEventStatus.Phase {
        if window.contains(today) { return .active }
        if today > window.upperBound { return .ended }
        let until = today.days(until: window.lowerBound)
        return until <= teaserDays ? .upcoming : .later
    }

    /// The data-bearing snapshot days whose logged date is inside `window`.
    static func days(in window: ClosedRange<SeasonalDate>, snapshot: SignalsSnapshot) -> [(date: SeasonalDate, signals: DaySignals)] {
        var result: [(date: SeasonalDate, signals: DaySignals)] = []
        for (key, signals) in snapshot.days {
            guard let date = SeasonalDate(dayKey: key), window.contains(date) else { continue }
            result.append((date: date, signals: signals))
        }
        return result.sorted { $0.date < $1.date }
    }

    /// The marks `quest` earns from `days` (already limited to the window).
    public static func marks(
        for quest: SeasonalQuest,
        year: Int,
        window: ClosedRange<SeasonalDate>,
        days: [(date: SeasonalDate, signals: DaySignals)]
    ) -> Set<String> {
        switch quest.rule {
        case .tagOnDays(let tags, _):
            return Set(days.filter { hasAny(tags, $0.signals) }.map { $0.date.dayKey })
        case .allOfTags(let groups):
            var result = Set<String>()
            for (index, group) in groups.enumerated() where days.contains(where: { hasAny(group, $0.signals) }) {
                result.insert("g\(index)")
            }
            return result
        case .tagOnDate(let tags, let dayRef):
            let target = dayRef.resolve(year: year)
            guard window.contains(target) else { return [] }
            return Set(days.filter { $0.date == target && hasAny(tags, $0.signals) }.map { $0.date.dayKey })
        case .anyEntry:
            return Set(days.filter { $0.signals.hasEntries }.map { $0.date.dayKey })
        }
    }

    private static func hasAny(_ tags: Set<FoodTag>, _ day: DaySignals) -> Bool {
        day.entries.contains { !$0.tags.isDisjoint(with: tags) }
    }

    /// Fresh marks from `snapshot` unioned with `stored`, per quest id.
    public static func mergedMarks(
        event: SeasonalEvent,
        year: Int,
        window: ClosedRange<SeasonalDate>,
        snapshot: SignalsSnapshot,
        stored: [String: Set<String>]
    ) -> [String: Set<String>] {
        let windowDays = days(in: window, snapshot: snapshot)
        var result: [String: Set<String>] = [:]
        for quest in event.quests {
            let fresh = marks(for: quest, year: year, window: window, days: windowDays)
            result[quest.id] = fresh.union(stored[quest.id] ?? [])
        }
        return result
    }

    public static func status(
        event: SeasonalEvent,
        year: Int,
        today: SeasonalDate,
        nameDay: SeasonalCalendar.MonthDay?,
        firstName: String?,
        marks: [String: Set<String>],
        completedYears: [Int]
    ) -> SeasonalEventStatus? {
        guard let window = event.window(year: year, nameDay: nameDay) else { return nil }
        let quests = event.quests.map { quest in
            SeasonalQuestStatus(
                id: quest.id,
                title: quest.title,
                isBonus: quest.isBonus,
                progress: min(marks[quest.id]?.count ?? 0, quest.target),
                target: quest.target
            )
        }
        let daysLeft = today > window.upperBound ? 0 : today.days(until: window.upperBound) + 1
        return SeasonalEventStatus(
            eventId: event.id,
            year: year,
            title: event.displayTitle(firstName: firstName),
            subtitle: event.subtitle,
            teaser: event.teaser,
            symbol: event.symbol,
            badgeId: event.badgeId,
            start: window.lowerBound,
            end: window.upperBound,
            phase: phase(today: today, window: window),
            quests: quests,
            completedYears: completedYears,
            daysUntilStart: today.days(until: window.lowerBound),
            daysLeft: min(daysLeft, window.lowerBound.days(until: window.upperBound) + 1)
        )
    }

    /// Whether every required quest of `event` is done given `marks`.
    public static func isCompleted(event: SeasonalEvent, marks: [String: Set<String>]) -> Bool {
        let required = event.requiredQuests
        guard !required.isEmpty else { return false }
        return required.allSatisfy { (marks[$0.id]?.count ?? 0) >= $0.target }
    }

    // MARK: - Collector badges (design D6)

    /// The collector badge ids earned by `completedYears`.
    public static func collectorBadgeIds(
        completedYears: [String: [Int]],
        nameDay: SeasonalCalendar.MonthDay?
    ) -> [String] {
        let distinct = Set(completedYears.filter { !$0.value.isEmpty }.keys)
        var result: [String] = []
        if distinct.count >= 4 { result.append(SeasonalEventCatalog.collector4BadgeId) }
        if distinct.count >= 8 { result.append(SeasonalEventCatalog.collector8BadgeId) }
        let years = Set(completedYears.values.flatMap { $0 })
        for year in years.sorted() {
            let available = SeasonalEventCatalog.events(inYear: year, nameDay: nameDay).map(\.id)
            let doneThatYear = Set(completedYears.filter { $0.value.contains(year) }.keys)
            if !available.isEmpty, available.allSatisfy({ doneThatYear.contains($0) }) {
                result.append(SeasonalEventCatalog.fullYearBadgeId)
                break
            }
        }
        return result
    }
}

// SeasonTimelineModel.swift
//
// Plan -> Season as a pure model (add-season-phase-race-screens, spec
// training-season-view; design D3): the season's phases and races on one
// horizontal axis, today's mark, and the same phases and races as lists
// the screen can open.
//
// Everything on the axis is a FRACTION of the season's period, so the
// view only multiplies by a width. What is not planned is drawn, not
// hidden (the parity rule of the vault's planner, `seasonTimeline.ts`):
// the time between or around phases is a labelled gap ("No phase
// planned"), a race no phase covers says so, an approximate date is
// marked, and anything outside the season is clamped to the edge AND
// flagged -- never dropped. Race labels that would overlap go on separate
// lanes (`SeasonLanes.assign`), which never drops a label either.
//
// "Today" is the current training day (the app's day, like the race
// chip), not the file's `asOf`; the freshness notices already say when the
// file lags.
//
// Depended on by: the app's SeasonTimelineView. Tests:
// SeasonPhaseRaceTests (golden on the vault's example fixture).

import Foundation

// MARK: - Models

public enum PhaseStatusKind: String, Equatable, Sendable {
    case draft, active, closed, unknown

    init(_ status: OpenEnum<PhaseStatus>?) {
        switch status?.known {
        case .draft?: self = .draft
        case .active?: self = .active
        case .closed?: self = .closed
        case nil: self = .unknown
        }
    }
}

public enum RacePriorityKind: String, Equatable, Sendable {
    case a, b, c, unknown

    init(_ priority: OpenEnum<RacePriority>?) {
        switch priority?.known {
        case .a?: self = .a
        case .b?: self = .b
        case .c?: self = .c
        case nil: self = .unknown
        }
    }
}

public struct TimelineTickModel: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    public let fraction: Double
    /// "Oct", "Jan 2031".
    public let label: String

    public var id: LocalDate { date }
}

public struct PhaseBandModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let kindText: String?
    public let status: PhaseStatusKind
    public let statusText: String?
    /// "14 Oct – 31 Jan 2031".
    public let dateText: String
    /// "16 weeks".
    public let weeksText: String?
    public let start: Double
    public let end: Double
    /// The phase the file's `plan` is (goals, rules and weeks published).
    public let isSelected: Bool
    /// Today falls inside it.
    public let isCurrent: Bool
    /// Part of it lies outside the season and was clamped to the edge.
    public let isClamped: Bool
    public let accessibilityLabel: String
}

public struct TimelineGapModel: Equatable, Sendable, Identifiable {
    public let from: LocalDate
    public let to: LocalDate
    public let start: Double
    public let end: Double
    /// "No phase planned".
    public let label: String

    public var id: LocalDate { from }
}

public struct RaceMarkerModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let date: LocalDate
    public let dateText: String
    public let fraction: Double
    public let priority: RacePriorityKind
    /// "A", "B", "C" as written; `nil` when absent.
    public let priorityCode: String?
    /// "A race" ...; "Hero race" when `hero`.
    public let priorityText: String?
    public let isHero: Bool
    public let isApproximate: Bool
    /// No phase anchors it: "No phase covers this race yet".
    public let unanchoredText: String?
    public let isClamped: Bool
    public let isPast: Bool
    /// 0-based; labels on the same lane never overlap.
    public let lane: Int
    /// "in 11 days", "32 days ago", "today".
    public let countdown: String
    /// "30 km / 900m+", else "30 km · 900 m+".
    public let distanceText: String?
    public let accessibilityLabel: String
}

public struct TimelineMarkerModel: Equatable, Sendable {
    public let date: LocalDate
    public let fraction: Double
    public let isClamped: Bool
    public let label: String
}

public struct SeasonTimelineModel: Equatable, Sendable {
    public let title: String?
    public let goal: String?
    /// "2 Sep 2030 – 31 Aug 2031".
    public let periodText: String?
    public let ticks: [TimelineTickModel]
    /// In start order.
    public let bands: [PhaseBandModel]
    public let gaps: [TimelineGapModel]
    /// Date order.
    public let races: [RaceMarkerModel]
    /// How many label lanes the races need.
    public let lanes: Int
    public let today: TimelineMarkerModel?
    public let notices: [TrainingNotice]
    /// Set instead of the axis when there is no season to draw.
    public let emptyState: TrainingEmptyState?

    /// The next race on or after today, for the screen's highlight.
    public var nextRace: RaceMarkerModel? {
        races.first { !$0.isPast }
    }
}

// MARK: - Lanes

public enum SeasonLanes {
    /// How wide one race label is, as a fraction of the axis (a phone is
    /// narrower than the desk, so wider than the planner's 0.12).
    public static let labelWidth = 0.22

    /// Greedy lanes: each label goes on the first lane whose last label
    /// ends at or before it starts. One lane per input, in input order;
    /// nothing is dropped.
    public static func assign(_ fractions: [Double], width: Double = labelWidth) -> [Int] {
        let order = fractions.enumerated().sorted { lhs, rhs in
            (lhs.element, lhs.offset) < (rhs.element, rhs.offset)
        }
        var ends: [Double] = []
        var lanes = Array(repeating: 0, count: fractions.count)
        for (index, fraction) in order {
            var lane = 0
            while lane < ends.count && ends[lane] > fraction { lane += 1 }
            if lane == ends.count { ends.append(0) }
            ends[lane] = fraction + width
            lanes[index] = lane
        }
        return lanes
    }
}

// MARK: - Builder

public extension PlanBuilder {
    /// The season on one axis; an empty state without a season period.
    func seasonTimeline() -> SeasonTimelineModel {
        let text = format.text
        let language = format.language
        guard let snapshot = source.snapshot else {
            return SeasonTimelineModel(title: nil, goal: nil, periodText: nil, ticks: [], bands: [], gaps: [], races: [], lanes: 0, today: nil, notices: [], emptyState: format.emptyState(for: source) ?? format.emptyState(.fetching))
        }
        let notices = format.notices(snapshot.freshness)
        guard let season = snapshot.season, let from = season.period?.from, let to = season.period?.to, from < to else {
            let empty = TrainingEmptyState(kind: .noActivePlan, symbol: "chart.bar.xaxis", title: text(.seasonNoneTitle), message: text(.seasonNoneMessage))
            return SeasonTimelineModel(title: snapshot.season?.title.resolvedText(language), goal: snapshot.season?.goal.resolvedText(language), periodText: nil, ticks: [], bands: [], gaps: [], races: [], lanes: 0, today: nil, notices: notices, emptyState: empty)
        }
        let span = Double(from.days(until: to))
        func place(_ date: LocalDate) -> (fraction: Double, clamped: Bool) {
            let raw = Double(from.days(until: date)) / span
            return (min(1, max(0, raw)), raw < 0 || raw > 1)
        }

        // Ticks: the first of every month inside the period.
        var ticks: [TimelineTickModel] = []
        var tick = from.day == 1 ? from : LocalDate(dayNumber: from.firstOfMonth.adding(days: 31).firstOfMonth.dayNumber)
        while tick <= to {
            ticks.append(TimelineTickModel(date: tick, fraction: place(tick).fraction, label: format.dates.monthTick(year: tick.year, month: tick.month)))
            tick = tick.adding(days: 31).firstOfMonth
        }

        // Phase bands, in start order.
        let selectedID = snapshot.plan?.plan.phase.id
        var placed: [(band: PhaseBandModel, from: LocalDate, to: LocalDate)] = []
        for phase in season.phases {
            guard let start = phase.period?.from, let end = phase.period?.to, start <= end else { continue }
            let a = place(start)
            let b = place(end)
            let weeks = phase.outline.isEmpty ? (start.days(until: end) + 7) / 7 : phase.outline.count
            let title = phase.title.resolvedText(language) ?? phase.id
            let status = PhaseStatusKind(phase.status)
            let statusText = text.phaseStatusName(phase.status)
            let dateText = format.dates.longRange(start, end)
            let weeksText = text.format(.weeksCount, weeks)
            let spoken = [title, text.phaseKindName(phase.kind), statusText, dateText, weeksText].compactMap { $0 }.joined(separator: ", ")
            let band = PhaseBandModel(
                id: phase.id,
                title: title,
                kindText: text.phaseKindName(phase.kind),
                status: status,
                statusText: statusText,
                dateText: dateText,
                weeksText: weeksText,
                start: a.fraction,
                end: b.fraction,
                isSelected: phase.id == selectedID,
                isCurrent: start <= today && today <= end,
                isClamped: a.clamped || b.clamped,
                accessibilityLabel: spoken
            )
            placed.append((band, start, end))
        }
        placed.sort { ($0.band.start, $0.from) < ($1.band.start, $1.from) }

        // Gaps: before the first phase, between phases, after the last.
        var gaps: [TimelineGapModel] = []
        var cursor = from
        for item in placed {
            if item.from > cursor {
                let end = item.from.adding(days: -1)
                gaps.append(TimelineGapModel(from: cursor, to: end, start: place(cursor).fraction, end: place(end).fraction, label: text(.seasonNoPhase)))
            }
            let next = item.to.adding(days: 1)
            if next > cursor { cursor = next }
        }
        if cursor <= to {
            gaps.append(TimelineGapModel(from: cursor, to: to, start: place(cursor).fraction, end: 1, label: text(.seasonNoPhase)))
        }

        // Races, date order, on lanes.
        let races = season.races
        let fractions = races.map { place($0.date).fraction }
        let lanes = SeasonLanes.assign(fractions)
        let markers = races.enumerated().map { index, race in
            raceMarker(race, fraction: fractions[index], clamped: place(race.date).clamped, lane: lanes[index], snapshot: snapshot)
        }

        let todayPlace = place(today)
        return SeasonTimelineModel(
            title: season.title.resolvedText(language),
            goal: season.goal.resolvedText(language),
            periodText: format.dates.longRange(from, to),
            ticks: ticks,
            bands: placed.map { $0.band },
            gaps: gaps,
            races: markers,
            lanes: (lanes.max() ?? -1) + 1,
            today: TimelineMarkerModel(date: today, fraction: todayPlace.fraction, isClamped: todayPlace.clamped, label: text(.today)),
            notices: notices,
            emptyState: nil
        )
    }

    internal func raceMarker(_ race: Race, fraction: Double, clamped: Bool, lane: Int, snapshot: TrainingSnapshot) -> RaceMarkerModel {
        let text = format.text
        let name = race.name.resolvedText(format.language) ?? race.id
        let priorityText = race.hero ? text(.raceHero) : text.priorityName(race.priority)
        let countdown = raceCountdown(race)
        let anchored = race.phaseId.flatMap { snapshot.phase(id: $0) } != nil
        let unanchored = anchored ? nil : text(.raceUnanchored)
        let distance = raceDistanceText(race)
        let dateText = format.dates.dayMonthYear(race.date)
        let spoken = [name, priorityText, dateText, countdown, distance, unanchored].compactMap { $0 }.joined(separator: ", ")
        return RaceMarkerModel(
            id: race.id,
            name: name,
            date: race.date,
            dateText: dateText,
            fraction: fraction,
            priority: RacePriorityKind(race.priority),
            priorityCode: race.priority?.rawValue,
            priorityText: priorityText,
            isHero: race.hero,
            isApproximate: race.dateApprox,
            unanchoredText: unanchored,
            isClamped: clamped,
            isPast: race.date < today,
            lane: lane,
            countdown: countdown,
            distanceText: distance,
            accessibilityLabel: spoken
        )
    }

    /// "in 11 days", "in about 23 days", "tomorrow", "today", "32 days ago".
    internal func raceCountdown(_ race: Race) -> String {
        let days = today.days(until: race.date)
        if days < 0 {
            return format.text.format(race.dateApprox ? .countdownAboutDaysAgo : .countdownDaysAgo, -days)
        }
        return format.countdown.phrase(days: days, approximate: race.dateApprox)
    }

    /// The race's own label ("30 km / 900m+"), else "30 km · 900 m+".
    internal func raceDistanceText(_ race: Race) -> String? {
        if let label = race.distanceLabel, !label.isEmpty { return label }
        let parts = [
            race.distanceKm.map { NumberText.distance($0, format.language) },
            race.elevationM.map { NumberText.climb($0, format.language) }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

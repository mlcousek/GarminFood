// PlanModels.swift
//
// The Plan tab's week agenda and month calendar as pure models (spec
// training-plan-view; design D10):
//
//   - `WeekAgendaModel`: one ISO week, Monday first -- the week's own phase
//     (by `phaseId`, so a window week of the next phase is titled with
//     it), status, outline kind and note, targets against the vault's
//     `actual` ("Run 34 of 60 km", "5 done · 1 missed of 9"), and seven day
//     rows with sessions, the done option, fuel and unplanned activities.
//     Weeks only in an outline say their sessions aren't written yet;
//     weeks outside every phase have no plan. Paging spans the season.
//   - `MonthCalendarModel`: a 6 x 7 Monday-first grid with ISO week
//     numbers and each week's run target, up to three sport glyphs a day
//     styled by status (plus "+n"), the morning light, race flags from the
//     season's races and today's mark.
//   - `DayRowModel` doubles as the month's day sheet.
//
// add-plan-editing: a session row carries this phone's plan-change mark
// (`editBadge`: waiting for the vault, or not applied), and a written week
// lists this phone's changes for it (`planChanges`) with the vault's
// answers (PlanEditModels.swift).
//
// add-checkin-pain-score D6: a day row carries its recorded morning pain as
// tags ("Achilles (left) 5.5/10"), the vault's or the phone's answer.
//
// add-daily-checkin-and-pain-mode: a day is looked up with
// `TrainingSnapshot.day` (a written week's day, else its skeleton), so the
// month cells and the day sheet show a check-in light and unplanned
// activities outside the written weeks, with no plan too; a week that is
// not written lists such days under its message (`unwrittenDays`). Pain
// tags are built only in pain mode.
//
// Nothing is summed here: `actual`, statuses and matching come from the
// file. Glyph styles carry a shape as well as a colour in the app, so they
// are distinguishable without colour (spec "Missed and done sessions").
//
// Depended on by: the app's Plan views. Tests: PlanBuilderTests (golden on
// the vault's example fixture; W53 across the year boundary).

import Foundation

// MARK: - Models

public struct SessionRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let date: LocalDate
    public let sportSymbol: String
    public let title: String
    public let slotText: String?
    public let keyTarget: String?
    public let status: SessionStatusKind
    public let statusText: String?
    /// "Done · R", or "Done" when the option is unknown; `nil` otherwise.
    public let doneText: String?
    public let badgeText: String?
    public let fuelLine: String?
    /// add-plan-editing: this phone's change on it waits for the vault, or
    /// was not applied; with its text ("Change pending").
    public var editBadge: PlanEditBadge? = nil
    public var editBadgeText: String? = nil
}

public struct UnplannedRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let sportSymbol: String
    public let text: String
}

public struct DayRowModel: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    /// "Wed 23" (week rows) / "Wed 23 Oct" (day sheet).
    public let title: String
    public let isToday: Bool
    public let lightText: String?
    public let sessions: [SessionRowModel]
    public let unplanned: [UnplannedRowModel]
    public let fuelLine: String?
    public let raceLines: [String]
    /// "Rest day" when there is nothing at all.
    public let restText: String?
    /// add-checkin-pain-score: one tag per recorded site; `[]` when the
    /// pain was not asked or nothing hurts.
    public var painTags: [String] = []

    public var id: LocalDate { date }
}

public struct WeekAgendaModel: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case days([DayRowModel])
        /// Only in an outline: "Sessions for this week aren't written yet".
        case outlineOnly(String)
        case empty(TrainingEmptyState)
    }

    public let week: ISOWeek
    /// "W43 · 21–27 Oct".
    public let title: String
    public let phaseTitle: String?
    public let statusText: String?
    public let kindText: String?
    public let noteText: String?
    public let runLine: String?
    public let sessionsLine: String?
    public let content: Content
    public let previous: ISOWeek?
    public let next: ISOWeek?
    public let notices: [TrainingNotice]
    /// The vault's rule notes for a written week (add-hub-ingest), e.g. a
    /// red morning holding the volume.
    public var ruleNoteLines: [String] = []
    /// add-plan-editing: this phone's plan changes for the week, with the
    /// vault's answers.
    public var planChanges: [PlanChangeLineModel] = []
    /// add-daily-checkin-and-pain-mode: in a week that is not written (or
    /// with no plan), the days that still have something to show -- a
    /// check-in light, an unplanned activity, pain tags in pain mode.
    public var unwrittenDays: [DayRowModel] = []
}

public enum GlyphStyle: String, Equatable, Sendable {
    case done, planned, missed, skipped, unplanned, unknown
}

public struct DayGlyph: Equatable, Sendable, Identifiable {
    public let id: String
    public let sportSymbol: String
    public let style: GlyphStyle
}

public struct DayCellModel: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    public let dayNumber: Int
    public let isInMonth: Bool
    public let isToday: Bool
    /// At most three.
    public let glyphs: [DayGlyph]
    /// How many more than three.
    public let overflow: Int
    public let lightName: String?
    public let raceNames: [String]
    public let accessibilityLabel: String

    public var id: LocalDate { date }
    public var isRaceDay: Bool { !raceNames.isEmpty }
    public var hasContent: Bool { !glyphs.isEmpty || isRaceDay }
}

public struct MonthWeekRowModel: Equatable, Sendable, Identifiable {
    public let week: ISOWeek
    /// "W43".
    public let label: String
    /// "60 km".
    public let targetText: String?
    public let cells: [DayCellModel]

    public var id: ISOWeek { week }
}

public struct MonthCalendarModel: Equatable, Sendable {
    public let year: Int
    public let month: Int
    /// "October 2030".
    public let title: String
    /// Monday first.
    public let weekdayHeaders: [String]
    /// Always six.
    public let rows: [MonthWeekRowModel]
    public let notices: [TrainingNotice]
    public let emptyState: TrainingEmptyState?

    /// (year, month) of the month before / after.
    public var previous: (year: Int, month: Int) { MonthCalendarModel.shift(year: year, month: month, by: -1) }
    public var next: (year: Int, month: Int) { MonthCalendarModel.shift(year: year, month: month, by: 1) }

    public static func shift(year: Int, month: Int, by delta: Int) -> (year: Int, month: Int) {
        let index = year * 12 + (month - 1) + delta
        return (index / 12, index % 12 + 1)
    }
}

// MARK: - Builder

public struct PlanBuilder: Sendable {
    public let source: TrainingSource
    public let format: TrainingFormatting
    /// The current training day (today's mark, "today" for countdowns).
    public let today: LocalDate

    public init(source: TrainingSource, language: TrainingLanguage, today: LocalDate) {
        self.source = source
        self.format = TrainingFormatting(language: language, zones: source.snapshot?.athlete.hrZones)
        self.today = today
    }

    private var text: TrainingText { format.text }

    // MARK: Week

    public func week(_ isoWeek: ISOWeek) -> WeekAgendaModel {
        var model = baseWeek(isoWeek)
        if case .days = model.content { return model }
        guard let snapshot = source.snapshot else { return model }
        var rows: [DayRowModel] = []
        for date in isoWeek.days {
            guard let day = snapshot.day(date) else { continue }
            let hasPain = snapshot.painMode.isActive && !(day.pains ?? []).isEmpty
            if day.light?.known != nil || !day.unplanned.isEmpty || hasPain {
                // Not "Rest day": nothing is known about an unwritten day.
                rows.append(dayRow(date, snapshot: snapshot, long: false, restWhenEmpty: false))
            }
        }
        model.unwrittenDays = rows
        return model
    }

    private func baseWeek(_ isoWeek: ISOWeek) -> WeekAgendaModel {
        let title = format.weekTitle(isoWeek)
        guard let snapshot = source.snapshot else {
            let state = format.emptyState(for: source) ?? format.emptyState(.fetching)
            return WeekAgendaModel(week: isoWeek, title: title, phaseTitle: nil, statusText: nil, kindText: nil, noteText: nil, runLine: nil, sessionsLine: nil, content: .empty(state), previous: nil, next: nil, notices: [])
        }
        let notices = format.notices(snapshot.freshness)
        let range = snapshot.pagingRange
        let previous = range.flatMap { isoWeek.adding(weeks: -1) >= $0.lowerBound ? isoWeek.adding(weeks: -1) : nil }
        let next = range.flatMap { isoWeek.adding(weeks: 1) <= $0.upperBound ? isoWeek.adding(weeks: 1) : nil }

        guard let plan = snapshot.plan else {
            return WeekAgendaModel(week: isoWeek, title: title, phaseTitle: nil, statusText: nil, kindText: nil, noteText: nil, runLine: nil, sessionsLine: nil, content: .empty(format.emptyState(.noActivePlan)), previous: previous, next: next, notices: notices)
        }
        let outline = snapshot.outlineRow(for: isoWeek)

        if let written = plan.week(isoWeek) {
            let phase = snapshot.phase(id: written.phaseId) ?? outline?.phase
            let targetKm = written.targets.runKm ?? outline?.row.runKmTarget
            var model = WeekAgendaModel(
                week: isoWeek,
                title: title,
                phaseTitle: phase?.title.resolvedText(format.language),
                statusText: text.weekStatusName(written.status),
                kindText: text.outlineKindName(outline?.row.kind),
                noteText: outline?.row.note.resolvedText(format.language),
                runLine: runLine(actual: written.actual, targetKm: targetKm),
                sessionsLine: sessionsLine(actual: written.actual, planned: written.targets.sessions),
                content: .days(isoWeek.days.map { dayRow($0, snapshot: snapshot, long: false) }),
                previous: previous,
                next: next,
                notices: notices
            )
            model.ruleNoteLines = written.ruleNotes.compactMap(format.freeText)
            model.planChanges = planChangeLines(isoWeek, snapshot: snapshot)
            return model
        }
        if let outline {
            return WeekAgendaModel(
                week: isoWeek,
                title: title,
                phaseTitle: outline.phase.title.resolvedText(format.language),
                statusText: nil,
                kindText: text.outlineKindName(outline.row.kind),
                noteText: outline.row.note.resolvedText(format.language),
                runLine: outline.row.runKmTarget.map { text.format(.weekRunTarget, NumberText.decimal($0, format.language)) },
                sessionsLine: nil,
                content: .outlineOnly(text(.weekNotWrittenMessage)),
                previous: previous,
                next: next,
                notices: notices
            )
        }
        let phase = isoWeek.days.lazy.compactMap { snapshot.phase(containing: $0) }.first
        return WeekAgendaModel(
            week: isoWeek,
            title: title,
            phaseTitle: phase?.title.resolvedText(format.language),
            statusText: nil,
            kindText: nil,
            noteText: nil,
            runLine: nil,
            sessionsLine: nil,
            content: .empty(format.emptyState(.noPlanThisWeek)),
            previous: previous,
            next: next,
            notices: notices
        )
    }

    /// The week Plan opens on: the one containing `date`.
    public func week(containing date: LocalDate) -> WeekAgendaModel {
        week(ISOWeek(containing: date))
    }

    private func runLine(actual: WeekActual?, targetKm: Double?) -> String? {
        let language = format.language
        if let done = actual?.runKm {
            if let targetKm {
                return text.format(.weekRunOfTarget, NumberText.decimal(done, language), NumberText.decimal(targetKm, language))
            }
            return text.format(.weekRun, NumberText.decimal(done, language))
        }
        return targetKm.map { text.format(.weekRunTarget, NumberText.decimal($0, language)) }
    }

    private func sessionsLine(actual: WeekActual?, planned: Int?) -> String? {
        if let actual, let done = actual.sessionsDone, let missed = actual.sessionsMissed, let planned {
            return text.format(.weekSessionsDoneMissed, done, missed, planned)
        }
        return planned.map { text.format(.weekSessionsPlanned, $0) }
    }

    // MARK: Days

    /// A day's sessions and unplanned activities: a week row, or the
    /// month's day sheet (`long` titles it with the month).
    public func dayRow(_ date: LocalDate, long: Bool = true) -> DayRowModel {
        guard let snapshot = source.snapshot else {
            return DayRowModel(date: date, title: format.dates.short(date), isToday: date == today, lightText: nil, sessions: [], unplanned: [], fuelLine: nil, raceLines: [], restText: text(.stateRestDayTitle))
        }
        return dayRow(date, snapshot: snapshot, long: long)
    }

    /// `restWhenEmpty`: say "Rest day" when the day has nothing at all
    /// (off for the days listed under a week that is not written).
    func dayRow(_ date: LocalDate, snapshot: TrainingSnapshot, long: Bool, restWhenEmpty: Bool = true) -> DayRowModel {
        let day = snapshot.day(date)
        let sessions = (day?.sessions ?? []).map { sessionRow($0, date: date, snapshot: snapshot) }
        let unplanned = (day?.unplanned ?? []).enumerated().map { index, activity in
            UnplannedRowModel(id: "\(date)-unplanned-\(index)", sportSymbol: SportSymbol.name(activity.group), text: format.unplannedLine(activity))
        }
        let races = snapshot.races(on: date).map { race in
            text.format(.raceDayLine, race.name.resolvedText(format.language) ?? race.id)
        }
        let isEmpty = sessions.isEmpty && unplanned.isEmpty && races.isEmpty
        var row = DayRowModel(
            date: date,
            title: long ? format.dates.short(date) : format.dates.weekdayAndDay(date),
            isToday: date == today,
            lightText: text.lightName(day?.light).map { text.format(.lightLine, $0) },
            sessions: sessions,
            unplanned: unplanned,
            fuelLine: format.fuel.dayLine(day?.fuel),
            raceLines: races,
            restText: isEmpty && restWhenEmpty ? text(.stateRestDayTitle) : nil
        )
        // Only in pain mode (add-daily-checkin-and-pain-mode).
        if snapshot.painMode.isActive {
            row.painTags = format.painTags(day?.pains)
        }
        return row
    }

    func sessionRow(_ session: Session, date: LocalDate, snapshot: TrainingSnapshot) -> SessionRowModel {
        let status = SessionStatusKind(session.status)
        var doneText: String?
        if status == .done {
            if let code = session.done?.option?.rawValue, !session.options.isEmpty {
                doneText = text.format(.doneWithOption, code)
            } else {
                doneText = text(.statusDone)
            }
        }
        let badgeText: String?
        switch session.type?.known {
        case .test?: badgeText = text(.badgeTest)
        case .race?: badgeText = text(.race)
        default: badgeText = nil
        }
        var row = SessionRowModel(
            id: session.id,
            date: date,
            sportSymbol: SportSymbol.name(session.sport),
            title: format.title(of: session, in: snapshot),
            slotText: text.slotName(session.slot),
            keyTarget: format.targets.key(session.targets),
            status: status,
            statusText: text.statusName(session.status),
            doneText: doneText,
            badgeText: badgeText,
            fuelLine: format.fuel.sessionLine(session.fuel)
        )
        if let mark = format.editBadge(sessionID: session.id, snapshot: snapshot) {
            row.editBadge = mark.badge
            row.editBadgeText = mark.text
        }
        return row
    }

    // MARK: Month

    public static let maxGlyphs = 3

    public func month(year: Int, month: Int) -> MonthCalendarModel {
        let first = LocalDate(year: year, month: month, day: 1) ?? today.firstOfMonth
        let firstWeek = ISOWeek(containing: first)
        let snapshot = source.snapshot
        let rows = (0..<6).map { offset -> MonthWeekRowModel in
            let isoWeek = firstWeek.adding(weeks: offset)
            let target = snapshot.flatMap { snapshot -> Double? in
                snapshot.plan?.week(isoWeek)?.targets.runKm ?? snapshot.outlineRow(for: isoWeek)?.row.runKmTarget
            }
            return MonthWeekRowModel(
                week: isoWeek,
                label: text.format(.weekNumber, isoWeek.week),
                targetText: target.map { NumberText.distance($0, format.language) },
                cells: isoWeek.days.map { cell($0, month: first.month, snapshot: snapshot) }
            )
        }
        return MonthCalendarModel(
            year: first.year,
            month: first.month,
            title: format.dates.monthTitle(year: first.year, month: first.month),
            weekdayHeaders: format.dates.weekdayHeaders,
            rows: rows,
            notices: snapshot.map { format.notices($0.freshness) } ?? [],
            emptyState: snapshot == nil ? format.emptyState(for: source) : (snapshot?.plan == nil ? format.emptyState(.noActivePlan) : nil)
        )
    }

    public func month(containing date: LocalDate) -> MonthCalendarModel {
        month(year: date.year, month: date.month)
    }

    func cell(_ date: LocalDate, month: Int, snapshot: TrainingSnapshot?) -> DayCellModel {
        let day = snapshot?.day(date)
        var glyphs: [DayGlyph] = []
        for session in day?.sessions ?? [] {
            glyphs.append(DayGlyph(id: session.id, sportSymbol: SportSymbol.name(session.sport), style: glyphStyle(session.status)))
        }
        for (index, activity) in (day?.unplanned ?? []).enumerated() {
            glyphs.append(DayGlyph(id: "\(date)-unplanned-\(index)", sportSymbol: SportSymbol.name(activity.group), style: .unplanned))
        }
        let races = snapshot?.races(on: date).map { $0.name.resolvedText(format.language) ?? $0.id } ?? []
        let lightName = text.lightName(day?.light)
        let shown = Array(glyphs.prefix(Self.maxGlyphs))

        var spoken = [format.dates.short(date)]
        if date == today { spoken.append(text(.today)) }
        for glyph in glyphs {
            if let snapshot, let session = day?.sessions.first(where: { $0.id == glyph.id }) {
                spoken.append([format.title(of: session, in: snapshot), text.statusName(session.status)].compactMap { $0 }.joined(separator: ", "))
            } else {
                spoken.append(text(.unplanned))
            }
        }
        spoken.append(contentsOf: races.map { text.format(.raceDayLine, $0) })
        if let lightName { spoken.append(text.format(.lightLine, lightName)) }

        return DayCellModel(
            date: date,
            dayNumber: date.day,
            isInMonth: date.month == month,
            isToday: date == today,
            glyphs: shown,
            overflow: max(0, glyphs.count - shown.count),
            lightName: lightName,
            raceNames: races,
            accessibilityLabel: spoken.joined(separator: ". ")
        )
    }

    private func glyphStyle(_ status: OpenEnum<SessionStatus>?) -> GlyphStyle {
        switch SessionStatusKind(status) {
        case .done: return .done
        case .planned: return .planned
        case .missed: return .missed
        case .skipped: return .skipped
        case .unknown: return .unknown
        }
    }
}

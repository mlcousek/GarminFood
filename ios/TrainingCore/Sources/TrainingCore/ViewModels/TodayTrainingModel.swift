// TodayTrainingModel.swift
//
// The four training cards on Today, as pure models (spec training-today;
// design D7, D8):
//
//   - `TodayTrainingModel` -- the day's sessions with their G/A/R option
//     cards (or one card for a session without options), status, test or
//     race badge, fuel lines and the morning light, or a designed state;
//   - `HabitRowModel` -- today's expected habits, display only (and the
//     rows of polish-training-today's Habits card, HabitsCardModel.swift);
//   - `RaceChipModel` -- the next race of any priority, as a countdown,
//     with the season's main (hero, else A) race when that is a later one
//     (polish-training-today D3; it was the next A or hero race);
//   - `WeeklyNoteTeaserModel` -- this week's AI note, else the latest
//     earlier week's.
//
// An option's action is always `.openDetail`: tapping a card to read it
// never records anything. add-training-checkins (design D6) adds, when
// `TrainingCapabilities` allow it, the morning check-in row
// (`TodayTrainingModel.checkIn`, CheckInModels.swift) and on/off habit
// ticks (`HabitTick.tickable`); a check-in's light reaches the option
// cards as the existing morning-light highlight, through `EffectivePlan`.
//
// The highlighted option is the done one (with a check), else the one the
// morning light points at, else none; a done session whose option the
// vault couldn't tell (G and A are both runs) reads "Done" with no card
// marked (design D7, deviation 15).
//
// Depended on by: the app's Today cards (Training/). Tests:
// TodayBuilderTests (golden, on the vault's example fixture).

import Foundation

// MARK: - Models

public enum SessionStatusKind: String, Equatable, Sendable {
    case planned, done, missed, skipped, unknown

    init(_ status: OpenEnum<SessionStatus>?) {
        switch status?.known {
        case .planned?: self = .planned
        case .done?: self = .done
        case .missed?: self = .missed
        case .skipped?: self = .skipped
        case nil: self = .unknown
        }
    }
}

public enum SessionBadge: String, Equatable, Sendable {
    case test, race
}

public struct OptionCardModel: Equatable, Sendable, Identifiable {
    public enum Highlight: Equatable, Sendable {
        /// The option that was done (shown with a check).
        case done
        /// The option the morning light points at.
        case morningLight
    }

    public enum Action: Equatable, Sendable {
        /// Opens the session detail at this option; records nothing.
        case openDetail(sessionID: String, option: String?)
    }

    public let sessionID: String
    /// "G", "A", "R"; `nil` for a session's single card.
    public let code: String?
    public let knownCode: OptionCode?
    /// "Planned session", "Easier", "Alternative".
    public let meaning: String?
    public let label: String
    public let sportSymbol: String
    public let targetLines: [String]
    /// Reserved until the Garmin push change publishes it.
    public let watchLine: String?
    public let highlight: Highlight?
    public let action: Action
    /// One VoiceOver element: letter with meaning, label, targets, state.
    public let accessibilityLabel: String

    public var id: String { "\(sessionID)|\(code ?? "-")" }
}

public struct SessionCardModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let date: LocalDate
    public let slotText: String?
    public let sportSymbol: String
    public let sportName: String?
    public let title: String
    public let status: SessionStatusKind
    public let statusText: String?
    public let badge: SessionBadge?
    public let badgeText: String?
    /// G, A, R for a traffic-light session.
    public let options: [OptionCardModel]
    /// The one card of a session without options.
    public let single: OptionCardModel?
    public let fuelLine: String?
    /// Done, but the vault couldn't tell which option.
    public let doneOptionUnknown: Bool
    /// add-plan-editing: "Change pending" while this phone's change on it
    /// waits for the vault, "Change not applied" when the vault did not
    /// apply it; else `nil`.
    public let pendingBadge: String?
    /// The compact variant's one line.
    public let compactLine: String
}

public struct TodayTrainingModel: Equatable, Sendable {
    public let date: LocalDate
    public let dateText: String
    public let sessions: [SessionCardModel]
    /// Set instead of sessions for every non-happy state (design D11).
    public let emptyState: TrainingEmptyState?
    public let carbLoadLine: String?
    public let lightLine: String?
    public let notices: [TrainingNotice]
    /// add-training-checkins: the morning check-in row, when allowed.
    public var checkIn: CheckInRowModel? = nil
}

public enum HabitTick: Equatable, Sendable {
    /// No control: ticking isn't allowed (no vault device id).
    case displayOnly
    /// add-training-checkins (decision A42): an on/off toggle. `pending`
    /// while the phone's latest tick is not uploaded yet.
    case tickable(done: Bool, pending: Bool)
}

public struct HabitRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let icon: String?
    public let label: String
    public let dose: String?
    public let schedule: String?
    /// "18 of 24 · 75 %" or "not recorded yet".
    public let adherence: String
    /// 0...1 for the ring; `nil` when not recorded.
    public let fraction: Double?
    /// The gate as 0...1.
    public let gateFraction: Double?
    /// "Today: 1 of 2", when the vault published the day's count.
    public let doneToday: String?
    public let tick: HabitTick
    /// polish-training-today: the plan expects it on the shown day (the
    /// Habits card also lists active habits that are not expected).
    public var isScheduledToday: Bool = true
    /// "Not on today's plan" when not scheduled.
    public var notTodayText: String? = nil
}

public struct RaceChipModel: Equatable, Sendable {
    public let raceID: String
    public let name: String
    public let date: LocalDate
    public let dateText: String
    /// "in 23 days", "in about 23 days", "tomorrow", "today".
    public let countdown: String
    /// polish-training-today D3: "A", "B", "C" as written; `nil` when absent.
    public let priorityCode: String?
    public let priority: RacePriorityKind
    /// "B race", or "Hero race" for the hero.
    public let priorityText: String?
    public let isHero: Bool
    /// The season's main race when it is not this one.
    public let mainRace: MainRaceLineModel?
    public let accessibilityLabel: String
}

/// The chip's second line: the hero race, else the next A race.
public struct MainRaceLineModel: Equatable, Sendable {
    public let raceID: String
    public let name: String
    public let countdown: String
    /// "Main race: Ridge Ultra · in about 241 days".
    public let text: String
}

public struct WeeklyNoteTeaserModel: Equatable, Sendable, Identifiable {
    public var id: ISOWeek { week }
    public let week: ISOWeek
    /// "W42 · 14–20 Oct".
    public let weekLabel: String
    public let isCurrentWeek: Bool
    public let text: String
}

// MARK: - Builder

public struct TodayTrainingBuilder: Sendable {
    public let source: TrainingSource
    public let format: TrainingFormatting

    public init(source: TrainingSource, language: TrainingLanguage) {
        self.source = source
        self.format = TrainingFormatting(language: language, zones: source.snapshot?.athlete.hrZones)
    }

    private var text: TrainingText { format.text }

    /// The training card for `date` (already resolved by `TrainingDay`),
    /// with the check-in row when allowed (add-training-checkins D6).
    public func trainingDay(on date: LocalDate) -> TodayTrainingModel {
        var model = baseTrainingDay(on: date)
        model.checkIn = checkInRow(on: date)
        return model
    }

    private func baseTrainingDay(on date: LocalDate) -> TodayTrainingModel {
        let dateText = format.dates.short(date)
        guard let snapshot = source.snapshot else {
            return TodayTrainingModel(date: date, dateText: dateText, sessions: [], emptyState: format.emptyState(for: source), carbLoadLine: nil, lightLine: nil, notices: [])
        }
        let notices = format.notices(snapshot.freshness)
        func empty(_ state: TrainingEmptyState, day: Day? = nil) -> TodayTrainingModel {
            TodayTrainingModel(date: date, dateText: dateText, sessions: [], emptyState: state, carbLoadLine: format.fuel.dayLine(day?.fuel), lightLine: nil, notices: notices)
        }
        guard let plan = snapshot.plan else {
            return empty(format.emptyState(.noActivePlan))
        }
        guard let day = plan.day(date) else {
            let isoWeek = ISOWeek(containing: date)
            if plan.week(isoWeek) != nil {
                // A written week without this day (a malformed file):
                // nothing is planned that the app knows of.
                return empty(format.emptyState(.restDay))
            }
            if let outline = snapshot.outlineRow(for: isoWeek) {
                return empty(format.emptyState(.weekNotWritten, target: outline.row.runKmTarget))
            }
            return empty(format.emptyState(.noPlanThisWeek))
        }
        let lightLine = format.text.lightName(day.light).map { text.format(.lightLine, $0) }
        guard !day.sessions.isEmpty else {
            return TodayTrainingModel(date: date, dateText: dateText, sessions: [], emptyState: format.emptyState(.restDay), carbLoadLine: format.fuel.dayLine(day.fuel), lightLine: lightLine, notices: notices)
        }
        return TodayTrainingModel(
            date: date,
            dateText: dateText,
            sessions: day.sessions.map { sessionCard($0, day: day, snapshot: snapshot) },
            emptyState: nil,
            carbLoadLine: format.fuel.dayLine(day.fuel),
            lightLine: lightLine,
            notices: notices
        )
    }

    func sessionCard(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> SessionCardModel {
        let status = SessionStatusKind(session.status)
        let title = format.title(of: session, in: snapshot)
        let badge: SessionBadge? = session.type?.known == .test ? .test : (session.type?.known == .race ? .race : nil)
        let badgeText = badge.map { $0 == .test ? text(.badgeTest) : text(.race) }
        let doneCode = status == .done ? session.done?.option?.known : nil
        let lightCode = day.light?.known?.option

        let options = session.options.map { option -> OptionCardModel in
            let highlight: OptionCardModel.Highlight?
            if let doneCode {
                highlight = option.code.known == doneCode ? .done : nil
            } else if status != .done, let lightCode {
                highlight = option.code.known == lightCode ? .morningLight : nil
            } else {
                highlight = nil
            }
            return optionCard(option, session: session, highlight: highlight)
        }
        let single: OptionCardModel? = session.options.isEmpty ? singleCard(session, title: title, snapshot: snapshot) : nil
        let statusText = text.statusName(session.status)
        let compact = [text.slotName(session.slot), title, format.targets.key(session.targets), statusText]
            .compactMap { $0 }
            .joined(separator: " · ")

        return SessionCardModel(
            id: session.id,
            date: day.date,
            slotText: text.slotName(session.slot),
            sportSymbol: SportSymbol.name(session.sport),
            sportName: text.sportName(session.sport),
            title: title,
            status: status,
            statusText: statusText,
            badge: badge,
            badgeText: badgeText,
            options: options,
            single: single,
            fuelLine: format.fuel.sessionLine(session.fuel),
            doneOptionUnknown: status == .done && !session.options.isEmpty && doneCode == nil,
            pendingBadge: format.editBadge(sessionID: session.id, snapshot: snapshot)?.text,
            compactLine: compact
        )
    }

    private func optionCard(_ option: SessionOption, session: Session, highlight: OptionCardModel.Highlight?) -> OptionCardModel {
        let label = option.label.resolvedText(format.language) ?? option.code.rawValue
        let lines = format.targets.lines(option.targets)
        let meaning = text.optionMeaning(option.code)
        var spoken = text.format(.a11yOption, option.code.rawValue, meaning ?? option.code.rawValue, label)
        if !lines.isEmpty { spoken += ", " + lines.joined(separator: ", ") }
        let watch = watchLine(option.watch)
        if let watch { spoken += ". " + watch }
        switch highlight {
        case .done?: spoken += ". " + text(.statusDone)
        case .morningLight?: spoken += ". " + text(.a11yMatchesLight)
        case nil: break
        }
        return OptionCardModel(
            sessionID: session.id,
            code: option.code.rawValue,
            knownCode: option.code.known,
            meaning: meaning,
            label: label,
            sportSymbol: SportSymbol.name(option.sport ?? session.sport),
            targetLines: lines,
            watchLine: watch,
            highlight: highlight,
            action: .openDetail(sessionID: session.id, option: option.code.rawValue),
            accessibilityLabel: spoken
        )
    }

    private func singleCard(_ session: Session, title: String, snapshot: TrainingSnapshot) -> OptionCardModel {
        let lines = format.targets.lines(session.targets)
        var spoken = title
        if !lines.isEmpty { spoken += ", " + lines.joined(separator: ", ") }
        if let status = text.statusName(session.status) { spoken += ". " + status }
        return OptionCardModel(
            sessionID: session.id,
            code: nil,
            knownCode: nil,
            meaning: nil,
            label: title,
            sportSymbol: SportSymbol.name(session.sport),
            targetLines: lines,
            watchLine: nil,
            highlight: nil,
            action: .openDetail(sessionID: session.id, option: nil),
            accessibilityLabel: spoken
        )
    }

    /// The option's watch-push state (contract point 12): `scheduled` is
    /// "on Garmin calendar" -- the channel's calendar, not the watch's own
    /// list. An unknown state shows nothing.
    func watchLine(_ watch: OptionWatch?) -> String? {
        switch watch?.state?.known {
        case .scheduled?: return text(.watchScheduled)
        case .pending?: return text(.watchPending)
        case .failed?: return text(.watchFailed)
        case nil: return nil
        }
    }

    // MARK: Habits

    /// The habits the plan expects on `date`; empty hides the card.
    public func habits(on date: LocalDate) -> [HabitRowModel] {
        guard let snapshot = source.snapshot, let day = snapshot.plan?.day(date) else { return [] }
        return day.habitsExpected.compactMap { id in
            guard let habit = snapshot.habits.habit(id) else { return nil }
            return habitRow(habit, day: day, gate: snapshot.habits.gate, snapshot: snapshot)
        }
    }

    func habitRow(_ habit: Habit, day: Day?, gate: HabitGate, snapshot: TrainingSnapshot? = nil, scheduled: Bool = true) -> HabitRowModel {
        let adherence = HabitText.adherence(habit.window14, gate: gate, text: text)
        let doneCount: Int? = day?.habitsDone?[habit.id]
        let doneToday = doneCount.map {
            text.format(.habitTodayCount, $0, habit.schedule?.expectedPerDay ?? 1)
        }
        return HabitRowModel(
            id: habit.id,
            icon: habit.icon,
            label: habit.label.resolvedText(format.language) ?? habit.id,
            dose: habit.dose.resolvedText(format.language),
            schedule: format.schedule.line(habit.schedule),
            adherence: adherence,
            fraction: habit.window14?.pct.map { Double(min(max($0, 0), 100)) / 100 },
            gateFraction: gate.adherencePct.map { Double(min(max($0, 0), 100)) / 100 },
            doneToday: doneToday,
            tick: habitTick(habit, day: day, snapshot: snapshot),
            isScheduledToday: scheduled,
            notTodayText: scheduled ? nil : text(.habitNotToday)
        )
    }

    /// add-training-checkins: an on/off toggle when ticking is allowed.
    private func habitTick(_ habit: Habit, day: Day?, snapshot: TrainingSnapshot?) -> HabitTick {
        guard let snapshot, let day, snapshot.capabilities.canTickHabits else { return .displayOnly }
        let state = snapshot.habitDone(habit.id, on: day.date)
        return .tickable(done: state.done, pending: state.local?.delivery == .savedOnPhone)
    }

    // MARK: Race chip

    /// polish-training-today D3: the next race on or after `date`, of any
    /// priority (it was A or hero only), with the season's main race --
    /// the next hero race, else the next A race -- as a second line when
    /// that is a different, later race. `nil` hides the chip.
    public func raceChip(from date: LocalDate) -> RaceChipModel? {
        guard let snapshot = source.snapshot else { return nil }
        let upcoming = snapshot.races.filter { $0.date >= date }
        guard let race = upcoming.first else { return nil }
        let name = race.name.resolvedText(format.language) ?? race.id
        let countdown = format.countdown.phrase(days: date.days(until: race.date), approximate: race.dateApprox)
        let priorityText = race.hero ? text(.raceHero) : text.priorityName(race.priority)

        let main = upcoming.first(where: { $0.hero }) ?? upcoming.first(where: { $0.priority?.known == .a })
        var mainLine: MainRaceLineModel?
        if let main, main.id != race.id {
            let mainName = main.name.resolvedText(format.language) ?? main.id
            let mainCountdown = format.countdown.phrase(days: date.days(until: main.date), approximate: main.dateApprox)
            mainLine = MainRaceLineModel(
                raceID: main.id,
                name: mainName,
                countdown: mainCountdown,
                text: text.format(.raceMainLine, mainName, mainCountdown)
            )
        }
        let spoken = [name, priorityText, countdown].compactMap { $0 }.joined(separator: ", ")
            + (mainLine.map { ". " + $0.text } ?? "")
        return RaceChipModel(
            raceID: race.id,
            name: name,
            date: race.date,
            dateText: format.dates.short(race.date),
            countdown: countdown,
            priorityCode: race.priority?.rawValue,
            priority: RacePriorityKind(race.priority),
            priorityText: priorityText,
            isHero: race.hero,
            mainRace: mainLine,
            accessibilityLabel: spoken
        )
    }

    // MARK: Weekly note

    /// This week's `aiNote`, else the latest earlier window week's.
    public func weeklyNote(for date: LocalDate) -> WeeklyNoteTeaserModel? {
        guard let plan = source.snapshot?.plan else { return nil }
        let current = ISOWeek(containing: date)
        let candidates = plan.weeks
            .filter { $0.week <= current }
            .sorted { $0.week > $1.week }
        for week in candidates {
            guard let note = week.aiNote.resolvedText(format.language) else { continue }
            return WeeklyNoteTeaserModel(
                week: week.week,
                weekLabel: format.weekTitle(week.week),
                isCurrentWeek: week.week == current,
                text: note
            )
        }
        return nil
    }
}

/// Adherence text shared by Today and the ladder.
enum HabitText {
    /// "18 of 24 · 75 %" (+ " · over 12 recorded days" when fewer than the
    /// window), or "not recorded yet".
    static func adherence(_ window: HabitWindow?, gate: HabitGate, text: TrainingText) -> String {
        guard let window, let done = window.done, let expected = window.expected else {
            return text(.habitNotRecorded)
        }
        let pct = window.pct ?? (expected > 0 ? done * 100 / expected : 0)
        var line = text.format(.habitWindow, done, expected, pct)
        let windowDays = gate.windowDays ?? 14
        if let recorded = window.recordedDays, recorded < windowDays {
            line += " · " + text.format(.habitRecordedDays, recorded)
        }
        return line
    }
}

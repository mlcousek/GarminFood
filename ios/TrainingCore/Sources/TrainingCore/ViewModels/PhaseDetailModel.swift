// PhaseDetailModel.swift
//
// One phase as a pure model (add-season-phase-race-screens, spec
// training-phase-view; design D4): its header (kind, status, dates, where
// today falls in it), goals and rules, the week-by-week run targets
// against the vault's `actual`, the key sessions and test results inside
// it, its races and, once it is closed, its recap with a short summary.
//
// `PhaseRamp` is the ONE computation of planned vs actual per outline
// week in the app (the vault planner's `rampSeries`/`rampTotals`): the
// Phase screen draws it and add-training-stats' volume view reuses it, so
// the two cannot disagree about the same phase. Its figures are the
// vault's: a week's target is the written week's `targets.runKm`, else the
// outline row's (contract point 4; the same number Plan -> Week shows),
// and its actual is the written week's `actual.runKm`. Nothing is
// estimated: a week that has started but is not in the file's window of
// written weeks has NO actual ("not in the app's window"), never 0 --
// the phone has no diary to fall back on.
//
// Only the SELECTED phase (the file's `plan`) carries goals, rules and
// concrete weeks; any other phase has its summary only, and the model
// says so (`restrictedText`) instead of showing empty sections that would
// read as empty facts.
//
// Depended on by: the app's PhaseDetailView; StatsModels (add-training-
// stats). Tests: SeasonPhaseRaceTests.

import Foundation

// MARK: - Ramp

/// One outline week of a phase: planned against done, as the vault has it.
public struct RampWeek: Equatable, Sendable, Identifiable {
    public let week: ISOWeek
    public let phaseID: String
    public let kind: OpenEnum<OutlineKind>?
    public let note: LocalizedText?
    public let targetKm: Double?
    /// `nil` for a future week, and for a started week outside the window.
    public let actualKm: Double?
    public let isCurrent: Bool
    public let isFuture: Bool
    /// Started, but the file holds no written week for it.
    public let isOutsideWindow: Bool

    public var id: ISOWeek { week }
}

/// The biggest known week of a ramp.
public struct RampPeak: Equatable, Sendable {
    public let week: ISOWeek
    public let km: Double
}

public struct RampTotals: Equatable, Sendable {
    public var weeks = 0
    public var plannedTotal = 0.0
    /// Planned km over the weeks WITH a known actual (like for like).
    public var plannedKnown = 0.0
    public var actualTotal = 0.0
    public var knownWeeks = 0
    /// Started weeks without an actual.
    public var unknownWeeks = 0
    public var deloads = 0
    /// Weeks with a known actual within +-10 % of their target.
    public var withinTen = 0
    public var biggest: RampPeak?
    public var meanWeekly: Double?

    public init() {}
}

public enum PhaseRamp {
    /// The phase's outline weeks with their target and the vault's actual.
    public static func series(_ phase: PhaseSummary, snapshot: TrainingSnapshot, today: LocalDate) -> [RampWeek] {
        phase.outline.map { row -> RampWeek in
            let written = snapshot.plan?.week(row.week)
            let isFuture = row.week.monday > today
            let isCurrent = row.week.contains(today)
            let actual = isFuture ? nil : written?.actual?.runKm
            return RampWeek(
                week: row.week,
                phaseID: phase.id,
                kind: row.kind,
                note: row.note,
                targetKm: written?.targets.runKm ?? row.runKmTarget,
                actualKm: actual,
                isCurrent: isCurrent,
                isFuture: isFuture,
                isOutsideWindow: !isFuture && written == nil
            )
        }
    }

    public static func totals(_ ramp: [RampWeek]) -> RampTotals {
        var totals = RampTotals()
        totals.weeks = ramp.count
        for week in ramp {
            if let target = week.targetKm { totals.plannedTotal += target }
            if week.kind?.known == .deload { totals.deloads += 1 }
            if week.isFuture { continue }
            guard let actual = week.actualKm else {
                totals.unknownWeeks += 1
                continue
            }
            totals.knownWeeks += 1
            totals.actualTotal += actual
            if let target = week.targetKm {
                totals.plannedKnown += target
                if target > 0, abs(actual - target) / target <= 0.1 { totals.withinTen += 1 }
            }
            if totals.biggest.map({ actual > $0.km }) ?? true { totals.biggest = RampPeak(week: week.week, km: actual) }
        }
        totals.plannedTotal = round1(totals.plannedTotal)
        totals.plannedKnown = round1(totals.plannedKnown)
        totals.actualTotal = round1(totals.actualTotal)
        totals.meanWeekly = totals.knownWeeks > 0 ? round1(totals.actualTotal / Double(totals.knownWeeks)) : nil
        return totals
    }

    static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

// MARK: - Models

public struct PhaseWeekRowModel: Equatable, Sendable, Identifiable {
    public let week: ISOWeek
    /// "W43 · 21–27 Oct".
    public let title: String
    public let kindText: String?
    public let noteText: String?
    /// "60 km"; `nil` without a target.
    public let targetText: String?
    /// "10.1 km"; "Not in the app's window" for a started week the file
    /// doesn't hold; `nil` for a future week.
    public let actualText: String?
    public let targetKm: Double?
    public let actualKm: Double?
    /// Bar lengths as fractions of the phase's largest figure.
    public let targetFraction: Double?
    public let actualFraction: Double?
    public let isCurrent: Bool
    public let isFuture: Bool
    public let accessibilityLabel: String

    public var id: ISOWeek { week }
}

/// A key session with its date ("Sat 19 Oct").
public struct KeySessionModel: Equatable, Sendable, Identifiable {
    public let row: SessionRowModel
    public let dateText: String

    public var id: String { row.id }
}

public struct PhaseTestResultModel: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let dateText: String
    /// "Left 22 reps · Right 27 reps".
    public let valuesText: String
}

public struct PhaseRecapModel: Equatable, Sendable {
    /// The vault's recap, when written.
    public let text: String?
    /// "Run 22.6 of 30 km planned".
    public let runLine: String?
    /// "1 of 1 weeks within 10 % of target".
    public let withinLine: String?
    /// "Biggest week: 22.6 km (W41)".
    public let biggestLine: String?
    /// One line per measure tested twice or more inside the phase:
    /// "Left: 18 → 22 reps · Improved".
    public let testLines: [String]
    public let raceLines: [String]
}

public struct PhaseDetailModel: Equatable, Sendable {
    public let id: String
    public let title: String
    public let kindText: String?
    public let status: PhaseStatusKind
    public let statusText: String?
    public let dateText: String?
    /// "Week 2 of 16 · 99 days left", "Starts in 12 days", "Finished".
    public let progressText: String?
    /// 0...1 through the phase; `nil` before it or without dates.
    public let progressFraction: Double?
    public let isSelected: Bool
    /// Set for a phase that isn't the selected one.
    public let restrictedText: String?
    public let goals: [String]
    public let rules: [String]
    public let weeks: [PhaseWeekRowModel]
    /// Long, quality, test and race sessions of the written weeks.
    public let keySessions: [KeySessionModel]
    public let tests: [PhaseTestResultModel]
    public let races: [RaceMarkerModel]
    public let recap: PhaseRecapModel?
    public let notices: [TrainingNotice]
}

// MARK: - Builder

public extension PlanBuilder {
    /// Session types the phase screen lists as key sessions.
    static let keySessionTypes: Set<SessionType> = [.long, .tempo, .threshold, .intervals, .vo2max, .test, .race]

    /// The phase Plan -> Season opens by default: the selected one, else
    /// the season's first.
    func defaultPhaseID() -> String? {
        source.snapshot.flatMap { $0.plan?.plan.phase.id ?? $0.phases.first?.id }
    }

    /// The phase `id`; `nil` when the file doesn't know it.
    func phaseDetail(id: String) -> PhaseDetailModel? {
        guard let snapshot = source.snapshot, let phase = snapshot.phase(id: id) else { return nil }
        let text = format.text
        let language = format.language
        let selected = snapshot.plan?.plan.phase.id == phase.id
        let from = phase.period?.from
        let to = phase.period?.to

        // Header: where today falls.
        var progressText: String?
        var progressFraction: Double?
        if PhaseStatusKind(phase.status) == .closed || (to.map { today > $0 } ?? false) {
            progressText = text(.phaseFinished)
            progressFraction = 1
        } else if let from, let to {
            let total = from.days(until: to) + 1
            let into = from.days(until: today)
            if into < 0 {
                progressText = text.format(.phaseStartsIn, -into)
            } else {
                let weekCount = (total + 6) / 7
                let weekIndex = into / 7 + 1
                let left = today.days(until: to)
                progressText = text.format(.phaseWeekOf, weekIndex, weekCount) + " · " + text.format(.phaseDaysLeft, left)
                progressFraction = min(1, Double(into + 1) / Double(total))
            }
        }

        // The ramp.
        let ramp = PhaseRamp.series(phase, snapshot: snapshot, today: today)
        let largest = ramp.reduce(0.0) { max($0, $1.targetKm ?? 0, $1.actualKm ?? 0) }
        let weeks = ramp.map { rampRow($0, largest: largest) }

        // Key sessions of the written weeks inside the phase.
        var keySessions: [KeySessionModel] = []
        if let plan = snapshot.plan {
            for week in plan.weeks {
                for day in week.days where phase.period?.contains(day.date) ?? (week.phaseId == phase.id) {
                    for session in day.sessions {
                        guard let type = session.type?.known, Self.keySessionTypes.contains(type) else { continue }
                        keySessions.append(KeySessionModel(row: sessionRow(session, date: day.date, snapshot: snapshot), dateText: format.dates.short(day.date)))
                    }
                }
            }
        }

        let tests = testResults(in: phase, snapshot: snapshot)
        let races = snapshot.races.filter { race in
            race.phaseId == phase.id || (race.phaseId == nil && (phase.period?.contains(race.date) ?? false))
        }
        let markers = races.map { raceMarker($0, fraction: 0, clamped: false, lane: 0, snapshot: snapshot) }

        let recapText = phase.recap.resolvedText(language)
        let recap: PhaseRecapModel?
        if PhaseStatusKind(phase.status) == .closed || recapText != nil {
            recap = recapModel(phase, text: recapText, ramp: ramp, snapshot: snapshot, races: markers)
        } else {
            recap = nil
        }

        return PhaseDetailModel(
            id: phase.id,
            title: phase.title.resolvedText(language) ?? phase.id,
            kindText: text.phaseKindName(phase.kind),
            status: PhaseStatusKind(phase.status),
            statusText: text.phaseStatusName(phase.status),
            dateText: from.flatMap { start in to.map { format.dates.longRange(start, $0) } },
            progressText: progressText,
            progressFraction: progressFraction,
            isSelected: selected,
            restrictedText: selected ? nil : text(.phaseRestricted),
            goals: selected ? (snapshot.plan?.plan.goals ?? []).map { $0.text.resolved(language) }.filter { !$0.isEmpty } : [],
            rules: selected ? (snapshot.plan?.plan.rules ?? []).map { $0.text.resolved(language) }.filter { !$0.isEmpty } : [],
            weeks: weeks,
            keySessions: keySessions,
            tests: tests,
            races: markers,
            recap: recap,
            notices: format.notices(snapshot.freshness)
        )
    }

    internal func rampRow(_ week: RampWeek, largest: Double) -> PhaseWeekRowModel {
        let text = format.text
        let language = format.language
        let title = format.weekTitle(week.week)
        let targetText = week.targetKm.map { NumberText.distance($0, language) }
        let actualText: String?
        if let actual = week.actualKm {
            actualText = NumberText.distance(actual, language)
        } else if week.isOutsideWindow {
            actualText = text(.weekOutsideWindow)
        } else {
            actualText = nil
        }
        let kindText = text.outlineKindName(week.kind)
        var spoken = [title, kindText].compactMap { $0 }
        if let targetText { spoken.append(text.format(.weekRunTarget, NumberText.decimal(week.targetKm ?? 0, language))) }
        if let actualText { spoken.append(actualText) }
        if week.isCurrent { spoken.append(text(.today)) }
        return PhaseWeekRowModel(
            week: week.week,
            title: title,
            kindText: kindText,
            noteText: week.note.resolvedText(language),
            targetText: targetText,
            actualText: actualText,
            targetKm: week.targetKm,
            actualKm: week.actualKm,
            targetFraction: largest > 0 ? week.targetKm.map { $0 / largest } : nil,
            actualFraction: largest > 0 ? week.actualKm.map { $0 / largest } : nil,
            isCurrent: week.isCurrent,
            isFuture: week.isFuture,
            accessibilityLabel: spoken.joined(separator: ", ")
        )
    }

    /// Test results dated inside the phase, date order.
    internal func testResults(in phase: PhaseSummary, snapshot: TrainingSnapshot) -> [PhaseTestResultModel] {
        guard let period = phase.period else { return [] }
        var rows: [(date: LocalDate, row: PhaseTestResultModel)] = []
        for test in snapshot.tests {
            let title = test.title.resolvedText(format.language) ?? snapshot.workout(test.workout)?.title.resolvedText(format.language) ?? test.workout
            for entry in test.history where period.contains(entry.date) {
                let values = test.measures.compactMap { measure -> String? in
                    guard let value = entry.values[measure.key] else { return nil }
                    let label = measure.label.resolvedText(format.language) ?? measure.key
                    return "\(label) \(measureValue(value, unit: measure.unit))"
                }
                rows.append((entry.date, PhaseTestResultModel(
                    id: "\(test.workout)|\(entry.date)",
                    title: title,
                    dateText: format.dates.short(entry.date),
                    valuesText: values.joined(separator: " · ")
                )))
            }
        }
        return rows.sorted { ($0.date, $0.row.id) < ($1.date, $1.row.id) }.map { $0.row }
    }

    internal func recapModel(_ phase: PhaseSummary, text recapText: String?, ramp: [RampWeek], snapshot: TrainingSnapshot, races: [RaceMarkerModel]) -> PhaseRecapModel {
        let text = format.text
        let language = format.language
        let totals = PhaseRamp.totals(ramp)
        let runLine = totals.knownWeeks > 0
            ? text.format(.recapRun, NumberText.decimal(totals.actualTotal, language), NumberText.decimal(totals.plannedKnown, language))
            : nil
        let withinLine = totals.knownWeeks > 0 ? text.format(.recapWithinTen, totals.withinTen, totals.knownWeeks) : nil
        let biggestLine = totals.biggest.map { text.format(.recapBiggest, NumberText.decimal($0.km, language), $0.week.week) }

        var testLines: [String] = []
        if let period = phase.period {
            for test in snapshot.tests {
                let inside = test.history.filter { period.contains($0.date) }
                for measure in test.measures {
                    let values = inside.compactMap { $0.values[measure.key] }
                    guard values.count >= 2, let first = values.first, let last = values.last else { continue }
                    let label = measure.label.resolvedText(language) ?? measure.key
                    var line = "\(label): \(measureValue(first, unit: nil)) → \(measureValue(last, unit: measure.unit))"
                    if let verdict = TestVerdict.judge(first: first, last: last, better: measure.better) {
                        line += " · " + verdict.text(text)
                    }
                    testLines.append(line)
                }
            }
        }
        return PhaseRecapModel(
            text: recapText,
            runLine: runLine,
            withinLine: withinLine,
            biggestLine: biggestLine,
            testLines: testLines,
            raceLines: races.map { "\($0.name) · \($0.dateText)" }
        )
    }

    /// "22 reps", "612 s".
    internal func measureValue(_ value: Double, unit: String?) -> String {
        let number = NumberText.decimal(value, format.language, maxFractionDigits: 2)
        guard let unit, !unit.isEmpty else { return number }
        return "\(number) \(unit)"
    }
}

/// A test value judged in the direction its measure says is better (the
/// vault planner's `judge`).
public enum TestVerdict: String, Equatable, Sendable {
    case improved, worse, unchanged

    public static func judge(first: Double, last: Double, better: OpenEnum<MeasureDirection>?) -> TestVerdict? {
        guard let direction = better?.known else { return nil }
        if last == first { return .unchanged }
        return (last > first) == (direction == .higher) ? .improved : .worse
    }

    public func text(_ text: TrainingText) -> String {
        switch self {
        case .improved: return text(.testImproved)
        case .worse: return text(.testWorse)
        case .unchanged: return text(.testUnchanged)
        }
    }
}

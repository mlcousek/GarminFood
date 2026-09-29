// StatsModels.swift
//
// Training statistics RELATIVE TO THE PLAN, as pure models
// (add-training-stats, spec training-stats; design D2-D6). "What did I do"
// (volume by sport, load, bests) is the maps plugin's training dashboard's
// job and is not repeated; this answers "did I do what was planned, and is
// the plan working":
//
//   - adherence: sessions done, missed, skipped and still planned, per
//     week and per phase, over the weeks the plan file holds. Weeks of the
//     scope that have started but aren't in the file are LISTED ("not in
//     the app's window"), never counted as zero;
//   - the G/A/R split: which option the done traffic-light sessions were,
//     with "option not identified" as its own share (G and A are both runs
//     and the vault can't always tell them apart);
//   - volume vs target per week: `PhaseRamp`, the same numbers the Phase
//     screen draws, so the two cannot disagree;
//   - tests: each measure's history judged in its `better` direction, and
//     `_l`/`_r` measures paired with their left/right asymmetry
//     |L - R| / max(L, R).
//
// The phone never computes what the vault computes: statuses, `actual`,
// the done option and matching are read from the file. What happens here
// is counting and display arithmetic over those facts -- the vault
// planner's `planStats.ts` does the same -- and a test checks the counts
// agree with the vault's own `actual.sessionsDone/Missed` on the fixture.
//
// Depended on by: the app's TrainingStatsView. Tests: TrainingStatsTests.

import Foundation

// MARK: - Scope

/// What the statistics cover.
public enum StatsScope: Hashable, Sendable {
    /// One phase's period.
    case phase(String)
    /// The whole season's period.
    case season
}

// MARK: - Models

/// Session statuses counted as the vault published them.
public struct StatusCounts: Equatable, Sendable {
    public var done = 0
    public var missed = 0
    public var skipped = 0
    public var planned = 0
    public var unknown = 0

    public init() {}

    public var total: Int { done + missed + skipped + planned + unknown }
    /// Sessions whose day has been decided: done, missed or skipped.
    public var due: Int { done + missed + skipped }
    /// done / due; `nil` before anything was due.
    public var adherence: Double? { due > 0 ? Double(done) / Double(due) : nil }

    mutating func add(_ status: SessionStatusKind) {
        switch status {
        case .done: done += 1
        case .missed: missed += 1
        case .skipped: skipped += 1
        case .planned: planned += 1
        case .unknown: unknown += 1
        }
    }

    static func + (lhs: StatusCounts, rhs: StatusCounts) -> StatusCounts {
        var sum = lhs
        sum.done += rhs.done
        sum.missed += rhs.missed
        sum.skipped += rhs.skipped
        sum.planned += rhs.planned
        sum.unknown += rhs.unknown
        return sum
    }
}

public struct AdherenceRowModel: Equatable, Sendable, Identifiable {
    public let id: String
    /// "W43" or a phase's title.
    public let title: String
    public let counts: StatusCounts
    /// "1 done · 1 missed · 4 planned".
    public let countsText: String
    /// "50 %"; `nil` before anything was due.
    public let adherenceText: String?
    public let isCurrent: Bool
    public let accessibilityLabel: String
}

public struct AdherenceModel: Equatable, Sendable {
    public let weeks: [AdherenceRowModel]
    public let phases: [AdherenceRowModel]
    public let totals: StatusCounts
    /// "Done 90 % of the sessions due so far" / "No sessions due yet".
    public let summary: String
    public let countsText: String
    /// "Not in the app's window: W36, W37, W38"; `nil` when every started
    /// week is held.
    public let outsideText: String?
    /// Legend names in the language: done, missed, skipped, planned.
    public let legend: StatusLegend
}

public struct StatusLegend: Equatable, Sendable {
    public let done: String
    public let missed: String
    public let skipped: String
    public let planned: String
}

public struct OptionShareModel: Equatable, Sendable, Identifiable {
    /// "G", "A", "R"; `nil` for "option not identified".
    public let code: String?
    public let knownCode: OptionCode?
    /// "Planned session", "Easier", "Alternative", "Option not identified".
    public let label: String
    public let count: Int
    public let fraction: Double
    /// "3 sessions · 60 %".
    public let text: String

    public var id: String { code ?? "?" }
}

public struct OptionSplitModel: Equatable, Sendable {
    /// G, A, R, then unknown; zero shares included so the bar is stable.
    public let shares: [OptionShareModel]
    public let total: Int
    /// "No traffic-light session done yet" when `total` is 0.
    public let emptyText: String?
}

public struct VolumeRowModel: Equatable, Sendable, Identifiable {
    public let week: ISOWeek
    /// "W43".
    public let label: String
    public let targetKm: Double?
    public let actualKm: Double?
    /// "10.1 of 60 km", "60 km", "Not in the app's window".
    public let valueText: String
    /// "+5.1 km (+9 %)"; `nil` without both figures.
    public let deltaText: String?
    public let isCurrent: Bool
    public let isFuture: Bool
    public let accessibilityLabel: String

    public var id: ISOWeek { week }
}

public struct VolumeModel: Equatable, Sendable {
    public let rows: [VolumeRowModel]
    public let totals: RampTotals
    /// "Planned 200 km in total", "Ran 70.2 of 115 km planned", ...
    public let summaryLines: [String]
}

public struct TestPointModel: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    public let dateText: String
    public let value: Double

    public var id: LocalDate { date }
}

public struct TestMeasureModel: Equatable, Sendable, Identifiable {
    public let key: String
    public let label: String
    public let unit: String?
    public let points: [TestPointModel]
    /// "22 reps".
    public let latestText: String?
    /// "18 → 22 reps"; `nil` with fewer than two results.
    public let changeText: String?
    public let verdict: TestVerdict?
    public let verdictText: String?

    public var id: String { key }
}

public struct AsymmetryPointModel: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    public let dateText: String
    public let left: Double
    public let right: Double
    /// |L - R| / max(L, R).
    public let asymmetry: Double
    /// "L 22 · R 27 · 19 %".
    public let text: String

    public var id: LocalDate { date }
}

public struct TestPairModel: Equatable, Sendable, Identifiable {
    /// The shared key stem ("reps").
    public let stem: String
    public let leftLabel: String
    public let rightLabel: String
    /// The latest date with both sides.
    public let latest: AsymmetryPointModel?
    /// "Asymmetry 19 %".
    public let latestText: String?
    /// Oldest first.
    public let history: [AsymmetryPointModel]

    public var id: String { stem }
}

public struct TestCardModel: Equatable, Sendable, Identifiable {
    public let workout: String
    public let title: String
    /// "No results yet" for a test never done.
    public let emptyText: String?
    public let measures: [TestMeasureModel]
    public let pairs: [TestPairModel]

    public var id: String { workout }
}

public struct TrainingStatsModel: Equatable, Sendable {
    public let scope: StatsScope
    /// The phase's title or "Whole season".
    public let scopeTitle: String
    /// "14 Oct 2030 – 31 Jan 2031".
    public let rangeText: String?
    public let adherence: AdherenceModel?
    public let options: OptionSplitModel?
    public let volume: VolumeModel?
    public let tests: [TestCardModel]
    public let notices: [TrainingNotice]
    /// Set instead of the sections when there is nothing to count.
    public let emptyState: TrainingEmptyState?
}

// MARK: - Builder

public extension PlanBuilder {
    /// The default scope: the selected phase, else the whole season.
    func defaultStatsScope() -> StatsScope {
        defaultPhaseID().map { .phase($0) } ?? .season
    }

    func stats(scope: StatsScope) -> TrainingStatsModel {
        let text = format.text
        guard let snapshot = source.snapshot else {
            return TrainingStatsModel(scope: scope, scopeTitle: "", rangeText: nil, adherence: nil, options: nil, volume: nil, tests: [], notices: [], emptyState: format.emptyState(for: source) ?? format.emptyState(.fetching))
        }
        let notices = format.notices(snapshot.freshness)
        let tests = testCards(snapshot: snapshot)

        let range: Period?
        let scopeTitle: String
        let rampPhases: [PhaseSummary]
        switch scope {
        case .phase(let id):
            let phase = snapshot.phase(id: id)
            range = phase?.period
            scopeTitle = phase?.title.resolvedText(format.language) ?? id
            rampPhases = phase.map { [$0] } ?? []
        case .season:
            range = snapshot.season?.period ?? snapshot.plan?.plan.period
            scopeTitle = text(.statsWholeSeason)
            rampPhases = snapshot.phases.sorted { ($0.period?.from ?? LocalDate(dayNumber: 0)) < ($1.period?.from ?? LocalDate(dayNumber: 0)) }
        }
        guard let from = range?.from, let to = range?.to, snapshot.plan != nil else {
            return TrainingStatsModel(scope: scope, scopeTitle: scopeTitle, rangeText: nil, adherence: nil, options: nil, volume: nil, tests: tests, notices: notices, emptyState: format.emptyState(.noActivePlan))
        }
        let scopeRange = Period(from: from, to: to)
        return TrainingStatsModel(
            scope: scope,
            scopeTitle: scopeTitle,
            rangeText: format.dates.longRange(from, to),
            adherence: adherence(in: scopeRange, snapshot: snapshot),
            options: optionSplit(in: scopeRange, snapshot: snapshot),
            volume: volume(rampPhases, snapshot: snapshot),
            tests: tests,
            notices: notices,
            emptyState: nil
        )
    }

    // MARK: Adherence

    internal func adherence(in range: Period, snapshot: TrainingSnapshot) -> AdherenceModel {
        let text = format.text
        var weeks: [AdherenceRowModel] = []
        var byPhase: [(id: String, counts: StatusCounts)] = []
        var totals = StatusCounts()
        var held = Set<ISOWeek>()

        for week in snapshot.plan?.weeks ?? [] {
            let days = week.days.filter { range.contains($0.date) }
            guard !days.isEmpty else { continue }
            held.insert(week.week)
            var counts = StatusCounts()
            for day in days {
                for session in day.sessions { counts.add(SessionStatusKind(session.status)) }
            }
            totals = totals + counts
            let phaseID = week.phaseId ?? snapshot.phase(containing: week.from)?.id ?? ""
            if let index = byPhase.firstIndex(where: { $0.id == phaseID }) {
                byPhase[index].counts = byPhase[index].counts + counts
            } else {
                byPhase.append((phaseID, counts))
            }
            let title = text.format(.weekNumber, week.week.week)
            weeks.append(adherenceRow(id: week.week.description, title: title, counts: counts, isCurrent: week.week.contains(today)))
        }

        let phases = byPhase.map { entry -> AdherenceRowModel in
            let phase = snapshot.phase(id: entry.id)
            let title = phase?.title.resolvedText(format.language) ?? entry.id
            return adherenceRow(id: entry.id, title: title, counts: entry.counts, isCurrent: phase?.period?.contains(today) ?? false)
        }

        // Every started week of the scope the file doesn't hold: listed.
        let lastDay = min(range.to ?? today, snapshot.asOf ?? today)
        var outside: [String] = []
        if let first = range.from, first <= lastDay {
            var week = ISOWeek(containing: first)
            let lastWeek = ISOWeek(containing: lastDay)
            while week <= lastWeek {
                if !held.contains(week) { outside.append(text.format(.weekNumber, week.week)) }
                week = week.adding(weeks: 1)
            }
        }

        let summary = totals.adherence.map { text.format(.statsAdherence, NumberText.percent($0)) } ?? text(.statsNoneDue)
        return AdherenceModel(
            weeks: weeks,
            phases: phases,
            totals: totals,
            summary: summary,
            countsText: countsText(totals),
            outsideText: outside.isEmpty ? nil : text.format(.statsOutsideWindow, outside.joined(separator: ", ")),
            legend: StatusLegend(done: text(.statusDone), missed: text(.statusMissed), skipped: text(.statusSkipped), planned: text(.statusPlanned))
        )
    }

    internal func adherenceRow(id: String, title: String, counts: StatusCounts, isCurrent: Bool) -> AdherenceRowModel {
        let countsLine = countsText(counts)
        let adherenceText = counts.adherence.map(NumberText.percent)
        return AdherenceRowModel(
            id: id,
            title: title,
            counts: counts,
            countsText: countsLine,
            adherenceText: adherenceText,
            isCurrent: isCurrent,
            accessibilityLabel: [title, countsLine, adherenceText].compactMap { $0 }.joined(separator: ", ")
        )
    }

    /// "8 done · 0 missed · 0 planned" (+ " · 1 skipped" when any).
    internal func countsText(_ counts: StatusCounts) -> String {
        let text = format.text
        var line = text.format(.statsCounts, counts.done, counts.missed, counts.planned)
        if counts.skipped > 0 { line += " · " + text.format(.statsSkipped, counts.skipped) }
        return line
    }

    // MARK: G / A / R

    internal func optionSplit(in range: Period, snapshot: TrainingSnapshot) -> OptionSplitModel {
        let text = format.text
        var counts: [OptionCode: Int] = [:]
        var unknown = 0
        for week in snapshot.plan?.weeks ?? [] {
            for day in week.days where range.contains(day.date) {
                for session in day.sessions where session.trafficLight && session.status?.known == .done {
                    if let code = session.done?.option?.known {
                        counts[code, default: 0] += 1
                    } else {
                        unknown += 1
                    }
                }
            }
        }
        let total = counts.values.reduce(0, +) + unknown
        func share(_ code: OptionCode?, _ count: Int) -> OptionShareModel {
            let fraction = total > 0 ? Double(count) / Double(total) : 0
            let label = code.map { text.optionMeaning(OpenEnum($0)) ?? $0.rawValue } ?? text(.optionNotIdentified)
            return OptionShareModel(
                code: code?.rawValue,
                knownCode: code,
                label: label,
                count: count,
                fraction: fraction,
                text: text.format(.statsSessions, count) + " · " + NumberText.percent(fraction)
            )
        }
        let shares = [OptionCode.g, .a, .r].map { share($0, counts[$0] ?? 0) } + [share(nil, unknown)]
        return OptionSplitModel(shares: shares, total: total, emptyText: total == 0 ? text(.statsNoOptions) : nil)
    }

    // MARK: Volume

    internal func volume(_ phases: [PhaseSummary], snapshot: TrainingSnapshot) -> VolumeModel {
        let text = format.text
        let language = format.language
        var seen = Set<ISOWeek>()
        let ramp = phases.flatMap { PhaseRamp.series($0, snapshot: snapshot, today: today) }.filter { seen.insert($0.week).inserted }
        let rows = ramp.map { week -> VolumeRowModel in
            let label = text.format(.weekNumber, week.week.week)
            let valueText: String
            switch (week.actualKm, week.targetKm) {
            case let (actual?, target?):
                valueText = text.format(.statsOfTarget, NumberText.decimal(actual, language), NumberText.decimal(target, language))
            case let (actual?, nil):
                valueText = NumberText.distance(actual, language)
            case let (nil, target?):
                valueText = week.isOutsideWindow ? text(.weekOutsideWindow) : NumberText.distance(target, language)
            case (nil, nil):
                valueText = week.isOutsideWindow ? text(.weekOutsideWindow) : "–"
            }
            var deltaText: String?
            if let actual = week.actualKm, let target = week.targetKm {
                let delta = PhaseRamp.round1(actual - target)
                var line = Self.signed(delta, language) + " km"
                if target > 0 { line += " (\(Self.signedPercent(delta / target)))" }
                deltaText = line
            }
            return VolumeRowModel(
                week: week.week,
                label: label,
                targetKm: week.targetKm,
                actualKm: week.actualKm,
                valueText: valueText,
                deltaText: deltaText,
                isCurrent: week.isCurrent,
                isFuture: week.isFuture,
                accessibilityLabel: [label, valueText, deltaText].compactMap { $0 }.joined(separator: ", ")
            )
        }
        let totals = PhaseRamp.totals(ramp)
        var lines: [String] = []
        if totals.plannedTotal > 0 { lines.append(text.format(.statsPlannedTotal, NumberText.decimal(totals.plannedTotal, language))) }
        if totals.knownWeeks > 0 {
            lines.append(text.format(.recapRun, NumberText.decimal(totals.actualTotal, language), NumberText.decimal(totals.plannedKnown, language)))
            lines.append(text.format(.recapWithinTen, totals.withinTen, totals.knownWeeks))
        }
        if let mean = totals.meanWeekly { lines.append(text.format(.statsMeanWeekly, NumberText.decimal(mean, language))) }
        return VolumeModel(rows: rows, totals: totals, summaryLines: lines)
    }

    /// "+5.1", "−4.9", "0" in the language's decimal style.
    internal static func signed(_ value: Double, _ language: TrainingLanguage) -> String {
        let magnitude = NumberText.decimal(abs(value), language)
        if value > 0 { return "+" + magnitude }
        if value < 0 { return "−" + magnitude }
        return magnitude
    }

    /// "+9 %", "−8 %".
    internal static func signedPercent(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        if percent > 0 { return "+\(percent) %" }
        if percent < 0 { return "−\(-percent) %" }
        return "0 %"
    }

    // MARK: Tests

    internal func testCards(snapshot: TrainingSnapshot) -> [TestCardModel] {
        let text = format.text
        let language = format.language
        return snapshot.tests.map { test -> TestCardModel in
            let title = test.title.resolvedText(language) ?? snapshot.workout(test.workout)?.title.resolvedText(language) ?? test.workout
            let measures = test.measures.map { measure -> TestMeasureModel in
                let points = test.history.compactMap { entry -> TestPointModel? in
                    guard let value = entry.values[measure.key] else { return nil }
                    return TestPointModel(date: entry.date, dateText: format.dates.dayMonth(entry.date), value: value)
                }
                let label = measure.label.resolvedText(language) ?? measure.key
                var changeText: String?
                var verdict: TestVerdict?
                if points.count >= 2, let first = points.first, let last = points.last {
                    changeText = "\(measureValue(first.value, unit: nil)) → \(measureValue(last.value, unit: measure.unit))"
                    verdict = TestVerdict.judge(first: first.value, last: last.value, better: measure.better)
                }
                return TestMeasureModel(
                    key: measure.key,
                    label: label,
                    unit: measure.unit,
                    points: points,
                    latestText: points.last.map { measureValue($0.value, unit: measure.unit) },
                    changeText: changeText,
                    verdict: verdict,
                    verdictText: verdict?.text(text)
                )
            }
            return TestCardModel(
                workout: test.workout,
                title: title,
                emptyText: test.history.isEmpty ? text(.statsNoResults) : nil,
                measures: measures,
                pairs: TestAsymmetry.pairs(test).map { pairModel($0, test: test) }
            )
        }
    }

    internal func pairModel(_ pair: TestAsymmetry.Pair, test: TestHistory) -> TestPairModel {
        let text = format.text
        let language = format.language
        let history = TestAsymmetry.history(pair, in: test).map { point -> AsymmetryPointModel in
            let sides = text.format(.statsLeftRight, NumberText.decimal(point.left, language, maxFractionDigits: 2), NumberText.decimal(point.right, language, maxFractionDigits: 2))
            return AsymmetryPointModel(
                date: point.date,
                dateText: format.dates.dayMonth(point.date),
                left: point.left,
                right: point.right,
                asymmetry: point.asymmetry,
                text: "\(sides) · \(NumberText.percent(point.asymmetry))"
            )
        }
        let latest = history.last
        return TestPairModel(
            stem: pair.stem,
            leftLabel: pair.left.label.resolvedText(language) ?? pair.left.key,
            rightLabel: pair.right.label.resolvedText(language) ?? pair.right.key,
            latest: latest,
            latestText: latest.map { text.format(.statsAsymmetry, NumberText.percent($0.asymmetry)) },
            history: history
        )
    }
}

// MARK: - Left / right

/// `_l`/`_r` measures of one test, paired, with |L - R| / max(L, R) (the
/// vault planner's `testCards` pairs).
public enum TestAsymmetry {
    public struct Pair: Equatable, Sendable {
        public let stem: String
        public let left: Measure
        public let right: Measure
    }

    public struct Point: Equatable, Sendable {
        public let date: LocalDate
        public let left: Double
        public let right: Double
        public let asymmetry: Double
    }

    /// Every `<stem>_l` with a matching `<stem>_r`, in measure order.
    public static func pairs(_ test: TestHistory) -> [Pair] {
        test.measures.compactMap { left -> Pair? in
            guard left.key.hasSuffix("_l") else { return nil }
            let stem = String(left.key.dropLast(2))
            guard let right = test.measures.first(where: { $0.key == stem + "_r" }) else { return nil }
            return Pair(stem: stem, left: left, right: right)
        }
    }

    /// The asymmetry on every date with both sides, oldest first.
    public static func history(_ pair: Pair, in test: TestHistory) -> [Point] {
        test.history.compactMap { entry -> Point? in
            guard let left = entry.values[pair.left.key], let right = entry.values[pair.right.key] else { return nil }
            return Point(date: entry.date, left: left, right: right, asymmetry: asymmetry(left: left, right: right))
        }
    }

    /// |L - R| / max(L, R); 0 when both are 0.
    public static func asymmetry(left: Double, right: Double) -> Double {
        let largest = max(abs(left), abs(right))
        return largest > 0 ? abs(left - right) / largest : 0
    }
}

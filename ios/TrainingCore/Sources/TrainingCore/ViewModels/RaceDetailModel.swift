// RaceDetailModel.swift
//
// One race as a pure model (add-season-phase-race-screens, spec
// training-race-view; design D5): the countdown, what kind of race it is,
// the phase that anchors it, and its structured preparation -- start and
// cutoff, the checkpoint table with clock times, buffers and section
// paces, race fuel with totals to the finish, the carb-load days, the gear
// list (mandatory first), the taper weeks from the anchoring phase's
// outline, and the plan's sessions that are this race.
//
// The desk computes the facts; this only does DISPLAY arithmetic over them
// (the vault planner's `racePlan.ts`): clock times, buffers, section
// paces, fuel totals. A missing target is never interpolated -- a
// checkpoint without one shows no pace, and the next section is measured
// from the last checkpoint that has one; the gun is km 0, minute 0 by
// definition.
//
// Carb-load grams: inside the file's window the day's own `fuel.carbsG`
// (the vault's number); outside it the contract's formula over the
// athlete's weight, `round(g/kg x athlete.weightKg)` (contract semantics
// 6: "the app may recompute"), labelled as an estimate with the weight
// used. Without a weight there is no gram figure, never a guessed one.
// Each carb-load day carries its date so the app can open that day's food
// log (race week linked to the food side).
//
// Depended on by: the app's RaceDetailView. Tests: SeasonPhaseRaceTests.

import Foundation

// MARK: - Models

public struct CheckpointRowModel: Equatable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    /// "11.5 km".
    public let kmText: String?
    /// "320 m+".
    public let climbText: String?
    public let aidText: String?
    /// "Target 1 h 5 min · 10:05".
    public let targetText: String?
    /// "Cutoff 3 h 30 min · 12:30".
    public let cutoffText: String?
    /// "Buffer 1 h 25 min", or how far past the cutoff the target is.
    public let bufferText: String?
    /// The target is after the cutoff.
    public let bufferIsNegative: Bool
    /// "6:19 /km" over the section from the last checkpoint with a target.
    public let paceText: String?
    /// "≤160 bpm".
    public let hrCapText: String?
    public let accessibilityLabel: String
}

public struct RaceFuelModel: Equatable, Sendable {
    /// "70 g carbs/h", "Every 25 min", "500 ml fluid/h".
    public let lines: [String]
    /// "About 208 g carbs to the finish" (needs the finish target).
    public let totalLines: [String]
}

public enum CarbLoadSource: Equatable, Sendable {
    /// The day's own `fuel.carbsG` from the file.
    case plan
    /// g/kg x the athlete's weight.
    case estimate(weightKg: Double)
    /// No weight: no gram figure.
    case unknown
}

public struct CarbLoadRowModel: Equatable, Sendable, Identifiable {
    public let date: LocalDate
    /// "Fri 1 Nov".
    public let dateText: String
    /// "2 days before".
    public let offsetText: String
    /// "560 g carbs · 8 g/kg".
    public let amountText: String
    public let grams: Int?
    public let source: CarbLoadSource
    /// "From your plan" / "Estimated for 70 kg".
    public let sourceText: String?
    public let isToday: Bool
    public let isPast: Bool

    public var id: LocalDate { date }
}

public struct GearRowModel: Equatable, Sendable, Identifiable {
    public let id: Int
    public let item: String
    public let isMandatory: Bool
    /// "Mandatory" / "Optional".
    public let tagText: String
}

public struct TaperWeekRowModel: Equatable, Sendable, Identifiable {
    public let week: ISOWeek
    /// "W44 · 28 Oct – 3 Nov".
    public let title: String
    public let kindText: String?
    public let targetText: String?
    public let noteText: String?
    public let isRaceWeek: Bool
    public let isCurrent: Bool

    public var id: ISOWeek { week }
}

public struct RaceDetailModel: Equatable, Sendable {
    public let id: String
    public let name: String
    public let date: LocalDate
    /// "Sun 3 Nov 2030".
    public let dateText: String
    public let isApproximate: Bool
    public let priority: RacePriorityKind
    public let priorityText: String?
    public let isHero: Bool
    public let category: String?
    public let distanceText: String?
    public let goalText: String?
    /// "in 11 days", "today", "32 days ago".
    public let countdown: String
    public let daysUntil: Int
    public let isPast: Bool
    /// The anchoring phase's title and id; `nil` for an unanchored race.
    public let phaseTitle: String?
    public let phaseID: String?
    public let unanchoredText: String?
    /// "Race prep not written yet" when the prep is empty.
    public let stubText: String?
    /// "Start 09:00".
    public let startText: String?
    /// "Cutoff 5 h 30 min · 14:30".
    public let cutoffText: String?
    public let checkpoints: [CheckpointRowModel]
    public let fuel: RaceFuelModel?
    public let carbLoad: [CarbLoadRowModel]
    public let gear: [GearRowModel]
    public let taper: [TaperWeekRowModel]
    /// The plan's sessions that are this race (`raceId`).
    public let sessions: [SessionRowModel]
    /// "Race report written" once the vault links one.
    public let reportText: String?
    public let notices: [TrainingNotice]
}

// MARK: - Builder

public extension PlanBuilder {
    /// The race `id`; `nil` when the season doesn't have it.
    func raceDetail(id: String) -> RaceDetailModel? {
        guard let snapshot = source.snapshot, let race = snapshot.race(id: id) else { return nil }
        let text = format.text
        let language = format.language
        let prep = race.prep
        let anchor = snapshot.phase(id: race.phaseId)

        var sessions: [SessionRowModel] = []
        for week in snapshot.plan?.weeks ?? [] {
            for day in week.days {
                for session in day.sessions where session.raceId == race.id {
                    sessions.append(sessionRow(session, date: day.date, snapshot: snapshot))
                }
            }
        }

        let startText = prep?.startTime.map { text.format(.raceStart, format.dates.clock($0)) }
        let cutoffText = prep?.cutoffMin.map { minutes -> String in
            let duration = NumberText.duration(minutes: minutes)
            if let clock = NumberText.clock(prep?.startTime, plus: minutes) {
                return text.format(.raceCutoff, "\(duration) · \(clock)")
            }
            return text.format(.raceCutoff, duration)
        }

        return RaceDetailModel(
            id: race.id,
            name: race.name.resolvedText(language) ?? race.id,
            date: race.date,
            dateText: "\(format.dates.weekdayShort(race.date.isoWeekday)) \(format.dates.dayMonthYear(race.date))",
            isApproximate: race.dateApprox,
            priority: RacePriorityKind(race.priority),
            priorityText: text.priorityName(race.priority),
            isHero: race.hero,
            category: race.category,
            distanceText: raceDistanceText(race),
            goalText: race.goal.resolvedText(language),
            countdown: raceCountdown(race),
            daysUntil: today.days(until: race.date),
            isPast: race.date < today,
            phaseTitle: anchor.map { $0.title.resolvedText(language) ?? $0.id },
            phaseID: anchor?.id,
            unanchoredText: anchor == nil ? text(.raceUnanchored) : nil,
            stubText: RacePrepMath.isStub(prep) ? text(.raceStub) : nil,
            startText: startText,
            cutoffText: cutoffText,
            checkpoints: checkpointRows(prep),
            fuel: fuelModel(prep),
            carbLoad: carbLoadRows(race, snapshot: snapshot),
            gear: gearRows(prep),
            taper: taperRows(race, snapshot: snapshot),
            sessions: sessions,
            reportText: race.report == nil ? nil : text(.raceReported),
            notices: format.notices(snapshot.freshness)
        )
    }

    /// The race Plan -> Season highlights: the first on or after today,
    /// else the last one.
    func nextRaceID() -> String? {
        let races = source.snapshot?.races ?? []
        return races.first { $0.date >= today }?.id ?? races.last?.id
    }

    internal func checkpointRows(_ prep: RacePrep?) -> [CheckpointRowModel] {
        guard let prep else { return [] }
        let text = format.text
        let language = format.language
        return RacePrepMath.checkpoints(prep).enumerated().map { index, row -> CheckpointRowModel in
            let checkpoint = row.checkpoint
            let name = checkpoint.name ?? text.format(.checkpointNumber, index + 1)
            let targetText = checkpoint.targetMin.map { minutes -> String in
                let duration = NumberText.duration(minutes: minutes)
                return text.format(.checkpointTarget, [duration, NumberText.clock(prep.startTime, plus: minutes)].compactMap { $0 }.joined(separator: " · "))
            }
            let cutoffText = checkpoint.cutoffMin.map { minutes -> String in
                let duration = NumberText.duration(minutes: minutes)
                return text.format(.raceCutoff, [duration, NumberText.clock(prep.startTime, plus: minutes)].compactMap { $0 }.joined(separator: " · "))
            }
            let bufferText = row.bufferMin.map { buffer -> String in
                buffer < 0
                    ? text.format(.checkpointOverCutoff, NumberText.duration(minutes: -buffer))
                    : text.format(.checkpointBuffer, NumberText.duration(minutes: buffer))
            }
            let paceText = row.sectionPace.flatMap { NumberText.pace(minutesPerKm: $0) }
            let hrCapText = checkpoint.hrCap.map { "≤\($0) bpm" }
            let kmText = checkpoint.km.map { NumberText.distance($0, language) }
            let climbText = checkpoint.dPlusM.map { NumberText.climb($0, language) }
            let aidText = text.aidName(checkpoint.aid)
            let spoken = [name, kmText, climbText, aidText, targetText, cutoffText, bufferText, paceText, hrCapText].compactMap { $0 }.joined(separator: ", ")
            return CheckpointRowModel(
                id: index,
                name: name,
                kmText: kmText,
                climbText: climbText,
                aidText: aidText,
                targetText: targetText,
                cutoffText: cutoffText,
                bufferText: bufferText,
                bufferIsNegative: (row.bufferMin ?? 0) < 0,
                paceText: paceText,
                hrCapText: hrCapText,
                accessibilityLabel: spoken
            )
        }
    }

    internal func fuelModel(_ prep: RacePrep?) -> RaceFuelModel? {
        guard let prep, let fuel = prep.fuel else { return nil }
        let text = format.text
        let language = format.language
        var lines: [String] = []
        if let perHour = fuel.carbsPerHour { lines.append(text.format(.raceFuelCarbs, NumberText.decimal(perHour, language))) }
        if let interval = fuel.intervalMin { lines.append(text.format(.raceFuelEvery, interval)) }
        if let fluid = fuel.fluidMlPerHour { lines.append(text.format(.raceFuelFluid, NumberText.decimal(fluid, language, maxFractionDigits: 0))) }
        let totals = RacePrepMath.fuelTotals(prep)
        var totalLines: [String] = []
        if let carbs = totals.carbsG { totalLines.append(text.format(.raceFuelTotalCarbs, String(carbs))) }
        if let litres = totals.fluidL { totalLines.append(text.format(.raceFuelTotalFluid, NumberText.decimal(litres, language))) }
        if lines.isEmpty && totalLines.isEmpty { return nil }
        return RaceFuelModel(lines: lines, totalLines: totalLines)
    }

    internal func carbLoadRows(_ race: Race, snapshot: TrainingSnapshot) -> [CarbLoadRowModel] {
        let text = format.text
        let language = format.language
        return RacePrepMath.carbLoad(race, snapshot: snapshot).map { row -> CarbLoadRowModel in
            let offsetText: String
            switch row.dayOffset {
            case 0: offsetText = text(.raceDay)
            case ..<0: offsetText = text.format(.carbLoadDaysBefore, -row.dayOffset)
            default: offsetText = text.format(.carbLoadDaysAfter, row.dayOffset)
            }
            let perKg = row.carbsGPerKg.map { NumberText.decimal($0, language) }
            let amountText: String
            switch (row.grams, perKg) {
            case let (grams?, perKg?): amountText = text.format(.carbLoadAmount, String(grams), perKg)
            case let (grams?, nil): amountText = text.format(.carbLoadGrams, String(grams))
            case let (nil, perKg?): amountText = text.format(.carbLoadPerKg, perKg)
            case (nil, nil): amountText = text(.carbLoadUnknown)
            }
            let sourceText: String?
            switch row.source {
            case .plan: sourceText = text(.carbLoadFromPlan)
            case .estimate(let weight): sourceText = text.format(.carbLoadEstimate, NumberText.decimal(weight, language))
            case .unknown: sourceText = row.carbsGPerKg == nil ? nil : text(.carbLoadNoWeight)
            }
            return CarbLoadRowModel(
                date: row.date,
                dateText: format.dates.short(row.date),
                offsetText: offsetText,
                amountText: amountText,
                grams: row.grams,
                source: row.source,
                sourceText: sourceText,
                isToday: row.date == today,
                isPast: row.date < today
            )
        }
    }

    internal func gearRows(_ prep: RacePrep?) -> [GearRowModel] {
        let text = format.text
        let gear = prep?.gear ?? []
        // Mandatory first, the rest in their written order.
        let ordered = gear.filter(\.mandatory) + gear.filter { !$0.mandatory }
        return ordered.enumerated().map { index, item in
            GearRowModel(id: index, item: item.item, isMandatory: item.mandatory, tagText: item.mandatory ? text(.gearMandatory) : text(.gearOptional))
        }
    }

    internal func taperRows(_ race: Race, snapshot: TrainingSnapshot) -> [TaperWeekRowModel] {
        let text = format.text
        let language = format.language
        let raceWeek = ISOWeek(containing: race.date)
        return RacePrepMath.taper(race, snapshot: snapshot).map { row -> TaperWeekRowModel in
            let written = snapshot.plan?.week(row.week)
            let target = written?.targets.runKm ?? row.runKmTarget
            return TaperWeekRowModel(
                week: row.week,
                title: format.weekTitle(row.week),
                kindText: text.outlineKindName(row.kind),
                targetText: target.map { text.format(.weekRunTarget, NumberText.decimal($0, language)) },
                noteText: row.note.resolvedText(language),
                isRaceWeek: row.week == raceWeek,
                isCurrent: row.week.contains(today)
            )
        }
    }
}

// MARK: - Display arithmetic

/// The race screen's arithmetic over the vault's facts, kept apart from
/// the text so it is tested on numbers.
public enum RacePrepMath {
    public struct CheckpointMath: Equatable, Sendable {
        public let checkpoint: Checkpoint
        /// cutoff - target; `nil` unless both are known.
        public let bufferMin: Int?
        /// Minutes per km over the section from the last checkpoint with a
        /// target (the gun is km 0, minute 0).
        public let sectionPace: Double?
        public let sectionKm: Double?
    }

    public struct CarbLoadMath: Equatable, Sendable {
        public let date: LocalDate
        public let dayOffset: Int
        public let carbsGPerKg: Double?
        public let grams: Int?
        public let source: CarbLoadSource
    }

    /// A prep with nothing filled in is a stub (the vault's race-prep
    /// skill hasn't run yet).
    public static func isStub(_ prep: RacePrep?) -> Bool {
        guard let prep else { return true }
        let fuelEmpty = prep.fuel.map { $0.carbsPerHour == nil && $0.intervalMin == nil && $0.fluidMlPerHour == nil } ?? true
        return prep.checkpoints.isEmpty && fuelEmpty && prep.carbLoad.isEmpty && prep.gear.isEmpty && prep.startTime == nil && prep.cutoffMin == nil
    }

    public static func checkpoints(_ prep: RacePrep) -> [CheckpointMath] {
        var anchorKm = 0.0
        var anchorMin = 0
        return prep.checkpoints.map { checkpoint -> CheckpointMath in
            let buffer: Int? = {
                guard let cutoff = checkpoint.cutoffMin, let target = checkpoint.targetMin else { return nil }
                return cutoff - target
            }()
            var pace: Double?
            var sectionKm: Double?
            if let target = checkpoint.targetMin, let km = checkpoint.km {
                let distance = km - anchorKm
                if distance > 0 {
                    sectionKm = distance
                    pace = Double(target - anchorMin) / distance
                }
                anchorKm = km
                anchorMin = target
            }
            return CheckpointMath(checkpoint: checkpoint, bufferMin: buffer, sectionPace: pace, sectionKm: sectionKm)
        }
    }

    /// Carbs and fluid to the finish: rate x the last checkpoint's target.
    public static func fuelTotals(_ prep: RacePrep) -> (carbsG: Int?, fluidL: Double?) {
        guard let fuel = prep.fuel, let finish = prep.checkpoints.last?.targetMin else { return (nil, nil) }
        let carbs = fuel.carbsPerHour.map { Int(($0 * Double(finish) / 60).rounded()) }
        let fluid = fuel.fluidMlPerHour.map { (($0 * Double(finish) / 60 / 100).rounded()) / 10 }
        return (carbs, fluid)
    }

    /// One row per carb-load entry, dated race day + offset.
    public static func carbLoad(_ race: Race, snapshot: TrainingSnapshot) -> [CarbLoadMath] {
        let weight = snapshot.athlete.weightKg
        return (race.prep?.carbLoad ?? []).map { entry -> CarbLoadMath in
            let date = race.date.adding(days: entry.dayOffset)
            if let fuel = snapshot.day(date)?.fuel, fuel.isCarbLoad, fuel.raceId == race.id, let grams = fuel.carbsG {
                return CarbLoadMath(date: date, dayOffset: entry.dayOffset, carbsGPerKg: entry.carbsGPerKg ?? fuel.carbsGPerKg, grams: grams, source: .plan)
            }
            if let perKg = entry.carbsGPerKg, let weight, weight > 0 {
                return CarbLoadMath(date: date, dayOffset: entry.dayOffset, carbsGPerKg: perKg, grams: Int((perKg * weight).rounded()), source: .estimate(weightKg: weight))
            }
            return CarbLoadMath(date: date, dayOffset: entry.dayOffset, carbsGPerKg: entry.carbsGPerKg, grams: nil, source: .unknown)
        }
    }

    /// The taper: the anchoring phase's outline weeks from the last `build`
    /// week before the race week up to the race week. Empty for a race no
    /// phase anchors.
    public static func taper(_ race: Race, snapshot: TrainingSnapshot) -> [OutlineWeek] {
        guard let phase = snapshot.phase(id: race.phaseId) else { return [] }
        let raceWeek = ISOWeek(containing: race.date)
        let upTo = phase.outline.filter { $0.week <= raceWeek }.sorted { $0.week < $1.week }
        var from = 0
        for (index, row) in upTo.enumerated() where row.kind?.known == .build && row.week != raceWeek {
            from = index
        }
        return Array(upTo[from...])
    }
}

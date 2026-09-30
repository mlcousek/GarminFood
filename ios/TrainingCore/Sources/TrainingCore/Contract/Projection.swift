// Projection.swift
//
// The final projection v1 (design D3; the vault's "Training Hub Contract"),
// as Swift models. Field names and places follow the contract exactly.
//
// Decoding rules (design D2), applied by hand in every `init(from:)`:
//   - identity is required, everything else is optional: a session needs
//     `id`, a week `week`/`from`/`to`, a day `date`, an option `code`, a
//     habit `id`, a race `id` and `date`, a phase `id`, a measure `key`, a
//     test history its `workout` and each result its `date`. Missing
//     identity throws, which drops that one element (`LossyArray`);
//   - every other field is lenient: absent, `null` and the wrong type all
//     read as `nil` / `[]` / `{}` (D4 treats them alike);
//   - enumerations are `OpenEnum`s, unknown values never fail;
//   - unknown keys are ignored.
//
// The reserved fields (`acks`, `outcomes`, `rejected`, week `absorbed`, day
// `light`, session `origin`/`ruleNotes`, habit `gateBlockedBy`) have slots
// now (D8), so the vault's later changes only change what it writes.
// Option `watch` was reserved until the vault's add-garmin-workout-push
// filled it on 2026-09-29 (additive, still v1): it is `OptionWatch`; that
// change also added `done.source: "activity-name"` and `workout.watchName`.
// Day `pains` came with the vault's morning pain score on 2026-09-30
// (add-checkin-pain-score, additive in v1). Vault paths (`folder`, `note`, `ref`) are decoded
// but never shown: the phone has no vault checkout.
//
// Depended on by: ProjectionDecoder, TrainingSnapshot and every builder.
// Tests: ProjectionDecodingTests (both vault fixtures, the edge fixtures).

import Foundation

// MARK: - Top level

public struct Projection: Equatable, Sendable, Decodable {
    public var schema: String
    public var schemaVersion: Int
    /// When the vault last changed the content -- never a freshness signal
    /// (design D5).
    public var generatedAt: String?
    public var generator: String?
    /// The training day the file describes.
    public var asOf: LocalDate?
    public var athlete: Athlete
    public var season: Season?
    /// The SELECTED phase (deviation 1), not "the" plan.
    public var plan: Plan?
    public var workouts: [String: Workout]
    public var tests: [TestHistory]
    public var habits: Habits
    public var acks: [String: JSONValue]
    public var outcomes: [JSONValue]
    public var rejected: [JSONValue]
    /// Not part of v1; tolerated if it ever appears (design D2).
    public var supersededBy: SupersededBy?

    enum CodingKeys: String, CodingKey {
        case schema, schemaVersion, generatedAt, generator, asOf, athlete, season, plan
        case workouts, tests, habits, acks, outcomes, rejected, supersededBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = c.lenientString(.schema) ?? ""
        schemaVersion = c.lenientInt(.schemaVersion) ?? 0
        generatedAt = c.lenientString(.generatedAt)
        generator = c.lenientString(.generator)
        asOf = c.lenient(LocalDate.self, .asOf)
        athlete = c.lenient(Athlete.self, .athlete) ?? Athlete()
        // A top-level section of the wrong type makes the document invalid
        // (design D2), so these two are strict about their shape.
        season = try c.decodeIfPresent(Season.self, forKey: .season)
        plan = try c.decodeIfPresent(Plan.self, forKey: .plan)
        workouts = [:]
        if let map = try c.decodeIfPresent(LossyMap<Workout>.self, forKey: .workouts) {
            // The map key is the workout's identity.
            workouts = Dictionary(uniqueKeysWithValues: map.values.map { key, workout in
                (key, workout.id.isEmpty ? workout.withID(key) : workout)
            })
        }
        tests = try c.decodeIfPresent(LossyArray<TestHistory>.self, forKey: .tests)?.elements ?? []
        habits = try c.decodeIfPresent(Habits.self, forKey: .habits) ?? Habits()
        acks = c.lenient([String: JSONValue].self, .acks) ?? [:]
        outcomes = c.lenient([JSONValue].self, .outcomes) ?? []
        rejected = c.lenient([JSONValue].self, .rejected) ?? []
        supersededBy = c.lenient(SupersededBy.self, .supersededBy)
    }
}

/// A hint that a newer major exists (design D2). Not emitted by v1.
public struct SupersededBy: Equatable, Sendable, Decodable {
    public var schemaVersion: Int?
    public var minAppBuild: String?

    enum CodingKeys: String, CodingKey { case schemaVersion, minAppBuild }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = c.lenientInt(.schemaVersion)
        minAppBuild = c.lenientString(.minAppBuild) ?? c.lenientInt(.minAppBuild).map { String($0) }
    }
}

// MARK: - Athlete

public struct Athlete: Equatable, Sendable, Decodable {
    /// IANA zone the plan's dates are local to; `nil` -> the device's.
    public var tz: String?
    /// Before this hour, "today" is still the previous training day.
    public var dayBoundaryHour: Int
    public var hrMax: Int?
    public var weightKg: Double?
    public var hrZones: HRZones?

    public init(tz: String? = nil, dayBoundaryHour: Int = 0, hrMax: Int? = nil, weightKg: Double? = nil, hrZones: HRZones? = nil) {
        self.tz = tz
        self.dayBoundaryHour = dayBoundaryHour
        self.hrMax = hrMax
        self.weightKg = weightKg
        self.hrZones = hrZones
    }

    enum CodingKeys: String, CodingKey { case tz, dayBoundaryHour, hrMax, weightKg, hrZones }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tz = c.lenientString(.tz)
        dayBoundaryHour = min(max(c.lenientInt(.dayBoundaryHour) ?? 0, 0), 23)
        hrMax = c.lenientInt(.hrMax)
        weightKg = c.lenientDouble(.weightKg)
        hrZones = c.lenient(HRZones.self, .hrZones)
    }

    /// `tz` if the system knows it, else `fallback` (design D6).
    public func timeZone(fallback: TimeZone) -> TimeZone {
        tz.flatMap(TimeZone.init(identifier:)) ?? fallback
    }
}

/// One heart-rate zone: `Z<number>` covering `low...high` bpm.
public struct HRZone: Hashable, Sendable {
    public let number: Int
    public let low: Int
    public let high: Int

    public init(number: Int, low: Int, high: Int) {
        self.number = number
        self.low = low
        self.high = high
    }

    public var label: String { "Z\(number)" }

    public func contains(_ bpm: Int) -> Bool {
        low <= bpm && bpm <= high
    }
}

/// `{ z1: [lo, hi], ... }`, keys matched without regard to case.
public struct HRZones: Equatable, Sendable, Decodable {
    public let zones: [HRZone]

    public init(_ zones: [HRZone]) {
        self.zones = zones.sorted { $0.number < $1.number }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        var result: [HRZone] = []
        for key in c.allKeys {
            let name = key.stringValue.lowercased()
            guard name.hasPrefix("z"), let number = Int(name.dropFirst()),
                  let bounds = try? c.decode([Double].self, forKey: key), bounds.count == 2
            else { continue }
            result.append(HRZone(number: number, low: Int(bounds[0].rounded()), high: Int(bounds[1].rounded())))
        }
        self.init(result)
    }

    public func zone(number: Int) -> HRZone? {
        zones.first { $0.number == number }
    }
}

// MARK: - Season, phases, races

public struct Period: Equatable, Sendable, Decodable {
    public var from: LocalDate?
    public var to: LocalDate?

    public init(from: LocalDate?, to: LocalDate?) {
        self.from = from
        self.to = to
    }

    enum CodingKeys: String, CodingKey { case from, to }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = c.lenient(LocalDate.self, .from)
        to = c.lenient(LocalDate.self, .to)
    }

    public func contains(_ date: LocalDate) -> Bool {
        guard let from, let to else { return false }
        return from <= date && date <= to
    }
}

public struct Season: Equatable, Sendable, Decodable {
    public var id: String?
    public var title: LocalizedText?
    public var period: Period?
    public var goal: LocalizedText?
    public var phases: [PhaseSummary]
    /// Date order.
    public var races: [Race]

    enum CodingKeys: String, CodingKey { case id, title, period, goal, phases, races }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        title = c.lenient(LocalizedText.self, .title)
        period = c.lenient(Period.self, .period)
        goal = c.lenient(LocalizedText.self, .goal)
        phases = c.lossyList(PhaseSummary.self, .phases)
        races = c.lossyList(Race.self, .races).sorted { $0.date < $1.date }
    }
}

public struct OutlineWeek: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "outline week"

    public var week: ISOWeek
    public var runKmTarget: Double?
    public var kind: OpenEnum<OutlineKind>?
    public var note: LocalizedText?

    enum CodingKeys: String, CodingKey { case week, runKmTarget, kind, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = try c.decode(ISOWeek.self, forKey: .week)
        runKmTarget = c.lenientDouble(.runKmTarget)
        kind = c.lenient(OpenEnum<OutlineKind>.self, .kind)
        note = c.lenient(LocalizedText.self, .note)
    }
}

public struct PhaseSummary: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "phase"

    public var id: String
    public var title: LocalizedText?
    public var period: Period?
    public var kind: OpenEnum<PhaseKind>?
    public var status: OpenEnum<PhaseStatus>?
    public var outline: [OutlineWeek]
    public var recap: LocalizedText?

    enum CodingKeys: String, CodingKey { case id, title, period, kind, status, outline, recap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(container: c, requireID: true)
    }

    init(container c: KeyedDecodingContainer<CodingKeys>, requireID: Bool) throws {
        id = try requireID ? c.identity(.id) : (c.lenientString(.id) ?? "")
        title = c.lenient(LocalizedText.self, .title)
        period = c.lenient(Period.self, .period)
        kind = c.lenient(OpenEnum<PhaseKind>.self, .kind)
        status = c.lenient(OpenEnum<PhaseStatus>.self, .status)
        outline = c.lossyList(OutlineWeek.self, .outline)
        recap = c.lenient(LocalizedText.self, .recap)
    }

    public func outlineRow(for week: ISOWeek) -> OutlineWeek? {
        outline.first { $0.week == week }
    }
}

public struct Race: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "race"

    public var id: String
    public var name: LocalizedText?
    public var date: LocalDate
    public var dateApprox: Bool
    public var priority: OpenEnum<RacePriority>?
    public var hero: Bool
    public var phaseId: String?
    public var folder: String?
    public var category: String?
    public var distanceLabel: String?
    public var distanceKm: Double?
    public var elevationM: Double?
    public var goal: LocalizedText?
    public var prep: RacePrep?
    public var report: RaceReport?

    enum CodingKeys: String, CodingKey {
        case id, name, date, dateApprox, priority, hero, phaseId, folder, category
        case distanceLabel, distanceKm, elevationM, goal, prep, report
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.identity(.id)
        date = try c.decode(LocalDate.self, forKey: .date)
        name = c.lenient(LocalizedText.self, .name)
        dateApprox = c.lenientBool(.dateApprox) ?? false
        priority = c.lenient(OpenEnum<RacePriority>.self, .priority)
        hero = c.lenientBool(.hero) ?? false
        phaseId = c.lenientString(.phaseId)
        folder = c.lenientString(.folder)
        category = c.lenientString(.category)
        distanceLabel = c.lenientString(.distanceLabel)
        distanceKm = c.lenientDouble(.distanceKm)
        elevationM = c.lenientDouble(.elevationM)
        goal = c.lenient(LocalizedText.self, .goal)
        prep = c.lenient(RacePrep.self, .prep)
        report = c.lenient(RaceReport.self, .report)
    }
}

public struct RaceReport: Equatable, Sendable, Decodable {
    public var note: String?

    enum CodingKeys: String, CodingKey { case note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = c.lenientString(.note)
    }
}

public struct RacePrep: Equatable, Sendable, Decodable {
    public var note: String?
    public var startTime: ClockTime?
    public var cutoffMin: Int?
    public var checkpoints: [Checkpoint]
    public var fuel: PrepFuel?
    public var carbLoad: [CarbLoadDay]
    public var gear: [GearItem]

    enum CodingKeys: String, CodingKey { case note, startTime, cutoffMin, checkpoints, fuel, carbLoad, gear }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = c.lenientString(.note)
        startTime = c.lenient(ClockTime.self, .startTime)
        cutoffMin = c.lenientInt(.cutoffMin)
        checkpoints = c.lossyList(Checkpoint.self, .checkpoints)
        fuel = c.lenient(PrepFuel.self, .fuel)
        carbLoad = c.lossyList(CarbLoadDay.self, .carbLoad)
        gear = c.lossyList(GearItem.self, .gear)
    }
}

public struct Checkpoint: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "checkpoint"

    public var name: String?
    public var km: Double?
    public var dPlusM: Double?
    public var aid: OpenEnum<CheckpointAid>?
    public var cutoffMin: Int?
    public var targetMin: Int?
    public var hrCap: Int?

    enum CodingKeys: String, CodingKey { case name, km, dPlusM, aid, cutoffMin, targetMin, hrCap }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name)
        km = c.lenientDouble(.km)
        dPlusM = c.lenientDouble(.dPlusM)
        aid = c.lenient(OpenEnum<CheckpointAid>.self, .aid)
        cutoffMin = c.lenientInt(.cutoffMin)
        targetMin = c.lenientInt(.targetMin)
        hrCap = c.lenientInt(.hrCap)
    }
}

public struct PrepFuel: Equatable, Sendable, Decodable {
    public var carbsPerHour: Double?
    public var intervalMin: Int?
    public var fluidMlPerHour: Double?

    enum CodingKeys: String, CodingKey { case carbsPerHour, intervalMin, fluidMlPerHour }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carbsPerHour = c.lenientDouble(.carbsPerHour)
        intervalMin = c.lenientInt(.intervalMin)
        fluidMlPerHour = c.lenientDouble(.fluidMlPerHour)
    }
}

public struct CarbLoadDay: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "carb-load day"

    public var dayOffset: Int
    public var carbsGPerKg: Double?

    enum CodingKeys: String, CodingKey { case dayOffset, carbsGPerKg }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let offset = c.lenientInt(.dayOffset) else {
            throw DecodingError.keyNotFound(CodingKeys.dayOffset, DecodingError.Context(codingPath: c.codingPath, debugDescription: "no day offset"))
        }
        dayOffset = offset
        carbsGPerKg = c.lenientDouble(.carbsGPerKg)
    }
}

public struct GearItem: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "gear item"

    public var item: String
    public var mandatory: Bool

    enum CodingKeys: String, CodingKey { case item, mandatory }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        item = try c.identity(.item)
        mandatory = c.lenientBool(.mandatory) ?? false
    }
}

// MARK: - Plan, weeks, days

/// A goal or rule: `{ id, en, cz }`, text at the same level as the id.
public struct PlanNote: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "plan note"

    public var id: String?
    public var text: LocalizedText

    enum CodingKeys: String, CodingKey { case id, en, cz, cs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id)
        var values: [String: String] = [:]
        values["en"] = c.lenientString(.en)
        values["cz"] = c.lenientString(.cz)
        values["cs"] = c.lenientString(.cs)
        text = LocalizedText(values: values)
    }
}

/// The selected phase with its window of weeks.
public struct Plan: Equatable, Sendable, Decodable {
    public var phase: PhaseSummary
    public var goals: [PlanNote]
    public var rules: [PlanNote]
    /// The window W(asOf)-2 ... W(asOf)+3 of written weeks, in order.
    public var weeks: [Week]

    enum CodingKeys: String, CodingKey { case goals, rules, weeks }

    public init(from decoder: Decoder) throws {
        let summary = try decoder.container(keyedBy: PhaseSummary.CodingKeys.self)
        phase = try PhaseSummary(container: summary, requireID: false)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goals = c.lossyList(PlanNote.self, .goals)
        rules = c.lossyList(PlanNote.self, .rules)
        weeks = c.lossyList(Week.self, .weeks).sorted { $0.week < $1.week }
    }

    public var id: String { phase.id }
    public var title: LocalizedText? { phase.title }
    public var period: Period? { phase.period }
    public var outline: [OutlineWeek] { phase.outline }
}

public struct WeekTargets: Equatable, Sendable, Decodable {
    public var runKm: Double?
    public var sessions: Int?

    public init(runKm: Double? = nil, sessions: Int? = nil) {
        self.runKm = runKm
        self.sessions = sessions
    }

    enum CodingKeys: String, CodingKey { case runKm, sessions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runKm = c.lenientDouble(.runKm)
        sessions = c.lenientInt(.sessions)
    }
}

/// What the vault counted for the week so far; `nil` for a future week.
public struct WeekActual: Equatable, Sendable, Decodable {
    public var runKm: Double?
    public var sessionsDone: Int?
    public var sessionsMissed: Int?

    enum CodingKeys: String, CodingKey { case runKm, sessionsDone, sessionsMissed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runKm = c.lenientDouble(.runKm)
        sessionsDone = c.lenientInt(.sessionsDone)
        sessionsMissed = c.lenientInt(.sessionsMissed)
    }
}

public struct Week: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "week"

    public var week: ISOWeek
    public var from: LocalDate
    public var to: LocalDate
    public var phaseId: String?
    public var status: OpenEnum<WeekStatus>?
    public var revision: Int?
    /// Reserved (`{}` in v1).
    public var absorbed: [String: JSONValue]
    public var targets: WeekTargets
    public var actual: WeekActual?
    /// Introduces THIS week (contract point 11).
    public var aiNote: LocalizedText?
    /// Monday first; seven in a well-formed file.
    public var days: [Day]
    /// The vault's rule notes for the week (`{ rule, en, cz }`, added by
    /// add-hub-ingest): e.g. a red morning holding the volume.
    public var ruleNotes: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case week, from, to, phaseId, status, revision, absorbed, targets, actual, aiNote, days, ruleNotes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        week = try c.decode(ISOWeek.self, forKey: .week)
        from = try c.decode(LocalDate.self, forKey: .from)
        to = try c.decode(LocalDate.self, forKey: .to)
        phaseId = c.lenientString(.phaseId)
        status = c.lenient(OpenEnum<WeekStatus>.self, .status)
        revision = c.lenientInt(.revision)
        absorbed = c.lenient([String: JSONValue].self, .absorbed) ?? [:]
        targets = c.lenient(WeekTargets.self, .targets) ?? WeekTargets()
        actual = c.lenient(WeekActual.self, .actual)
        aiNote = c.lenient(LocalizedText.self, .aiNote)
        days = c.lossyList(Day.self, .days).sorted { $0.date < $1.date }
        ruleNotes = c.lenient([JSONValue].self, .ruleNotes) ?? []
    }

    public func day(_ date: LocalDate) -> Day? {
        days.first { $0.date == date }
    }
}

public struct DayFuel: Equatable, Sendable, Decodable {
    public var kind: OpenEnum<DayFuelKind>?
    public var raceId: String?
    public var carbsGPerKg: Double?
    public var carbsG: Int?

    enum CodingKeys: String, CodingKey { case kind, raceId, carbsGPerKg, carbsG }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(OpenEnum<DayFuelKind>.self, .kind)
        raceId = c.lenientString(.raceId)
        carbsGPerKg = c.lenientDouble(.carbsGPerKg)
        carbsG = c.lenientInt(.carbsG)
    }
}

public struct Day: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "day"

    public var date: LocalDate
    /// The morning traffic light (the last check-in, else inferred from the
    /// executed option; days up to `asOf` only).
    public var light: OpenEnum<MorningLight>?
    /// Where `light` came from (add-hub-ingest); `nil` when unknown.
    public var lightSource: OpenEnum<LightSource>?
    /// add-checkin-pain-score (the vault's A57): the morning pain of the
    /// day's last check-in that carried it. `nil` = not asked (absent,
    /// `null` or not a list), `[]` = nothing hurts; a broken entry is
    /// dropped, an unknown site reads as `other` (Pain.swift).
    public var pains: [PainEntry]?
    public var habitsExpected: [String]
    /// Uncapped counts; a missing key or a `null` map means unknown.
    public var habitsDone: [String: Int]?
    public var fuel: DayFuel?
    /// am before pm, then id -- the file's order is kept.
    public var sessions: [Session]
    public var unplanned: [ActivityRef]

    enum CodingKeys: String, CodingKey { case date, light, lightSource, pains, habitsExpected, habitsDone, fuel, sessions, unplanned }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        light = c.lenient(OpenEnum<MorningLight>.self, .light)
        lightSource = c.lenient(OpenEnum<LightSource>.self, .lightSource)
        pains = c.lenient(LossyArray<PainEntry>.self, .pains)?.elements
        habitsExpected = c.stringList(.habitsExpected)
        habitsDone = c.intMap(.habitsDone)
        fuel = c.lenient(DayFuel.self, .fuel)
        sessions = c.lossyList(Session.self, .sessions)
        unplanned = c.lossyList(ActivityRef.self, .unplanned)
    }
}

// MARK: - Sessions

public struct Targets: Equatable, Sendable, Decodable {
    public var km: Double?
    public var min: Int?
    public var hrMin: Int?
    public var hrMax: Int?
    /// "Z2" (case tolerated).
    public var zone: String?

    public init(km: Double? = nil, min: Int? = nil, hrMin: Int? = nil, hrMax: Int? = nil, zone: String? = nil) {
        self.km = km
        self.min = min
        self.hrMin = hrMin
        self.hrMax = hrMax
        self.zone = zone
    }

    enum CodingKeys: String, CodingKey { case km, min, hrMin, hrMax, zone }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        km = c.lenientDouble(.km)
        min = c.lenientInt(.min)
        hrMin = c.lenientInt(.hrMin)
        hrMax = c.lenientInt(.hrMax)
        zone = c.lenientString(.zone)
    }

    public var isEmpty: Bool {
        km == nil && min == nil && hrMin == nil && hrMax == nil && zone == nil
    }
}

public struct SessionOption: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "option"

    public var code: OpenEnum<OptionCode>
    public var workout: String?
    public var label: LocalizedText?
    public var sport: OpenEnum<Sport>?
    public var targets: Targets
    /// The option on the watch push's channel; `null` when not eligible.
    public var watch: OptionWatch?

    enum CodingKeys: String, CodingKey { case code, workout, label, sport, targets, watch }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(OpenEnum<OptionCode>.self, forKey: .code)
        workout = c.lenientString(.workout)
        label = c.lenient(LocalizedText.self, .label)
        sport = c.lenient(OpenEnum<Sport>.self, .sport)
        targets = c.lenient(Targets.self, .targets) ?? Targets()
        watch = c.lenient(OptionWatch.self, .watch)
    }
}

/// `{ name, state, channel, ref, at }` (contract point 12). The state is
/// open: an unknown one decodes as `.unknown`.
public struct OptionWatch: Equatable, Sendable, Decodable {
    public var name: String?
    public var state: OpenEnum<WatchState>?
    public var channel: OpenEnum<WatchChannel>?
    public var ref: String?
    /// ISO 8601 with offset, kept as written.
    public var at: String?

    enum CodingKeys: String, CodingKey { case name, state, channel, ref, at }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.lenientString(.name)
        state = c.lenient(OpenEnum<WatchState>.self, .state)
        channel = c.lenient(OpenEnum<WatchChannel>.self, .channel)
        ref = c.lenientString(.ref) ?? c.lenientInt(.ref).map { String($0) }
        at = c.lenientString(.at)
    }
}

/// An activity: the one a session matched, or an unplanned one.
public struct ActivityRef: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "activity"

    public var note: String?
    /// The raw Strava type ("VirtualRide").
    public var sport: String?
    /// The sport group ("ride").
    public var group: OpenEnum<Sport>?
    public var start: ClockTime?
    public var km: Double?
    public var min: Int?

    enum CodingKeys: String, CodingKey { case note, sport, group, start, km, min }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = c.lenientString(.note)
        sport = c.lenientString(.sport)
        group = c.lenient(OpenEnum<Sport>.self, .group)
        start = c.lenient(ClockTime.self, .start)
        km = c.lenientDouble(.km)
        min = c.lenientInt(.min)
    }
}

public struct Done: Equatable, Sendable, Decodable {
    /// `nil` when the vault can't tell (G and A are both runs).
    public var option: OpenEnum<OptionCode>?
    public var source: OpenEnum<DoneSource>?
    public var matchedBy: OpenEnum<MatchedBy>?
    public var activity: ActivityRef?

    enum CodingKeys: String, CodingKey { case option, source, matchedBy, activity }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        option = c.lenient(OpenEnum<OptionCode>.self, .option)
        source = c.lenient(OpenEnum<DoneSource>.self, .source)
        matchedBy = c.lenient(OpenEnum<MatchedBy>.self, .matchedBy)
        activity = c.lenient(ActivityRef.self, .activity)
    }
}

public struct SessionFuel: Equatable, Sendable, Decodable {
    public var carbsPerHour: Double?

    enum CodingKeys: String, CodingKey { case carbsPerHour }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carbsPerHour = c.lenientDouble(.carbsPerHour)
    }
}

public struct SessionTest: Equatable, Sendable, Decodable {
    public var workout: String?
    /// `{ measureKey: value }`, `nil` before the test.
    public var result: [String: Double]?
    public var note: String?
    public var ref: String?

    enum CodingKeys: String, CodingKey { case workout, result, note, ref }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workout = c.lenientString(.workout)
        result = c.numberMap(.result)
        note = c.lenientString(.note)
        ref = c.lenientString(.ref)
    }
}

public struct Session: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "session"

    /// Opaque (`2030-w43-wed-am`): never parsed for a date or slot.
    public var id: String
    public var slot: OpenEnum<SessionSlot>?
    public var sport: OpenEnum<Sport>?
    public var type: OpenEnum<SessionType>?
    public var title: LocalizedText?
    public var why: LocalizedText?
    public var workout: String?
    public var targets: Targets
    public var status: OpenEnum<SessionStatus>?
    public var trafficLight: Bool
    /// G, A, R -- empty when the session isn't a traffic-light session.
    public var options: [SessionOption]
    public var done: Done?
    /// Reserved (`null` in v1).
    public var origin: JSONValue?
    /// Reserved (`[]` in v1).
    public var ruleNotes: [JSONValue]
    public var raceId: String?
    public var fuel: SessionFuel?
    public var test: SessionTest?
    /// The vault's fold of `session.rpe` / `session.note` (add-hub-ingest).
    public var feedback: SessionFeedback?

    enum CodingKeys: String, CodingKey {
        case id, slot, sport, type, title, why, workout, targets, status, trafficLight
        case options, done, origin, ruleNotes, raceId, fuel, test, feedback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.identity(.id)
        slot = c.lenient(OpenEnum<SessionSlot>.self, .slot)
        sport = c.lenient(OpenEnum<Sport>.self, .sport)
        type = c.lenient(OpenEnum<SessionType>.self, .type)
        title = c.lenient(LocalizedText.self, .title)
        why = c.lenient(LocalizedText.self, .why)
        workout = c.lenientString(.workout)
        targets = c.lenient(Targets.self, .targets) ?? Targets()
        status = c.lenient(OpenEnum<SessionStatus>.self, .status)
        trafficLight = c.lenientBool(.trafficLight) ?? false
        options = c.lossyList(SessionOption.self, .options)
        done = c.lenient(Done.self, .done)
        let originValue = c.lenient(JSONValue.self, .origin)
        origin = originValue?.isNull == true ? nil : originValue
        ruleNotes = c.lenient([JSONValue].self, .ruleNotes) ?? []
        raceId = c.lenientString(.raceId)
        fuel = c.lenient(SessionFuel.self, .fuel)
        test = c.lenient(SessionTest.self, .test)
        feedback = c.lenient(SessionFeedback.self, .feedback)
    }

    public func option(_ code: OptionCode) -> SessionOption? {
        options.first { $0.code.known == code }
    }
}

/// `session.feedback` `{ rpe, feel, note }` (add-hub-ingest): the latest
/// RPE (1-10), feel (1-5) and note the vault folded from the app's events.
public struct SessionFeedback: Equatable, Sendable, Decodable {
    public var rpe: Int?
    public var feel: Int?
    public var note: String?

    enum CodingKeys: String, CodingKey { case rpe, feel, note }

    public init(rpe: Int? = nil, feel: Int? = nil, note: String? = nil) {
        self.rpe = rpe
        self.feel = feel
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpe = c.lenientInt(.rpe)
        feel = c.lenientInt(.feel)
        note = c.lenientString(.note)
    }
}

// MARK: - Workout library

public struct Step: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "step"

    public var kind: OpenEnum<StepKind>?
    public var km: Double?
    public var min: Double?
    public var sec: Int?
    public var times: Int?
    public var recoverMin: Double?
    public var recoverSec: Int?
    public var zone: String?
    public var hrMax: Int?
    public var hrLo: Int?
    public var hrHi: Int?
    public var pace: String?
    public var name: String?
    public var sets: Int?
    public var reps: ScalarText?
    public var tempo: String?
    public var load: ScalarText?
    public var side: OpenEnum<StepSide>?
    public var note: String?

    public init(kind: StepKind) {
        self.kind = .known(kind)
    }

    enum CodingKeys: String, CodingKey {
        case kind, km, min, sec, times, recoverMin, recoverSec, zone, hrMax, hrLo, hrHi
        case pace, name, sets, reps, tempo, load, side, note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = c.lenient(OpenEnum<StepKind>.self, .kind)
        km = c.lenientDouble(.km)
        min = c.lenientDouble(.min)
        sec = c.lenientInt(.sec)
        times = c.lenientInt(.times)
        recoverMin = c.lenientDouble(.recoverMin)
        recoverSec = c.lenientInt(.recoverSec)
        zone = c.lenientString(.zone)
        hrMax = c.lenientInt(.hrMax)
        hrLo = c.lenientInt(.hrLo)
        hrHi = c.lenientInt(.hrHi)
        pace = c.lenientString(.pace)
        name = c.lenientString(.name)
        sets = c.lenientInt(.sets)
        reps = c.lenient(ScalarText.self, .reps)
        tempo = c.lenientString(.tempo)
        load = c.lenient(ScalarText.self, .load)
        side = c.lenient(OpenEnum<StepSide>.self, .side)
        note = c.lenientString(.note)
    }
}

public struct Measure: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "measure"

    public var key: String
    public var unit: String?
    public var better: OpenEnum<MeasureDirection>?
    public var label: LocalizedText?

    enum CodingKeys: String, CodingKey { case key, unit, better, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.identity(.key)
        unit = c.lenientString(.unit)
        better = c.lenient(OpenEnum<MeasureDirection>.self, .better)
        label = c.lenient(LocalizedText.self, .label)
    }
}

public struct Workout: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "workout"

    public var id: String
    public var sport: OpenEnum<Sport>?
    public var kind: OpenEnum<WorkoutKind>?
    public var title: LocalizedText?
    public var why: LocalizedText?
    /// The short name the watch push uses (<= 20 ASCII characters).
    public var watchName: String?
    public var targets: Targets
    public var steps: [Step]
    public var measures: [Measure]

    enum CodingKeys: String, CodingKey { case id, sport, kind, title, why, watchName, targets, steps, measures }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        sport = c.lenient(OpenEnum<Sport>.self, .sport)
        kind = c.lenient(OpenEnum<WorkoutKind>.self, .kind)
        title = c.lenient(LocalizedText.self, .title)
        why = c.lenient(LocalizedText.self, .why)
        watchName = c.lenientString(.watchName)
        targets = c.lenient(Targets.self, .targets) ?? Targets()
        steps = c.lossyList(Step.self, .steps)
        measures = c.lossyList(Measure.self, .measures)
    }

    func withID(_ id: String) -> Workout {
        var copy = self
        copy.id = id
        return copy
    }
}

public struct TestResultEntry: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "test result"

    public var date: LocalDate
    public var sessionId: String?
    public var values: [String: Double]
    public var note: String?

    enum CodingKeys: String, CodingKey { case date, sessionId, values, note }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(LocalDate.self, forKey: .date)
        sessionId = c.lenientString(.sessionId)
        values = c.numberMap(.values) ?? [:]
        note = c.lenientString(.note)
    }
}

public struct TestHistory: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "test history"

    public var workout: String
    public var title: LocalizedText?
    public var measures: [Measure]
    /// Date order, every week.
    public var history: [TestResultEntry]

    enum CodingKeys: String, CodingKey { case workout, title, measures, history }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workout = try c.identity(.workout)
        title = c.lenient(LocalizedText.self, .title)
        measures = c.lossyList(Measure.self, .measures)
        history = c.lossyList(TestResultEntry.self, .history).sorted { $0.date < $1.date }
    }
}

// MARK: - Habits

public struct HabitGate: Equatable, Sendable, Decodable {
    public var adherencePct: Int?
    public var windowDays: Int?

    public init(adherencePct: Int? = nil, windowDays: Int? = nil) {
        self.adherencePct = adherencePct
        self.windowDays = windowDays
    }

    enum CodingKeys: String, CodingKey { case adherencePct, windowDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        adherencePct = c.lenientInt(.adherencePct)
        windowDays = c.lenientInt(.windowDays)
    }
}

public struct HabitSchedule: Equatable, Sendable, Decodable {
    public var kind: OpenEnum<ScheduleKind>
    public var perDay: Int?
    /// Weekday codes ("MO", "TH").
    public var days: [String]
    public var times: Int?
    public var n: Int?
    public var day: String?
    public var anchor: LocalDate?
    public var sport: String?
    public var types: [String]

    enum CodingKeys: String, CodingKey { case kind, perDay, days, times, n, day, anchor, sport, types }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(OpenEnum<ScheduleKind>.self, forKey: .kind)
        perDay = c.lenientInt(.perDay)
        days = c.stringList(.days)
        times = c.lenientInt(.times)
        n = c.lenientInt(.n)
        day = c.lenientString(.day)
        anchor = c.lenient(LocalDate.self, .anchor)
        sport = c.lenientString(.sport)
        types = c.stringList(.types)
    }

    /// How many times a day the habit is expected when it is.
    public var expectedPerDay: Int {
        kind.known == .daily ? max(perDay ?? 1, 1) : 1
    }
}

public struct HabitWindow: Equatable, Sendable, Decodable {
    public var done: Int?
    public var expected: Int?
    public var pct: Int?
    public var recordedDays: Int?

    enum CodingKeys: String, CodingKey { case done, expected, pct, recordedDays }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        done = c.lenientInt(.done)
        expected = c.lenientInt(.expected)
        pct = c.lenientInt(.pct)
        recordedDays = c.lenientInt(.recordedDays)
    }
}

public struct Habit: Equatable, Sendable, Decodable, ProjectionElement {
    public static let elementName = "habit"

    public var id: String
    public var step: Int?
    public var icon: String?
    public var label: LocalizedText?
    public var dose: LocalizedText?
    public var why: LocalizedText?
    public var schedule: HabitSchedule?
    public var source: OpenEnum<HabitSource>?
    public var state: OpenEnum<HabitState>?
    public var started: LocalDate?
    public var earliest: LocalDate?
    /// `nil`: not recorded yet.
    public var window14: HabitWindow?
    /// Non-null only for the highest active step.
    public var gateMet: Bool?
    /// Reserved (`null` in v1).
    public var gateBlockedBy: JSONValue?

    enum CodingKeys: String, CodingKey {
        case id, step, icon, label, dose, why, schedule, source, state, started, earliest, window14, gateMet, gateBlockedBy
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.identity(.id)
        step = c.lenientInt(.step)
        icon = c.lenientString(.icon)
        label = c.lenient(LocalizedText.self, .label)
        dose = c.lenient(LocalizedText.self, .dose)
        why = c.lenient(LocalizedText.self, .why)
        schedule = c.lenient(HabitSchedule.self, .schedule)
        source = c.lenient(OpenEnum<HabitSource>.self, .source)
        state = c.lenient(OpenEnum<HabitState>.self, .state)
        started = c.lenient(LocalDate.self, .started)
        earliest = c.lenient(LocalDate.self, .earliest)
        window14 = c.lenient(HabitWindow.self, .window14)
        gateMet = c.lenientBool(.gateMet)
        let blocked = c.lenient(JSONValue.self, .gateBlockedBy)
        gateBlockedBy = blocked?.isNull == true ? nil : blocked
    }
}

public struct Habits: Equatable, Sendable, Decodable {
    public var gate: HabitGate
    /// In step order.
    public var ladder: [Habit]

    public init(gate: HabitGate = HabitGate(), ladder: [Habit] = []) {
        self.gate = gate
        self.ladder = ladder
    }

    enum CodingKeys: String, CodingKey { case gate, ladder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gate = c.lenient(HabitGate.self, .gate) ?? HabitGate()
        ladder = c.lossyList(Habit.self, .ladder).enumerated().sorted { lhs, rhs in
            (lhs.element.step ?? Int.max, lhs.offset) < (rhs.element.step ?? Int.max, rhs.offset)
        }.map(\.element)
    }

    public func habit(_ id: String) -> Habit? {
        ladder.first { $0.id == id }
    }
}

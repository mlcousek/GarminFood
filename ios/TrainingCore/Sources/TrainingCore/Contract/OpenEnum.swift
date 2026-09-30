// OpenEnum.swift
//
// The contract's consumer rule "decode unknown enum values as unknown"
// (design D2). Every enumeration the projection carries -- sport, session
// type, status, option code, step kind, habit state and so on -- is read
// through `OpenEnum<Known>`: a value this build knows becomes `.known`,
// anything else `.unknown(raw)`, and decoding never throws for a new value.
// So the vault can add a session type (`"hike"`) or a status without
// breaking an older app; the screens show such a value neutrally.
//
// `aliases` lets one enum accept a second spelling of the same value (the
// habit schedule kinds, written camelCase in the contract and snake_case in
// some planning notes, design D3).
//
// Depended on by: Projection.swift (every model). Tests: ContractPrimitivesTests.

import Foundation

/// A closed set of string values the app knows, read through `OpenEnum`.
public protocol OpenEnumValue: RawRepresentable, CaseIterable, Hashable, Sendable where RawValue == String {
    /// Extra spellings accepted for a case (never written back).
    static var aliases: [String: Self] { get }
}

public extension OpenEnumValue {
    static var aliases: [String: Self] { [:] }
}

public enum OpenEnum<Known: OpenEnumValue>: Hashable, Sendable {
    case known(Known)
    case unknown(String)

    public init(rawValue: String) {
        if let value = Known(rawValue: rawValue) ?? Known.aliases[rawValue] {
            self = .known(value)
        } else {
            self = .unknown(rawValue)
        }
    }

    public init(_ known: Known) {
        self = .known(known)
    }

    /// The known value, or `nil` for one this build doesn't know.
    public var known: Known? {
        if case .known(let value) = self { return value }
        return nil
    }

    /// The value as written in the file (a known alias reads as its case).
    public var rawValue: String {
        switch self {
        case .known(let value): return value.rawValue
        case .unknown(let raw): return raw
        }
    }
}

extension OpenEnum: Decodable {
    /// Throws only when the value isn't a string at all (a malformed file);
    /// an unknown string is `.unknown`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }
}

extension OpenEnum: Encodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - The contract's enumerations (Training Hub Contract, "Enums")

public enum Sport: String, OpenEnumValue {
    case run, ride, walk, swim, strength, mobility, winter, other
}

public enum SessionType: String, OpenEnumValue {
    case easy, long, tempo, threshold, intervals, vo2max, recovery, cross, strength, mobility, test, race, other
}

public enum SessionSlot: String, OpenEnumValue {
    case am, pm
}

public enum SessionStatus: String, OpenEnumValue {
    case planned, done, missed
    /// Reserved in v1 (never produced); shown if it ever appears.
    case skipped
}

public enum WeekStatus: String, OpenEnumValue {
    case proposed, approved, closed
}

public enum OutlineKind: String, OpenEnumValue {
    case build, deload, taper, race, transition, recovery
}

public enum PhaseKind: String, OpenEnumValue {
    case base, build, specific, taper, transition
}

public enum PhaseStatus: String, OpenEnumValue {
    case draft, active, closed
}

/// G (the planned session), A (easier), R (an alternative without running).
public enum OptionCode: String, OpenEnumValue {
    case g = "G"
    case a = "A"
    case r = "R"
}

/// The morning traffic light (reserved, always `null` in v1). The case
/// names avoid colour words so the app's design-token lint, which forbids
/// `.red`/`.green` literals in views, never trips over a switch on it.
public enum MorningLight: String, OpenEnumValue {
    case greenLight = "green"
    case amberLight = "amber"
    case redLight = "red"

    /// The option a light points at (G <-> green, A <-> amber, R <-> red).
    public var option: OptionCode {
        switch self {
        case .greenLight: return .g
        case .amberLight: return .a
        case .redLight: return .r
        }
    }
}

/// Where a day's `light` came from (add-hub-ingest, additive in v1): the
/// morning check-in, or inferred from the executed traffic-light option.
public enum LightSource: String, OpenEnumValue {
    case checkin
    case option
}

public enum DoneSource: String, OpenEnumValue {
    /// The option token at the start of the activity's name ("A W43 Tue ...",
    /// added to v1 by the vault's add-garmin-workout-push, 2026-09-29).
    case activityName = "activity-name"
    case sportInferred = "sport-inferred"
}

/// An option's state on the watch push's channel (contract point 12).
/// `scheduled` means on the channel's calendar, not on the watch itself.
public enum WatchState: String, OpenEnumValue {
    case pending, scheduled, failed
}

public enum WatchChannel: String, OpenEnumValue {
    case intervals, garmin
}

public enum MatchedBy: String, OpenEnumValue {
    case dateSportGroup = "date-sport-group"
    case testResult = "test-result"
}

public enum RacePriority: String, OpenEnumValue {
    case a = "A"
    case b = "B"
    case c = "C"
}

public enum CheckpointAid: String, OpenEnumValue {
    case full, water, none
}

public enum WorkoutKind: String, OpenEnumValue {
    case session, test
}

public enum StepKind: String, OpenEnumValue {
    case warmup, active, interval, recovery, cooldown, exercise, hold, rest
}

public enum StepSide: String, OpenEnumValue {
    case each
    case left = "L"
    case right = "R"
    case both
}

public enum MeasureDirection: String, OpenEnumValue {
    case higher, lower
}

public enum HabitSource: String, OpenEnumValue {
    case dailyNote = "daily-note"
    case activity, plan
}

public enum HabitState: String, OpenEnumValue {
    case active, next, later
}

public enum ScheduleKind: String, OpenEnumValue {
    case daily, weekly, weeklyCount, everyNWeeks, withSessions

    /// design D3: snake_case spellings seen in planning notes.
    public static var aliases: [String: ScheduleKind] {
        ["weekly_count": .weeklyCount, "every_n_weeks": .everyNWeeks, "with_sessions": .withSessions]
    }
}

public enum DayFuelKind: String, OpenEnumValue {
    case carbLoad = "carb-load"
}

// CheckInOverlay.swift
//
// The optimistic half of the check-ins (add-training-checkins design D5;
// the architecture note's section 4.4): the phone's own recent events,
// folded into "latest wins" state, so a check-in, a habit tick, an RPE or
// a note shows the moment it is recorded -- long before the vault has
// ingested it and published a new projection.
//
//   - latest wins per key: the light per training day, a tick per (day,
//     habit), an RPE and a note per session. "Latest" is the recording
//     time, then `seq` (a device's own order; a new device id starts at 1
//     again, but always later);
//   - each value says whether it is only saved on the phone, sent (its
//     segment is no longer pending in VaultKit's write queue) or received
//     (the projection's `acks[deviceId].seq` has reached its `seq`: the
//     vault read every event of this device up to it -- the contract's
//     rule for clearing a pending event);
//   - it wins over the projection's value for the same key while the event
//     is kept (TrainingEventLog, 21 days). The vault ingests the very same
//     events, so both then agree; `acks` in the projection are reserved in
//     v1 and not read yet.
//
// The phone never runs the vault's traffic-light rules: an amber check-in
// shows amber, and the week adapts at the next desk sync.
//
// `EffectivePlan` applies `lights` to each day's `light`, so every builder
// (Today's highlight, the month glyph, the detail's pre-selection) shows
// the phone's check-in without a builder change.
//
// Plan commands and retractions (add-plan-editing) are not folded here:
// they are PendingOverlay's (PlanCommandOverlay.swift).
//
// Depended on by: TrainingSnapshot/EffectivePlan, the builders,
// TrainingReminderPlanner. Tests: CheckInOverlayTests.

import Foundation

public enum EventDelivery: Equatable, Sendable {
    case savedOnPhone
    case sent
    /// The vault acknowledged it (`acks[deviceId].seq >= seq`).
    case received
}

public struct OverlayValue<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let delivery: EventDelivery

    public init(value: Value, delivery: EventDelivery) {
        self.value = value
        self.delivery = delivery
    }
}

public struct HabitDayKey: Hashable, Sendable {
    public let date: LocalDate
    public let habitId: String

    public init(date: LocalDate, habitId: String) {
        self.date = date
        self.habitId = habitId
    }
}

public struct CheckInOverlay: Equatable, Sendable {
    public static let empty = CheckInOverlay()

    public private(set) var lights: [LocalDate: OverlayValue<MorningLight>] = [:]
    /// The session a check-in named, per day (kept with the light).
    public private(set) var checkInSessions: [LocalDate: String] = [:]
    public private(set) var habitTicks: [HabitDayKey: OverlayValue<Bool>] = [:]
    public private(set) var rpes: [String: OverlayValue<Int>] = [:]
    public private(set) var notes: [String: OverlayValue<String>] = [:]

    public init() {}

    public var isEmpty: Bool {
        lights.isEmpty && habitTicks.isEmpty && rpes.isEmpty && notes.isEmpty
    }

    public func light(on date: LocalDate) -> OverlayValue<MorningLight>? {
        lights[date]
    }

    public func habitTick(on date: LocalDate, habitId: String) -> OverlayValue<Bool>? {
        habitTicks[HabitDayKey(date: date, habitId: habitId)]
    }

    public func rpe(session id: String) -> OverlayValue<Int>? {
        rpes[id]
    }

    public func note(session id: String) -> OverlayValue<String>? {
        notes[id]
    }

    /// The projection's `acks` as `deviceId -> seq` (the highest `n` with
    /// events `1...n` all received). Anything unreadable is left out.
    public static func ackedSeqs(from acks: [String: JSONValue]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (device, value) in acks {
            guard case .object(let fields) = value, case .number(let seq)? = fields["seq"], seq >= 0 else { continue }
            result[device] = Int(seq)
        }
        return result
    }

    /// Folds `events`; `unsentSegments` are the segment ids still pending
    /// (or failed) in the write queue; `ackedSeqs` from `ackedSeqs(from:)`.
    public static func fold(_ events: [LoggedEvent], unsentSegments: Set<UUID>, ackedSeqs: [String: Int] = [:]) -> CheckInOverlay {
        var overlay = CheckInOverlay()
        let ordered = events.sorted { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
            return lhs.event.seq < rhs.event.seq
        }
        for logged in ordered {
            let delivery: EventDelivery
            if let acked = ackedSeqs[logged.event.deviceId], logged.event.seq <= acked {
                delivery = .received
            } else if let segment = logged.segmentID, !unsentSegments.contains(segment) {
                delivery = .sent
            } else {
                delivery = .savedOnPhone
            }
            switch logged.event.payload {
            case .morningCheckIn(let payload):
                overlay.lights[payload.date] = OverlayValue(value: payload.light, delivery: delivery)
                overlay.checkInSessions[payload.date] = payload.sessionId
            case .habitTick(let payload):
                overlay.habitTicks[HabitDayKey(date: payload.date, habitId: payload.habitId)] = OverlayValue(value: payload.done, delivery: delivery)
            case .sessionRPE(let payload):
                overlay.rpes[payload.sessionId] = OverlayValue(value: payload.rpe, delivery: delivery)
            case .sessionNote(let payload):
                overlay.notes[payload.sessionId] = OverlayValue(value: payload.text, delivery: delivery)
            case .sessionMoved, .sessionsSwapped, .sessionSkipped, .sessionUnskipped, .ruleOverridden, .eventRetracted:
                // Plan commands and retractions: PendingOverlay's
                // (add-plan-editing). The app never retracts a fact.
                continue
            case .other:
                continue
            }
        }
        return overlay
    }

    /// `plan` with each day's `light` replaced by the phone's check-in.
    public func applyingLights(to plan: Plan) -> Plan {
        guard !lights.isEmpty else { return plan }
        var result = plan
        for weekIndex in result.weeks.indices {
            for dayIndex in result.weeks[weekIndex].days.indices {
                let date = result.weeks[weekIndex].days[dayIndex].date
                if let local = lights[date] {
                    result.weeks[weekIndex].days[dayIndex].light = OpenEnum(local.value)
                    result.weeks[weekIndex].days[dayIndex].lightSource = OpenEnum(LightSource.checkin)
                }
            }
        }
        return result
    }
}

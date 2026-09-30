// PlanCommandOverlay.swift
//
// The phone's plan edits between the tap and the vault's answer
// (add-plan-editing design D4, D5; the architecture note's section 4.4):
//
//   shown = apply(projection plan, my commands with seq > acks[me].seq)
//
// `PendingOverlay` fills the seam `add-training-today-and-plan` left in
// TrainingSnapshot (its D8): every screen that reads `EffectivePlan` shows
// a moved, swapped or skipped session where the phone put it, and every
// builder can ask what this phone asked for a session and what the vault
// answered.
//
//   - `fold`: each `plan.*` command in the local log (TrainingEventLog, 21
//     days) gets ONE status, in this order: the vault's outcome for its
//     event id (`outcomes[]`: applied, absorbed, superseded, refused,
//     retracted, with a bilingual reason); else a retraction of it by this
//     phone -- "withdrawing" until acknowledged, then retracted; else
//     "received" once `acks[deviceId].seq` covers it (the vault read it but
//     its week is outside the window, so no outcome); else pending, saved
//     on the phone or sent, exactly like the check-ins.
//   - `applying(to:)`: only PENDING commands are applied, in order, onto
//     the projection's plan (everything acknowledged is already in it): a
//     move puts the session on its new day, a swap trades two days, a skip
//     marks it skipped, an unskip planned again. A rule override has no
//     preview -- the phone cannot restore options a rule removed. A command
//     whose preconditions no longer hold (the session is gone or elsewhere,
//     a race) is simply not previewed; the vault's outcome will say why.
//     The phone never rebases or runs the rules (one implementation, the
//     vault's).
//
// Depended on by: TrainingSnapshot/EffectivePlan, PlanEditPolicy, the plan
// edit view models, TrainingRecorder (`planEdits`). Tests:
// PlanEditingTests.

import Foundation

// MARK: - The vault's outcomes

/// `outcomes[].status` (add-hub-ingest D7).
public enum PlanOutcomeStatus: String, OpenEnumValue {
    case applied, absorbed, superseded, refused, retracted
}

/// One entry of the projection's `outcomes`.
public struct PlanOutcome: Equatable, Sendable {
    public let event: String?
    public let deviceId: String?
    public let seq: Int?
    public let type: String?
    public let week: ISOWeek?
    public let sessionId: String?
    public let status: OpenEnum<PlanOutcomeStatus>
    /// `{ en, cz }`, shown in the app's language.
    public let reason: LocalizedText?

    public init(event: String?, deviceId: String?, seq: Int?, type: String?, week: ISOWeek?, sessionId: String?, status: OpenEnum<PlanOutcomeStatus>, reason: LocalizedText?) {
        self.event = event
        self.deviceId = deviceId
        self.seq = seq
        self.type = type
        self.week = week
        self.sessionId = sessionId
        self.status = status
        self.reason = reason
    }

    /// The projection's `outcomes`, tolerantly: an entry without a status
    /// is left out; anything else unreadable reads as `nil`.
    public static func parse(_ values: [JSONValue]) -> [PlanOutcome] {
        values.compactMap { value -> PlanOutcome? in
            guard case .object(let fields) = value, let status = fields["status"]?.stringValue else { return nil }
            var seq: Int?
            if case .number(let number)? = fields["seq"] { seq = Int(number) }
            var reason: LocalizedText?
            switch fields["reason"] {
            case .string(let plain)?:
                reason = plain.isEmpty ? nil : LocalizedText(plain)
            case .object(let texts)?:
                var values: [String: String] = [:]
                for (code, text) in texts {
                    if let string = text.stringValue { values[code] = string }
                }
                let text = LocalizedText(values: values)
                reason = text.isEmpty ? nil : text
            default:
                reason = nil
            }
            return PlanOutcome(
                event: fields["event"]?.stringValue,
                deviceId: fields["deviceId"]?.stringValue,
                seq: seq,
                type: fields["type"]?.stringValue,
                week: fields["week"]?.stringValue.flatMap { ISOWeek($0) },
                sessionId: fields["sessionId"]?.stringValue,
                status: OpenEnum(rawValue: status),
                reason: reason
            )
        }
    }
}

// MARK: - A command and its status

public enum PlanCommandKind: String, Equatable, Sendable {
    case move, swap, skip, unskip, overrideRule
}

public enum PlanCommandStatus: Equatable, Sendable {
    /// Not acknowledged: saved on the phone, or sent.
    case pending(EventDelivery)
    /// A retraction of it is not acknowledged yet.
    case withdrawing(EventDelivery)
    /// The vault's outcome (an unknown word kept as such).
    case resolved(OpenEnum<PlanOutcomeStatus>, reason: LocalizedText?)
    /// Acknowledged without an outcome (its week is outside the window).
    case received

    public var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    public var isWithdrawing: Bool {
        if case .withdrawing = self { return true }
        return false
    }

    /// Applied, or absorbed (the contract: "treat absorbed like applied").
    public var isApplied: Bool {
        if case .resolved(let status, _) = self {
            return status.known == .applied || status.known == .absorbed
        }
        return false
    }

    /// Superseded or refused: the vault did not do it.
    public var isNotApplied: Bool {
        if case .resolved(let status, _) = self {
            return status.known == .superseded || status.known == .refused
        }
        return false
    }
}

public struct PlanCommandRecord: Equatable, Sendable, Identifiable {
    /// The command's event id.
    public let id: String
    public let deviceId: String
    public let seq: Int
    public let recordedAt: Date
    public let payload: HubEventPayload
    public let status: PlanCommandStatus
    /// Whether the preview could apply it (`PendingOverlay.applying`).
    public internal(set) var previewed: Bool

    public init(id: String, deviceId: String, seq: Int, recordedAt: Date, payload: HubEventPayload, status: PlanCommandStatus, previewed: Bool = false) {
        self.id = id
        self.deviceId = deviceId
        self.seq = seq
        self.recordedAt = recordedAt
        self.payload = payload
        self.status = status
        self.previewed = previewed
    }

    public var kind: PlanCommandKind? {
        switch payload {
        case .sessionMoved: return .move
        case .sessionsSwapped: return .swap
        case .sessionSkipped: return .skip
        case .sessionUnskipped: return .unskip
        case .ruleOverridden: return .overrideRule
        default: return nil
        }
    }

    public var week: ISOWeek? { payload.commandWeek }
    public var sessionIDs: [String] { payload.commandSessionIDs }
}

// MARK: - The overlay

public struct PendingOverlay: Equatable, Sendable {
    public static let empty = PendingOverlay()

    /// This phone's commands in the log, oldest first.
    public let commands: [PlanCommandRecord]

    public init(commands: [PlanCommandRecord] = []) {
        self.commands = commands
    }

    public var isEmpty: Bool { commands.isEmpty }

    /// Commands naming session `id`, oldest first.
    public func commands(onSession id: String) -> [PlanCommandRecord] {
        commands.filter { $0.sessionIDs.contains(id) }
    }

    /// The newest command naming session `id`.
    public func latest(onSession id: String) -> PlanCommandRecord? {
        commands(onSession: id).last
    }

    /// Whether a command on session `id` still waits for the vault
    /// (pending, or its withdrawal pending).
    public func isWaiting(onSession id: String) -> Bool {
        commands(onSession: id).contains { $0.status.isPending || $0.status.isWithdrawing }
    }

    public func commands(inWeek week: ISOWeek) -> [PlanCommandRecord] {
        commands.filter { $0.week == week }
    }

    public func command(id: String) -> PlanCommandRecord? {
        commands.first { $0.id.lowercased() == id.lowercased() }
    }

    // MARK: Fold

    /// See this file's header. `unsentSegments` and `ackedSeqs` as for
    /// `CheckInOverlay.fold`; `outcomes` from `PlanOutcome.parse`.
    public static func fold(_ events: [LoggedEvent], unsentSegments: Set<UUID>, ackedSeqs: [String: Int] = [:], outcomes: [PlanOutcome] = []) -> PendingOverlay {
        let ordered = events.sorted { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
            return lhs.event.seq < rhs.event.seq
        }
        var retractions: [String: LoggedEvent] = [:]
        for logged in ordered {
            if case .eventRetracted(let payload) = logged.event.payload {
                retractions[payload.target.lowercased()] = logged
            }
        }
        var outcomesByEvent: [String: PlanOutcome] = [:]
        for outcome in outcomes {
            if let event = outcome.event { outcomesByEvent[event.lowercased()] = outcome }
        }

        var records: [PlanCommandRecord] = []
        for logged in ordered where logged.event.payload.isPlanCommand {
            let event = logged.event
            let outcome = outcomesByEvent[event.id.lowercased()]
                ?? outcomes.first { $0.event == nil && $0.deviceId == event.deviceId && $0.seq == event.seq }
            let status: PlanCommandStatus
            if let outcome {
                status = .resolved(outcome.status, reason: outcome.reason)
            } else if let retraction = retractions[event.id.lowercased()],
                      retraction.event.deviceId == event.deviceId,
                      retraction.event.seq > event.seq {
                let delivery = Self.delivery(retraction, unsentSegments: unsentSegments, ackedSeqs: ackedSeqs)
                status = delivery == .received ? .resolved(OpenEnum(PlanOutcomeStatus.retracted), reason: nil) : .withdrawing(delivery)
            } else {
                let delivery = Self.delivery(logged, unsentSegments: unsentSegments, ackedSeqs: ackedSeqs)
                status = delivery == .received ? .received : .pending(delivery)
            }
            records.append(PlanCommandRecord(id: event.id, deviceId: event.deviceId, seq: event.seq, recordedAt: logged.recordedAt, payload: event.payload, status: status))
        }
        return PendingOverlay(commands: records)
    }

    /// Received once acknowledged, sent once its segment left the queue,
    /// else saved on the phone (CheckInOverlay's rule).
    static func delivery(_ logged: LoggedEvent, unsentSegments: Set<UUID>, ackedSeqs: [String: Int]) -> EventDelivery {
        if let acked = ackedSeqs[logged.event.deviceId], logged.event.seq <= acked {
            return .received
        }
        if let segment = logged.segmentID, !unsentSegments.contains(segment) {
            return .sent
        }
        return .savedOnPhone
    }

    // MARK: Preview

    /// `plan` with the pending commands applied, and this overlay with
    /// each command's `previewed` set.
    public func applying(to plan: Plan) -> (plan: Plan, overlay: PendingOverlay) {
        guard commands.contains(where: { $0.status.isPending }) else { return (plan, self) }
        var result = plan
        var records = commands
        for index in records.indices where records[index].status.isPending {
            records[index].previewed = Self.apply(records[index], to: &result)
        }
        return (result, PendingOverlay(commands: records))
    }

    /// One command onto `plan`; `false` when its preconditions don't hold.
    static func apply(_ record: PlanCommandRecord, to plan: inout Plan) -> Bool {
        guard let week = record.week, let w = plan.weeks.firstIndex(where: { $0.week == week }) else { return false }
        switch record.payload {
        case .sessionMoved(let payload):
            guard let found = locate(payload.sessionId, in: plan.weeks[w]),
                  plan.weeks[w].days[found.day].date == payload.from,
                  let target = plan.weeks[w].days.firstIndex(where: { $0.date == payload.to }),
                  target != found.day
            else { return false }
            var session = plan.weeks[w].days[found.day].sessions[found.session]
            guard !session.isRace else { return false }
            plan.weeks[w].days[found.day].sessions.remove(at: found.session)
            session.origin = origin("moved", base: baseDate(of: session, current: payload.from), event: record.id)
            insert(session, into: &plan.weeks[w].days[target])
            return true

        case .sessionsSwapped(let payload):
            guard let foundA = locate(payload.a, in: plan.weeks[w]),
                  let foundB = locate(payload.b, in: plan.weeks[w]),
                  foundA.day != foundB.day,
                  plan.weeks[w].days[foundA.day].date == payload.aDate,
                  plan.weeks[w].days[foundB.day].date == payload.bDate
            else { return false }
            var a = plan.weeks[w].days[foundA.day].sessions[foundA.session]
            var b = plan.weeks[w].days[foundB.day].sessions[foundB.session]
            guard !a.isRace, !b.isRace else { return false }
            // Different days, so each removal leaves the other index valid.
            plan.weeks[w].days[foundA.day].sessions.remove(at: foundA.session)
            plan.weeks[w].days[foundB.day].sessions.remove(at: foundB.session)
            a.origin = origin("swapped", base: baseDate(of: a, current: payload.aDate), event: record.id)
            b.origin = origin("swapped", base: baseDate(of: b, current: payload.bDate), event: record.id)
            insert(a, into: &plan.weeks[w].days[foundB.day])
            insert(b, into: &plan.weeks[w].days[foundA.day])
            return true

        case .sessionSkipped(let payload):
            guard let found = locate(payload.sessionId, in: plan.weeks[w]) else { return false }
            guard !plan.weeks[w].days[found.day].sessions[found.session].isRace else { return false }
            plan.weeks[w].days[found.day].sessions[found.session].status = OpenEnum(SessionStatus.skipped)
            return true

        case .sessionUnskipped(let payload):
            guard let found = locate(payload.sessionId, in: plan.weeks[w]),
                  plan.weeks[w].days[found.day].sessions[found.session].status?.known == .skipped
            else { return false }
            plan.weeks[w].days[found.day].sessions[found.session].status = OpenEnum(SessionStatus.planned)
            return true

        default:
            // A rule override: no preview (see this file's header).
            return false
        }
    }

    private static func locate(_ sessionID: String, in week: Week) -> (day: Int, session: Int)? {
        for (dayIndex, day) in week.days.enumerated() {
            if let sessionIndex = day.sessions.firstIndex(where: { $0.id == sessionID }) {
                return (dayIndex, sessionIndex)
            }
        }
        return nil
    }

    /// The date the plan had it on before any move: an existing
    /// moved/swapped origin's `from`, else where it is now.
    private static func baseDate(of session: Session, current: LocalDate) -> LocalDate {
        let kind = session.origin?["kind"]?.stringValue
        if kind == "moved" || kind == "swapped", let from = session.origin?["from"]?.stringValue.flatMap({ LocalDate($0) }) {
            return from
        }
        return current
    }

    private static func origin(_ kind: String, base: LocalDate, event: String) -> JSONValue {
        .object([
            "kind": .string(kind),
            "from": .string(base.description),
            "rule": .null,
            "event": .string(event)
        ])
    }

    /// Adds `session` to `day`, keeping am before pm, then id order.
    private static func insert(_ session: Session, into day: inout Day) {
        day.sessions.append(session)
        day.sessions.sort { lhs, rhs in
            let left = slotOrder(lhs.slot)
            let right = slotOrder(rhs.slot)
            if left != right { return left < right }
            return lhs.id < rhs.id
        }
    }

    private static func slotOrder(_ slot: OpenEnum<SessionSlot>?) -> Int {
        switch slot?.known {
        case .am?: return 0
        case .pm?: return 1
        case nil: return 2
        }
    }
}

public extension Session {
    /// A race session is fixed by the organiser (decision A50): the vault
    /// refuses moving, swapping or skipping it.
    var isRace: Bool {
        raceId != nil || type?.known == .race
    }
}

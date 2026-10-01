// PlanEditPolicy.swift
//
// What the phone may ask the vault to change about one session, and the
// commands that ask it (add-plan-editing design D3). The vault judges every
// command itself (its add-hub-ingest D8); this file only makes sure the
// app never OFFERS what the vault would refuse for a reason the phone can
// know:
//
//   - no edits without `canEditPlan` (vault connection on, device id), for
//     a week outside the projection's window, or a week without a
//     `revision` (the commands' `baseRevision`);
//   - a race session (`raceId`, or type `race`) is fixed by the organiser
//     (decision A50): no move, swap or skip, and it is nobody's swap
//     partner;
//   - move and swap only between days of the same ISO week, both on or
//     after the current training day ("past days follow the activities"),
//     never a done session;
//   - skip any planned or missed session, past days included (the vault
//     allows it), never a done one (tasks 0.2); unskip a skipped one;
//   - override a rule (decision A17) only where the vault's rule changed
//     the session (`origin.kind == "rule"` or a rule note naming it), once.
//     A note that only informs and never edits (`noteOnlyRules`: the
//     vault's session pain notes of 2026-10-01) has nothing to override;
//   - while this phone's command on the session waits for the vault, only
//     Withdraw (tasks 0.1). Withdraw = `event.retracted`, for a pending
//     command or an applied rule override (tasks 0.3).
//
// Every builder re-checks the same rules and throws `PlanEditError` rather
// than build a command the vault would refuse. `today` is the current
// training day (TrainingDay: the plan's zone and day boundary).
//
// Depended on by: the plan edit view models (PlanEditModels.swift) and the
// app's TrainingModel. Tests: PlanEditingTests.

import Foundation

public enum PlanEditBlock: String, Equatable, Sendable {
    /// Decision A50.
    case race
    /// Move and swap are not offered before `today`.
    case pastDay
    /// A done session follows its activity.
    case done
    /// The week has no revision in the projection.
    case noRevision
    /// This phone's command on it is still waiting for the vault.
    case waiting
}

public struct SwapPartner: Equatable, Sendable, Identifiable {
    public let sessionID: String
    public let date: LocalDate

    public var id: String { sessionID }
}

public struct PlanEditOptions: Equatable, Sendable {
    public let sessionID: String
    public let date: LocalDate
    public let week: ISOWeek
    /// `nil` when the week has no revision (then nothing but Withdraw).
    public let baseRevision: Int?
    /// Other days of the same week, on or after today.
    public let moveTargets: [LocalDate]
    public let swapPartners: [SwapPartner]
    public let canSkip: Bool
    public let canUnskip: Bool
    /// Rule ids the owner may override on this session.
    public let overridableRules: [String]
    /// Ids of this phone's commands on the session that may be withdrawn.
    public let withdrawable: [String]
    /// Why move, swap or skip are missing, when there is one reason.
    public let block: PlanEditBlock?

    public var hasActions: Bool {
        !moveTargets.isEmpty || !swapPartners.isEmpty || canSkip || canUnskip || !overridableRules.isEmpty || !withdrawable.isEmpty
    }
}

public enum PlanEditError: Error, Equatable, Sendable {
    /// The edit isn't offered (see PlanEditPolicy's header); the words say
    /// which rule, for the diagnostics log.
    case notAllowed(String)
}

public enum PlanEditPolicy {
    /// What may be asked for session `sessionID`; `nil` when editing isn't
    /// allowed or the plan doesn't have the session.
    public static func options(sessionID: String, snapshot: TrainingSnapshot, today: LocalDate) -> PlanEditOptions? {
        guard snapshot.capabilities.canEditPlan, let plan = snapshot.plan,
              let found = locate(sessionID, in: plan)
        else { return nil }
        let week = found.week
        let day = found.day
        let session = found.session
        let overlay = plan.overlay

        let own = overlay.commands(onSession: sessionID)
        let withdrawable = own.filter { command in
            command.status.isPending || (command.kind == .overrideRule && command.status.isApplied)
        }.map(\.id)

        func only(withdraw block: PlanEditBlock?) -> PlanEditOptions {
            PlanEditOptions(sessionID: sessionID, date: day.date, week: week.week, baseRevision: week.revision, moveTargets: [], swapPartners: [], canSkip: false, canUnskip: false, overridableRules: [], withdrawable: withdrawable, block: block)
        }

        if overlay.isWaiting(onSession: sessionID) { return only(withdraw: .waiting) }
        guard let revision = week.revision, revision >= 1 else { return only(withdraw: .noRevision) }

        // A17: each rule that edited it, unless this phone already
        // overrode it (pending, withdrawing or applied).
        let overridden = Set(own.compactMap { command -> String? in
            guard case .ruleOverridden(let payload) = command.payload else { return nil }
            let isOpen = command.status.isPending || command.status.isWithdrawing || command.status.isApplied || command.status == .received
            return isOpen ? payload.rule : nil
        })
        let rules = ruleIDs(of: session).filter { !overridden.contains($0) }

        let status = session.status?.known
        let isDone = status == .done
        if session.isRace {
            return PlanEditOptions(sessionID: sessionID, date: day.date, week: week.week, baseRevision: revision, moveTargets: [], swapPartners: [], canSkip: false, canUnskip: status == .skipped, overridableRules: rules, withdrawable: withdrawable, block: .race)
        }

        let movable = day.date >= today && !isDone
        var targets: [LocalDate] = []
        var partners: [SwapPartner] = []
        if movable {
            targets = week.week.days.filter { $0 >= today && $0 != day.date }
            for other in week.days where other.date != day.date && other.date >= today {
                for candidate in other.sessions where candidate.id != sessionID
                    && !candidate.isRace
                    && candidate.status?.known != .done
                    && !overlay.isWaiting(onSession: candidate.id) {
                    partners.append(SwapPartner(sessionID: candidate.id, date: other.date))
                }
            }
        }
        let block: PlanEditBlock?
        if isDone {
            block = .done
        } else if day.date < today {
            block = .pastDay
        } else {
            block = nil
        }
        return PlanEditOptions(
            sessionID: sessionID,
            date: day.date,
            week: week.week,
            baseRevision: revision,
            moveTargets: targets,
            swapPartners: partners,
            canSkip: !isDone && status != .skipped,
            canUnskip: status == .skipped,
            overridableRules: rules,
            withdrawable: withdrawable,
            block: block
        )
    }

    // MARK: Commands

    public static func move(sessionID: String, to date: LocalDate, snapshot: TrainingSnapshot, today: LocalDate) throws -> HubEventPayload {
        let options = try allowed(sessionID, snapshot, today)
        guard let revision = options.baseRevision, options.moveTargets.contains(date) else {
            throw PlanEditError.notAllowed("move \(sessionID) to \(date)")
        }
        return .sessionMoved(SessionMovedPayload(week: options.week, baseRevision: revision, sessionId: sessionID, from: options.date, to: date))
    }

    public static func swap(sessionID: String, with partnerID: String, snapshot: TrainingSnapshot, today: LocalDate) throws -> HubEventPayload {
        let options = try allowed(sessionID, snapshot, today)
        guard let revision = options.baseRevision, let partner = options.swapPartners.first(where: { $0.sessionID == partnerID }) else {
            throw PlanEditError.notAllowed("swap \(sessionID) with \(partnerID)")
        }
        return .sessionsSwapped(SessionsSwappedPayload(week: options.week, baseRevision: revision, a: sessionID, aDate: options.date, b: partner.sessionID, bDate: partner.date))
    }

    /// `reason` is trimmed; empty is no reason (tasks 0.4).
    public static func skip(sessionID: String, reason: String?, snapshot: TrainingSnapshot, today: LocalDate) throws -> HubEventPayload {
        let options = try allowed(sessionID, snapshot, today)
        guard let revision = options.baseRevision, options.canSkip else {
            throw PlanEditError.notAllowed("skip \(sessionID)")
        }
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = trimmed.isEmpty ? nil : String(trimmed.prefix(SessionNotePayload.maxLength))
        return .sessionSkipped(SessionSkippedPayload(week: options.week, baseRevision: revision, sessionId: sessionID, reason: text))
    }

    public static func unskip(sessionID: String, snapshot: TrainingSnapshot, today: LocalDate) throws -> HubEventPayload {
        let options = try allowed(sessionID, snapshot, today)
        guard let revision = options.baseRevision, options.canUnskip else {
            throw PlanEditError.notAllowed("unskip \(sessionID)")
        }
        return .sessionUnskipped(SessionUnskippedPayload(week: options.week, baseRevision: revision, sessionId: sessionID))
    }

    /// Decision A17. The app shows its warning BEFORE calling this.
    public static func overrideRule(_ rule: String, sessionID: String, snapshot: TrainingSnapshot, today: LocalDate) throws -> HubEventPayload {
        let options = try allowed(sessionID, snapshot, today)
        guard let revision = options.baseRevision, options.overridableRules.contains(rule) else {
            throw PlanEditError.notAllowed("override \(rule) on \(sessionID)")
        }
        return .ruleOverridden(RuleOverriddenPayload(week: options.week, baseRevision: revision, sessionId: sessionID, rule: rule))
    }

    /// Withdraws this phone's command `commandID` (a retraction).
    public static func withdraw(commandID: String, snapshot: TrainingSnapshot) throws -> HubEventPayload {
        guard snapshot.capabilities.canEditPlan, let command = snapshot.plan?.overlay.command(id: commandID),
              command.status.isPending || (command.kind == .overrideRule && command.status.isApplied)
        else {
            throw PlanEditError.notAllowed("withdraw \(commandID)")
        }
        return .eventRetracted(EventRetractedPayload(target: command.id))
    }

    // MARK: Helpers

    private static func allowed(_ sessionID: String, _ snapshot: TrainingSnapshot, _ today: LocalDate) throws -> PlanEditOptions {
        guard let options = options(sessionID: sessionID, snapshot: snapshot, today: today) else {
            throw PlanEditError.notAllowed("no edits for \(sessionID)")
        }
        return options
    }

    static func locate(_ sessionID: String, in plan: EffectivePlan) -> (week: Week, day: Day, session: Session)? {
        for week in plan.weeks {
            for day in week.days {
                if let session = day.sessions.first(where: { $0.id == sessionID }) {
                    return (week, day, session)
                }
            }
        }
        return nil
    }

    /// Rule notes that only inform and never edit the session, so there
    /// is nothing to override (add-daily-checkin-and-pain-mode: the vault's
    /// contract of 2026-10-01 puts `session-pain` and `pain-not-settled`
    /// into a session's `ruleNotes` -- "notes only, never an edit"). They
    /// are still shown with the session's other notes.
    public static let noteOnlyRules: Set<String> = ["session-pain", "pain-not-settled"]

    /// The rules that edited `session`: its `origin.rule` when
    /// `origin.kind` is `rule`, then every rule note's `rule`, once each
    /// (never a note-only rule).
    public static func ruleIDs(of session: Session) -> [String] {
        var result: [String] = []
        if session.origin?["kind"]?.stringValue == "rule", let rule = session.origin?["rule"]?.stringValue, !rule.isEmpty {
            result.append(rule)
        }
        for note in session.ruleNotes {
            if let rule = note["rule"]?.stringValue, !rule.isEmpty, !noteOnlyRules.contains(rule), !result.contains(rule) {
                result.append(rule)
            }
        }
        return result
    }
}

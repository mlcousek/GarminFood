// PlanEditModels.swift
//
// The plan edits as the screens show them (add-plan-editing design D6),
// built from the same `TrainingSnapshot` as everything else:
//
//   - `SessionEditModel`: the session detail's "Change the plan" card --
//     the latest command of this phone on the session with its status
//     ("Pending · Saved on phone", "Applied", "Refused") and the vault's
//     reason in the app's language; the allowed actions from
//     PlanEditPolicy (move targets, swap partners, skip, unskip, rule
//     overrides with their A17 warning, withdraw); and why nothing is
//     offered when that isn't obvious (a race, a past day).
//   - `PlanChangeLineModel`: one command of this phone in the week agenda's
//     "Plan changes" list, with its status, reason and Withdraw.
//   - `PlanEditBadge`: the week row's and Today card's mark -- a change
//     waiting for the vault, or one the vault did not apply.
//
// Nothing here decides what is allowed (PlanEditPolicy) or what the vault
// did (PendingOverlay); this only words it.
//
// Depended on by: SessionDetailModel, PlanBuilder (week rows),
// TodayTrainingBuilder (session card), the app's SessionDetailView and
// WeekAgendaView. Tests: PlanEditingTests.

import Foundation

public enum PlanEditStatusKind: String, Equatable, Sendable {
    case pending, withdrawing, applied, notApplied, refused, withdrawn, received, answered
}

public enum PlanEditBadge: String, Equatable, Sendable {
    /// A change waits for the vault.
    case pending
    /// The vault superseded or refused the phone's change.
    case notApplied
}

public struct PlanEditStatusModel: Equatable, Sendable, Identifiable {
    public let commandID: String
    /// "Move to Thu 31 Oct", "Skip: calf tight".
    public let description: String
    public let kind: PlanEditStatusKind
    /// "Pending · Saved on phone", "Refused", ...
    public let statusText: String
    /// The vault's reason, in the app's language.
    public let reason: String?
    public let canWithdraw: Bool

    public var id: String { commandID }
}

public struct EditChoiceModel: Equatable, Sendable, Identifiable {
    /// A date (`YYYY-MM-DD`) for a move, a session id for a swap.
    public let id: String
    public let date: LocalDate
    /// "Thu 31 Oct" / "Easy run · Tue 29 Oct".
    public let title: String
}

public struct RuleOverrideModel: Equatable, Sendable, Identifiable {
    /// The rule id (`two-ambers`).
    public let rule: String
    /// "Override the rule two-ambers".
    public let buttonTitle: String
    /// "Override the rule two-ambers?".
    public let warningTitle: String
    /// The rule's own note on the session, then why the warning matters.
    public let warningMessage: String

    public var id: String { rule }
}

public struct SessionEditModel: Equatable, Sendable {
    public let sessionID: String
    public let date: LocalDate
    /// This phone's latest command on the session.
    public let latest: PlanEditStatusModel?
    public let moveTargets: [EditChoiceModel]
    public let swapPartners: [EditChoiceModel]
    public let canSkip: Bool
    public let canUnskip: Bool
    public let overrides: [RuleOverrideModel]
    /// Commands that may be withdrawn, newest first.
    public let withdrawable: [PlanEditStatusModel]
    /// Why move, swap or skip are missing ("A race: ...").
    public let blockText: String?

    public var hasActions: Bool {
        !moveTargets.isEmpty || !swapPartners.isEmpty || canSkip || canUnskip || !overrides.isEmpty || !withdrawable.isEmpty
    }
}

public struct PlanChangeLineModel: Equatable, Sendable, Identifiable {
    public let commandID: String
    /// The session's title ("Easy run").
    public let sessionTitle: String
    public let status: PlanEditStatusModel

    public var id: String { commandID }
}

// MARK: - Wording

extension TrainingFormatting {
    /// "Move to Thu 31 Oct", seen from `sessionID` (a swap names the other
    /// session).
    func editDescription(_ command: PlanCommandRecord, from sessionID: String?, snapshot: TrainingSnapshot) -> String {
        switch command.payload {
        case .sessionMoved(let payload):
            return text.format(.editMoveTo, dates.short(payload.to))
        case .sessionsSwapped(let payload):
            let seenFromB = sessionID == payload.b
            let otherID = seenFromB ? payload.a : payload.b
            let otherDate = seenFromB ? payload.aDate : payload.bDate
            return text.format(.editSwapWith, sessionTitle(otherID, snapshot: snapshot), dates.short(otherDate))
        case .sessionSkipped(let payload):
            if let reason = payload.reason, !reason.isEmpty {
                return text.format(.editSkipReason, reason)
            }
            return text(.editSkip)
        case .sessionUnskipped:
            return text(.editUnskip)
        case .ruleOverridden(let payload):
            return text.format(.editOverride, payload.rule)
        default:
            return command.payload.type.rawValue
        }
    }

    func editStatus(_ command: PlanCommandRecord, from sessionID: String?, snapshot: TrainingSnapshot) -> PlanEditStatusModel {
        let kind: PlanEditStatusKind
        let statusText: String
        var reason: String?
        switch command.status {
        case .pending(let delivery):
            kind = .pending
            statusText = text(delivery == .savedOnPhone ? .editPendingSaved : .editPendingSent)
        case .withdrawing(let delivery):
            kind = .withdrawing
            statusText = text(delivery == .savedOnPhone ? .editWithdrawingSaved : .editWithdrawingSent)
        case .resolved(let status, let why):
            reason = why.resolvedText(language)
            switch status.known {
            case .applied?, .absorbed?:
                kind = .applied
                statusText = text(.editApplied)
            case .superseded?:
                kind = .notApplied
                statusText = text(.editNotApplied)
            case .refused?:
                kind = .refused
                statusText = text(.editRefused)
            case .retracted?:
                kind = .withdrawn
                statusText = text(.editWithdrawn)
            case nil:
                kind = .answered
                statusText = text(.editAnswered)
            }
        case .received:
            kind = .received
            statusText = text(.deliveryReceived)
        }
        let withdrawable = snapshot.capabilities.canEditPlan
            && (command.status.isPending || (command.kind == .overrideRule && command.status.isApplied))
        return PlanEditStatusModel(
            commandID: command.id,
            description: editDescription(command, from: sessionID, snapshot: snapshot),
            kind: kind,
            statusText: statusText,
            reason: reason,
            canWithdraw: withdrawable
        )
    }

    /// The mark on a session row or Today's card, from this phone's latest
    /// command on it.
    func editBadge(sessionID: String, snapshot: TrainingSnapshot) -> (badge: PlanEditBadge, text: String)? {
        guard let overlay = snapshot.plan?.overlay, let latest = overlay.latest(onSession: sessionID) else { return nil }
        if latest.status.isPending || latest.status.isWithdrawing {
            return (PlanEditBadge.pending, text(.editBadgePending))
        }
        if latest.status.isNotApplied {
            return (PlanEditBadge.notApplied, text(.editBadgeNotApplied))
        }
        return nil
    }

    /// A session's title from the effective plan, else its id.
    func sessionTitle(_ id: String, snapshot: TrainingSnapshot) -> String {
        guard let plan = snapshot.plan, let found = PlanEditPolicy.locate(id, in: plan) else { return id }
        let title = self.title(of: found.session, in: snapshot)
        return title.isEmpty ? id : title
    }

    func blockText(_ block: PlanEditBlock?) -> String? {
        switch block {
        case .race?: return text(.editBlockRace)
        case .pastDay?: return text(.editBlockPastDay)
        case .done?: return text(.editBlockDone)
        case .noRevision?: return text(.editBlockNoRevision)
        case .waiting?: return text(.editBlockWaiting)
        case nil: return nil
        }
    }
}

// MARK: - Builders

extension PlanBuilder {
    /// The "Change the plan" card for `session`; `nil` when editing isn't
    /// allowed and this phone never asked anything about it.
    func sessionEdit(_ session: Session, day: Day, snapshot: TrainingSnapshot) -> SessionEditModel? {
        let overlay = snapshot.plan?.overlay ?? .empty
        let own = overlay.commands(onSession: session.id)
        let options = PlanEditPolicy.options(sessionID: session.id, snapshot: snapshot, today: today)
        guard options != nil || !own.isEmpty else { return nil }

        let latest = own.last.map { format.editStatus($0, from: session.id, snapshot: snapshot) }
        let withdrawable = (options?.withdrawable ?? []).reversed().compactMap { id -> PlanEditStatusModel? in
            overlay.command(id: id).map { format.editStatus($0, from: session.id, snapshot: snapshot) }
        }
        let moves = (options?.moveTargets ?? []).map { date in
            EditChoiceModel(id: date.description, date: date, title: format.dates.short(date))
        }
        let swaps = (options?.swapPartners ?? []).map { partner in
            EditChoiceModel(
                id: partner.sessionID,
                date: partner.date,
                title: format.sessionTitle(partner.sessionID, snapshot: snapshot) + " · " + format.dates.short(partner.date)
            )
        }
        let overrides = (options?.overridableRules ?? []).map { rule -> RuleOverrideModel in
            let note = session.ruleNotes
                .first { $0["rule"]?.stringValue == rule }
                .flatMap(format.freeText)
            let why = format.text(.editOverrideMessage)
            return RuleOverrideModel(
                rule: rule,
                buttonTitle: format.text.format(.editOverride, rule),
                warningTitle: format.text.format(.editOverrideTitle, rule),
                warningMessage: [note, why].compactMap { $0 }.joined(separator: "\n\n")
            )
        }
        return SessionEditModel(
            sessionID: session.id,
            date: day.date,
            latest: latest,
            moveTargets: moves,
            swapPartners: swaps,
            canSkip: options?.canSkip ?? false,
            canUnskip: options?.canUnskip ?? false,
            overrides: overrides,
            withdrawable: withdrawable,
            blockText: format.blockText(options?.block)
        )
    }

    /// This phone's commands for `week`, oldest first.
    func planChangeLines(_ week: ISOWeek, snapshot: TrainingSnapshot) -> [PlanChangeLineModel] {
        guard let overlay = snapshot.plan?.overlay else { return [] }
        return overlay.commands(inWeek: week).map { command in
            let sessionID = command.sessionIDs.first
            return PlanChangeLineModel(
                commandID: command.id,
                sessionTitle: sessionID.map { format.sessionTitle($0, snapshot: snapshot) } ?? "",
                status: format.editStatus(command, from: sessionID, snapshot: snapshot)
            )
        }
    }
}

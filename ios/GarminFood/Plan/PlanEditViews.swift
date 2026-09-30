// PlanEditViews.swift
//
// Plan edits from the phone (add-plan-editing design D6):
//
//   SessionEditCard     the session detail's "Change the plan" card: this
//                       phone's latest change with its status and the
//                       vault's reason, then Move (a list of the week's
//                       allowed days), Swap (a list of partners), Skip (with
//                       an optional reason), Undo the skip, Override the
//                       rule (behind the A17 warning: the rule's own note,
//                       "you have the last word", destructive-styled
//                       "Override anyway") and Withdraw -- each only when
//                       TrainingCore's PlanEditPolicy allows it -- and why
//                       nothing is offered for a race or a past day.
//   PlanEditStatusView  one change: what it asks, its status (symbol AND
//                       text, never colour alone) and the vault's reason.
//   PlanEditBadgeLabel  the week row's "Change pending" / "Change not
//                       applied" mark.
//   PlanChangesList     the week agenda's "Plan changes" with Withdraw.
//
// Every action goes through TrainingModel (a local, durable event; the
// vault answers later); every word comes from TrainingCore's
// PlanEditModels. Depended on by: SessionDetailView, WeekAgendaView.

import SwiftUI
import TrainingCore

// MARK: - Session detail card

struct SessionEditCard: View {
    let editing: SessionEditModel

    @Environment(AppEnvironment.self) private var environment
    @State private var showMove = false
    @State private var showSwap = false
    @State private var showSkip = false
    @State private var skipReason = ""
    @State private var pendingOverride: RuleOverrideModel?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Change the plan", comment: "add-plan-editing: session detail, section with move, swap, skip and the vault's answers."))
            if let latest = editing.latest {
                PlanEditStatusView(status: latest)
            }
            if let block = editing.blockText {
                Label {
                    Text(verbatim: block)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            actions
        }
        .card()
        .confirmationDialog("Move to which day?", isPresented: $showMove, titleVisibility: .visible) {
            ForEach(editing.moveTargets) { choice in
                Button(choice.title) {
                    let sessionID = editing.sessionID
                    Task { await environment.training.moveSession(sessionID, to: choice.date) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Swap with which session?", isPresented: $showSwap, titleVisibility: .visible) {
            ForEach(editing.swapPartners) { choice in
                Button(choice.title) {
                    let sessionID = editing.sessionID
                    Task { await environment.training.swapSession(sessionID, with: choice.id) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Skip this session?", isPresented: $showSkip) {
            TextField("Reason (optional)", text: $skipReason)
            Button("Skip") {
                let sessionID = editing.sessionID
                let reason = skipReason
                skipReason = ""
                Task { await environment.training.skipSession(sessionID, reason: reason) }
            }
            Button("Cancel", role: .cancel) { skipReason = "" }
        } message: {
            Text("The vault marks it skipped: it takes no activity and leaves the watch.")
        }
        .alert(
            pendingOverride?.warningTitle ?? "",
            isPresented: Binding(get: { pendingOverride != nil }, set: { if !$0 { pendingOverride = nil } }),
            presenting: pendingOverride
        ) { warning in
            Button("Override anyway", role: .destructive) {
                let sessionID = editing.sessionID
                Task { await environment.training.overrideRule(warning.rule, sessionID: sessionID) }
            }
            Button("Keep the rule", role: .cancel) {}
        } message: { warning in
            Text(verbatim: warning.warningMessage)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if editing.hasActions {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if !editing.moveTargets.isEmpty {
                    actionButton { showMove = true } label: {
                        Label("Move to another day", systemImage: "calendar.badge.clock")
                    }
                }
                if !editing.swapPartners.isEmpty {
                    actionButton { showSwap = true } label: {
                        Label("Swap with another session", systemImage: "arrow.left.arrow.right")
                    }
                }
                if editing.canSkip {
                    actionButton { showSkip = true } label: {
                        Label("Skip", systemImage: "forward.circle")
                    }
                }
                if editing.canUnskip {
                    actionButton {
                        let sessionID = editing.sessionID
                        Task { await environment.training.unskipSession(sessionID) }
                    } label: {
                        Label("Undo the skip", systemImage: "arrow.uturn.backward.circle")
                    }
                }
                ForEach(editing.overrides) { rule in
                    actionButton {
                        Haptics.selection()
                        pendingOverride = rule
                    } label: {
                        Label {
                            Text(verbatim: rule.buttonTitle)
                        } icon: {
                            Image(systemName: "exclamationmark.shield")
                        }
                    }
                }
                ForEach(editing.withdrawable) { status in
                    actionButton {
                        let commandID = status.commandID
                        Task { await environment.training.withdrawPlanChange(commandID) }
                    } label: {
                        Label {
                            Text("Withdraw: \(status.description)")
                        } icon: {
                            Image(systemName: "xmark.circle")
                        }
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    private func actionButton<L: View>(action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }
}

// MARK: - One change and its status

struct PlanEditStatusView: View {
    let status: PlanEditStatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(verbatim: status.description)
                    .font(.subheadline.weight(.semibold))
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            Text(verbatim: status.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            if let reason = status.reason {
                Text(verbatim: reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch status.kind {
        case .pending: return "clock"
        case .withdrawing: return "clock.arrow.circlepath"
        case .applied: return "checkmark.circle.fill"
        case .notApplied, .refused: return "exclamationmark.triangle.fill"
        case .withdrawn: return "arrow.uturn.backward.circle"
        case .received: return "tray.and.arrow.down"
        case .answered: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status.kind {
        case .applied: return Theme.success
        case .notApplied, .refused: return Theme.warning
        default: return Color.secondary
        }
    }
}

/// "Change pending" / "Change not applied" on a session row: a symbol and
/// the words, so it reads without colour.
struct PlanEditBadgeLabel: View {
    let badge: PlanEditBadge?
    let text: String

    var body: some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: badge == .notApplied ? "exclamationmark.triangle.fill" : "clock")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(badge == .notApplied ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(Color.secondary))
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - The week's changes

struct PlanChangesList: View {
    let changes: [PlanChangeLineModel]

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Plan changes", comment: "add-plan-editing: week agenda, this phone's changes to the week and the vault's answers."))
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        if !change.sessionTitle.isEmpty {
                            Text(verbatim: change.sessionTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        PlanEditStatusView(status: change.status)
                        if change.status.canWithdraw {
                            Button("Withdraw") {
                                let commandID = change.commandID
                                Task { await environment.training.withdrawPlanChange(commandID) }
                            }
                            .font(.caption.weight(.semibold))
                            .tint(Theme.accent)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
    }
}

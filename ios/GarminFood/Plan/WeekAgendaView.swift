// WeekAgendaView.swift
//
// Plan -> Week (add-training-today-and-plan task 5.2, design D10): the
// week's header -- "W43 · 21–27 Oct", its own phase (a window week of the
// next phase names that phase), status, outline kind and note, targets
// against the vault's `actual` -- then seven day rows, Monday first, with
// each session (sport, title, key target, status, the done option),
// fuel, and unplanned activities as muted rows. Outline-only weeks say
// their sessions aren't written yet; weeks outside every phase have no
// plan. Previous/next page across the season.
//
// Everything shown is `WeekAgendaModel` from TrainingCore's PlanBuilder;
// nothing is summed here. Depended on by: PlanTabView (and `DayRowView` by
// its day sheet).

import SwiftUI
import TrainingCore

struct WeekAgendaView: View {
    let model: WeekAgendaModel
    let onPage: (ISOWeek) -> Void
    let onOpen: (SessionDetailTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
            header
            switch model.content {
            case .days(let days):
                ForEach(days) { day in
                    DayRowView(row: day, onOpen: onOpen)
                        .card()
                }
            case .outlineOnly(let message):
                TrainingEmptyStateView(state: TrainingEmptyState(kind: .weekNotWritten, symbol: "square.and.pencil", title: message, message: nil))
                    .card()
            case .empty(let state):
                TrainingEmptyStateView(state: state)
                    .card()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    if let previous = model.previous { onPage(previous) }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(model.previous == nil)
                .accessibilityLabel("Previous week")

                VStack(spacing: 2) {
                    Text(verbatim: model.title)
                        .font(.headline)
                    if let phase = model.phaseTitle {
                        Text(verbatim: phase)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Button {
                    if let next = model.next { onPage(next) }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(model.next == nil)
                .accessibilityLabel("Next week")
            }
            .tint(Theme.accent)

            let tags = [model.statusText, model.kindText].compactMap { $0 }
            if !tags.isEmpty || model.noteText != nil {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        Text(verbatim: tag)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().strokeBorder(Theme.stroke))
                    }
                    if let note = model.noteText {
                        Text(verbatim: note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let run = model.runLine {
                Label {
                    Text(verbatim: run)
                } icon: {
                    Image(systemName: "figure.run")
                }
                .font(.subheadline.weight(.semibold))
            }
            if let sessions = model.sessionsLine {
                Text(verbatim: sessions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TrainingNoticeLines(notices: model.notices)
        }
        .card()
    }
}

/// One day: its sessions, fuel, races and unplanned activities.
struct DayRowView: View {
    let row: DayRowModel
    let onOpen: (SessionDetailTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(verbatim: row.title)
                    .font(.subheadline.weight(.semibold))
                if row.isToday {
                    Text("Today")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent))
                }
                Spacer(minLength: 0)
                if let light = row.lightText {
                    Text(verbatim: light)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            ForEach(row.raceLines, id: \.self) { line in
                Label {
                    Text(verbatim: line)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            ForEach(row.sessions) { session in
                Button {
                    onOpen(SessionDetailTarget(sessionID: session.id, option: nil))
                } label: {
                    SessionRowView(session: session)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the session")
            }
            if let fuel = row.fuelLine {
                Label {
                    Text(verbatim: fuel)
                } icon: {
                    Image(systemName: "fork.knife.circle")
                }
                .font(.caption)
                .foregroundStyle(Theme.accent)
            }
            ForEach(row.unplanned) { activity in
                Label {
                    Text(verbatim: activity.text)
                } icon: {
                    Image(systemName: activity.sportSymbol)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let rest = row.restText {
                Text(verbatim: rest)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct SessionRowView: View {
    let session: SessionRowModel

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: session.sportSymbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: session.title)
                        .font(.subheadline)
                    if let badge = session.badgeText {
                        Text(verbatim: badge)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                let details = [session.slotText, session.keyTarget, session.fuelLine].compactMap { $0 }
                if !details.isEmpty {
                    Text(verbatim: details.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.xs)
            if let done = session.doneText {
                Label {
                    Text(verbatim: done)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.success)
            } else {
                SessionStatusChip(status: session.status, text: session.statusText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

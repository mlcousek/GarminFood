// PhaseDetailView.swift
//
// One training phase (add-season-phase-race-screens, design D4, spec
// training-phase-view): the header (kind, status, dates, where today is in
// it), goals and rules for the current phase, the week-by-week run target
// against what the vault counted, the key sessions and test results
// inside it, its races and, once it is closed, the recap with a short
// summary. A phase other than the current one says that goals and rules
// are published for the current phase only.
//
// Everything shown is `PhaseDetailModel` from TrainingCore's PlanBuilder
// (the ramp is `PhaseRamp`, the same numbers the statistics use); nothing
// is summed here. Read-only. Pushed from Plan -> Season and from a race's
// anchoring phase.
//
// Depended on by: SeasonTimelineView, RaceDetailView.

import SwiftUI
import TrainingCore

struct PhaseDetailView: View {
    let phaseID: String

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let detail = environment.training.planBuilder().phaseDetail(id: phaseID)
        ScrollView {
            if let detail {
                content(detail)
                    .padding(Theme.Spacing.md)
            } else {
                TrainingEmptyStateView(state: TrainingEmptyState(
                    kind: .noActivePlan,
                    symbol: "calendar.badge.exclamationmark",
                    title: String(localized: "This phase is no longer in the plan", comment: "Phase screen: the phase's id isn't in the latest plan."),
                    message: nil
                ))
                .card()
                .padding(Theme.Spacing.md)
            }
        }
        .background { GradientHeaderBackground() }
        .navigationTitle(detail.map { Text(verbatim: $0.title) } ?? Text("Phase"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ detail: PhaseDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
            header(detail)

            if !detail.goals.isEmpty {
                noteList(title: String(localized: "Goals", comment: "Phase screen: the phase's goals."), symbol: "scope", lines: detail.goals)
            }
            if !detail.rules.isEmpty {
                noteList(title: String(localized: "Rules", comment: "Phase screen: the plan's rules."), symbol: "list.bullet.rectangle", lines: detail.rules)
            }
            if let recap = detail.recap {
                recapCard(recap)
            }
            if !detail.weeks.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Weeks", comment: "Phase screen: week-by-week targets against what was run."))
                    PhaseRampLegend()
                    ForEach(detail.weeks) { week in
                        PhaseWeekRow(row: week)
                    }
                }
                .card()
            }
            if !detail.keySessions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Key sessions", comment: "Phase screen: long runs, quality sessions, tests and races."))
                    ForEach(detail.keySessions) { key in
                        NavigationLink {
                            SessionDetailView(target: SessionDetailTarget(sessionID: key.id, option: nil))
                        } label: {
                            KeySessionRow(session: key.row, dateText: key.dateText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
            if !detail.tests.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Test results", comment: "Phase screen: test results dated inside the phase."))
                    ForEach(detail.tests) { test in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: test.title)
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: "\(test.dateText) · \(test.valuesText)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if !detail.races.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Races", comment: "Season screen: section listing the season's races."))
                    ForEach(detail.races) { race in
                        NavigationLink {
                            RaceDetailView(raceID: race.id)
                        } label: {
                            RaceMarkerRow(race: race)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func header(_ detail: PhaseDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(verbatim: detail.title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            let tags = [detail.kindText, detail.statusText].compactMap { $0 }
            if !tags.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        Text(verbatim: tag)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(Capsule().strokeBorder(Theme.stroke))
                    }
                }
            }
            if let dates = detail.dateText {
                Text(verbatim: dates)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let progress = detail.progressText {
                if let fraction = detail.progressFraction {
                    ProgressView(value: fraction)
                        .tint(Theme.accent)
                        .accessibilityHidden(true)
                }
                Text(verbatim: progress)
                    .font(.subheadline.weight(.semibold))
            }
            if let restricted = detail.restrictedText {
                Label {
                    Text(verbatim: restricted)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            TrainingNoticeLines(notices: detail.notices)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func noteList(title: String, symbol: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: title)
            ForEach(lines, id: \.self) { line in
                Label {
                    Text(verbatim: line)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: symbol)
                        .foregroundStyle(Theme.accent)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func recapCard(_ recap: PhaseRecapModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Recap", comment: "Phase screen: the summary of a finished phase."))
            if let text = recap.text {
                Text(verbatim: text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach([recap.runLine, recap.withinLine, recap.biggestLine].compactMap { $0 }, id: \.self) { line in
                Label {
                    Text(verbatim: line)
                } icon: {
                    Image(systemName: "figure.run")
                }
                .font(.caption)
            }
            ForEach(recap.testLines, id: \.self) { line in
                Label {
                    Text(verbatim: line)
                } icon: {
                    Image(systemName: "stopwatch")
                }
                .font(.caption)
            }
            ForEach(recap.raceLines, id: \.self) { line in
                Label {
                    Text(verbatim: line)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Weeks

/// Target (outlined) against run (filled): shape as well as colour.
struct PhaseRampLegend: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Label {
                Text("Target")
            } icon: {
                Capsule().strokeBorder(Theme.accent, lineWidth: 1.5).frame(width: 16, height: 8)
            }
            Label {
                Text("Run")
            } icon: {
                Capsule().fill(Theme.accent).frame(width: 16, height: 8)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

private struct PhaseWeekRow: View {
    let row: PhaseWeekRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(verbatim: row.title)
                    .font(.caption.weight(.semibold))
                if let kind = row.kindText {
                    Text(verbatim: kind)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if row.isCurrent {
                    Text("Now")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .background(Capsule().fill(Theme.accent))
                }
                Spacer(minLength: 0)
                Text(verbatim: [row.actualText, row.targetText].compactMap { $0 }.joined(separator: " / "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    if let target = row.targetFraction {
                        Capsule()
                            .strokeBorder(Theme.accent, lineWidth: 1.5)
                            .frame(width: max(CGFloat(target) * proxy.size.width, 6))
                    }
                    if let actual = row.actualFraction {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(CGFloat(actual) * proxy.size.width, 6))
                            .padding(.vertical, 2)
                    }
                }
            }
            .frame(height: 10)
            if let note = row.noteText {
                Text(verbatim: note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(row.isFuture ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct KeySessionRow: View {
    let session: SessionRowModel
    let dateText: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: session.sportSymbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: session.title)
                    .font(.subheadline)
                Text(verbatim: [dateText, session.badgeText, session.keyTarget].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: Theme.Spacing.xs)
            SessionStatusChip(status: session.status, text: session.doneText ?? session.statusText)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// RaceDetailView.swift
//
// One race and its preparation (add-season-phase-race-screens, design D5,
// spec training-race-view): the countdown and what kind of race it is,
// the phase that anchors it, start and cutoff, the checkpoint table
// (clock times, buffers, section paces, heart-rate caps), race fuel with
// totals to the finish, the carb-load days, the gear list (mandatory
// first), the taper weeks and the plan's race-day session.
//
// Race week is linked to the food side (design D6): each carb-load day
// has "Open food log", which switches to Today on that date -- the day's
// food log, calorie summary and the training card with its carb-load line
// -- through AppEnvironment's existing day navigation. Nothing is logged or
// changed by it.
//
// Everything shown is `RaceDetailModel` from TrainingCore's PlanBuilder.
// Read-only. Pushed from Plan -> Season, a phase's races and Today's race
// chip (via AppRouter.openRace).
//
// Depended on by: SeasonTimelineView, PhaseDetailView, PlanTabView.

import SwiftUI
import AppearanceKit
import TrainingCore

struct RaceDetailView: View {
    let raceID: String

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let detail = environment.training.planBuilder().raceDetail(id: raceID)
        ScrollView {
            if let detail {
                content(detail)
                    .padding(Theme.Spacing.md)
            } else {
                TrainingEmptyStateView(state: TrainingEmptyState(
                    kind: .noActivePlan,
                    symbol: "flag.slash",
                    title: String(localized: "This race is no longer in the season", comment: "Race screen: the race's id isn't in the latest plan."),
                    message: nil
                ))
                .card()
                .padding(Theme.Spacing.md)
            }
        }
        .background { GradientHeaderBackground() }
        .navigationTitle(detail.map { Text(verbatim: $0.name) } ?? Text("Race"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ detail: RaceDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
            header(detail)

            if let stub = detail.stubText {
                TrainingEmptyStateView(state: TrainingEmptyState(kind: .weekNotWritten, symbol: "square.and.pencil", title: stub, message: nil))
                    .card()
            }
            if !detail.checkpoints.isEmpty || detail.startText != nil || detail.cutoffText != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Race plan", comment: "Race screen: start, cutoff and the checkpoint table."))
                    let times = [detail.startText, detail.cutoffText].compactMap { $0 }
                    if !times.isEmpty {
                        Text(verbatim: times.joined(separator: " · "))
                            .font(.subheadline.weight(.semibold))
                    }
                    ForEach(detail.checkpoints) { checkpoint in
                        CheckpointRow(row: checkpoint)
                        if checkpoint.id != detail.checkpoints.last?.id {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if let fuel = detail.fuel {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Race fuel", comment: "Race screen: what to eat and drink during the race."))
                    ForEach(fuel.lines, id: \.self) { line in
                        Label {
                            Text(verbatim: line)
                        } icon: {
                            Image(systemName: "drop")
                        }
                        .font(.subheadline)
                    }
                    ForEach(fuel.totalLines, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if !detail.carbLoad.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Carb load", comment: "Race screen: the carbohydrate-loading days before the race."))
                    ForEach(detail.carbLoad) { day in
                        CarbLoadRow(row: day) {
                            openFoodLog(on: day.date)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if !detail.gear.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Gear", comment: "Race screen: the race gear list."))
                    ForEach(detail.gear) { item in
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: item.isMandatory ? "checkmark.seal.fill" : "circle")
                                .foregroundStyle(item.isMandatory ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary))
                                .accessibilityHidden(true)
                            Text(verbatim: item.item)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Text(verbatim: item.tagText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if !detail.taper.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Taper", comment: "Race screen: the weeks leading into the race."))
                    ForEach(detail.taper) { week in
                        TaperWeekRow(row: week)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
            if !detail.sessions.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Race day in the plan", comment: "Race screen: the plan's session that is this race."))
                    ForEach(detail.sessions) { session in
                        NavigationLink {
                            SessionDetailView(target: SessionDetailTarget(sessionID: session.id, option: nil))
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: session.sportSymbol)
                                    .foregroundStyle(Theme.accent)
                                    .accessibilityHidden(true)
                                Text(verbatim: [session.title, session.keyTarget].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card()
            }
        }
    }

    private func header(_ detail: RaceDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: detail.countdown)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(detail.isPast ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.accent))
                Spacer(minLength: 0)
                let tags = [detail.isHero ? "★" : nil, detail.priorityText].compactMap { $0 }
                if !tags.isEmpty {
                    Text(verbatim: tags.joined(separator: " "))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().strokeBorder(Theme.stroke))
                }
            }
            Text(verbatim: "\(detail.isApproximate ? "≈ " : "")\(detail.dateText)")
                .font(.subheadline.weight(.semibold))
            let facts = [detail.category, detail.distanceText].compactMap { $0 }
            if !facts.isEmpty {
                Text(verbatim: facts.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let goal = detail.goalText {
                Label {
                    Text(verbatim: goal)
                } icon: {
                    Image(systemName: "scope")
                }
                .font(.subheadline.weight(.semibold))
            }
            if let phaseID = detail.phaseID, let phase = detail.phaseTitle {
                NavigationLink {
                    PhaseDetailView(phaseID: phaseID)
                } label: {
                    Label {
                        Text(verbatim: phase)
                    } icon: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .font(.caption.weight(.semibold))
                }
                .tint(Theme.accent)
            } else if let unanchored = detail.unanchoredText {
                Text(verbatim: unanchored)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let report = detail.reportText {
                Label {
                    Text(verbatim: report)
                } icon: {
                    Image(systemName: "doc.text")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            TrainingNoticeLines(notices: detail.notices)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Race week linked to the food side: Today on that date. The offset is
    /// counted in the phone's calendar, like the day switcher.
    private func openFoodLog(on date: LocalDate) {
        let deviceToday = LocalDate(date: Date(), timeZone: .current)
        let offset = deviceToday.days(until: date)
        Task {
            await environment.goToToday()
            if offset != 0 { await environment.stepDay(byDays: offset) }
            environment.router.selectedTab = .today
        }
    }
}

// MARK: - Rows

private struct CheckpointRow: View {
    let row: CheckpointRowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(verbatim: row.name)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(verbatim: [row.kmText, row.climbText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            let plan = [row.targetText, row.paceText].compactMap { $0 }
            if !plan.isEmpty {
                Text(verbatim: plan.joined(separator: " · "))
                    .font(.caption.monospacedDigit())
            }
            let limits = [row.cutoffText, row.aidText, row.hrCapText].compactMap { $0 }
            if !limits.isEmpty {
                Text(verbatim: limits.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let buffer = row.bufferText {
                Label {
                    Text(verbatim: buffer)
                } icon: {
                    Image(systemName: row.bufferIsNegative ? "exclamationmark.triangle.fill" : "clock")
                }
                .font(.caption.weight(row.bufferIsNegative ? .semibold : .regular))
                .foregroundStyle(row.bufferIsNegative ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Color.secondary))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

private struct CarbLoadRow: View {
    let row: CarbLoadRowModel
    let onOpenFood: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: row.dateText)
                        .font(.subheadline.weight(.semibold))
                    Text(verbatim: row.offsetText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: row.amountText)
                    .font(.subheadline)
                if let source = row.sourceText {
                    Text(verbatim: source)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: onOpenFood) {
                Label("Open food log", systemImage: "fork.knife")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .tint(Theme.accent)
        }
        .opacity(row.isPast ? 0.6 : 1)
    }
}

private struct TaperWeekRow: View {
    let row: TaperWeekRowModel

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: row.isRaceWeek ? "flag.checkered" : "arrow.down.right")
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: row.title)
                        .font(.subheadline.weight(.semibold))
                    if row.isCurrent {
                        Text("Now")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, Theme.Spacing.xs)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
                Text(verbatim: [row.kindText, row.targetText, row.noteText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

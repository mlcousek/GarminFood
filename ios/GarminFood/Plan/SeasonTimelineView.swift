// SeasonTimelineView.swift
//
// Plan -> Season (add-season-phase-race-screens, design D3, spec
// training-season-view): the whole season as one arc -- its phases as
// bands on a horizontal axis with month ticks, the stretches no phase
// covers as dashed "No phase planned" gaps, each race as a flag on its own
// label lane, and a line at today -- then the same phases and races as
// rows that open the Phase and Race screens.
//
// The axis is drawn from `SeasonTimelineModel` fractions only (TrainingCore
// did the date arithmetic); this view multiplies by the width it gets.
// Colour is never the only signal: the selected phase is filled AND
// labelled, a closed one is lighter AND says "Closed", race priority is a
// letter as well as a flag, an approximate date carries "≈". The drawing is
// one VoiceOver element with a summary; the rows below carry the detail.
//
// Depended on by: PlanTabView (the Season segment).

import SwiftUI
import TrainingCore

struct SeasonTimelineView: View {
    let model: SeasonTimelineModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
            if let state = model.emptyState {
                TrainingEmptyStateView(state: state)
                    .card()
                TrainingNoticeLines(notices: model.notices)
            } else {
                header
                SeasonAxisView(model: model)
                    .card()
                phases
                races
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let title = model.title {
                Text(verbatim: title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            if let period = model.periodText {
                Text(verbatim: period)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let goal = model.goal {
                Label {
                    Text(verbatim: goal)
                } icon: {
                    Image(systemName: "scope")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
            TrainingNoticeLines(notices: model.notices)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var phases: some View {
        if !model.bands.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Phases", comment: "Season screen: section listing the training phases."))
                ForEach(model.bands) { band in
                    NavigationLink {
                        PhaseDetailView(phaseID: band.id)
                    } label: {
                        PhaseBandRow(band: band)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var races: some View {
        if !model.races.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Races", comment: "Season screen: section listing the season's races."))
                ForEach(model.races) { race in
                    NavigationLink {
                        RaceDetailView(raceID: race.id)
                    } label: {
                        RaceMarkerRow(race: race, isNext: race.id == model.nextRace?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - The axis

private struct SeasonAxisView: View {
    let model: SeasonTimelineModel

    @ScaledMetric(relativeTo: .caption) private var barHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var laneHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .caption2) private var tickHeight: CGFloat = 16

    var body: some View {
        let lanes = max(model.lanes, 1)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                ticks(width: width)
                bar(width: width)
                    .offset(y: tickHeight)
                ForEach(model.races) { race in
                    RaceFlag(race: race)
                        .frame(width: width * CGFloat(SeasonLanes.labelWidth), alignment: .leading)
                        .offset(
                            x: clampedX(CGFloat(race.fraction) * width, labelWidth: width * CGFloat(SeasonLanes.labelWidth), total: width),
                            y: tickHeight + barHeight + 4 + CGFloat(race.lane) * laneHeight
                        )
                }
                if let today = model.today {
                    todayLine(today, width: width, height: tickHeight + barHeight + CGFloat(lanes) * laneHeight)
                }
            }
        }
        .frame(height: tickHeight + barHeight + CGFloat(lanes) * laneHeight + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func ticks(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.ticks) { tick in
                Text(verbatim: tick.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: min(CGFloat(tick.fraction) * width, max(width - 44, 0)))
            }
        }
        .frame(height: tickHeight, alignment: .topLeading)
    }

    private func bar(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.stroke.opacity(0.35))
                .frame(width: width, height: barHeight)
            ForEach(model.gaps) { gap in
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: max(CGFloat(gap.end - gap.start) * width, 2), height: barHeight)
                    .offset(x: CGFloat(gap.start) * width)
            }
            ForEach(model.bands) { band in
                let bandWidth = max(CGFloat(band.end - band.start) * width, 4)
                RoundedRectangle(cornerRadius: 6)
                    .fill(fill(band))
                    .overlay {
                        if band.status == .draft {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    .overlay(alignment: .leading) {
                        if bandWidth > 44 {
                            Text(verbatim: band.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(band.isSelected ? AnyShapeStyle(Theme.onAccent) : AnyShapeStyle(Color.primary))
                                .lineLimit(1)
                                .padding(.horizontal, Theme.Spacing.xs)
                        }
                    }
                    .frame(width: bandWidth, height: barHeight)
                    .offset(x: CGFloat(band.start) * width)
            }
        }
    }

    private func fill(_ band: PhaseBandModel) -> Color {
        if band.isSelected { return Theme.accent }
        switch band.status {
        case .closed: return Theme.accent.opacity(0.3)
        case .draft: return Theme.accent.opacity(0.12)
        case .active, .unknown: return Theme.accent.opacity(0.55)
        }
    }

    private func todayLine(_ today: TimelineMarkerModel, width: CGFloat, height: CGFloat) -> some View {
        let x = CGFloat(today.fraction) * width
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.primary)
                .frame(width: 2, height: height)
                .offset(x: x - 1)
            Text(verbatim: today.label)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 4)
                .background(Capsule().fill(Theme.cardBackground))
                .fixedSize()
                .offset(x: clampedX(x + 3, labelWidth: 48, total: width), y: height - 14)
        }
    }

    private func clampedX(_ x: CGFloat, labelWidth: CGFloat, total: CGFloat) -> CGFloat {
        min(max(x, 0), max(total - labelWidth, 0))
    }

    private var accessibilitySummary: String {
        var parts = model.bands.map(\.accessibilityLabel)
        parts.append(contentsOf: model.races.map(\.accessibilityLabel))
        if let today = model.today { parts.append(today.label) }
        return parts.joined(separator: ". ")
    }
}

private struct RaceFlag: View {
    let race: RaceMarkerModel

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Image(systemName: race.priority == .a || race.isHero ? "flag.fill" : "flag")
                .font(.caption2)
                .foregroundStyle(race.isPast ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.accent))
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: (race.isApproximate ? "≈ " : "") + race.name)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                if let code = race.priorityCode {
                    Text(verbatim: race.isHero ? "\(code) ★" : code)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(race.isPast ? 0.6 : 1)
    }
}

// MARK: - Rows

private struct PhaseBandRow: View {
    let band: PhaseBandModel

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RoundedRectangle(cornerRadius: 3)
                .fill(band.isSelected ? Theme.accent : Theme.accent.opacity(band.status == .closed ? 0.3 : 0.55))
                .frame(width: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(verbatim: band.title)
                        .font(.subheadline.weight(.semibold))
                    if band.isCurrent {
                        Text("Now")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
                Text(verbatim: [band.kindText, band.statusText, band.weeksText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: band.dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(band.accessibilityLabel)
        .accessibilityHint(Text("Opens the phase"))
    }
}

struct RaceMarkerRow: View {
    let race: RaceMarkerModel
    var isNext = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: race.priority == .a || race.isHero ? "flag.checkered" : "flag")
                .font(.title3)
                .foregroundStyle(race.isPast ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Theme.accent))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: race.name)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: [race.priorityText, race.distanceText].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(race.isApproximate ? "≈ " : "")\(race.dateText) · \(race.countdown)")
                    .font(.caption.weight(isNext ? .semibold : .regular))
                    .foregroundStyle(isNext ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.secondary))
                if let unanchored = race.unanchoredText {
                    Text(verbatim: unanchored)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card()
        .opacity(race.isPast ? 0.75 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(race.accessibilityLabel)
        .accessibilityHint(Text("Opens the race"))
    }
}

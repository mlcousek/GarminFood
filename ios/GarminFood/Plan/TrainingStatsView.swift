// TrainingStatsView.swift
//
// Training statistics relative to the plan (add-training-stats, design
// D2-D7, spec training-stats): for one phase or the whole season --
// adherence per week and per phase (done, missed, skipped, still planned;
// weeks outside the plan file's window listed, not counted), which option
// the done traffic-light days were (G, A, R and "option not identified"),
// the weekly run volume against its target, and every test's history
// with the left/right asymmetry.
//
// Charts are Swift Charts in the app's existing style (Weight, Trends):
// Theme tokens only, a legend and a text row for everything a chart shows,
// so colour is never the only signal and VoiceOver reads the rows. All
// numbers and text come from TrainingCore's `TrainingStatsModel`; nothing
// is counted here. Read-only.
//
// Reached from the Plan tab's toolbar (the selected phase) and from a
// phase's screen (that phase). Depended on by: PlanTabView,
// PhaseDetailView.

import SwiftUI
import Charts
import TrainingCore

struct TrainingStatsView: View {
    /// The phase the "This phase" scope means; `nil`: the plan's default.
    let phaseID: String?

    @Environment(AppEnvironment.self) private var environment
    @State private var wholeSeason = false

    var body: some View {
        let builder = environment.training.planBuilder()
        let phase = phaseID ?? builder.defaultPhaseID()
        let scope: StatsScope = wholeSeason || phase == nil ? .season : .phase(phase ?? "")
        let stats = builder.stats(scope: scope)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
                if phase != nil {
                    Picker("Scope", selection: $wholeSeason) {
                        Text("This phase").tag(false)
                        Text("Whole season").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                header(stats)
                if let state = stats.emptyState {
                    TrainingEmptyStateView(state: state)
                        .card()
                } else {
                    if let adherence = stats.adherence {
                        AdherenceCard(model: adherence)
                    }
                    if let options = stats.options {
                        OptionSplitCard(model: options)
                    }
                    if let volume = stats.volume, !volume.rows.isEmpty {
                        VolumeCard(model: volume)
                    }
                }
                if !stats.tests.isEmpty {
                    SectionHeader(title: String(localized: "Tests", comment: "Statistics: section with every test's history."))
                    ForEach(stats.tests) { test in
                        TestCard(model: test)
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background { GradientHeaderBackground() }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ stats: TrainingStatsModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(verbatim: stats.scopeTitle)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let range = stats.rangeText {
                Text(verbatim: range)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            TrainingNoticeLines(notices: stats.notices)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Adherence

private struct AdherenceCard: View {
    let model: AdherenceModel

    private struct Bar: Identifiable {
        let id: String
        let week: String
        let status: String
        let count: Int
    }

    private var bars: [Bar] {
        model.weeks.flatMap { row -> [Bar] in
            [
                Bar(id: row.id + "d", week: row.title, status: model.legend.done, count: row.counts.done),
                Bar(id: row.id + "m", week: row.title, status: model.legend.missed, count: row.counts.missed),
                Bar(id: row.id + "s", week: row.title, status: model.legend.skipped, count: row.counts.skipped),
                Bar(id: row.id + "p", week: row.title, status: model.legend.planned, count: row.counts.planned)
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Adherence", comment: "Statistics: sessions done against the plan."))
            Text(verbatim: model.summary)
                .font(.headline)
            Text(verbatim: model.countsText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !model.weeks.isEmpty {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Week", bar.week),
                        y: .value("Sessions", bar.count)
                    )
                    .foregroundStyle(by: .value("Status", bar.status))
                }
                .chartForegroundStyleScale(
                    domain: [model.legend.done, model.legend.missed, model.legend.skipped, model.legend.planned],
                    range: [Theme.success, Theme.danger, Theme.warning, Theme.stroke]
                )
                .chartLegend(position: .bottom)
                .frame(height: 170)
                .accessibilityHidden(true)
            }
            ForEach(model.weeks) { row in
                AdherenceRow(row: row)
            }
            if model.phases.count > 1 {
                SectionHeader(title: String(localized: "By phase", comment: "Statistics: adherence grouped by training phase."))
                ForEach(model.phases) { row in
                    AdherenceRow(row: row)
                }
            }
            if let outside = model.outsideText {
                Label {
                    Text(verbatim: outside)
                } icon: {
                    Image(systemName: "calendar.badge.minus")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct AdherenceRow: View {
    let row: AdherenceRowModel

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(verbatim: row.title)
                .font(.subheadline.weight(row.isCurrent ? .bold : .semibold))
            Text(verbatim: row.countsText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if let adherence = row.adherenceText {
                Text(verbatim: adherence)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

// MARK: - G / A / R

private struct OptionSplitCard: View {
    let model: OptionSplitModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Options on done days", comment: "Statistics: which of G, A and R the done traffic-light sessions were."))
            if let empty = model.emptyText {
                Text(verbatim: empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(model.shares.filter { $0.count > 0 }) { share in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(OptionStyle.tint(share.knownCode).opacity(share.knownCode == nil ? 0.35 : 0.85))
                                .overlay {
                                    Text(verbatim: share.code ?? "?")
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(Theme.onAccent)
                                }
                                .frame(width: max(CGFloat(share.fraction) * proxy.size.width - 2, 18))
                        }
                    }
                }
                .frame(height: 26)
                .accessibilityHidden(true)
                ForEach(model.shares) { share in
                    HStack(spacing: Theme.Spacing.sm) {
                        OptionCodeBadge(code: share.code ?? "?", knownCode: share.knownCode)
                        Text(verbatim: share.label)
                            .font(.subheadline)
                        Spacer(minLength: 0)
                        Text(verbatim: share.text)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: "\(share.code ?? "") \(share.label), \(share.text)"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Volume

private struct VolumeCard: View {
    let model: VolumeModel

    private struct Bar: Identifiable {
        let id: String
        let week: String
        let series: String
        let km: Double
    }

    private var targetName: String { String(localized: "Target", comment: "add-season-phase-race-screens: chart legend: the planned kilometres.") }
    private var runName: String { String(localized: "Run") }

    private var bars: [Bar] {
        model.rows.flatMap { row -> [Bar] in
            var result: [Bar] = []
            if let target = row.targetKm { result.append(Bar(id: row.id.description + "t", week: row.label, series: targetName, km: target)) }
            if let actual = row.actualKm { result.append(Bar(id: row.id.description + "a", week: row.label, series: runName, km: actual)) }
            return result
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Volume vs target", comment: "Statistics: weekly running kilometres against the plan's target."))
            Chart(bars) { bar in
                BarMark(
                    x: .value("Week", bar.week),
                    y: .value("Kilometres", bar.km)
                )
                .foregroundStyle(by: .value("Series", bar.series))
                .position(by: .value("Series", bar.series))
            }
            .chartForegroundStyleScale(domain: [targetName, runName], range: [Theme.accent.opacity(0.3), Theme.accent])
            .chartLegend(position: .bottom)
            .frame(height: 180)
            .accessibilityHidden(true)
            ForEach(model.rows) { row in
                HStack(spacing: Theme.Spacing.sm) {
                    Text(verbatim: row.label)
                        .font(.subheadline.weight(row.isCurrent ? .bold : .semibold))
                    Text(verbatim: row.valueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let delta = row.deltaText {
                        Text(verbatim: delta)
                            .font(.caption.monospacedDigit())
                    }
                }
                .opacity(row.isFuture ? 0.7 : 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
            }
            ForEach(model.summaryLines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Tests

private struct TestCard: View {
    let model: TestCardModel

    private struct Point: Identifiable {
        let id: String
        let date: String
        let measure: String
        let value: Double
    }

    private var points: [Point] {
        model.measures.flatMap { measure in
            measure.points.map { Point(id: measure.key + $0.date.description, date: $0.dateText, measure: measure.label, value: $0.value) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(verbatim: model.title)
                .font(.headline)
            if let empty = model.emptyText {
                Text(verbatim: empty)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                if points.count > 1 {
                    Chart(points) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(by: .value("Series", point.measure))
                        .symbol(by: .value("Series", point.measure))
                    }
                    .chartLegend(position: .bottom)
                    .frame(height: 150)
                    .accessibilityHidden(true)
                }
                ForEach(model.measures) { measure in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(verbatim: measure.label)
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: measure.changeText ?? measure.latestText ?? "–")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        if let verdict = measure.verdictText {
                            Label {
                                Text(verbatim: verdict)
                            } icon: {
                                Image(systemName: symbol(measure.verdict))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(measure.verdict == .worse ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.success))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                ForEach(model.pairs) { pair in
                    VStack(alignment: .leading, spacing: 2) {
                        if let latest = pair.latestText {
                            Label {
                                Text(verbatim: latest)
                            } icon: {
                                Image(systemName: "arrow.left.and.right")
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        ForEach(pair.history) { point in
                            Text(verbatim: "\(point.dateText) · \(point.text)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func symbol(_ verdict: TestVerdict?) -> String {
        switch verdict {
        case .improved?: return "arrow.up.right"
        case .worse?: return "arrow.down.right"
        case .unchanged?, nil: return "equal"
        }
    }
}

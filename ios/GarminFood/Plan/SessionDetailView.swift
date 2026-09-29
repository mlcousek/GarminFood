// SessionDetailView.swift
//
// One session explained (add-training-today-and-plan task 5.4, design D10,
// spec "The session detail explains the session"): date and slot, sport,
// status, the Test/Race badge; a G/A/R picker opening on the tapped
// option (else the done one, else the morning light's, else G); per
// option its targets in the athlete's zones, its workout's steps ("Steps
// not published" when there are none) and the watch state once
// published; why; where it came from once published; the done option or
// "Option not identified" with the matched activity and how it was
// recognised; fuel; a test's results against the test history; the race.
//
// Pushed from Today's option cards and from Plan's week, month and day
// sheet. Read-only: no control moves, swaps, skips, checks in or rates
// the session. Everything shown is `SessionDetailModel` from TrainingCore.
//
// Depended on by: TodayView, PlanTabView.

import SwiftUI
import TrainingCore

struct SessionDetailView: View {
    let target: SessionDetailTarget

    @Environment(AppEnvironment.self) private var environment
    @State private var selectedIndex: Int?

    var body: some View {
        let detail = environment.training.planBuilder().sessionDetail(id: target.sessionID, option: target.option)
        ScrollView {
            if let detail {
                content(detail)
                    .padding(Theme.Spacing.md)
            } else {
                TrainingEmptyStateView(state: TrainingEmptyState(
                    kind: .restDay,
                    symbol: "calendar.badge.exclamationmark",
                    title: String(localized: "This session is no longer in the plan", comment: "Session detail: the session's id isn't in the latest plan."),
                    message: nil
                ))
                .card()
                .padding(Theme.Spacing.md)
            }
        }
        .background { GradientHeaderBackground() }
        .navigationTitle(detail.map { Text(verbatim: $0.title) } ?? Text("Session"))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(_ detail: SessionDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
            headerCard(detail)

            if !detail.options.isEmpty {
                let index = min(selectedIndex ?? detail.initialOptionIndex, detail.options.count - 1)
                Picker("Option", selection: Binding(
                    get: { index },
                    set: { selectedIndex = $0 }
                )) {
                    ForEach(Array(detail.options.enumerated()), id: \.offset) { offset, option in
                        Text(verbatim: option.code ?? "?").tag(offset)
                    }
                }
                .pickerStyle(.segmented)
                optionCard(detail.options[index])
            } else if let single = detail.single {
                optionCard(single)
            }

            if !detail.whyLines.isEmpty || detail.originText != nil {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Why this session", comment: "Session detail: section with the reasons for the session."))
                    ForEach(detail.whyLines, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let origin = detail.originText {
                        Label {
                            Text(verbatim: origin)
                        } icon: {
                            Image(systemName: "arrow.triangle.branch")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .card()
            }

            if let done = detail.done {
                doneCard(done)
            }

            if !detail.fuelLines.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionHeader(title: String(localized: "Fuel", comment: "Session detail: section with carbohydrate targets."))
                    ForEach(detail.fuelLines, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.subheadline)
                    }
                }
                .card()
            }

            if let test = detail.test {
                testCard(test)
            }
        }
    }

    private func headerCard(_ detail: SessionDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: detail.sportSymbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: detail.title)
                        .font(.headline)
                    Text(verbatim: [detail.dateLine, detail.sportName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if let badge = detail.badgeText {
                    Text(verbatim: badge)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(Capsule().strokeBorder(Theme.stroke))
                }
            }
            SessionStatusChip(status: detail.status, text: detail.statusText)
            if let race = detail.raceLine {
                Label {
                    Text(verbatim: race)
                } icon: {
                    Image(systemName: "flag.checkered")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func optionCard(_ option: DetailOptionModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                if option.code != nil {
                    OptionCodeBadge(code: option.code, knownCode: option.knownCode)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: option.label)
                        .font(.headline)
                    if let meaning = option.meaning {
                        Text(verbatim: meaning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if !option.targetLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(option.targetLines, id: \.self) { line in
                        Text(verbatim: line)
                            .font(.subheadline.monospacedDigit())
                    }
                }
            }
            if let watch = option.watchLine {
                Label {
                    Text(verbatim: watch)
                } icon: {
                    Image(systemName: "calendar.badge.checkmark")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Divider()
            SectionHeader(title: String(localized: "Steps", comment: "Session detail: the workout's steps."))
            if let placeholder = option.stepsPlaceholder {
                Text(verbatim: placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(option.steps.enumerated()), id: \.offset) { offset, step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(verbatim: "\(offset + 1).")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text(verbatim: step)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func doneCard(_ done: DoneDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionHeader(title: String(localized: "Done activity", comment: "Session detail: the activity that completed the session."))
            if let option = done.optionText {
                Text(verbatim: option)
                    .font(.subheadline.weight(.semibold))
            }
            if let activity = done.activityLine {
                Label {
                    Text(verbatim: activity)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                }
                .font(.subheadline)
            }
            if let recognised = done.recognisedText {
                Text(verbatim: recognised)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func testCard(_ test: TestDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Test result", comment: "Session detail: a test session's results."))
            if let placeholder = test.placeholder {
                Text(verbatim: placeholder)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(test.rows) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: row.label)
                        .font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(verbatim: row.valueText)
                            .font(.headline.monospacedDigit())
                        let comparison = [row.previousText, row.trendText].compactMap { $0 }.joined(separator: " · ")
                        if !comparison.isEmpty {
                            Label {
                                Text(verbatim: comparison)
                            } icon: {
                                Image(systemName: trendSymbol(row.trend))
                            }
                            .font(.caption)
                            .foregroundStyle(row.trend == .improved ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Color.secondary))
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let note = test.note {
                Text(verbatim: note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func trendSymbol(_ trend: TestTrend?) -> String {
        switch trend {
        case .improved?: return "arrow.up.right"
        case .worse?: return "arrow.down.right"
        case .unchanged?: return "equal"
        case nil: return "minus"
        }
    }
}

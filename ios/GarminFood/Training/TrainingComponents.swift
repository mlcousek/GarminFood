// TrainingComponents.swift
//
// Small views every training screen shares (add-training-today-and-plan
// D9, D11): the G/A/R option style (theme tint AND letter AND shape, so
// colour is never the only signal), the session status chip, the notice
// lines ("Plan as of ...", the loud "Update Jirka's Arc ..."), a designed
// empty state for every non-happy state, and the navigation value that
// opens a session's detail.
//
// Display text comes from TrainingCore's builders (already in the app's
// language) and is shown verbatim; colours are Theme tokens only (the
// design-token lint). Read-only: nothing here records anything.
//
// Depended on by: the Today training cards and the Plan views.

import SwiftUI
import TrainingCore

/// Pushes the session detail at an option (Today and Plan).
struct SessionDetailTarget: Hashable, Identifiable {
    let sessionID: String
    let option: String?

    var id: String { "\(sessionID)|\(option ?? "-")" }
}

/// G, A, R: a theme colour, a letter and a shape each (design D9).
enum OptionStyle {
    static func tint(_ code: OptionCode?) -> Color {
        switch code {
        case .g?: return Theme.success
        case .a?: return Theme.warning
        case .r?: return Theme.danger
        case nil: return Theme.accent
        }
    }

    /// G circle, A triangle, R square; a neutral shape for the rest.
    static func symbol(_ code: OptionCode?) -> String {
        switch code {
        case .g?: return "circle.fill"
        case .a?: return "triangle.fill"
        case .r?: return "square.fill"
        case nil: return "diamond.fill"
        }
    }
}

/// The option's letter next to its shape, e.g. "● G".
struct OptionCodeBadge: View {
    let code: String?
    let knownCode: OptionCode?

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .caption) private var shapeSize: CGFloat = 9

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: OptionStyle.symbol(knownCode))
                .font(.system(size: differentiateWithoutColor ? shapeSize * 1.6 : shapeSize))
            if let code {
                Text(verbatim: code)
                    .font(.caption.weight(.heavy))
            }
        }
        .foregroundStyle(OptionStyle.tint(knownCode))
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(OptionStyle.tint(knownCode).opacity(differentiateWithoutColor ? 0.08 : 0.16))
        )
        .accessibilityHidden(true)
    }
}

/// "Done" / "Missed" / "Planned" with a symbol, never colour alone.
struct SessionStatusChip: View {
    let status: SessionStatusKind
    let text: String?

    var body: some View {
        if let text {
            Label {
                Text(verbatim: text)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .labelStyle(.titleAndIcon)
        }
    }

    private var symbol: String {
        switch status {
        case .done: return "checkmark.circle.fill"
        case .missed: return "xmark.circle"
        case .skipped: return "forward.circle"
        case .planned: return "circle.dashed"
        case .unknown: return "questionmark.circle"
        }
    }

    private var tint: Color {
        switch status {
        case .done: return Theme.success
        case .missed: return Theme.danger
        default: return Color.secondary
        }
    }
}

/// The freshness and problem lines under a card or in a header (D11).
struct TrainingNoticeLines: View {
    let notices: [TrainingNotice]

    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(notices) { notice in
                    Label {
                        Text(verbatim: notice.text)
                    } icon: {
                        Image(systemName: symbol(notice.kind))
                    }
                    .font(notice.isLoud ? .footnote.weight(.semibold) : .caption)
                    .foregroundStyle(notice.isLoud ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(Color.secondary))
                }
            }
        }
    }

    private func symbol(_ kind: TrainingNotice.Kind) -> String {
        switch kind {
        case .updateApp: return "arrow.down.app"
        case .unreadable: return "exclamationmark.triangle"
        case .behind: return "calendar.badge.clock"
        case .stale: return "clock.arrow.circlepath"
        case .newerVersion: return "sparkles"
        case .dateUnknown: return "questionmark.circle"
        }
    }
}

/// A designed empty state from TrainingCore (fetching, no plan, rest day,
/// week not written, ...).
struct TrainingEmptyStateView: View {
    let state: TrainingEmptyState

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 28

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: state.symbol)
                .font(.system(size: iconSize))
                .foregroundStyle(.tertiary)
            Text(verbatim: state.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let message = state.message {
                Text(verbatim: message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

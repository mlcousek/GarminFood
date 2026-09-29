// MonthCalendarView.swift
//
// Plan -> Month, like Garmin's calendar (add-training-today-and-plan task
// 5.3, design D10): a Monday-first 6 x 7 grid with the ISO week number and
// the week's run target on the left, up to three sport glyphs per day
// ("+n" beyond), the morning light as a dot, a flag on race days, a ring
// on today and dimmed days outside the month. Tapping a day opens its
// sheet (PlanTabView). Arrows or a horizontal swipe change the month.
//
// Glyph styles are distinguishable without colour (spec "Missed and done
// sessions"): done is a FILLED disc, planned an outlined circle, missed a
// dashed outline with a cross, skipped a struck-through glyph, unplanned a
// small bare glyph. Colours are Theme tokens only.
//
// Everything shown is `MonthCalendarModel` from TrainingCore's PlanBuilder.
// Depended on by: PlanTabView.

import SwiftUI
import TrainingCore

struct MonthCalendarView: View {
    let model: MonthCalendarModel
    let onPage: (PlanMonth) -> Void
    let onSelectDay: (LocalDate) -> Void

    @ScaledMetric(relativeTo: .caption) private var weekColumnWidth: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Density.stackSpacing) {
            VStack(spacing: Theme.Spacing.sm) {
                header
                weekdayRow
                ForEach(model.rows) { row in
                    weekRow(row)
                }
                TrainingNoticeLines(notices: model.notices)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .card(padding: Theme.Spacing.sm)
            .gesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        if value.translation.width < -60 {
                            onPage(PlanMonth(year: model.next.year, month: model.next.month))
                        } else if value.translation.width > 60 {
                            onPage(PlanMonth(year: model.previous.year, month: model.previous.month))
                        }
                    }
            )
            if let state = model.emptyState {
                TrainingEmptyStateView(state: state)
                    .card()
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                onPage(PlanMonth(year: model.previous.year, month: model.previous.month))
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous month")
            Text(verbatim: model.title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            Button {
                onPage(PlanMonth(year: model.next.year, month: model.next.month))
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next month")
        }
        .tint(Theme.accent)
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            Color.clear.frame(width: weekColumnWidth, height: 1)
            ForEach(Array(model.weekdayHeaders.enumerated()), id: \.offset) { _, name in
                Text(verbatim: name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func weekRow(_ row: MonthWeekRowModel) -> some View {
        HStack(alignment: .top, spacing: 2) {
            VStack(spacing: 1) {
                Text(verbatim: row.label)
                    .font(.caption2.weight(.semibold))
                if let target = row.targetText {
                    Text(verbatim: target)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
            }
            .frame(width: weekColumnWidth)
            .padding(.top, Theme.Spacing.xs)
            .accessibilityElement(children: .combine)

            ForEach(row.cells) { cell in
                Button {
                    onSelectDay(cell.date)
                } label: {
                    DayCellView(cell: cell)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cell.accessibilityLabel)
            }
        }
    }
}

private struct DayCellView: View {
    let cell: DayCellModel

    @ScaledMetric(relativeTo: .caption) private var minHeight: CGFloat = 58

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 1) {
                Text(verbatim: String(cell.dayNumber))
                    .font(.caption.weight(cell.isToday ? .bold : .regular))
                    .foregroundStyle(cell.isInMonth ? AnyShapeStyle(HierarchicalShapeStyle.primary) : AnyShapeStyle(HierarchicalShapeStyle.tertiary))
                    .padding(3)
                    .background {
                        if cell.isToday {
                            Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                        }
                    }
                if cell.isRaceDay {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.accent)
                }
            }
            VStack(spacing: 1) {
                ForEach(cell.glyphs) { glyph in
                    GlyphView(glyph: glyph)
                }
                if cell.overflow > 0 {
                    Text(verbatim: "+\(cell.overflow)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if cell.lightName != nil {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(cell.hasContent && cell.isInMonth ? Theme.groupedBackground : Color.clear)
        )
        .opacity(cell.isInMonth ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}

/// One sport glyph, styled by status with a shape as well as a colour.
private struct GlyphView: View {
    let glyph: DayGlyph

    private let size: CGFloat = 16

    var body: some View {
        switch glyph.style {
        case .done:
            Image(systemName: glyph.sportSymbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: size, height: size)
                .background(Circle().fill(Theme.accent))
        case .planned:
            Image(systemName: glyph.sportSymbol)
                .font(.system(size: 8))
                .foregroundStyle(Theme.accent)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 1))
        case .missed:
            Image(systemName: glyph.sportSymbol)
                .font(.system(size: 8))
                .foregroundStyle(Theme.danger)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Theme.danger, style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .heavy))
                        .foregroundStyle(Theme.danger)
                        .offset(x: 3, y: -3)
                }
        case .skipped:
            Image(systemName: glyph.sportSymbol)
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .frame(width: size, height: size)
                .overlay(Rectangle().fill(Color.secondary).frame(height: 1).rotationEffect(.degrees(-35)))
        case .unplanned:
            Image(systemName: glyph.sportSymbol)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .frame(width: size, height: 12)
        case .unknown:
            Image(systemName: glyph.sportSymbol)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

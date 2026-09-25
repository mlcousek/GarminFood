// BingoGridView.swift
//
// add-weekly-bingo design D8: the 3x3 bingo grid shared by the current card
// and every page of the past-cards pager on `BingoCardView`, plus the small
// display helpers (weekday / week-range / difficulty / data-source text and
// the per-square VoiceOver label) both of them need.
//
// Squares are laid out as equal squares (`Color.clear.aspectRatio(1)`), so
// the completed-line strokes drawn over the grid can be computed from the
// grid's own rect without measuring each cell. Lines draw in with a spring
// the first time the current card appears; with Reduce Motion they fade in
// instead. Each square is one VoiceOver element: "Row 1, column 2, Fruit
// Salad, done on Tuesday" / "... not done" / "... free square".
//
// Thin: every value comes from `BingoCardStatus` (Gamification,
// unit-tested); task titles arrive already localized, hence
// `Text(verbatim:)`. Days are `yyyy-MM-dd` keys, formatted here for display
// only.
//
// Depends on: WeeklyBingoFeature's BingoCardStatus/BingoSquareStatus, Theme.
// Depended on by: BingoCardView.

import SwiftUI
import Gamification

/// Display-only formatting for bingo squares and cards.
enum BingoFormat {
    private static func date(_ day: String) -> Date? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone.current
        parser.dateFormat = "yyyy-MM-dd"
        return parser.date(from: day)
    }

    /// "Tuesday" for a `yyyy-MM-dd` key (the key itself if unparsable).
    static func weekday(_ day: String) -> String {
        date(day)?.formatted(.dateTime.weekday(.wide)) ?? day
    }

    /// "Tue".
    static func shortWeekday(_ day: String) -> String {
        date(day)?.formatted(.dateTime.weekday(.abbreviated)) ?? day
    }

    /// "Tuesday, 22 Sep".
    static func longDay(_ day: String) -> String {
        date(day)?.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) ?? day
    }

    /// "21 Sep – 27 Sep" for an ISO week.
    static func weekRange(_ week: WeekKey) -> String {
        let calendar = Calendar.current
        guard let start = week.start(calendar: calendar),
              let end = calendar.date(byAdding: .day, value: 6, to: start)
        else { return week.rawValue }
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
        return start.formatted(style) + " – " + end.formatted(style)
    }

    static func difficulty(_ difficulty: BingoDifficulty) -> String {
        switch difficulty {
        case .easy: return String(localized: "Easy task", comment: "Bingo square difficulty.")
        case .medium: return String(localized: "Medium task", comment: "Bingo square difficulty.")
        case .hard: return String(localized: "Hard task", comment: "Bingo square difficulty.")
        }
    }

    /// Which of the owner's data a task is judged from (empty = the food log).
    static func dataSources(_ requirement: DataRequirement) -> [String] {
        var lines: [String] = []
        if requirement.contains(.macros) {
            lines.append(String(localized: "Judged from your nutrition totals and goals.", comment: "Bingo square sheet: the task uses macro data."))
        }
        if requirement.contains(.water) {
            lines.append(String(localized: "Judged from your water log and goal.", comment: "Bingo square sheet: the task uses water data."))
        }
        if requirement.contains(.activities) {
            lines.append(String(localized: "Judged from your Garmin activities.", comment: "Bingo square sheet: the task uses Garmin activities."))
        }
        if lines.isEmpty {
            lines.append(String(localized: "Judged from the foods you log.", comment: "Bingo square sheet: the task uses only logged foods."))
        }
        return lines
    }

    /// The square's VoiceOver label.
    static func accessibilityLabel(_ square: BingoSquareStatus) -> String {
        let row = square.row
        let column = square.column
        guard let task = square.task else {
            return String(localized: "Row \(row), column \(column), free square", comment: "VoiceOver label of the bingo centre square.")
        }
        let title = task.title
        if let day = square.completedDay {
            let doneOn = BingoFormat.weekday(day)
            return String(localized: "Row \(row), column \(column), \(title), done on \(doneOn)", comment: "VoiceOver label of a done bingo square. Row, column, task title, weekday it was done.")
        }
        return String(localized: "Row \(row), column \(column), \(title), not done", comment: "VoiceOver label of a bingo square not done yet. Row, column, task title.")
    }
}

/// The 3x3 card. `onSelect` is called for task squares (not the FREE one).
struct BingoGrid: View {
    enum Size {
        case large, compact
    }

    let card: BingoCardStatus
    let size: Size
    /// Draw completed lines in with an animation on first appearance.
    let animateLines: Bool
    let onSelect: (BingoSquareStatus) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var linesShown = false

    init(
        card: BingoCardStatus,
        size: Size = .large,
        animateLines: Bool = false,
        onSelect: @escaping (BingoSquareStatus) -> Void = { _ in }
    ) {
        self.card = card
        self.size = size
        self.animateLines = animateLines
        self.onSelect = onSelect
    }

    private var spacing: CGFloat { size == .large ? Theme.Spacing.sm : Theme.Spacing.xs }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { column in
                        cell(row * 3 + column)
                    }
                }
            }
        }
        .overlay {
            lineStrokes
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear {
            guard animateLines, !linesShown else {
                linesShown = true
                return
            }
            let animation: Animation = reduceMotion
                ? .easeInOut(duration: 0.35)
                : .spring(response: 0.7, dampingFraction: 0.85).delay(0.2)
            withAnimation(animation) {
                linesShown = true
            }
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let square: BingoSquareStatus? = index < card.squares.count ? card.squares[index] : nil
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let square {
                    if square.isFree {
                        BingoSquareCell(square: square, size: size)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(verbatim: BingoFormat.accessibilityLabel(square)))
                    } else {
                        Button {
                            onSelect(square)
                        } label: {
                            BingoSquareCell(square: square, size: size)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: BingoFormat.accessibilityLabel(square)))
                        .accessibilityHint(Text("Shows the rule"))
                    }
                }
            }
    }

    /// Completed rows/columns/diagonals as strokes across the grid.
    private var lineStrokes: some View {
        // Without the entrance animation (past cards) lines are simply there.
        let shown = linesShown || !animateLines
        let progress: CGFloat = (shown || reduceMotion) ? 1 : 0
        let opacity: Double = (shown || !reduceMotion) ? 1 : 0
        return ZStack {
            ForEach(card.lines) { line in
                BingoLineShape(line: line, spacing: spacing)
                    .trim(from: 0, to: progress)
                    .stroke(
                        Theme.accentDeep.opacity(0.75),
                        style: StrokeStyle(lineWidth: size == .large ? 5 : 3, lineCap: .round)
                    )
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One square's face: family symbol, title, and the day it was done.
private struct BingoSquareCell: View {
    let square: BingoSquareStatus
    let size: BingoGrid.Size

    var body: some View {
        VStack(spacing: size == .large ? Theme.Spacing.xs : 2) {
            if let task = square.task {
                Image(systemName: task.symbol)
                    .font(size == .large ? Font.title3 : Font.caption)
                    .foregroundStyle(square.isDone ? Theme.onAccent : Theme.accent)
                if size == .large {
                    Text(verbatim: task.title)
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(square.isDone ? Theme.onAccent : Color.primary)
                    if let day = square.completedDay {
                        Label {
                            Text(verbatim: BingoFormat.shortWeekday(day))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                        }
                        .font(.caption2)
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.onAccent)
                    }
                }
            } else {
                Image(systemName: "star.fill")
                    .font(size == .large ? Font.title3 : Font.caption)
                    .foregroundStyle(Theme.onAccent)
                if size == .large {
                    Text("FREE")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                }
            }
        }
        .padding(size == .large ? Theme.Spacing.xs : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(square.isDone ? Theme.accent : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .strokeBorder(square.isDone ? Theme.accentDeep : Theme.stroke, lineWidth: 1)
        )
    }
}

/// A straight stroke from the centre of a line's first square to the
/// centre of its last, for a grid of three equal rows and columns separated
/// by `spacing`.
private struct BingoLineShape: Shape {
    let line: BingoLine
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        let cellWidth = (rect.width - 2 * spacing) / 3
        let cellHeight = (rect.height - 2 * spacing) / 3
        func centre(_ index: Int) -> CGPoint {
            let column = CGFloat(index % 3)
            let row = CGFloat(index / 3)
            return CGPoint(
                x: rect.minX + column * (cellWidth + spacing) + cellWidth / 2,
                y: rect.minY + row * (cellHeight + spacing) + cellHeight / 2
            )
        }
        var path = Path()
        guard let first = line.indices.first, let last = line.indices.last else { return path }
        path.move(to: centre(first))
        path.addLine(to: centre(last))
        return path
    }
}

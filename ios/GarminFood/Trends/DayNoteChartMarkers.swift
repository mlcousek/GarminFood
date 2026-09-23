// DayNoteChartMarkers.swift
//
// Day-note markers on the Trends charts (add-day-notes): every TAGGED day
// (a day whose `DayNote` has at least one `DayNoteTag`, written from the
// Today screen's `DayNoteCard`) gets a faint vertical line with its tag
// emoji along the top of each daily chart, and tapping near it opens the
// note. WHY: a 3800 kcal spike reads very differently once it carries a 🎉
// -- that is the whole point of writing the note (proposal.md).
//
// The pieces here are shared by both chart views in `TrendsComponents.
// swift` (`MacroLineChartView`, `HydrationTrendChartView`) rather than
// repeated in each:
//   - `DayNoteChartMarker`: a note resolved to the chart's x-axis `Date`.
//   - `DayNoteMarks`: the Swift Charts content (a `RuleMark` + emoji
//     annotation per marker).
//   - `.dayNoteMarkerTaps(...)`: a `chartOverlay` that turns a tap into the
//     nearest marker, and `.dayNoteMarkerAccessibilityActions(...)`, the
//     VoiceOver equivalent (the charts themselves are a single
//     ignored-children accessibility element, so the markers can't be
//     focused individually).
//   - `DayNoteRevealSheet`: what a tap shows.
//
// Only tagged days get a marker (spec: "a marker for each tagged day"); a
// text-only note stays on its Today card. Day keys are parsed with
// `NutritionDayBoundary.date(fromDayString:)` -- the same parser
// `MacroTrendDay.make` uses for Garmin's `mealDate`, so a note's marker
// lands on exactly the same `Date` as that day's data point.

import SwiftUI
import Charts
import FoodLogCore
import Gamification

// MARK: - Marker

struct DayNoteChartMarker: Identifiable {
    /// Local midnight of the note's day.
    let date: Date
    let note: DayNote

    var id: String { note.day }

    /// Up to two tag emoji -- more would crowd a 30-day phone-width chart.
    var emoji: String {
        let shown = note.tags.prefix(2).map(\.emoji).joined()
        return note.tags.count > 2 ? shown + "…" : shown
    }

    var accessibilityLabel: String {
        let tags = note.tags.map(\.title).joined(separator: ", ")
        return "\(tags), \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))"
    }

    /// Tagged notes only, oldest first, each resolved to its chart `Date`.
    static func markers(from notes: [DayNote], calendar: Calendar = .current) -> [DayNoteChartMarker] {
        notes
            .filter { !$0.tags.isEmpty }
            .compactMap { note -> DayNoteChartMarker? in
                guard let date = NutritionDayBoundary.date(fromDayString: note.day, calendar: calendar) else { return nil }
                return DayNoteChartMarker(date: date, note: note)
            }
            .sorted { $0.date < $1.date }
    }

    /// The markers that fall inside `first...last` (a chart's own x range),
    /// so a marker never stretches the axis beyond the plotted data.
    static func visible(_ markers: [DayNoteChartMarker], from first: Date?, to last: Date?) -> [DayNoteChartMarker] {
        guard let first, let last else { return [] }
        return markers.filter { $0.date >= first && $0.date <= last }
    }

    /// Where the marker sits on the x axis. A bar chart plotted with
    /// `unit: .day` centres each bar on the middle of its day, so its
    /// marker is shifted to noon to line up with the bar; a line chart
    /// plots each point at midnight, so its marker stays there.
    func plotDate(centeredOnDay: Bool, calendar: Calendar = .current) -> Date {
        guard centeredOnDay else { return date }
        return calendar.date(byAdding: .hour, value: 12, to: date) ?? date
    }
}

// MARK: - Chart content

/// A faint dashed vertical rule per marker with the tag emoji pinned to the
/// top of the plot -- it marks the whole day without covering the data
/// point, and still shows on a tagged day with nothing logged.
struct DayNoteMarks: ChartContent {
    let markers: [DayNoteChartMarker]
    var centeredOnDay = false

    var body: some ChartContent {
        ForEach(markers) { marker in
            RuleMark(x: .value("Date", marker.plotDate(centeredOnDay: centeredOnDay)))
                .foregroundStyle(Color.secondary.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .overlay, alignment: .top, spacing: 0) {
                    Text(marker.emoji)
                        .font(.caption)
                }
        }
    }
}

// MARK: - Tap + VoiceOver

extension View {
    /// Apply to a `Chart` that draws `DayNoteMarks(markers:)`. A tap within
    /// `hitSlop` points of a marker's x position opens that marker's note.
    /// VoiceOver can't reach this -- pair it with
    /// `dayNoteMarkerAccessibilityActions` on the chart's accessibility
    /// element.
    func dayNoteMarkerTaps(
        _ markers: [DayNoteChartMarker],
        centeredOnDay: Bool = false,
        hitSlop: CGFloat = 22,
        onSelect: ((DayNote) -> Void)?
    ) -> some View {
        self
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            guard let onSelect, !markers.isEmpty,
                                  let plotFrame = proxy.plotFrame else { return }
                            let plotOriginX = geometry[plotFrame].origin.x
                            let tappedX = location.x - plotOriginX
                            let nearest = markers
                                .compactMap { marker -> (marker: DayNoteChartMarker, distance: CGFloat)? in
                                    guard let x = proxy.position(forX: marker.plotDate(centeredOnDay: centeredOnDay)) else { return nil }
                                    return (marker, abs(x - tappedX))
                                }
                                .min { $0.distance < $1.distance }
                            if let nearest, nearest.distance <= hitSlop {
                                onSelect(nearest.marker.note)
                            }
                        }
                }
            }
    }

    /// One VoiceOver custom action per marker. Must be applied AFTER the
    /// chart's `.accessibilityElement(children: .ignore)`, or the actions
    /// land on the ignored child and are never offered.
    func dayNoteMarkerAccessibilityActions(
        _ markers: [DayNoteChartMarker],
        onSelect: ((DayNote) -> Void)?
    ) -> some View {
        accessibilityActions {
            if let onSelect {
                ForEach(markers) { marker in
                    Button("Show note: \(marker.accessibilityLabel)") {
                        onSelect(marker.note)
                    }
                }
            }
        }
    }
}

// MARK: - Reveal sheet

/// What tapping a marker shows: the day, its tags, and the note text.
/// Read-only -- notes are edited from that day's Today screen.
struct DayNoteRevealSheet: View {
    let note: DayNote

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if !note.tags.isEmpty {
                        DayNoteTagFlowLayout(spacing: Theme.Spacing.sm) {
                            ForEach(note.tags) { tag in
                                DayNoteTagChip(tag: tag, isSelected: true)
                            }
                        }
                    }

                    let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        Text("No note text for this day, just tags.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(trimmed)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        guard let date = NutritionDayBoundary.date(fromDayString: note.day) else { return note.day }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

#Preview("DayNoteRevealSheet") {
    DayNoteRevealSheet(note: DayNote(day: "2026-09-19", text: "Half marathon PB, pizza after.", tags: [.race, .celebration]))
}

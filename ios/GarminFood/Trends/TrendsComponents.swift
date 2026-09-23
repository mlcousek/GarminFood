// TrendsComponents.swift
//
// Small, composable chart views for the Trends screen (add-trends-and-
// insights) -- same idiom as `Weight/WeightComponents.swift`: nothing new
// invented visually, just `Theme` tokens and Swift Charts in the exact
// style `WeightChartView` already established (`.interpolationMethod
// (.catmullRom)`, a static `foregroundStyle` tint rather than a
// data-driven one, an accessibility label + value summarizing the trend
// for VoiceOver instead of forcing it to read every point).
//
// `MacroLineChartView` is one reusable chart parameterized by which macro
// to plot (`actual`/`goal` closures into `MacroTrendDay`) rather than four
// near-identical views -- config.yaml's "small, composable views... makes
// adding the next thing cheap" principle applies exactly as much to charts
// as to any other view.
//
// Both charts optionally draw day-note markers (add-day-notes) -- the
// shared marker content, tap handling and reveal sheet live in
// `DayNoteChartMarkers.swift`; each chart only filters the markers to its
// own date range and hands a tap back through `onSelectNote`.

import SwiftUI
import Charts
import FoodLogCore

// MARK: - Macro line chart

/// One macro's actual-vs-goal line over `days` -- a solid line for what was
/// actually logged, a dashed line for the day's goal. A day with `nil` for
/// either (see `MacroTrendDay`'s doc comment: "nothing logged", not zero)
/// is simply skipped for that series, so the line has a real gap rather
/// than dipping to 0.
struct MacroLineChartView: View {
    let title: String
    let unit: String
    let tint: Color
    let days: [MacroTrendDay]
    let actual: (MacroTrendDay) -> Double?
    let goal: (MacroTrendDay) -> Double?
    /// add-day-notes: every tagged day's marker; only those inside `days`'
    /// range are drawn.
    var noteMarkers: [DayNoteChartMarker] = []
    var onSelectNote: ((DayNote) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(.sectionHeader)
                .foregroundStyle(.secondary)
            Chart {
                ForEach(days) { day in
                    if let value = actual(day) {
                        LineMark(
                            x: .value("Date", day.date),
                            y: .value(title, value)
                        )
                        .foregroundStyle(tint)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Date", day.date),
                            y: .value(title, value)
                        )
                        .foregroundStyle(tint)
                        .symbolSize(14)
                    }
                }
                ForEach(days) { day in
                    if let goalValue = goal(day) {
                        LineMark(
                            x: .value("Date", day.date),
                            y: .value("\(title) goal", goalValue)
                        )
                        .foregroundStyle(tint.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                DayNoteMarks(markers: visibleNoteMarkers)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4))
            }
            .dayNoteMarkerTaps(visibleNoteMarkers, onSelect: onSelectNote)
            .frame(height: 140)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) trend")
            .accessibilityValue(accessibilitySummary)
            .dayNoteMarkerAccessibilityActions(visibleNoteMarkers, onSelect: onSelectNote)
        }
    }

    private var visibleNoteMarkers: [DayNoteChartMarker] {
        DayNoteChartMarker.visible(noteMarkers, from: days.first?.date, to: days.last?.date)
    }

    private var accessibilitySummary: String {
        let values = days.compactMap(actual)
        guard let first = values.first, let last = values.last else {
            return "No \(title.lowercased()) logged in this range"
        }
        return "From \(first.wholeNumberText) to \(last.wholeNumberText) \(unit) over \(values.count) days logged"
    }
}

// MARK: - Hydration trend chart

/// One day's water total, for the Trends screen's hydration bar chart --
/// deliberately a separate small type from `HydrationEntry` (an individual
/// drink): this is already a day-total, pre-computed via
/// `HydrationHistory.total(for:on:calendar:)`, the same pure helper
/// `HydrationLoader.todayTotalML` uses for "today" specifically.
struct HydrationTrendPoint: Identifiable {
    let date: Date
    let totalML: Double
    var id: Date { date }
}

/// A bar per day against a dashed goal line -- bars that reached the goal
/// read as the same "hydrated" blue (`Theme.carbs`, matching
/// `HydrationHeroCard`'s own progress-ring tint) at full opacity; days that
/// fell short are the same hue dimmed, so "did I hit my goal" reads at a
/// glance without a second color needing its own legend.
struct HydrationTrendChartView: View {
    let points: [HydrationTrendPoint]
    let goalML: Double
    /// add-day-notes -- same as `MacroLineChartView`'s.
    var noteMarkers: [DayNoteChartMarker] = []
    var onSelectNote: ((DayNote) -> Void)?

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Water", point.totalML)
                )
                .foregroundStyle(point.totalML >= goalML && goalML > 0 ? Theme.carbs : Theme.carbs.opacity(0.4))
            }
            if goalML > 0 {
                RuleMark(y: .value("Goal", goalML))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            }
            // Bars are plotted with `unit: .day`, so markers centre on the day.
            DayNoteMarks(markers: visibleNoteMarkers, centeredOnDay: true)
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4))
        }
        .dayNoteMarkerTaps(visibleNoteMarkers, centeredOnDay: true, onSelect: onSelectNote)
        .frame(height: 140)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water trend")
        .accessibilityValue(accessibilitySummary)
        .dayNoteMarkerAccessibilityActions(visibleNoteMarkers, onSelect: onSelectNote)
    }

    private var visibleNoteMarkers: [DayNoteChartMarker] {
        DayNoteChartMarker.visible(noteMarkers, from: points.first?.date, to: points.last?.date)
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "No data" }
        let metCount = points.filter { $0.totalML >= goalML && goalML > 0 }.count
        return "From \(first.totalML.wholeNumberText) to \(last.totalML.wholeNumberText) milliliters over \(points.count) days, goal met on \(metCount) of them"
    }
}

#Preview("MacroLineChartView") {
    let days = (0..<14).map { offset -> MacroTrendDay in
        let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date())!
        return MacroTrendDay(
            date: date,
            calories: Double.random(in: 1800...2600),
            proteinG: Double.random(in: 80...140),
            carbsG: Double.random(in: 200...350),
            fatG: Double.random(in: 50...90),
            calorieGoal: 2300,
            proteinGoalG: 115,
            carbsGoalG: 316,
            fatGoalG: 64
        )
    }.reversed()
    MacroLineChartView(title: "Calories", unit: "kcal", tint: Theme.accent, days: Array(days), actual: { $0.calories }, goal: { $0.calorieGoal })
        .card()
        .padding()
}

#Preview("HydrationTrendChartView") {
    let points = (0..<14).map { offset -> HydrationTrendPoint in
        HydrationTrendPoint(date: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!, totalML: Double.random(in: 800...2400))
    }.reversed()
    HydrationTrendChartView(points: Array(points), goalML: 2000)
        .card()
        .padding()
}

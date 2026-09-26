// FastingHistoryView.swift
//
// The fasting detail screen, reached by tapping the home card
// (redesign-fasting-schedule 2.3): the kept-days streak, and the last 30
// days' fasts, each marked kept or broken (with when it was broken). It
// replaces the old `FastingView`, whose Start / Break Fast / End buttons
// and protocol picker are gone -- there is nothing to start or stop any
// more, the window runs daily from Settings.
//
// Every verdict is computed, not stored: `FastingDayEvaluator.history`
// judges each day's window against the moments food was logged. Those
// moments come only from what's already on the device -- the usage history
// (every food logged in this app, `UsageHistoryStore`) plus any Garmin day
// logs `DayLogLoader` happens to have cached (which also catches foods
// logged in the official Garmin Connect app, for those days) -- never a
// 30-day network fetch (config.yaml: the UI never waits on Garmin). When
// that data can't vouch for a day (fasting was off, or the usage history
// has trimmed that far back) the day shows as "Not tracked" rather than a
// guessed "kept", and the streak stops there.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct FastingHistoryView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Eating moments gathered once per appearance (see header); the
    /// verdicts themselves are recomputed every minute from these.
    @State private var logMoments: [Date] = []
    @State private var coverageStart: Date?
    @State private var hasLoaded = false

    private static let dayCount = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let schedule = environment.preferences.activeFastingSchedule {
                    TimelineView(.everyMinute) { context in
                        content(schedule: schedule, now: context.date)
                    }
                } else {
                    EmptyStateView(
                        systemImage: "moon.zzz",
                        title: "Fasting is off",
                        message: "Turn on a daily fasting window to see which days you kept."
                    )
                    .card()
                }

                NavigationLink {
                    FastingScheduleSettingsView()
                } label: {
                    HStack {
                        Label("Fasting schedule", systemImage: "clock")
                        Spacer()
                        if let schedule = environment.preferences.fastingSchedule, environment.preferences.fastingEnabled {
                            Text(Self.windowText(schedule))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Fasting")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadLogMoments() }
        .refreshable { await loadLogMoments() }
    }

    @ViewBuilder
    private func content(schedule: FastingSchedule, now: Date) -> some View {
        let days = FastingDayEvaluator.history(
            schedule: schedule,
            days: Self.dayCount,
            logTimestamps: logMoments,
            trackedSince: trackedSince,
            now: now,
            calendar: .current
        )
        let streak = FastingDayEvaluator.keptStreak(days: days)
        let keptCount = days.filter { $0.result == .kept }.count
        let judgedCount = days.filter { $0.result == .kept || Self.isBroken($0.result) }.count

        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                // Count-independent label (the number is the tile's value),
                // so no `== 1 ?` singular switch that Czech can't follow.
                StatTile(value: "\(streak)", label: String(localized: "Days kept in a row"), systemImage: "flame.fill", tint: Theme.ember)
                StatTile(value: "\(keptCount)/\(judgedCount)", label: String(localized: "Kept, last \(Self.dayCount) days", comment: "Fasting stat tile label; %lld = days in the window (30). Plural."), systemImage: "checkmark.seal.fill", tint: Theme.success)
            }

            FastingHomeCard(schedule: schedule, now: now, showsChevron: false, onTap: {})
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Last \(Self.dayCount) days", comment: "Fasting history section header; %lld = days shown (30). Plural."))
                if hasLoaded {
                    VStack(spacing: 0) {
                        ForEach(days) { day in
                            FastingDayRow(day: day)
                            if day.id != days.last?.id {
                                Divider()
                            }
                        }
                    }
                    .card()
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .card()
                }
                Text("Judged from the times foods were logged in GarminFood (and in Garmin Connect, for days you've opened here). A fast is broken by the first food logged inside it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Tracking starts at the later of "fasting switched on" and "the
    /// usage history is complete from here".
    private var trackedSince: Date? {
        switch (environment.preferences.fastingTrackedSince, coverageStart) {
        case let (since?, coverage?): return max(since, coverage)
        case let (since?, nil): return since
        case let (nil, coverage?): return coverage
        case (nil, nil): return nil
        }
    }

    private func loadLogMoments() async {
        let calendar = Calendar.current
        let events = await environment.usageHistory.all()
        var moments = FastingLogMoments.moments(from: events, calendar: calendar)
        for (date, log) in environment.dayLog.cachedFoodLogs {
            moments.append(contentsOf: FastingLogMoments.moments(fromGarminLog: log, date: date, calendar: calendar))
        }
        logMoments = moments
        coverageStart = FastingLogMoments.coverageStart(events: events)
        hasLoaded = true
    }

    private static func isBroken(_ result: FastingDayResult) -> Bool {
        if case .broken = result { return true }
        return false
    }

    private static func windowText(_ schedule: FastingSchedule) -> String {
        let start = FastingFormat.clock(FastingFormat.date(minuteOfDay: schedule.startMinute))
        let end = FastingFormat.clock(FastingFormat.date(minuteOfDay: schedule.endMinute))
        return "\(start) – \(end)"
    }
}

// MARK: - Day row

struct FastingDayRow: View {
    let day: FastingDay

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "\(FastingFormat.clock(day.window.start)) – \(FastingFormat.clock(day.window.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch day.result {
        case .kept: return String(localized: "Kept", comment: "Fasting history row: the fast was kept that day.")
        case .broken(let at): return String(localized: "Broken at \(FastingFormat.clock(at))", comment: "Fasting history row: the fast was broken; %@ = clock time of the first food logged inside the window.")
        case .inProgress: return String(localized: "In progress", comment: "Fasting history row: today's window is still running.")
        case .upcoming: return String(localized: "Upcoming", comment: "Fasting history row / streak dot: a day or window that hasn't started yet.")
        case .notTracked: return String(localized: "Not tracked", comment: "Fasting history row: no data to judge that day (fasting off or history trimmed).")
        }
    }

    private var symbol: String {
        switch day.result {
        case .kept: return "checkmark.circle.fill"
        case .broken: return "xmark.circle.fill"
        case .inProgress: return "hourglass"
        case .upcoming: return "clock"
        case .notTracked: return "minus.circle"
        }
    }

    private var tint: Color {
        switch day.result {
        case .kept: return Theme.success
        case .broken: return Theme.warning
        case .inProgress, .upcoming: return Theme.accent
        case .notTracked: return .secondary
        }
    }
}

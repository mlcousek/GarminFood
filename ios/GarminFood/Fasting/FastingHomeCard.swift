// FastingHomeCard.swift
//
// The always-on fasting card on the Today screen (redesign-fasting-schedule
// 2.2). Replaces the old `FastingTodayCard`, which only appeared while a
// manually started fast was running: now the window is a daily schedule,
// so whenever fasting is enabled the card is simply there, saying which
// phase you're in right now --
//   fasting: "Fasting · 11 h 20 m in · eating opens at 12:00"
//   eating:  "Eating window · closes at 20:00 (3 h 10 m)"
// -- with a small progress ring through the current phase. Tapping it opens
// `FastingHistoryView`.
//
// Driven by `TimelineView(.everyMinute)` (a 60-second periodic schedule
// aligned to the minute, so "11 h 20 m" flips exactly when the clock does),
// with the phase derived fresh from `FastingSchedule.phase(at:)` on every
// tick -- no timers or cached phase in state, so it can't drift or go
// stale while the app sits in the background.
//
// Its own file so TodayView only gains a one-line `FastingHomeSection`
// (TodayView is edited by several concurrent changes). Reuses
// `ProgressRing`/`SectionHeader`/`card()` and the `ProgressStrip`-style
// "whole card is one tap target" shape rather than a bespoke style.

import SwiftUI
import FoodLogCore

/// The "Fasting" header + card, or nothing at all while fasting is off.
@MainActor
struct FastingHomeSection: View {
    @Environment(AppEnvironment.self) private var environment
    let onOpen: () -> Void

    var body: some View {
        if let schedule = environment.preferences.activeFastingSchedule {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Fasting"))
                TimelineView(.everyMinute) { context in
                    FastingHomeCard(schedule: schedule, now: context.date, onTap: onOpen)
                }
            }
        }
    }
}

struct FastingHomeCard: View {
    let schedule: FastingSchedule
    let now: Date
    /// Off where the card is shown for information only (the history
    /// screen's own header), not as a way in.
    var showsChevron = true
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 44

    var body: some View {
        if let phase = schedule.phase(at: now, calendar: .current) {
            let isFasting = phase.kind == .fasting
            let tint = isFasting ? Theme.accent : Theme.success
            let title = isFasting ? String(localized: "Fasting") : String(localized: "Eating window")
            let detail = Self.detail(for: phase, now: now)

            Button(action: onTap) {
                HStack(spacing: Theme.Spacing.md) {
                    ProgressRing(fraction: phase.fraction(at: now), lineWidth: 5, tint: tint) {
                        Image(systemName: isFasting ? "moon.stars.fill" : "fork.knife")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                    }
                    .frame(width: ringSize, height: ringSize)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Spacing.xs)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .card(padding: Theme.Spacing.sm + 4)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(title). \(detail)"))
            .accessibilityHint(showsChevron ? Text("Opens your fasting history") : Text(verbatim: ""))
        }
    }

    static func detail(for phase: FastingPhase, now: Date) -> String {
        switch phase.kind {
        case .fasting:
            let elapsed = FastingFormat.duration(phase.elapsed(at: now))
            let opensAt = FastingFormat.clock(phase.scheduledEndAt)
            return String(localized: "\(elapsed) in · eating opens at \(opensAt)", comment: "Fasting card detail. First %@ = time fasted so far ('11 h 20 m'), second = clock time the eating window opens.")
        case .eating:
            let closesAt = FastingFormat.clock(phase.scheduledEndAt)
            let remaining = FastingFormat.duration(phase.remaining(at: now))
            return String(localized: "closes at \(closesAt) (\(remaining))", comment: "Eating-window card detail. First %@ = clock time it closes, second = time remaining ('2 h 5 m').")
        }
    }
}

#Preview("Fasting") {
    FastingHomeCard(schedule: .standard, now: Calendar.current.date(bySettingHour: 7, minute: 20, second: 0, of: Date()) ?? Date(), onTap: {})
        .padding()
}

#Preview("Eating") {
    FastingHomeCard(schedule: .standard, now: Calendar.current.date(bySettingHour: 16, minute: 50, second: 0, of: Date()) ?? Date(), onTap: {})
        .padding()
}

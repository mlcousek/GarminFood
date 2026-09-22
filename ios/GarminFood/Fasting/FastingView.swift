// FastingView.swift
//
// The Fasting tab content (owner request 2026-09-22, following a
// competitive read that found Yazio's fasting timer to be its signature
// differentiator): a live ring for whichever phase the active session is
// in, the start/break/end action for that phase, and a history list below.
// Reuses `ProgressRing`/`PrimaryButton`/`EmptyStateView`/`card()` as-is
// (design-system principle, config.yaml) rather than drawing a second ring
// or button style just for this screen. `TimelineView(.periodic(from:by:))`
// drives the live countdown -- no manual `Timer`, and it composes cleanly
// with `ProgressRing`'s own Reduce-Motion-aware animation (the ring's
// `fraction` just changes value on each tick; the ring decides how to
// animate that, same as everywhere else it's used).
//
// All the actual state lives in `AppEnvironment.fastingStore` /
// `AppEnvironment.startFasting`/`breakFast`/`endFastingSession`/
// `cancelActiveFast` -- this view only loads a local snapshot to render
// (same `.task`/`@State` pattern `TodayView` uses for `mealPresets`/
// `quickPickItems`) and re-loads after every action, since the store itself
// has no observable/publisher of its own (it's a plain actor, matching
// every other FoodLogCore store).

import SwiftUI
import FoodLogCore

@MainActor
struct FastingView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var activeSession: FastingSession?
    @State private var history: [FastingSession] = []
    @State private var showingProtocolPicker = false
    @State private var isBusy = false
    @State private var actionError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    FastingPhaseCard(
                        session: activeSession,
                        now: context.date,
                        isBusy: isBusy,
                        onStart: { showingProtocolPicker = true },
                        onBreakFast: { perform { try await environment.breakFast() } },
                        onEndEating: { perform { try await environment.endFastingSession() } },
                        onCancel: { perform { try await environment.cancelActiveFast() } }
                    )
                }

                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionHeader(
                            title: "History",
                            trailing: FastingStats.currentRun(history: history) > 0
                                ? "\(FastingStats.currentRun(history: history)) in a row"
                                : nil
                        )
                        VStack(spacing: 0) {
                            ForEach(history) { session in
                                FastingHistoryRow(session: session)
                                if session.id != history.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .card()
                    }
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.groupedBackground)
        .navigationTitle("Fasting")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .refreshable { await refresh() }
        .sheet(isPresented: $showingProtocolPicker) {
            FastingProtocolPickerView { chosen in
                perform { try await environment.startFasting(protocolKind: chosen) }
            }
        }
        .alert(
            "Couldn't update fast",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func refresh() async {
        activeSession = await environment.fastingStore.active()
        history = await environment.fastingStore.history()
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await action()
                Haptics.success()
                await refresh()
            } catch {
                actionError = error.localizedDescription
                Haptics.warning()
            }
        }
    }
}

// MARK: - Phase card

struct FastingPhaseCard: View {
    let session: FastingSession?
    let now: Date
    let isBusy: Bool
    let onStart: () -> Void
    let onBreakFast: () -> Void
    let onEndEating: () -> Void
    let onCancel: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 220

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if let session {
                let phase = session.currentPhase(at: now)
                let tint = phase.kind == .fasting ? Theme.accent : Theme.success

                ProgressRing(fraction: phase.fraction(at: now), lineWidth: 14, tint: tint) {
                    VStack(spacing: 4) {
                        Text(phase.kind == .fasting ? "Fasting" : "Eating")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(Self.clock(phase.isOverdue(at: now) ? phase.elapsed(at: now) - phase.duration : phase.remaining(at: now)))
                            .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(phase.isOverdue(at: now) ? "over target" : "remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(Theme.Spacing.sm)
                }
                .frame(width: ringSize, height: ringSize)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(phase.kind == .fasting ? "Fasting" : "Eating") phase")
                .accessibilityValue(accessibilityValue(phase: phase))

                Text(session.protocolKind.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if phase.kind == .fasting {
                    PrimaryButton(title: "Break Fast", isDisabled: isBusy, action: onBreakFast)
                } else {
                    PrimaryButton(title: "End Eating Window", isDisabled: isBusy, action: onEndEating)
                }
                Button("Cancel fast", role: .destructive, action: onCancel)
                    .font(.footnote)
                    .disabled(isBusy)
            } else {
                EmptyStateView(
                    systemImage: "timer",
                    title: "No active fast",
                    message: "Start a fast to track your fasting and eating windows."
                )
                PrimaryButton(title: "Start Fasting", isDisabled: isBusy, action: onStart)
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func accessibilityValue(phase: FastingPhase) -> String {
        let seconds = phase.isOverdue(at: now) ? phase.elapsed(at: now) - phase.duration : phase.remaining(at: now)
        let minutes = max(0, Int(seconds / 60))
        let suffix = phase.isOverdue(at: now) ? "over target" : "remaining"
        return "\(minutes) minutes \(suffix)"
    }

    private static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }
}

// MARK: - History row

struct FastingHistoryRow: View {
    let session: FastingSession

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.protocolKind.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(session.startedAt.formatted(.dateTime.month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(durationText)
                    .font(.macroValue)
                statusLabel
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var durationText: String {
        guard let fastingEndedAt = session.fastingEndedAt else { return "In progress" }
        let hours = fastingEndedAt.timeIntervalSince(session.startedAt) / 3600
        return String(format: "%.1fh fasted", hours)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if session.metFastingTarget {
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.success)
        } else if session.fastingEndedAt != nil {
            Label("Broke early", systemImage: "exclamationmark.circle")
                .font(.caption2)
                .foregroundStyle(Theme.warning)
        }
    }
}

#Preview("No active fast") {
    NavigationStack {
        FastingPhaseCard(
            session: nil,
            now: Date(),
            isBusy: false,
            onStart: {},
            onBreakFast: {},
            onEndEating: {},
            onCancel: {}
        )
        .padding()
    }
}

#Preview("Fasting") {
    FastingPhaseCard(
        session: FastingSession(protocolKind: .sixteenEight, startedAt: Date().addingTimeInterval(-3600 * 4)),
        now: Date(),
        isBusy: false,
        onStart: {},
        onBreakFast: {},
        onEndEating: {},
        onCancel: {}
    )
    .padding()
}

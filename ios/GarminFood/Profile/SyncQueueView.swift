// SyncQueueView.swift
//
// profile-and-settings spec: every entry Garmin hasn't accepted, with its
// meal, date, state and last error, plus retry, delete and sync-now. This
// is the only place a `.failed` entry (one that has exhausted its retries)
// becomes actionable again.
//
// sync-weight-hydration-with-garmin: weigh-in adds/DELETES and drinks/
// corrections Garmin hasn't accepted are listed too, in their own section
// (spec: a failed weigh-in delete "is visible in the sync queue"). They can
// be retried here; a queued Garmin delete can also be cancelled (the
// weigh-in then stays in Garmin). Removing an add or a drink is done from
// the Weight/Water screens, which keep their local records consistent.
//
// add-log-entry-editing: an edit whose corrected entry is already in Garmin
// but whose old entry isn't removed yet (`.createdAwaitingDelete`) is listed
// here too, so the temporary duplicate is never silent -- and, once parked
// (the delete gave up), offered a retry that only re-attempts the delete.

import SwiftUI
import GarminKit

@MainActor
struct SyncQueueView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var pendingDelete: OutboxEntry?
    @State private var isSyncing = false
    @State private var actionError: String?

    var body: some View {
        let entries = environment.undeliveredEntries.sorted { $0.createdAt > $1.createdAt }
        let weightEntries = environment.undeliveredWeightEntries
        let hydrationEntries = environment.undeliveredHydrationEntries
        let isEmpty = entries.isEmpty && weightEntries.isEmpty && hydrationEntries.isEmpty

        List {
            if !weightEntries.isEmpty || !hydrationEntries.isEmpty {
                Section("Weight & water") {
                    ForEach(weightEntries) { entry in
                        WeightQueueRow(entry: entry) {
                            Task {
                                do {
                                    try await environment.retryWeightQueued(id: entry.id)
                                } catch {
                                    actionError = "Couldn't retry this entry: \(error.localizedDescription)"
                                }
                            }
                        } onCancelDelete: {
                            Task {
                                do {
                                    try await environment.cancelWeightDelete(entry)
                                } catch {
                                    actionError = "Couldn't cancel this delete: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                    ForEach(hydrationEntries) { entry in
                        HydrationQueueRow(entry: entry) {
                            Task {
                                do {
                                    try await environment.retryHydrationQueued(id: entry.id)
                                } catch {
                                    actionError = "Couldn't retry this entry: \(error.localizedDescription)"
                                }
                            }
                        }
                    }
                }
            }

            if isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "All synced",
                        message: "Every logged entry has reached Garmin."
                    )
                }
            } else if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        QueueEntryRow(entry: entry) {
                            Task {
                                do {
                                    try await environment.retryQueued(id: entry.id)
                                } catch {
                                    actionError = "Couldn't retry this entry: \(error.localizedDescription)"
                                }
                            }
                        } onDelete: {
                            pendingDelete = entry
                        }
                    }
                } footer: {
                    Text("Entries here are still saved on this phone and will keep retrying, or you can retry or delete them.")
                }
            }
        }
        .navigationTitle("Sync queue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isSyncing = true
                    Task {
                        await environment.drainAndReconcile()
                        isSyncing = false
                    }
                } label: {
                    if isSyncing {
                        ProgressView()
                    } else {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isSyncing || isEmpty)
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await environment.deleteQueued(entry)
                    } catch {
                        actionError = "Couldn't delete this entry: \(error.localizedDescription)"
                    }
                }
            }
        } message: { _ in
            Text("It hasn't reached Garmin yet, so nothing is removed there.")
        }
        .alert(
            "Couldn't complete that action",
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
}

private struct QueueEntryRow: View {
    let entry: OutboxEntry
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Label(entry.mealType.displayName, systemImage: entry.mealType.symbolName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            statusLine
            if let error = entry.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            if entry.state == .failed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusLine: some View {
        HStack(spacing: Theme.Spacing.xs) {
            switch entry.state {
            case .pending:
                Image(systemName: "clock")
                Text("Waiting to sync")
            case .sent:
                Image(systemName: "checkmark.circle")
                Text("Sent, confirming…")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Failed after \(entry.attemptCount) attempts")
            }
        }
        .font(.caption)
        .foregroundStyle(entry.state == .failed ? Theme.warning : .secondary)
    }
}

/// One queued weigh-in add or Garmin delete (sync-weight-hydration-with-
/// garmin). Retry when failed; a delete can also be cancelled.
private struct WeightQueueRow: View {
    let entry: WeightOutboxEntry
    let onRetry: () -> Void
    let onCancelDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Label(title, systemImage: entry.kind == .delete ? "trash" : "scalemass")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            QueueStatusLine(state: entry.state, attemptCount: entry.attemptCount)
            if let error = entry.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if entry.kind == .delete {
                Button(role: .destructive, action: onCancelDelete) {
                    Label("Keep in Garmin", systemImage: "arrow.uturn.backward")
                }
            }
            if entry.state == .failed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch entry.kind {
        case .add: return "Weigh-in \(entry.weightKg.formattedKg) kg"
        case .delete: return "Delete weigh-in \(entry.weightKg.formattedKg) kg"
        }
    }
}

/// One queued drink, or a negative correction for a removed drink.
private struct HydrationQueueRow: View {
    let entry: HydrationOutboxEntry
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Label(title, systemImage: "drop.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.loggedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            QueueStatusLine(state: entry.state, attemptCount: entry.attemptCount)
            if let error = entry.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if entry.state == .failed {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        entry.isCorrection
            ? "Remove \(abs(entry.valueInML).formattedML) ml of water"
            : "Water \(entry.valueInML.formattedML) ml"
    }
}

/// The waiting/failed line shared by the weight and water queue rows.
private struct QueueStatusLine: View {
    let state: OutboxEntryState
    let attemptCount: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            switch state {
            case .pending:
                Image(systemName: "clock")
                Text("Waiting to sync")
            case .sent:
                Image(systemName: "checkmark.circle")
                Text("Sent")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                Text("Failed after \(attemptCount) attempts")
            }
        }
        .font(.caption)
        .foregroundStyle(state == .failed ? Theme.warning : .secondary)
    }
}

// SyncQueueView.swift
//
// profile-and-settings spec: every entry Garmin hasn't accepted, with its
// meal, date, state and last error, plus retry, delete and sync-now. This
// is the only place a `.failed` entry (one that has exhausted its retries)
// becomes actionable again.

import SwiftUI
import GarminKit

@MainActor
struct SyncQueueView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var pendingDelete: OutboxEntry?
    @State private var isSyncing = false

    var body: some View {
        let entries = environment.undeliveredEntries.sorted { $0.createdAt > $1.createdAt }

        List {
            if entries.isEmpty {
                Section {
                    EmptyStateView(
                        systemImage: "checkmark.circle",
                        title: "All synced",
                        message: "Every logged entry has reached Garmin."
                    )
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        QueueEntryRow(entry: entry) {
                            Task { await environment.retryQueued(id: entry.id) }
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
                .disabled(isSyncing || entries.isEmpty)
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
                Task { await environment.deleteQueued(entry) }
            }
        } message: { _ in
            Text("It hasn't reached Garmin yet, so nothing is removed there.")
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

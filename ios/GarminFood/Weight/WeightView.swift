// WeightView.swift
//
// The whole weight-tracking screen (add-weight-tracking): current weight
// and goal progress up top, a trend chart once there's enough data, then
// the full history with per-row sync status, swipe-to-delete, and
// swipe-to-retry on a failed delivery -- same information architecture as
// `SyncQueueView` (list + per-row actions) plus `ProgressViews.swift`'s
// hero-card idiom.
//
// sync-weight-hydration-with-garmin: the history is Garmin's weigh-ins
// merged with the app's own not-yet-synced ones (`WeightLoader.rows`,
// design.md D1), so a scale or Garmin Connect weigh-in appears here, and
// deleting a Garmin weigh-in deletes it in Garmin too -- queued in the
// durable outbox, never a blocking call (D3). Appearing on screen reads
// Garmin (`refreshGarminHealth`), pull-to-refresh re-reads the full
// history; both render from the cache first.
//
// Reads `environment.weightLoader` rather than talking to any store
// directly -- keeps this file, like every other screen in `GarminFood/`,
// thin: no domain logic here beyond simple view-state.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct WeightView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isPresentingAdd = false
    @State private var pendingDelete: WeighInDisplayEntry?
    @State private var actionError: String?

    var body: some View {
        let loader = environment.weightLoader
        let rows = loader.rows

        List {
            Section {
                WeightHeroCard(
                    latest: loader.latest,
                    previous: loader.previous,
                    progress: loader.progress,
                    refreshFailed: loader.lastGarminRefreshFailed
                )
            }

            if rows.count >= 2 {
                Section("Trend") {
                    WeightChartView(rows: chartRows(rows), targetKg: loader.goal?.targetKg)
                        .frame(height: 180)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }

            Section {
                if rows.isEmpty {
                    EmptyStateView(
                        systemImage: "scalemass",
                        title: "No weigh-ins yet",
                        message: "Tap + to log your weight. It's saved on this phone right away and synced to Garmin in the background. Weigh-ins from a Garmin scale or Garmin Connect show up here too."
                    )
                } else {
                    ForEach(rows) { row in
                        WeightRow(
                            row: row,
                            onDelete: { pendingDelete = row },
                            onRetry: { Task { await retry(row) } }
                        )
                    }
                }
            } header: {
                Text("History")
            } footer: {
                if !rows.isEmpty {
                    Text("Your Garmin weigh-ins, plus any logged here that haven't synced yet. Deleting one here deletes it in Garmin too.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add weight")
            }
        }
        .task { await environment.refreshGarminHealth() }
        .refreshable {
            await environment.drainAndReconcile()
            await environment.refreshGarminHealth(force: true)
        }
        .sheet(isPresented: $isPresentingAdd) {
            NavigationStack {
                AddWeightSheet()
            }
        }
        .confirmationDialog(
            "Delete this weigh-in?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { row in
            Button("Delete", role: .destructive) {
                Task { await delete(row) }
            }
        } message: { row in
            Text(deleteMessage(for: row))
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

    /// The last 90 rows, oldest first, for the chart.
    private func chartRows(_ rows: [WeighInDisplayEntry]) -> [WeighInDisplayEntry] {
        Array(rows.prefix(90).reversed())
    }

    private func deleteMessage(for row: WeighInDisplayEntry) -> String {
        if row.isFromGarmin {
            return "Deletes it from Garmin Connect too. If you're offline, it's deleted there once you're back online."
        }
        switch row.syncState {
        case .pending, .failed:
            return "It hasn't reached Garmin yet, so it simply won't be sent."
        case .synced, .deleteFailed:
            return "Deletes it from Garmin Connect too. If you're offline, it's deleted there once you're back online."
        }
    }

    private func delete(_ row: WeighInDisplayEntry) async {
        do {
            try await environment.deleteWeighIn(row)
        } catch {
            actionError = "Couldn't delete this entry."
        }
    }

    private func retry(_ row: WeighInDisplayEntry) async {
        guard let outboxEntryId = row.outboxEntryId else { return }
        do {
            try await environment.retryWeightQueued(id: outboxEntryId)
        } catch {
            actionError = "Couldn't retry this entry."
        }
    }
}

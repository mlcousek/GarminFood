// WeightView.swift
//
// The whole weight-tracking screen (add-weight-tracking): current weight up
// top, a trend chart once there's enough data, then the full history with
// per-row sync status, swipe-to-delete, and swipe-to-retry on a failed
// delivery -- same information architecture as `SyncQueueView` (list +
// per-row actions) plus `ProgressViews.swift`'s hero-card idiom, since this
// screen is reached from the Progress tab (see WeightSummaryCard there).
//
// Reads `environment.weightLoader` (a plain in-memory snapshot of
// `WeightStore`/`WeightOutbox`, refreshed on `.task`/`.refreshable` and
// after every add/delete) rather than talking to either store directly --
// keeps this file, like every other screen in `GarminFood/`, thin: no
// domain logic here beyond simple view-state.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct WeightView: View {
    @Environment(AppEnvironment.self) private var environment

    @State private var isPresentingAdd = false
    @State private var pendingDelete: WeightEntry?
    @State private var actionError: String?

    var body: some View {
        let loader = environment.weightLoader
        let entries = loader.entries

        List {
            Section {
                WeightHeroCard(latest: loader.latest, previous: loader.previous)
            }

            if entries.count >= 2 {
                Section("Trend") {
                    WeightChartView(entries: Array(entries.prefix(90).reversed()))
                        .frame(height: 180)
                        .padding(.vertical, Theme.Spacing.xs)
                }
            }

            Section {
                if entries.isEmpty {
                    EmptyStateView(
                        systemImage: "scalemass",
                        title: "No weigh-ins yet",
                        message: "Tap + to log your weight. It's saved on this phone right away and synced to Garmin in the background."
                    )
                } else {
                    ForEach(entries) { entry in
                        WeightRow(
                            entry: entry,
                            syncState: loader.outboxState(for: entry),
                            onDelete: { pendingDelete = entry },
                            onRetry: { Task { await retry(entry) } }
                        )
                    }
                }
            } header: {
                Text("History")
            } footer: {
                if !entries.isEmpty {
                    Text("Synced to your Garmin account automatically. A failed entry keeps retrying, or you can retry it directly.")
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
        .task { await loader.refresh() }
        .refreshable { await environment.drainAndReconcile() }
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
        ) { entry in
            Button("Delete", role: .destructive) {
                Task { await delete(entry) }
            }
        } message: { _ in
            Text("Removes it from this phone. If it already reached Garmin, it stays there.")
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

    private func delete(_ entry: WeightEntry) async {
        do {
            try await environment.deleteWeight(entry)
        } catch {
            actionError = "Couldn't delete this entry."
        }
    }

    private func retry(_ entry: WeightEntry) async {
        guard let outboxEntryId = entry.outboxEntryId else { return }
        do {
            try await environment.weightOutbox.retry(id: outboxEntryId)
            await environment.drainAndReconcile()
        } catch {
            actionError = "Couldn't retry this entry."
        }
    }
}

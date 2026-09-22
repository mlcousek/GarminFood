// HydrationView.swift
//
// The whole hydration-tracking screen (add-hydration-tracking): today's
// total against a local goal up top, one-tap quick-add for the amounts
// people actually reach for, then the full history with per-row sync
// status, swipe-to-delete, and swipe-to-retry on a failed delivery -- same
// information architecture as WeightView.swift, reached the same way (see
// HydrationSummaryCard on the Progress tab).
//
// Reads `environment.hydrationLoader` (a plain in-memory snapshot of
// `HydrationStore`/`HydrationOutbox`, refreshed on `.task`/`.refreshable`
// and after every add/delete) rather than talking to either store directly
// -- same reasoning as WeightView.swift's own header.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct HydrationView: View {
    @Environment(AppEnvironment.self) private var environment

    /// Purely local -- Garmin's hydration goal isn't readable from this
    /// app (HydrationComponents.swift's header covers why), so this is a
    /// per-device preference, not synced state.
    @AppStorage("hydrationDailyGoalML") private var dailyGoalML: Double = 2000

    @State private var isPresentingAdd = false
    @State private var isPresentingGoalEditor = false
    @State private var goalText = ""
    @State private var pendingDelete: HydrationEntry?
    @State private var actionError: String?

    var body: some View {
        let loader = environment.hydrationLoader
        let entries = loader.entries

        List {
            Section {
                HydrationHeroCard(todayTotalML: loader.todayTotalML, goalML: dailyGoalML)
            }

            Section("Quick add") {
                HydrationQuickAddRow(
                    onAdd: { amount in Task { await quickAdd(amount) } },
                    onCustom: { isPresentingAdd = true }
                )
            }

            Section {
                if entries.isEmpty {
                    EmptyStateView(
                        systemImage: "drop",
                        title: "No water logged yet",
                        message: "Tap an amount above to log a drink. It's saved on this phone right away and synced to Garmin in the background."
                    )
                } else {
                    ForEach(entries) { entry in
                        HydrationRow(
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
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        goalText = String(Int(dailyGoalML))
                        isPresentingGoalEditor = true
                    } label: {
                        Label("Edit goal", systemImage: "target")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Hydration options")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add water")
            }
        }
        .task { await loader.refresh() }
        .refreshable { await environment.drainAndReconcile() }
        .sheet(isPresented: $isPresentingAdd) {
            NavigationStack {
                AddHydrationSheet()
            }
        }
        .alert("Daily goal", isPresented: $isPresentingGoalEditor) {
            TextField("Milliliters", text: $goalText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let value = Double(goalText), value > 0 {
                    dailyGoalML = value
                }
            }
        } message: {
            Text("How much water you're aiming for each day.")
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

    private func quickAdd(_ amount: Double) async {
        do {
            _ = try await environment.hydrationLogCoordinator.logHydration(valueInML: amount)
            await environment.hydrationLogged()
        } catch {
            actionError = "Couldn't save this entry."
        }
    }

    private func delete(_ entry: HydrationEntry) async {
        do {
            try await environment.deleteHydration(entry)
        } catch {
            actionError = "Couldn't delete this entry."
        }
    }

    private func retry(_ entry: HydrationEntry) async {
        guard let outboxEntryId = entry.outboxEntryId else { return }
        do {
            try await environment.hydrationOutbox.retry(id: outboxEntryId)
            await environment.drainAndReconcile()
        } catch {
            actionError = "Couldn't retry this entry."
        }
    }
}

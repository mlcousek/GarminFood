// HydrationView.swift
//
// The whole hydration-tracking screen (add-hydration-tracking): today's
// total against the goal up top, one-tap quick-add for the amounts people
// actually reach for, then the drinks logged in this app with per-row sync
// status, swipe-to-remove, and swipe-to-retry on a failed delivery -- same
// information architecture as WeightView.swift.
//
// sync-weight-hydration-with-garmin (design.md D4/D5): the total is
// Garmin's day total plus drinks not delivered yet, so water logged on the
// watch or in Garmin Connect counts; the goal is Garmin's unless overridden
// (here via "Edit goal", or Settings -> Goals). Garmin has no per-drink
// list, so the history shows only drinks logged here. Removing a drink that
// already reached Garmin queues a negative correction so Garmin's total
// drops too; removing an undelivered one just cancels it.
//
// Reads `environment.hydrationLoader` rather than talking to any store
// directly -- same reasoning as WeightView.swift's own header.

import SwiftUI
import FoodLogCore
import GarminKit

@MainActor
struct HydrationView: View {
    @Environment(AppEnvironment.self) private var environment

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
                HydrationHeroCard(
                    todayTotalML: loader.todayTotalML,
                    goalML: loader.goalML,
                    refreshFailed: loader.lastGarminRefreshFailed
                )
            } footer: {
                if loader.hasGarminTotalToday {
                    Text("Today's total comes from Garmin, so water logged on your watch or in Garmin Connect counts too.")
                }
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
                        title: "No water logged in this app yet",
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
                Text("Logged in this app")
            } footer: {
                if !entries.isEmpty {
                    Text("Synced to your Garmin account automatically. Removing a drink lowers Garmin's total too.")
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
                        goalText = String(Int(loader.goalML.rounded()))
                        isPresentingGoalEditor = true
                    } label: {
                        Label("Edit goal", systemImage: "target")
                    }
                    if environment.preferences.waterGoalOverrideML != nil {
                        Button {
                            environment.preferences.waterGoalOverrideML = nil
                        } label: {
                            Label("Use Garmin's goal", systemImage: "arrow.uturn.backward")
                        }
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
        .task { await environment.refreshGarminHealth() }
        .refreshable {
            await environment.drainAndReconcile()
            await environment.refreshGarminHealth(force: true)
        }
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
                if let value = DecimalInput.parse(goalText), value > 0 {
                    environment.preferences.waterGoalOverrideML = value
                }
            }
        } message: {
            Text("How much water you're aiming for each day. Stays on this phone; Garmin's own goal is unchanged.")
        }
        .confirmationDialog(
            "Remove this drink?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { entry in
            Button("Remove", role: .destructive) {
                Task { await remove(entry) }
            }
        } message: { entry in
            Text(removeMessage(for: entry))
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

    private func removeMessage(for entry: HydrationEntry) -> String {
        switch environment.hydrationLoader.outboxState(for: entry) {
        case .pending?, .failed?:
            return "It hasn't reached Garmin yet, so it simply won't be sent."
        // `.createdAwaitingDelete` is food-outbox-only (add-log-entry-editing).
        case .sent?, .createdAwaitingDelete?, nil:
            return "Garmin's total for that day is lowered by \(entry.valueInML.formattedML) ml too."
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

    private func remove(_ entry: HydrationEntry) async {
        do {
            try await environment.removeHydration(entry)
        } catch {
            actionError = "Couldn't remove this drink."
        }
    }

    private func retry(_ entry: HydrationEntry) async {
        guard let outboxEntryId = entry.outboxEntryId else { return }
        do {
            try await environment.retryHydrationQueued(id: outboxEntryId)
        } catch {
            actionError = "Couldn't retry this entry."
        }
    }
}

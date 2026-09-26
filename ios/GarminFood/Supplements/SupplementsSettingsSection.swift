// SupplementsSettingsSection.swift
//
// add-supplements D10, task 3.1: the Settings row "Supplements" / "Doplňky
// stravy" -- a toggle with a short explainer, off by default. Turning it on
// for the first time (no products yet) opens a two-step onboarding: pick
// products from the catalog (each added with its suggested slot, editable
// later), then the reminder times. Turning it off hides the screen, card and
// row and cancels the reminders (the scheduler's diff removes them), but
// keeps every product and tick; earned badges stay.
//
// Depends on: AppEnvironment (preferences, supplements, syncNotifications),
// SupplementReminderTimesSection, SupplementsView. Depended on by:
// SettingsView.

import SwiftUI
import FoodLogCore

@MainActor
struct SupplementsSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isOnboarding = false

    var body: some View {
        let preferences = environment.preferences
        Section {
            Toggle(isOn: Binding(
                get: { preferences.supplementsEnabled },
                set: { isOn in
                    preferences.supplementsEnabled = isOn
                    Task {
                        await environment.supplements.reload()
                        if isOn && environment.supplements.plan.products.isEmpty {
                            isOnboarding = true
                        }
                        await environment.syncNotifications()
                    }
                }
            )) {
                Label("Supplements", systemImage: "pills")
            }
            if preferences.supplementsEnabled {
                NavigationLink {
                    SupplementsView()
                } label: {
                    Text("Open supplements")
                }
            }
        } footer: {
            Text("Track your supplement stack: a daily checklist, reminders, totals against upper limits, and stock. Stays on this phone. Turning it off keeps your data.", comment: "Settings: explainer under the Supplements toggle.")
        }
        .sheet(isPresented: $isOnboarding) {
            NavigationStack {
                SupplementsOnboardingView { isOnboarding = false }
            }
        }
    }
}

/// First enable: pick products from the catalog, then reminder times.
@MainActor
struct SupplementsOnboardingView: View {
    @Environment(AppEnvironment.self) private var environment
    let onDone: () -> Void
    @State private var picked: Set<String> = []
    @State private var step = 0

    var body: some View {
        Group {
            if step == 0 {
                List {
                    Section {
                        ForEach(SupplementCatalog.all) { product in
                            let isOn = picked.contains(product.id)
                            Button {
                                if isOn { picked.remove(product.id) } else { picked.insert(product.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: product.name)
                                            .foregroundStyle(.primary)
                                        Text(verbatim: product.suggestedSlot.displayName + " · " + product.servingDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? Theme.accent : Color.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    } header: {
                        Text("What do you take?")
                    } footer: {
                        Text("You can change amounts and times, or add your own products, later in My stack.", comment: "Supplements onboarding: under the catalog list.")
                    }
                }
                .navigationTitle("Supplements")
            } else {
                Form {
                    SupplementReminderTimesSection()
                }
                .navigationTitle("Reminders")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { onDone() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if step == 0 {
                    Button("Next") {
                        Task {
                            await addPicked()
                            step = 1
                            await NotificationScheduler.shared.requestAuthorizationIfNeeded()
                        }
                    }
                } else {
                    Button("Done") {
                        Task { await environment.syncNotifications() }
                        onDone()
                    }
                }
            }
        }
    }

    private func addPicked() async {
        let supplements = environment.supplements
        for product in SupplementCatalog.all where picked.contains(product.id) {
            await supplements.save(product.makeProduct(), schedule: product.suggestedSchedule, updateSchedule: true)
        }
    }
}

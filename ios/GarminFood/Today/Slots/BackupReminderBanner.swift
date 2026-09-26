// BackupReminderBanner.swift
//
// add-data-safety D6 (and add-standalone-mode 6.3, in both modes): a quiet
// Today banner when the last export is older than 14 days, or there has
// never been one, and the reminder wasn't dismissed in the last 14 days.
// The phone's own daily snapshots are deleted with the app, so only an
// exported file survives a reinstall or a lost phone -- that's what this
// nudges towards.
//
// "Export" opens the Data screen in a sheet (where Export lives, with its
// note about entries still waiting for Garmin); "Not now" hides it for 14
// days. The rule is `BackupReminderPolicy.shouldShow` (FoodLogCore,
// unit-tested); the two dates are UserDefaults keys that backups exclude,
// so restoring an old backup never rewinds them.
//
// Depends on: FoodLogCore (BackupReminderPolicy), DataSettingsView.
// Depended on by: TodaySlotHost.

import SwiftUI
import FoodLogCore

@MainActor
struct BackupReminderBanner: View {
    @State private var isShowingDataScreen = false
    /// Bumped when either date may have changed (dismissed here, or the
    /// Data sheet closed after an export), so `shouldShow` is re-read.
    @State private var revision = 0

    var body: some View {
        // A VStack, not a Group, like the other slots: an empty slot must
        // still host the sheet modifier.
        VStack(spacing: 0) {
            if shouldShow {
                card
            }
        }
        .sheet(isPresented: $isShowingDataScreen, onDismiss: { revision += 1 }) {
            NavigationStack {
                DataSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingDataScreen = false }
                        }
                    }
            }
        }
    }

    /// The dates are stored as `Date` objects (DataSafetyController writes
    /// them with `set(_:forKey:)`), which `@AppStorage` can't hold -- and an
    /// `@AppStorage<Double>` on the same key would overwrite them -- so
    /// they're read directly; `revision` makes the view re-read them.
    private var shouldShow: Bool {
        _ = revision
        let defaults = UserDefaults.standard
        return BackupReminderPolicy.shouldShow(
            lastExportAt: defaults.object(forKey: BackupReminderPolicy.lastExportAtKey) as? Date,
            dismissedAt: defaults.object(forKey: BackupReminderPolicy.dismissedAtKey) as? Date,
            now: Date()
        )
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep a copy of your data")
                        .font(.headline)
                    Text("Export a backup to Files so a reinstall or a new phone doesn't lose anything.", comment: "Today backup reminder: why to export.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: Theme.Spacing.sm) {
                Button("Export") { isShowingDataScreen = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                Button("Not now") {
                    UserDefaults.standard.set(Date(), forKey: BackupReminderPolicy.dismissedAtKey)
                    revision += 1
                }
                .buttonStyle(.bordered)
            }
        }
        .card()
        .accessibilityElement(children: .contain)
    }
}

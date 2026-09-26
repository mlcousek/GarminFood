// DataSettingsView.swift
//
// add-data-safety D6: Settings -> Data. Everything that keeps the owner's
// data safe across app updates, reinstalls and a new phone, in one place:
// - where the food log lives and the mode switch (`DataModeSection`,
//   add-standalone-mode 5.4, moved here from Settings as that file's
//   header anticipated);
// - a staged restore waiting for the next launch, with "Cancel restore";
// - the last restore's result, shown once;
// - automatic backups: when the last one was taken, a warning when the
//   last attempt failed, "Back up now", and the snapshot list (tap to
//   restore, after a confirmation);
// - export to a single file (Files / iCloud Drive), with a note that
//   entries still waiting for Garmin are not in any backup (design D8);
// - import from a file, through a preview (`BackupImportPreviewSheet`).
//
// Built from Sections so another one can be added with one line. Thin:
// the state and actions are `DataSafetyController`; the logic is
// FoodLogCore's `Backup/`.
//
// Depends on: DataSafetyController, DataModeSection, BackupImportPreviewSheet,
// AppEnvironment (undeliveredCount, dataMode). Depended on by: SettingsView,
// BackupReminderBanner.

import SwiftUI
import UniformTypeIdentifiers
import FoodLogCore

@MainActor
struct DataSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var controller = DataSafetyController()
    @State private var snapshotToRestore: BackupSnapshot?
    @State private var exportDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var importedBackup: ImportedBackup?

    var body: some View {
        Form {
            DataModeSection()

            if let pending = controller.pendingRestore {
                pendingRestoreSection(pending)
            }

            if let record = controller.unacknowledgedRestore {
                restoreResultSection(record)
            }

            automaticBackupsSection
            exportSection
            importSection
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { await controller.reload() }
        .disabled(controller.isWorking)
        .overlay {
            if controller.isWorking {
                ProgressView()
            }
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(get: { snapshotToRestore != nil }, set: { if !$0 { snapshotToRestore = nil } }),
            titleVisibility: .visible,
            presenting: snapshotToRestore
        ) { snapshot in
            Button("Restore") {
                Task { await controller.stageRestore(snapshotId: snapshot.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { snapshot in
            Text("Your data will be replaced with the backup from \(snapshot.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) the next time you open GarminFood. Your current data is saved as a safety backup first.", comment: "Data screen: confirming a restore from a snapshot. %@ = the backup's date and time.")
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: controller.exportFileName
        ) { result in
            controller.didExport(result)
            exportDocument = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task { importedBackup = await controller.readImport(url) }
        }
        .sheet(item: $importedBackup) { imported in
            BackupImportPreviewSheet(imported: imported) {
                importedBackup = nil
                Task { await controller.stageRestore(container: imported.container) }
            }
        }
        .alert(
            controller.message ?? "",
            isPresented: Binding(get: { controller.message != nil }, set: { if !$0 { controller.message = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private func pendingRestoreSection(_ pending: BackupManifest) -> some View {
        Section {
            Label {
                Text("Close GarminFood and open it again to finish restoring the backup from \(pending.createdAt.formatted(date: .abbreviated, time: .shortened)).", comment: "Data screen: a restore is staged. %@ = the backup's date and time.")
            } icon: {
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .foregroundStyle(Theme.warning)
            }
            Button("Cancel restore", role: .destructive) {
                Task { await controller.cancelPendingRestore() }
            }
        } header: {
            Text("Restore waiting")
        }
    }

    private func restoreResultSection(_ record: BackupStatus.RestoreRecord) -> some View {
        Section {
            if record.succeeded {
                Label {
                    if let createdAt = record.backupCreatedAt {
                        Text("Restored the backup from \(createdAt.formatted(date: .abbreviated, time: .shortened)).", comment: "Data screen: the last restore worked. %@ = the backup's date and time.")
                    } else {
                        Text("The backup was restored.")
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                }
            } else {
                Label {
                    Text("The restore failed and your data was left as it was. Settings › Diagnostics has the details.", comment: "Data screen: the last restore failed.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.danger)
                }
            }
            Button("OK") {
                Task { await controller.acknowledgeRestore() }
            }
        } header: {
            Text("Last restore")
        }
    }

    private var automaticBackupsSection: some View {
        Section {
            HStack {
                Text("Last backup")
                Spacer()
                Text(Self.relativeDay(controller.lastBackupAt))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if controller.lastAttemptFailed {
                Label {
                    Text("The last automatic backup failed. Settings › Diagnostics has the details.", comment: "Data screen: the daily snapshot failed.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                }
            }

            Button {
                Task { await controller.backUpNow() }
            } label: {
                Label("Back up now", systemImage: "externaldrive.badge.plus")
            }

            ForEach(controller.snapshots) { snapshot in
                Button {
                    snapshotToRestore = snapshot
                } label: {
                    SnapshotRow(snapshot: snapshot)
                }
                .foregroundStyle(.primary)
                .accessibilityHint(Text("Restores this backup after a confirmation"))
            }
        } header: {
            Text("Backups on this phone")
        } footer: {
            Text("GarminFood backs up once a day when you open it and keeps the last 14 backups. They're deleted with the app, so export one now and then.", comment: "Data screen: footer under the snapshot list.")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                Task {
                    guard let document = await controller.makeExportDocument() else { return }
                    exportDocument = document
                    isExporting = true
                }
            } label: {
                Label("Export backup…", systemImage: "square.and.arrow.up")
            }
            HStack {
                Text("Last export")
                Spacer()
                Text(controller.lastExportAt.map { Self.relativeDay($0) } ?? String(localized: "Never", comment: "Data screen: no export yet."))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } header: {
            Text("Export")
        } footer: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Saves everything in one file you can keep in Files or iCloud Drive, and restore after reinstalling or on a new phone. Your Garmin sign-in isn't included.", comment: "Data screen: footer under Export.")
                if environment.dataMode != .standalone && environment.undeliveredCount > 0 {
                    Text("\(environment.undeliveredCount) entries are still waiting for Garmin. Backups don't include them, so let them sync first.", comment: "Data screen: undelivered entries aren't backed up. Plural.")
                        .foregroundStyle(Theme.warning)
                }
            }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                isImporting = true
            } label: {
                Label("Import backup…", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Shows what's in the file before anything changes.", comment: "Data screen: footer under Import.")
        }
    }

    /// "Today", "Yesterday", "N days ago", or "None yet".
    static func relativeDay(_ date: Date?) -> String {
        guard let date else {
            return String(localized: "None yet", comment: "Data screen: no backup has been taken yet.")
        }
        let days = BackupReminderPolicy.daysSince(date, now: Date())
        switch days {
        case 0: return String(localized: "Today", comment: "Data screen: last backup or export was today.")
        case 1: return String(localized: "Yesterday", comment: "Data screen: last backup or export was yesterday.")
        default: return String(localized: "\(days) days ago", comment: "Data screen: last backup or export, in whole days. Plural.")
        }
    }
}

/// One snapshot in the list: when, why, and how many files.
private struct SnapshotRow: View {
    let snapshot: BackupSnapshot

    private var kindText: String {
        switch snapshot.manifest.kind {
        case .automatic: return String(localized: "Automatic", comment: "Data screen: a daily snapshot.")
        case .manual: return String(localized: "Manual", comment: "Data screen: a snapshot from Back up now.")
        case .safety: return String(localized: "Before a restore", comment: "Data screen: the safety snapshot taken right before a restore.")
        case .export: return String(localized: "Imported", comment: "Data screen: a snapshot of kind export (rare).")
        }
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                Text(kindText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(snapshot.manifest.files.count) files", comment: "Data screen: number of files in a snapshot. Plural.")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

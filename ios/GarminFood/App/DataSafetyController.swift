// DataSafetyController.swift
//
// add-data-safety D6: the state and actions behind Settings -> Data
// (`DataSettingsView`) -- automatic snapshots, "Back up now", staging a
// restore from a snapshot or an imported file, cancelling it, and the
// single-file export. An `@Observable` owned by the Data screen, NOT stored
// in AppEnvironment: nothing else needs it, and every piece of state it
// shows is re-read from disk (`Backups/`) or UserDefaults on `reload()`.
//
// Thin glue only: every operation is a `BackupVault` call (FoodLogCore
// `Backup/`, unit-tested there) run through `DataSafetyQueue`, so one vault
// operation runs at a time and never on the main thread. This file maps
// `BackupError` to user-facing text, records the export date for the
// reminder (`BackupReminderPolicy`), and logs failures to DiagnosticsLog
// (the app's only post-mortem, see CLAUDE.md) -- a failed backup is never
// silent.
//
// Depends on: FoodLogCore (BackupVault, BackupContainer, BackupPreview,
// BackupReminderPolicy), DataSafetyLaunch.swift (DataSafetyQueue,
// DataSafetyPreferences), GarminKit (DiagnosticsLog).
// Depended on by: DataSettingsView, BackupImportPreviewSheet.

import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import FoodLogCore
import GarminKit

@MainActor
@Observable
final class DataSafetyController {
    private(set) var status = BackupStatus()
    private(set) var snapshots: [BackupSnapshot] = []
    private(set) var pendingRestore: BackupManifest?
    private(set) var lastExportAt: Date?
    private(set) var isWorking = false
    /// A one-off message for an alert ("Backup saved", or what went wrong).
    var message: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Reading

    func reload() async {
        let state = await DataSafetyQueue.shared.perform { vault in
            VaultState(status: vault.status(), snapshots: vault.listSnapshots(), pendingRestore: vault.pendingRestore())
        }
        status = state.status
        // Newest first, the order the list is read in.
        snapshots = state.snapshots.sorted { $0.manifest.createdAt > $1.manifest.createdAt }
        pendingRestore = state.pendingRestore
        lastExportAt = defaults.object(forKey: BackupReminderPolicy.lastExportAtKey) as? Date
    }

    /// The newest automatic or manual snapshot (safety snapshots don't
    /// count as "your last backup").
    var lastBackupAt: Date? {
        snapshots.first { $0.manifest.kind != .safety }?.manifest.createdAt ?? status.lastSuccessAt
    }

    /// The last automatic attempt failed after the last success.
    var lastAttemptFailed: Bool {
        guard status.lastError != nil, let attempt = status.lastAttemptAt else { return false }
        guard let success = status.lastSuccessAt else { return true }
        return attempt > success
    }

    /// A restore result the user hasn't seen yet.
    var unacknowledgedRestore: BackupStatus.RestoreRecord? {
        guard let record = status.lastRestore, record.acknowledged != true else { return nil }
        return record
    }

    // MARK: - Actions

    func backUpNow() async {
        await run {
            let result = try await DataSafetyQueue.shared.perform { vault in
                try vault.writeSnapshot(
                    kind: .manual,
                    preferences: DataSafetyPreferences.capture(),
                    appVersion: DataSafetyPreferences.appVersion,
                    now: Date()
                )
            }
            self.logSkipped(result?.skippedPaths ?? [])
            self.message = result == nil
                ? String(localized: "There's nothing to back up yet.", comment: "Data screen: Back up now with no data on the phone.")
                : String(localized: "Backup saved on this phone.", comment: "Data screen: Back up now succeeded.")
        }
    }

    /// Step 1 of a restore from one of the phone's snapshots (design D4).
    func stageRestore(snapshotId: String) async {
        await run {
            _ = try await DataSafetyQueue.shared.perform { vault in
                try vault.stageRestore(snapshotId: snapshotId)
            }
        }
    }

    /// Step 1 of a restore from an imported file (design D5).
    func stageRestore(container: BackupContainer) async {
        await run {
            _ = try await DataSafetyQueue.shared.perform { vault in
                try vault.stageRestore(container: container)
            }
        }
    }

    func cancelPendingRestore() async {
        await run {
            try await DataSafetyQueue.shared.perform { vault in
                try vault.cancelPendingRestore()
            }
        }
    }

    func acknowledgeRestore() async {
        await DataSafetyQueue.shared.perform { vault in
            vault.acknowledgeLastRestore()
        }
        await reload()
    }

    // MARK: - Export and import

    /// Builds the export file off the main thread. `nil` (with `message`
    /// set) when it couldn't be built.
    func makeExportDocument() async -> BackupDocument? {
        isWorking = true
        defer { isWorking = false }
        do {
            let preferences = DataSafetyPreferences.capture()
            let appVersion = DataSafetyPreferences.appVersion
            let export = try await DataSafetyQueue.shared.perform { vault in
                let made = try vault.makeExportContainer(preferences: preferences, appVersion: appVersion, now: Date())
                return ExportResult(data: try made.container.encoded(), skippedPaths: made.skippedPaths)
            }
            logSkipped(export.skippedPaths)
            return BackupDocument(data: export.data)
        } catch {
            fail(error, action: "Export")
            return nil
        }
    }

    var exportFileName: String {
        BackupVault.exportFileName(now: Date())
    }

    /// `fileExporter` finished.
    func didExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            let now = Date()
            defaults.set(now, forKey: BackupReminderPolicy.lastExportAtKey)
            lastExportAt = now
            message = String(localized: "Backup exported.", comment: "Data screen: the export file was saved.")
        case .failure(let error):
            // Cancelling the picker is not a failure worth an alert.
            if (error as NSError).code == NSUserCancelledError { return }
            fail(error, action: "Export")
        }
    }

    /// Reads a picked file (inside its security scope) and checks it
    /// before the preview is shown. `nil`, with `message` set, when it
    /// can't be restored.
    func readImport(_ url: URL) async -> ImportedBackup? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        isWorking = true
        defer { isWorking = false }
        do {
            // Off the main actor: an export is a few MB of base64 JSON.
            let checked = try await Task.detached(priority: .userInitiated) { () throws -> CheckedImport in
                let data = try Data(contentsOf: url)
                let container = try BackupContainer.decode(data)
                try BackupCompatibility.check(container.manifest)
                return CheckedImport(container: container, preview: BackupPreview.make(container: container))
            }.value
            return ImportedBackup(container: checked.container, preview: checked.preview)
        } catch {
            fail(error, action: "Import")
            return nil
        }
    }

    // MARK: - Helpers

    private func run(_ body: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await body()
        } catch {
            fail(error, action: "Backup")
        }
        await reload()
    }

    private func fail(_ error: Error, action: String) {
        DiagnosticsLog.log(.error, category: DataSafetyLaunch.diagnosticsCategory, "\(action) failed: \(DataSafetyLaunch.describe(error))")
        message = Self.userText(for: error)
    }

    private func logSkipped(_ paths: [String]) {
        guard !paths.isEmpty else { return }
        DiagnosticsLog.log(.warning, category: DataSafetyLaunch.diagnosticsCategory, "Left out of the backup because they look like credentials: \(paths.joined(separator: ", "))")
    }

    /// Design D4's refusal texts; anything else says it failed and points
    /// at Diagnostics, where the full reason is.
    static func userText(for error: Error) -> String {
        guard let backupError = error as? BackupError else {
            return String(localized: "Something went wrong. Settings › Diagnostics has the details.", comment: "Data screen: a backup operation failed for a reason other than the file itself.")
        }
        switch backupError {
        case .notABackup, .unsafePath:
            return String(localized: "This isn't a GarminFood backup.", comment: "Data screen: the imported file isn't a backup.")
        case .newerFormat, .newerStoreVersion:
            return String(localized: "This backup is from a newer version of GarminFood. Update the app, then try again.", comment: "Data screen: the backup was written by a newer app.")
        case .snapshotNotFound:
            return String(localized: "That backup is no longer on this phone.", comment: "Data screen: the chosen snapshot was deleted meanwhile.")
        case .safetySnapshotFailed, .fileOperationFailed:
            return String(localized: "Something went wrong. Settings › Diagnostics has the details.", comment: "Data screen: a backup operation failed for a reason other than the file itself.")
        }
    }
}

/// What `reload()` reads in one vault operation (a struct, not a tuple, so
/// it satisfies `DataSafetyQueue.perform`'s `Sendable` result).
private struct VaultState: Sendable {
    let status: BackupStatus
    let snapshots: [BackupSnapshot]
    let pendingRestore: BackupManifest?
}

/// A decoded, compatible import (built off the main thread).
private struct CheckedImport: Sendable {
    let container: BackupContainer
    let preview: BackupPreview
}

/// The encoded export file, built (and encoded) off the main thread.
private struct ExportResult: Sendable {
    let data: Data
    let skippedPaths: [String]
}

/// A checked import, waiting for the user to confirm the preview.
struct ImportedBackup: Identifiable {
    let id = UUID()
    let container: BackupContainer
    let preview: BackupPreview
}

/// The export file for `fileExporter`: the encoded `BackupContainer` as-is.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
